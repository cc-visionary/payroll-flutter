-- wp_person_load filtered only on employment_status = 'ACTIVE' and ignored the
-- soft-delete column, so an archived employee (deleted_at set, status still
-- ACTIVE) was still returned. The app's employee list excludes soft-deleted
-- rows, so that person had no name to join against and the Balance tab
-- rendered their raw UUID with an em-dash role.
--
-- Add `e.deleted_at is null` to match how the rest of the app defines "active".
-- Column list/order is unchanged, so CREATE OR REPLACE is valid.

create or replace view wp_person_load with (security_invoker = true) as
select
  e.id         as employee_id,
  e.company_id,
  count(tc.task_id) as tasks_owned,
  coalesce(sum(tc.hours_per_month_base) filter (where not tc.is_growing), 0) as hours_fixed,
  coalesce(sum(tc.hours_per_month_base) filter (where tc.is_growing), 0)     as hours_growing_base,
  coalesce(ov.capacity_hours, cfg.default_capacity_hours, 160) as capacity_hours,
  coalesce(cfg.growth_multiplier, 1) as growth_multiplier
from employees e
left join wp_task_computed      tc  on tc.owner_employee_id = e.id
left join wp_capacity_overrides ov  on ov.employee_id = e.id
left join wp_config             cfg on cfg.company_id = e.company_id
where e.employment_status = 'ACTIVE'
  and e.deleted_at is null
group by e.id, e.company_id, ov.capacity_hours, cfg.default_capacity_hours, cfg.growth_multiplier;
