-- Contributors carry hours too. The step-4 view filtered assignment_role =
-- 'PRIMARY', which was correct only while PRIMARY was the sole row type; the
-- spec's own worked example has a CONTRIBUTOR at 40%. Drop the predicate from
-- both legs so every assignment's allocation_pct is attributed. This also makes
-- the fallback CTE correct: a task with only a CONTRIBUTOR is now attributed
-- through `assigned` instead of vanishing from load.
--
-- Output columns are unchanged. Numerically inert today: every existing row is a
-- PRIMARY @100, so the same rows are selected as before (parity-checked).
create or replace view wp_person_load with (security_invoker = true) as
with holders as (
  select e.id as employee_id, e.role_scorecard_id,
         count(*) over (partition by e.role_scorecard_id) as holder_count
  from employees e
  where e.employment_status = 'ACTIVE' and e.deleted_at is null
    and e.role_scorecard_id is not null
),
assigned as (
  select a.employee_id, tc.task_id,
         tc.hours_per_month_base * a.allocation_pct / 100.0 as hours, tc.is_growing
  from wp_task_computed tc
  join wp_task_assignments a
    on a.task_id = tc.task_id and a.employee_id is not null
  union all
  select h.employee_id, tc.task_id,
         tc.hours_per_month_base * a.allocation_pct / 100.0 / h.holder_count, tc.is_growing
  from wp_task_computed tc
  join wp_task_assignments a
    on a.task_id = tc.task_id and a.role_scorecard_id is not null
  join holders h on h.role_scorecard_id = a.role_scorecard_id
),
fallback as (
  select tc.owner_employee_id as employee_id, tc.task_id,
         tc.hours_per_month_base as hours, tc.is_growing
  from wp_task_computed tc
  where tc.owner_employee_id is not null
    and not exists (select 1 from wp_task_assignments a where a.task_id = tc.task_id)
  union all
  select h.employee_id, tc.task_id,
         tc.hours_per_month_base / h.holder_count, tc.is_growing
  from wp_task_computed tc
  join wp_tasks t on t.id = tc.task_id
  join holders  h on h.role_scorecard_id = t.role_scorecard_id
  where tc.owner_employee_id is null and t.role_scorecard_id is not null
    and not exists (select 1 from wp_task_assignments a where a.task_id = tc.task_id)
),
attributed as (
  select * from assigned
  union all
  select * from fallback
)
select
  e.id         as employee_id,
  e.company_id,
  count(a.task_id) as tasks_owned,
  coalesce(sum(a.hours) filter (where not a.is_growing), 0) as hours_fixed,
  coalesce(sum(a.hours) filter (where a.is_growing), 0)     as hours_growing_base,
  coalesce(ov.capacity_hours, cfg.default_capacity_hours, 160) as capacity_hours,
  coalesce(cfg.growth_multiplier, 1) as growth_multiplier
from employees e
left join attributed            a   on a.employee_id = e.id
left join wp_capacity_overrides ov  on ov.employee_id = e.id
left join wp_config             cfg on cfg.company_id = e.company_id
where e.employment_status = 'ACTIVE' and e.deleted_at is null
group by e.id, e.company_id, ov.capacity_hours, cfg.default_capacity_hours, cfg.growth_multiplier;

-- Deferred from step 4: keep updated_at fresh once rows start being UPDATEd
-- (the % editor is the first thing that UPDATEs them).
create trigger _wp_task_assignments_updated before update on wp_task_assignments
  for each row execute function set_updated_at();
