-- Pure inheritance: a person's KPIs are their role's KPIs.
--
-- employee_kpis let an employee be tracked on a SUBSET of their role card's
-- KPIs, with zero rows meaning "the whole role set". That subset is retired:
-- a role now defines 2-4 KPIs and whoever holds it inherits them, so a new
-- hire is measurable on assignment and a role change moves measurement with
-- no per-employee setup.
--
-- generate_employee_review is rewritten FIRST, in this same migration, because
-- it reads employee_kpis and dropping the table under a live function would
-- break review generation for everyone.
--
-- Blast radius: employees with no curated subset are unaffected by definition,
-- since zero rows already meant the full role set. Employees with a narrowed
-- subset widen to their full role set -- which is the intent, not a defect.

create or replace function generate_employee_review(
  p_review_cycle_id uuid,
  p_employee_id uuid
) returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_cycle review_cycles%rowtype;
  v_employee employees%rowtype;
  v_card role_scorecards%rowtype;
  v_review_id uuid;
  v_item jsonb;
  v_index integer;
begin
  select * into v_cycle from review_cycles where id = p_review_cycle_id;
  if not found then raise exception 'Review cycle not found'; end if;

  select * into v_employee from employees
    where id = p_employee_id and deleted_at is null;
  if not found then raise exception 'Employee not found or archived'; end if;
  if v_employee.company_id <> v_cycle.company_id then
    raise exception 'Employee and review cycle belong to different companies';
  end if;
  if v_employee.role_scorecard_id is null then
    raise exception 'Employee has no role';
  end if;
  if v_employee.reports_to_id is null then
    raise exception 'Employee has no direct manager';
  end if;

  select * into v_card from role_scorecards where id = v_employee.role_scorecard_id;
  if not found then raise exception 'Role not found'; end if;

  select id into v_review_id from employee_reviews
    where review_cycle_id = p_review_cycle_id and employee_id = p_employee_id;
  if found then return v_review_id; end if;

  insert into employee_reviews (
    review_cycle_id, employee_id, employee_name_snapshot,
    responsibility_card_id, responsibility_card_version, direct_manager_id,
    review_type, review_period_start, review_period_end,
    responsibility_snapshot
  ) values (
    v_cycle.id, v_employee.id,
    concat_ws(' ', v_employee.first_name, v_employee.middle_name, v_employee.last_name),
    v_card.id, v_card.version, v_employee.reports_to_id,
    v_cycle.review_type, v_cycle.period_start, v_cycle.period_end,
    v_card.key_responsibilities
  ) returning id into v_review_id;

  -- Every KPI on the role, with no per-employee filter. This is the whole
  -- change: v_has_assignment and its EXISTS clause are gone.
  v_index := 0;
  for v_item in
    select jsonb_build_object(
      'name', k.name,
      'measurement', k.measurement_unit,
      'target', rsk.target
    ) as value
    from role_scorecard_kpis rsk
      join kpis k on k.id = rsk.kpi_id
    where rsk.role_scorecard_id = v_card.id
    order by rsk.sort_order
  loop
    insert into review_kpi_results (
      review_id, snapshot_order, kpi_name, description,
      measurement_unit, target_value, is_qualitative
    ) values (
      v_review_id, v_index,
      coalesce(v_item->>'name', ''),
      null, v_item->>'measurement', v_item->>'target',
      false
    );
    v_index := v_index + 1;
  end loop;

  v_index := 0;
  for v_item in select value from jsonb_array_elements(v_card.required_skills)
  loop
    insert into review_skill_ratings (
      review_id, snapshot_order, skill_name, skill_description,
      skill_category, required_level
    ) values (
      v_review_id, v_index, coalesce(v_item->>'name', ''),
      v_item->>'description', 'TECHNICAL',
      coalesce((v_item->>'required_level')::integer, 3)
    );
    v_index := v_index + 1;
  end loop;

  for v_item in select value from jsonb_array_elements(v_card.behavioral_expectations)
  loop
    insert into review_skill_ratings (
      review_id, snapshot_order, skill_name, skill_description,
      skill_category, required_level
    ) values (
      v_review_id, v_index, coalesce(v_item->>'name', ''),
      v_item->>'description', 'BEHAVIORAL', null
    );
    v_index := v_index + 1;
  end loop;

  return v_review_id;
end;
$$;

-- Announce the blast radius before the one-way door closes. This runs by
-- hand via `supabase db push`, not through CI, so the person applying it is
-- the last line of defence -- they should see the size of what they are
-- about to discard.
--
-- Guarded so a RE-RUN (e.g. a retried `db push` after this already applied
-- successfully) does not itself fail: without the guard, `employee_kpis`
-- would already be gone and the bare `select ... from employee_kpis` would
-- raise 42P01 (undefined_table) before ever reaching `drop table if
-- exists` below -- a migration marked idempotent must not error out on its
-- own second run.
do $$
declare
  v_rows int;
  v_employees int;
begin
  if to_regclass('public.employee_kpis') is not null then
    select count(*), count(distinct employee_id)
      into v_rows, v_employees
      from employee_kpis;
    raise notice
      'employee_kpis: about to drop % row(s) covering % distinct employee(s). '
      'This is irreversible -- every employee with a curated subset widens to '
      'their full role set.',
      v_rows, v_employees;
  else
    raise notice 'employee_kpis already dropped -- nothing to announce.';
  end if;
end $$;

drop table if exists employee_kpis;
