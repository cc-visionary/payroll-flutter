-- Canonical per-task hours and per-person aggregates. security_invoker so base
-- table RLS governs visibility. base = multiplier 1. A task "grows" only when it
-- is driver-bound AND its driver grows; hours_growing_base is those tasks at x1,
-- so any multiplier m projects as hours_fixed + hours_growing_base * m (in Dart).

create view wp_task_computed with (security_invoker = true) as
select
  x.*,
  (x.times_per_month_base * x.minutes_each / 60.0) as hours_per_month_base
from (
  select
    t.id                as task_id,
    t.company_id,
    t.owner_employee_id,
    t.node_id,
    t.skill_tier,
    t.risk,
    (t.times_source = 'driver' and coalesce(d.grows, false)) as is_growing,
    case when t.times_source = 'driver'
         then coalesce(d.value, 0) * t.driver_factor
         else coalesce(t.times_manual, 0) end as times_per_month_base,
    case when t.minutes_source = 'rate'
         then coalesce(r.minutes_each, 0)
         else coalesce(t.minutes_manual, 0) end as minutes_each
  from wp_tasks t
  left join wp_drivers d on d.id = t.driver_id
  left join wp_rates   r on r.id = t.rate_id
) x;

create view wp_person_load with (security_invoker = true) as
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
group by e.id, e.company_id, ov.capacity_hours, cfg.default_capacity_hours, cfg.growth_multiplier;
