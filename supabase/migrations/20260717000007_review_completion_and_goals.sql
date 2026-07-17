-- Discussion, finalization, reopening, and development goals.

create type development_goal_type as enum (
  'PERFORMANCE', 'SKILL_DEVELOPMENT', 'CROSS_TRAINING',
  'BEHAVIORAL_IMPROVEMENT', 'CAREER_READINESS', 'COMPLIANCE', 'PIP_OBJECTIVE'
);
create type development_goal_status as enum (
  'NOT_STARTED', 'IN_PROGRESS', 'ON_TRACK', 'AT_RISK', 'OFF_TRACK',
  'COMPLETED', 'CANCELLED', 'CARRIED_FORWARD'
);

alter table employee_reviews
  add column discussion_date date,
  add column discussion_notes text,
  add column discussion_completed_by uuid references users(id),
  add column discussion_completed_at timestamptz;

create table development_goals (
  id                    uuid primary key default gen_random_uuid(),
  employee_id           uuid not null references employees(id) on delete cascade,
  source_review_id      uuid references employee_reviews(id) on delete set null,
  goal_type             development_goal_type not null,
  title                 text not null,
  description           text,
  baseline              text,
  target                text not null,
  start_date            date not null,
  due_date              date not null,
  owner_id              uuid not null references employees(id),
  manager_id            uuid not null references employees(id),
  trainer_id            uuid references employees(id),
  progress              integer not null default 0,
  status                development_goal_status not null default 'NOT_STARTED',
  evidence_required     text,
  completion_evidence   jsonb not null default '[]'::jsonb,
  completion_note       text,
  completed_at          timestamptz,
  created_by            uuid not null references users(id),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  constraint development_goal_dates_valid check (start_date <= due_date),
  constraint development_goal_progress_valid check (progress between 0 and 100),
  constraint development_goal_evidence_array
    check (jsonb_typeof(completion_evidence) = 'array')
);
create index on development_goals (employee_id, status, due_date);
create index on development_goals (manager_id, status, due_date);
create index on development_goals (source_review_id);
create trigger _development_goals_updated before update on development_goals
  for each row execute function set_updated_at();

create or replace function complete_review_discussion(
  p_review_id uuid,
  p_discussion_date date,
  p_discussion_notes text
) returns void
language plpgsql security definer set search_path = public as $$
declare v_status employee_review_status;
begin
  if not can_manage_employee_review(p_review_id) then
    raise exception 'Not authorized for this allocated employee';
  end if;
  select status into v_status from employee_reviews where id = p_review_id for update;
  if not found then raise exception 'Review not found'; end if;
  if v_status <> 'READY_FOR_DISCUSSION' then
    raise exception 'Manager review must be submitted before discussion completion';
  end if;
  if p_discussion_date is null then raise exception 'Discussion date is required'; end if;
  update employee_reviews set
    status = 'DISCUSSION_COMPLETED',
    discussion_date = p_discussion_date,
    discussion_notes = nullif(trim(p_discussion_notes), ''),
    discussion_completed_by = auth.uid(),
    discussion_completed_at = now()
  where id = p_review_id;
end;
$$;

create or replace function finalize_employee_review(
  p_review_id uuid,
  p_goals jsonb default '[]'::jsonb,
  p_override_reason text default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_review employee_reviews%rowtype;
  v_item jsonb;
  v_goal_id uuid;
  v_goal_count integer;
begin
  if auth_app_role() not in ('SUPER_ADMIN', 'ADMIN', 'HR', 'HR_ADMIN') then
    raise exception 'Only HR can finalize reviews';
  end if;
  select * into v_review from employee_reviews where id = p_review_id for update;
  if not found then raise exception 'Review not found'; end if;
  if not can_manage_employee_review(p_review_id) then raise exception 'Review is outside your company'; end if;
  if v_review.status = 'FINALIZED' then raise exception 'Review is already finalized'; end if;
  if not exists (select 1 from manager_reviews where review_id = p_review_id and submitted_at is not null) then
    raise exception 'Manager review must be submitted';
  end if;
  if v_review.status <> 'DISCUSSION_COMPLETED'
    and nullif(trim(p_override_reason), '') is null then
    raise exception 'Complete the discussion or provide an HR override reason';
  end if;
  if jsonb_typeof(coalesce(p_goals, '[]')) <> 'array'
    or jsonb_array_length(coalesce(p_goals, '[]')) > 2 then
    raise exception 'A maximum of two goals is allowed';
  end if;

  select count(*) into v_goal_count from development_goals
    where source_review_id = p_review_id and status <> 'CANCELLED';
  if v_review.overall_outcome in (
    'CONTINUE_DEVELOPMENT', 'READY_FOR_CROSS_TRAINING', 'NEEDS_CLOSER_COACHING',
    'FORMAL_PERFORMANCE_CONCERN', 'PIP_RECOMMENDED'
  ) and v_goal_count + jsonb_array_length(coalesce(p_goals, '[]')) = 0 then
    raise exception 'This outcome requires at least one development goal';
  end if;

  for v_item in select value from jsonb_array_elements(coalesce(p_goals, '[]')) loop
    if nullif(trim(v_item->>'title'), '') is null
      or nullif(trim(v_item->>'target'), '') is null then
      raise exception 'Every goal requires a title and target';
    end if;
    v_goal_id := nullif(v_item->>'id', '')::uuid;
    if v_goal_id is null then
      insert into development_goals (
        employee_id, source_review_id, goal_type, title, description,
        baseline, target, start_date, due_date, owner_id, manager_id,
        trainer_id, evidence_required, created_by
      ) values (
        v_review.employee_id, p_review_id,
        (v_item->>'goal_type')::development_goal_type,
        trim(v_item->>'title'), nullif(trim(v_item->>'description'), ''),
        nullif(trim(v_item->>'baseline'), ''), trim(v_item->>'target'),
        (v_item->>'start_date')::date, (v_item->>'due_date')::date,
        v_review.employee_id, v_review.direct_manager_id,
        nullif(v_item->>'trainer_id', '')::uuid,
        nullif(trim(v_item->>'evidence_required'), ''), auth.uid()
      );
    else
      update development_goals set
        goal_type = (v_item->>'goal_type')::development_goal_type,
        title = trim(v_item->>'title'),
        description = nullif(trim(v_item->>'description'), ''),
        baseline = nullif(trim(v_item->>'baseline'), ''),
        target = trim(v_item->>'target'),
        start_date = (v_item->>'start_date')::date,
        due_date = (v_item->>'due_date')::date,
        trainer_id = nullif(v_item->>'trainer_id', '')::uuid,
        evidence_required = nullif(trim(v_item->>'evidence_required'), '')
      where id = v_goal_id and source_review_id = p_review_id
        and status = 'NOT_STARTED';
      if not found then raise exception 'Only not-started goals from this review can be edited'; end if;
    end if;
  end loop;

  if (select count(*) from development_goals
      where source_review_id = p_review_id and status <> 'CANCELLED') > 2 then
    raise exception 'A maximum of two goals is allowed';
  end if;
  update employee_reviews set
    status = 'FINALIZED', finalized_by = auth.uid(), finalized_at = now(),
    reopen_reason = case when nullif(trim(p_override_reason), '') is not null
      then concat('Finalization override: ', trim(p_override_reason))
      else reopen_reason end
  where id = p_review_id;
end;
$$;

create or replace function reopen_employee_review(
  p_review_id uuid,
  p_reason text
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth_app_role() not in ('SUPER_ADMIN', 'ADMIN', 'HR', 'HR_ADMIN') then
    raise exception 'Only HR can reopen reviews';
  end if;
  if nullif(trim(p_reason), '') is null then raise exception 'Reopen reason is required'; end if;
  if not can_manage_employee_review(p_review_id) then raise exception 'Review is outside your company'; end if;
  update employee_reviews set
    status = case when discussion_completed_at is null
      then 'READY_FOR_DISCUSSION'::employee_review_status
      else 'DISCUSSION_COMPLETED'::employee_review_status end,
    reopened_at = now(), reopened_by = auth.uid(), reopen_reason = trim(p_reason),
    finalized_by = null, finalized_at = null
  where id = p_review_id and status = 'FINALIZED';
  if not found then raise exception 'Only finalized reviews can be reopened'; end if;
end;
$$;

revoke all on function complete_review_discussion(uuid, date, text) from public;
grant execute on function complete_review_discussion(uuid, date, text) to authenticated;
revoke all on function finalize_employee_review(uuid, jsonb, text) from public;
grant execute on function finalize_employee_review(uuid, jsonb, text) to authenticated;
revoke all on function reopen_employee_review(uuid, text) from public;
grant execute on function reopen_employee_review(uuid, text) to authenticated;

alter table development_goals enable row level security;
create policy development_goals_read on development_goals for select using (
  auth_app_role() in ('SUPER_ADMIN', 'ADMIN', 'HR', 'HR_ADMIN')
  or employee_id = auth_employee_id()
  or manager_id = auth_employee_id()
  or trainer_id = auth_employee_id()
);
create policy development_goals_hr_write on development_goals for all using (
  auth_app_role() in ('SUPER_ADMIN', 'ADMIN', 'HR', 'HR_ADMIN')
) with check (
  auth_app_role() in ('SUPER_ADMIN', 'ADMIN', 'HR', 'HR_ADMIN')
);

-- HR_ADMIN is an application administrator role and must receive the same
-- performance-module access as HR across the earlier foundation tables.
create policy review_cycles_hr_admin_access on review_cycles for all using (
  company_id = auth_company_id() and auth_app_role() = 'HR_ADMIN'
) with check (
  company_id = auth_company_id() and auth_app_role() = 'HR_ADMIN'
);
create policy employee_reviews_hr_admin_access on employee_reviews for all using (
  auth_app_role() = 'HR_ADMIN' and exists (
    select 1 from review_cycles cycle
    where cycle.id = employee_reviews.review_cycle_id
      and cycle.company_id = auth_company_id()
  )
) with check (
  auth_app_role() = 'HR_ADMIN' and exists (
    select 1 from review_cycles cycle
    where cycle.id = employee_reviews.review_cycle_id
      and cycle.company_id = auth_company_id()
  )
);
create policy review_kpi_hr_admin_access on review_kpi_results for all using (
  auth_app_role() = 'HR_ADMIN' and can_manage_employee_review(review_id)
) with check (
  auth_app_role() = 'HR_ADMIN' and can_manage_employee_review(review_id)
);
create policy review_skill_hr_admin_access on review_skill_ratings for all using (
  auth_app_role() = 'HR_ADMIN' and can_manage_employee_review(review_id)
) with check (
  auth_app_role() = 'HR_ADMIN' and can_manage_employee_review(review_id)
);
