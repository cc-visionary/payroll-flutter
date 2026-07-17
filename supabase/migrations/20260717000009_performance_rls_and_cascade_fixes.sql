-- Fixes for the performance review module shipped in 20260717000001..08.
-- Those migrations are already applied, so every correction here is forward-only.
--
-- 1. HR_ADMIN could not activate a review cycle at all.
--    20260717000007 back-patched HR_ADMIN onto review_cycles, employee_reviews,
--    review_kpi_results and review_skill_ratings but missed self_review_requests
--    and self_review_submissions. activate_review_cycle() is SECURITY INVOKER, so
--    its insert into self_review_requests is checked against that table's policy
--    and an HR_ADMIN hit "new row violates row-level security policy". The read
--    side failed silently: the delivery-status panel just rendered empty.
--
-- 2. The ADMIN/HR branch of the new policies was not company-scoped, unlike
--    review_cycles_company_read twelve lines above it in the same file. Left as
--    is, an ADMIN/HR of one company could read *and write* another company's
--    reviews, ratings and outcomes. The *_hr_write policies are FOR ALL with a
--    bare role check, and permissive policies OR together, so their USING clause
--    also handed out unscoped SELECT — bypassing the narrower _read policies.
--
-- 3. The new employees(id) foreign keys have no ON DELETE, which broke
--    delete_employee_cascade for any employee who manages someone.
--
-- 4. save_manager_evaluation left submitted_at set on a draft save while wiping
--    overall_outcome, which let finalize_employee_review past its submitted-check
--    and into a raw CHECK violation.
--
-- Company scoping must go through SECURITY DEFINER helpers. A policy's subquery
-- is itself subject to the referenced table's RLS, so an inline
-- `exists (select 1 from review_cycles ...)` would be filtered to nothing for a
-- non-staff caller and would deny employees their own rows. can_manage_employee_review()
-- (20260717000006) is already definer, already company-scoped and already
-- HR_ADMIN-aware, so it is reused wherever a review_id is in scope.

-- =============================================================================
-- Helpers
-- =============================================================================

-- Staff access to a cycle, company-scoped. Definer so it can see review_cycles
-- regardless of the caller's own RLS view of that table.
create or replace function auth_is_performance_admin_for_cycle(p_cycle_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select auth_app_role() = 'SUPER_ADMIN'
    or (auth_app_role() in ('ADMIN', 'HR', 'HR_ADMIN')
      and exists (
        select 1 from review_cycles cycle
        where cycle.id = p_cycle_id
          and cycle.company_id = auth_company_id()
      ));
$$;
revoke all on function auth_is_performance_admin_for_cycle(uuid) from public;
grant execute on function auth_is_performance_admin_for_cycle(uuid) to authenticated;

-- Staff access to an employee, company-scoped. For development_goals and
-- monthly_development_checkins, whose link to a cycle is nullable.
create or replace function auth_is_performance_admin_for_employee(p_employee_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select auth_app_role() = 'SUPER_ADMIN'
    or (auth_app_role() in ('ADMIN', 'HR', 'HR_ADMIN')
      and exists (
        select 1 from employees employee
        where employee.id = p_employee_id
          and employee.company_id = auth_company_id()
      ));
$$;
revoke all on function auth_is_performance_admin_for_employee(uuid) from public;
grant execute on function auth_is_performance_admin_for_employee(uuid) to authenticated;

-- =============================================================================
-- employee_reviews — company-scope both policies, fold in the HR_ADMIN patch
-- =============================================================================

drop policy if exists employee_reviews_read on employee_reviews;
create policy employee_reviews_read on employee_reviews for select using (
  auth_is_performance_admin_for_cycle(review_cycle_id)
  or employee_id = auth_employee_id()
  or direct_manager_id = auth_employee_id()
);

drop policy if exists employee_reviews_hr_write on employee_reviews;
create policy employee_reviews_hr_write on employee_reviews for all
  using (auth_is_performance_admin_for_cycle(review_cycle_id))
  with check (auth_is_performance_admin_for_cycle(review_cycle_id));

-- Superseded: HR_ADMIN is now covered by the policies above.
drop policy if exists employee_reviews_hr_admin_access on employee_reviews;

-- =============================================================================
-- review_kpi_results / review_skill_ratings
-- The _read policies delegate to employee_reviews' own RLS via exists(), so they
-- inherit the scoping fixed above and need no change. The _hr_write policies do.
-- =============================================================================

drop policy if exists review_kpi_results_hr_write on review_kpi_results;
create policy review_kpi_results_hr_write on review_kpi_results for all
  using (can_manage_employee_review(review_id))
  with check (can_manage_employee_review(review_id));
drop policy if exists review_kpi_hr_admin_access on review_kpi_results;

drop policy if exists review_skill_ratings_hr_write on review_skill_ratings;
create policy review_skill_ratings_hr_write on review_skill_ratings for all
  using (can_manage_employee_review(review_id))
  with check (can_manage_employee_review(review_id));
drop policy if exists review_skill_hr_admin_access on review_skill_ratings;

-- =============================================================================
-- self_review_requests — the HR_ADMIN activation blocker
-- =============================================================================

drop policy if exists self_review_requests_read on self_review_requests;
create policy self_review_requests_read on self_review_requests for select using (
  can_manage_employee_review(review_id)
  or employee_id = auth_employee_id()
);

drop policy if exists self_review_requests_hr_write on self_review_requests;
create policy self_review_requests_hr_write on self_review_requests for all
  using (can_manage_employee_review(review_id))
  with check (can_manage_employee_review(review_id));

-- =============================================================================
-- self_review_submissions — read-only to clients; writes go through
-- ingest_self_review_submission() (definer, service_role only).
-- =============================================================================

drop policy if exists self_review_submissions_read on self_review_submissions;
create policy self_review_submissions_read on self_review_submissions for select using (
  can_manage_employee_review(review_id)
  or employee_id = auth_employee_id()
);

-- =============================================================================
-- development_goals — scoped via the employee, since source_review_id is nullable
-- =============================================================================

drop policy if exists development_goals_read on development_goals;
create policy development_goals_read on development_goals for select using (
  auth_is_performance_admin_for_employee(employee_id)
  or employee_id = auth_employee_id()
  or manager_id = auth_employee_id()
  or trainer_id = auth_employee_id()
);

drop policy if exists development_goals_hr_write on development_goals;
create policy development_goals_hr_write on development_goals for all
  using (auth_is_performance_admin_for_employee(employee_id))
  with check (auth_is_performance_admin_for_employee(employee_id));

-- =============================================================================
-- monthly_development_checkins — writes go through
-- record_monthly_development_checkin() (definer), so read scoping is the fix.
-- monthly_checkin_goal_updates delegates via exists() and inherits this.
-- =============================================================================

drop policy if exists monthly_development_checkins_read on monthly_development_checkins;
create policy monthly_development_checkins_read
  on monthly_development_checkins for select using (
    auth_is_performance_admin_for_employee(employee_id)
    or employee_id = auth_employee_id()
    or manager_id = auth_employee_id()
  );

-- =============================================================================
-- delete_employee_cascade — the new FKs have no ON DELETE
-- =============================================================================

-- trainer_id is already nullable, so it can follow the departments.manager_id
-- precedent and unlink itself.
alter table development_goals
  drop constraint if exists development_goals_trainer_id_fkey;
alter table development_goals
  add constraint development_goals_trainer_id_fkey
  foreign key (trainer_id) references employees(id) on delete set null;

-- The remaining refs (employee_reviews.direct_manager_id, development_goals
-- .owner_id/.manager_id, monthly_development_checkins.manager_id/.action_owner_id)
-- are NOT NULL and belong to the *reviewed* employee's history, not the manager's.
-- Nulling them would need a schema+model change; deleting them would destroy a
-- subordinate's review record. So the delete is refused with an actionable
-- message instead of the raw 23503 foreign-key error it raises today.
create or replace function delete_employee_cascade(_employee_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_blocking integer;
begin
  -- Authorization: SUPER_ADMIN only.
  v_role := auth_app_role();
  if v_role is null or v_role <> 'SUPER_ADMIN' then
    raise exception 'Only SUPER_ADMIN can hard-delete employees'
      using errcode = '42501';
  end if;

  -- Performance records naming this employee as manager/owner belong to their
  -- reports. Refuse rather than orphan or destroy them.
  select
    (select count(*) from employee_reviews where direct_manager_id = _employee_id)
    + (select count(*) from development_goals
        where owner_id = _employee_id or manager_id = _employee_id)
    + (select count(*) from monthly_development_checkins
        where manager_id = _employee_id or action_owner_id = _employee_id)
    into v_blocking;
  if v_blocking > 0 then
    raise exception
      'Cannot delete: this employee is the manager or owner of record on % performance record(s) belonging to other employees. Reassign those reviews, goals and check-ins first.',
      v_blocking
      using errcode = '23503';
  end if;

  -- Unlink applicant references (preserve applicant rows).
  update applicants set converted_to_employee_id = null
    where converted_to_employee_id = _employee_id;
  update applicants set referred_by_id = null
    where referred_by_id = _employee_id;

  -- Unlink interview references (NOT applicants — separate table).
  update interviews set primary_interviewer_id = null
    where primary_interviewer_id = _employee_id;
  update interviews
    set interviewer_ids = array_remove(interviewer_ids, _employee_id)
    where _employee_id = any(interviewer_ids);

  -- Unlink org-chart references.
  update employees set reports_to_id = null
    where reports_to_id = _employee_id;
  -- departments.manager_id has ON DELETE SET NULL (employees migration
  -- line 159), so no manual unlink is needed.

  -- Hard-delete non-cascading children.
  delete from payslip_lines
    where payslip_id in (select id from payslips where employee_id = _employee_id);
  delete from payslips where employee_id = _employee_id;
  delete from attendance_day_records where employee_id = _employee_id;
  delete from workflow_instances where employee_id = _employee_id;
  delete from manual_adjustment_lines where employee_id = _employee_id;

  -- Finally: the employee row. The audit trigger writes the DELETE row.
  delete from employees where id = _employee_id;
end;
$$;

grant execute on function delete_employee_cascade(uuid) to authenticated;

-- =============================================================================
-- save_manager_evaluation — keep draft state internally consistent
-- =============================================================================

-- Only the submitted_at/submitted_by pair changes: a draft save now clears them,
-- matching the status regression to MANAGER_REVIEW_IN_PROGRESS and the wiped
-- overall_rating/overall_outcome that the same statement already performs.
-- Previously submitted_at survived a draft save, so finalize_employee_review's
-- "Manager review must be submitted" check passed on stale data and the HR
-- override path drove straight into employee_reviews_finalization_valid (23514).
-- Now finalize stops with that friendly message until the manager re-submits.
create or replace function save_manager_evaluation(
  p_review_id uuid,
  p_kpis jsonb,
  p_skills jsonb,
  p_overall_feedback text,
  p_performance_concerns text,
  p_support_manager_will_provide text,
  p_readiness_for_additional_duties text,
  p_strengths jsonb,
  p_development_areas jsonb,
  p_overall_rating numeric,
  p_recommended_outcome review_outcome,
  p_submit boolean default false
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_review employee_reviews%rowtype;
  v_item jsonb;
begin
  select * into v_review from employee_reviews where id = p_review_id for update;
  if not found then raise exception 'Review not found'; end if;
  if not can_manage_employee_review(p_review_id) then raise exception 'Not authorized for this allocated employee'; end if;
  if v_review.status in ('FINALIZED', 'CANCELLED') then raise exception 'This review is locked'; end if;
  if jsonb_typeof(coalesce(p_strengths, '[]')) <> 'array'
    or jsonb_array_length(coalesce(p_strengths, '[]')) > 3 then
    raise exception 'A maximum of three strengths is allowed';
  end if;
  if jsonb_typeof(coalesce(p_development_areas, '[]')) <> 'array'
    or jsonb_array_length(coalesce(p_development_areas, '[]')) > 2 then
    raise exception 'A maximum of two development areas is allowed';
  end if;

  for v_item in select value from jsonb_array_elements(coalesce(p_kpis, '[]')) loop
    update review_kpi_results set
      actual_value = nullif(v_item->>'actual_value', ''),
      result_status = nullif(v_item->>'result_status', '')::kpi_result_status,
      manager_rating = nullif(v_item->>'manager_rating', '')::integer,
      manager_comment = nullif(v_item->>'manager_comment', '')
    where id = (v_item->>'id')::uuid and review_id = p_review_id;
  end loop;
  for v_item in select value from jsonb_array_elements(coalesce(p_skills, '[]')) loop
    update review_skill_ratings set
      manager_rating = nullif(v_item->>'manager_rating', '')::integer,
      manager_comment = nullif(v_item->>'manager_comment', ''),
      development_needed = coalesce((v_item->>'development_needed')::boolean, false)
    where id = (v_item->>'id')::uuid and review_id = p_review_id;
  end loop;

  insert into manager_reviews (
    review_id, overall_feedback, performance_concerns,
    support_manager_will_provide, readiness_for_additional_duties,
    strengths, development_areas, recommended_outcome,
    submitted_at, submitted_by
  ) values (
    p_review_id, nullif(trim(p_overall_feedback), ''),
    nullif(trim(p_performance_concerns), ''),
    nullif(trim(p_support_manager_will_provide), ''),
    nullif(trim(p_readiness_for_additional_duties), ''),
    coalesce(p_strengths, '[]'), coalesce(p_development_areas, '[]'),
    p_recommended_outcome, case when p_submit then now() end,
    case when p_submit then auth.uid() end
  ) on conflict (review_id) do update set
    overall_feedback = excluded.overall_feedback,
    performance_concerns = excluded.performance_concerns,
    support_manager_will_provide = excluded.support_manager_will_provide,
    readiness_for_additional_duties = excluded.readiness_for_additional_duties,
    strengths = excluded.strengths,
    development_areas = excluded.development_areas,
    recommended_outcome = excluded.recommended_outcome,
    submitted_at = case when p_submit then now() else null end,
    submitted_by = case when p_submit then auth.uid() else null end;

  if p_submit then
    if nullif(trim(p_overall_feedback), '') is null then raise exception 'Overall feedback is required'; end if;
    if p_overall_rating is null or p_recommended_outcome is null then
      raise exception 'Overall rating and recommended outcome are required';
    end if;
    if exists (select 1 from review_kpi_results where review_id = p_review_id
      and (result_status is null or manager_rating is null)) then
      raise exception 'Complete every KPI result and rating';
    end if;
    if exists (select 1 from review_skill_ratings where review_id = p_review_id
      and manager_rating is null) then raise exception 'Rate every skill and expectation'; end if;
    if exists (select 1 from jsonb_array_elements(coalesce(p_strengths, '[]')) item
      where nullif(trim(item->>'title'), '') is null) then
      raise exception 'Every strength requires a title';
    end if;
    if exists (select 1 from jsonb_array_elements(coalesce(p_development_areas, '[]')) item
      where nullif(trim(item->>'area'), '') is null) then
      raise exception 'Every development area requires a name';
    end if;
  end if;

  update employee_reviews set
    overall_rating = p_overall_rating,
    overall_outcome = p_recommended_outcome,
    status = case when p_submit then 'READY_FOR_DISCUSSION'::employee_review_status
      else 'MANAGER_REVIEW_IN_PROGRESS'::employee_review_status end
  where id = p_review_id;
end;
$$;

revoke all on function save_manager_evaluation(
  uuid, jsonb, jsonb, text, text, text, text, jsonb, jsonb, numeric, review_outcome, boolean
) from public;
grant execute on function save_manager_evaluation(
  uuid, jsonb, jsonb, text, text, text, text, jsonb, jsonb, numeric, review_outcome, boolean
) to authenticated;

-- =============================================================================
-- Indexes on the columns the policies above filter by
-- =============================================================================

create index if not exists development_goals_trainer_id_idx
  on development_goals (trainer_id);
create index if not exists self_review_submissions_employee_id_idx
  on self_review_submissions (employee_id);
create index if not exists employee_reviews_direct_manager_id_idx
  on employee_reviews (direct_manager_id);
create index if not exists monthly_development_checkins_manager_id_idx
  on monthly_development_checkins (manager_id);
