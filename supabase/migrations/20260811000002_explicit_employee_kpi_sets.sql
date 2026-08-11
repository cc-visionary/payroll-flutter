-- An employee's stored KPI set becomes the set. Before this, zero rows in
-- employee_kpis meant "tracks the full role set" (see 20260718000005/06), so
-- the stored set and the effective set were different things — and scoring
-- cannot tell "tracks all ten" from "nobody has chosen".
--
-- Materialise today's effective set for everyone who has one, so no person's
-- tracked KPIs change on the day this runs. After it, an empty set genuinely
-- means nobody has chosen, which is what the app now flags as a gap.
--
-- The empty-set fallbacks in generate_employee_review (20260718000006) and in
-- employeesByKpi are DELIBERATELY left in place. Post-backfill they fire only
-- for a genuinely absent set, where falling back is both unchanged from today
-- and safer than generating a review with no KPIs at all.
do $$
declare v_rows int;
begin
  insert into employee_kpis (employee_id, kpi_id)
  select e.id, l.kpi_id
  from employees e
    join role_scorecard_kpis l on l.role_scorecard_id = e.role_scorecard_id
  where e.deleted_at is null
    and e.employment_status = 'ACTIVE'
    and e.role_scorecard_id is not null
    and not exists (
      select 1 from employee_kpis ek where ek.employee_id = e.id
    )
  on conflict (employee_id, kpi_id) do nothing;

  get diagnostics v_rows = row_count;
  raise notice 'explicit KPI sets: % employee_kpis rows materialised', v_rows;
end $$;
