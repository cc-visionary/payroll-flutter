-- Direct-hours workload: a plain hours/month figure that wins over the
-- times x minutes driver calc.
--
-- HRCI's own model for "how much work" is a plain estimatedHours figure; the
-- times x minutes x driver machinery is this app's addition for volume work.
-- Making the simple field the default is what removes the editing friction.
--
-- A task is EITHER direct-hours OR driver-calc: when hours_per_month is set the
-- driver/rate columns are ignored (and nulled on write by the app). A
-- direct-hours task is flat -- it never responds to the growth multiplier,
-- because a manual number does not scale with volume.

alter table wp_tasks
  add column if not exists hours_per_month numeric
    check (hours_per_month is null or hours_per_month >= 0);

comment on column wp_tasks.hours_per_month is
  'Direct monthly-hours figure. When set it is the workload and wins over the '
  'times x minutes driver calc; the driver/rate columns are then ignored.';

-- Re-point the one place that turns a task into hours. Output columns are
-- unchanged in name/order/type, so wp_person_load needs no change. The outer
-- column list is written explicitly (not x.*) so the added inner column does
-- not shift the output shape.
create or replace view wp_task_computed with (security_invoker = true) as
select
  x.task_id,
  x.company_id,
  x.owner_employee_id,
  x.node_id,
  x.skill_tier,
  x.risk,
  x.is_growing,
  x.times_per_month_base,
  x.minutes_each,
  case when x.direct_hours is not null
       then x.direct_hours
       else x.times_per_month_base * x.minutes_each / 60.0 end as hours_per_month_base
from (
  select
    t.id                as task_id,
    t.company_id,
    t.owner_employee_id,
    t.node_id,
    t.skill_tier,
    t.risk,
    t.hours_per_month   as direct_hours,
    -- A direct-hours task is never growing: only a driver-bound, growing task
    -- (with no direct figure overriding it) responds to the multiplier.
    (t.hours_per_month is null
       and t.times_source = 'driver'
       and coalesce(d.grows, false)) as is_growing,
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
