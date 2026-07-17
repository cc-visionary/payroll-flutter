-- Lightweight monthly progress check-ins for review development goals.

create type monthly_checkin_status as enum ('ON_TRACK', 'NEEDS_ATTENTION', 'OFF_TRACK');

create table monthly_development_checkins (
  id                  uuid primary key default gen_random_uuid(),
  employee_id         uuid not null references employees(id) on delete cascade,
  manager_id          uuid not null references employees(id),
  source_review_id    uuid not null references employee_reviews(id) on delete cascade,
  review_cycle_id     uuid not null references review_cycles(id) on delete cascade,
  checkin_date        date not null,
  what_went_well      text,
  needs_attention     text,
  support_needed      text,
  agreed_next_action  text not null,
  action_owner_id     uuid not null references employees(id),
  action_due_date     date not null,
  general_status      monthly_checkin_status not null,
  completed_by        uuid not null references users(id),
  completed_at        timestamptz not null default now(),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint monthly_checkin_action_date_valid
    check (checkin_date <= action_due_date)
);
create index on monthly_development_checkins (employee_id, checkin_date desc);
create index on monthly_development_checkins (manager_id, checkin_date desc);
create index on monthly_development_checkins (source_review_id, checkin_date desc);
create trigger _monthly_development_checkins_updated
  before update on monthly_development_checkins
  for each row execute function set_updated_at();

create table monthly_checkin_goal_updates (
  id              uuid primary key default gen_random_uuid(),
  checkin_id      uuid not null references monthly_development_checkins(id) on delete cascade,
  goal_id         uuid not null references development_goals(id) on delete cascade,
  progress        integer not null,
  goal_status     development_goal_status not null,
  progress_note   text,
  created_at      timestamptz not null default now(),
  constraint monthly_goal_progress_valid check (progress between 0 and 100),
  unique (checkin_id, goal_id)
);
create index on monthly_checkin_goal_updates (goal_id, created_at desc);

create or replace function record_monthly_development_checkin(
  p_review_id uuid,
  p_checkin_date date,
  p_what_went_well text,
  p_needs_attention text,
  p_support_needed text,
  p_agreed_next_action text,
  p_action_owner_id uuid,
  p_action_due_date date,
  p_general_status monthly_checkin_status,
  p_goal_updates jsonb default '[]'::jsonb
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_review employee_reviews%rowtype;
  v_checkin_id uuid;
  v_item jsonb;
  v_goal development_goals%rowtype;
  v_progress integer;
  v_status development_goal_status;
begin
  if not can_manage_employee_review(p_review_id) then
    raise exception 'Not authorized for this allocated employee';
  end if;
  select * into v_review from employee_reviews where id = p_review_id;
  if not found then raise exception 'Review not found'; end if;
  if v_review.status <> 'FINALIZED' then
    raise exception 'Monthly development check-ins require a finalized review';
  end if;
  if nullif(trim(p_agreed_next_action), '') is null then
    raise exception 'One agreed next action is required';
  end if;
  if p_action_owner_id not in (v_review.employee_id, v_review.direct_manager_id) then
    raise exception 'Action owner must be the employee or allocated manager';
  end if;
  if p_checkin_date is null or p_action_due_date is null
    or p_action_due_date < p_checkin_date then
    raise exception 'Check-in and action due dates are invalid';
  end if;
  if jsonb_typeof(coalesce(p_goal_updates, '[]')) <> 'array' then
    raise exception 'Goal updates must be an array';
  end if;

  insert into monthly_development_checkins (
    employee_id, manager_id, source_review_id, review_cycle_id,
    checkin_date, what_went_well, needs_attention, support_needed,
    agreed_next_action, action_owner_id, action_due_date,
    general_status, completed_by
  ) values (
    v_review.employee_id, v_review.direct_manager_id, v_review.id,
    v_review.review_cycle_id, p_checkin_date,
    nullif(trim(p_what_went_well), ''),
    nullif(trim(p_needs_attention), ''),
    nullif(trim(p_support_needed), ''), trim(p_agreed_next_action),
    p_action_owner_id, p_action_due_date, p_general_status, auth.uid()
  ) returning id into v_checkin_id;

  for v_item in select value from jsonb_array_elements(coalesce(p_goal_updates, '[]')) loop
    select * into v_goal from development_goals
      where id = (v_item->>'goal_id')::uuid
        and source_review_id = p_review_id for update;
    if not found then raise exception 'Goal does not belong to this review'; end if;
    v_progress := (v_item->>'progress')::integer;
    v_status := (v_item->>'goal_status')::development_goal_status;
    if v_progress < 0 or v_progress > 100 then raise exception 'Goal progress must be 0 to 100'; end if;
    if v_status in ('CANCELLED', 'CARRIED_FORWARD') then
      raise exception 'Monthly check-ins cannot cancel or carry forward goals';
    end if;
    if v_status = 'COMPLETED' and v_progress <> 100 then
      raise exception 'Completed goals require 100 percent progress';
    end if;
    insert into monthly_checkin_goal_updates (
      checkin_id, goal_id, progress, goal_status, progress_note
    ) values (
      v_checkin_id, v_goal.id, v_progress, v_status,
      nullif(trim(v_item->>'progress_note'), '')
    );
    update development_goals set
      progress = v_progress, status = v_status,
      completed_at = case when v_status = 'COMPLETED' then now() else null end
    where id = v_goal.id;
  end loop;
  return v_checkin_id;
end;
$$;

revoke all on function record_monthly_development_checkin(
  uuid, date, text, text, text, text, uuid, date,
  monthly_checkin_status, jsonb
) from public;
grant execute on function record_monthly_development_checkin(
  uuid, date, text, text, text, text, uuid, date,
  monthly_checkin_status, jsonb
) to authenticated;

alter table monthly_development_checkins enable row level security;
alter table monthly_checkin_goal_updates enable row level security;
create policy monthly_development_checkins_read
  on monthly_development_checkins for select using (
    auth_app_role() in ('SUPER_ADMIN', 'ADMIN', 'HR', 'HR_ADMIN')
    or employee_id = auth_employee_id()
    or manager_id = auth_employee_id()
  );
create policy monthly_goal_updates_read
  on monthly_checkin_goal_updates for select using (
    exists (
      select 1 from monthly_development_checkins checkin
      where checkin.id = monthly_checkin_goal_updates.checkin_id
    )
  );
