-- Accountability attributes: criticality (HRCI prioritiser / ADA "importance"),
-- is_essential (ADA essential-function flag), and status (ACTIVE/ARCHIVED
-- lifecycle). Archived work drops out of load and every derived list but stays
-- for reference and can be restored -- deleting a row that carries history is
-- the wrong tool, archiving is the right one.

alter table wp_tasks
  add column if not exists criticality text
    check (criticality is null or criticality in ('LOW','MEDIUM','HIGH','CRITICAL'));

alter table wp_tasks
  add column if not exists is_essential boolean not null default true;

alter table wp_tasks
  add column if not exists status text not null default 'ACTIVE'
    check (status in ('ACTIVE','ARCHIVED'));

comment on column wp_tasks.criticality is
  'Business criticality LOW..CRITICAL. The ADA essential-function test''s '
  '"importance" leg; answers "does the business stop if this fails".';
comment on column wp_tasks.is_essential is
  'ADA essential-function flag: work that is a reason the role exists, vs a '
  'catch-all. An expectation is by definition non-essential (see the '
  'wp_tasks_expectation_non_essential constraint).';
comment on column wp_tasks.status is
  'ACTIVE or ARCHIVED. ARCHIVED work is excluded from wp_task_computed (so it '
  'leaves load, derived task lists and the duplicate check) but is retained.';

-- An expectation is a non-essential catch-all: reconcile existing rows BEFORE
-- adding the constraint, or the pre-existing expectation rows (is_essential
-- defaulted true) would violate it.
update wp_tasks set is_essential = false where coalesce(is_expectation, false);

alter table wp_tasks
  add constraint wp_tasks_expectation_non_essential
  check (not (coalesce(is_expectation, false) and is_essential));

-- Re-point wp_task_computed to skip ARCHIVED rows. Output columns are unchanged
-- in name/order/type, so the dependent wp_person_load view needs no change; only
-- the row set shrinks (archived tasks stop contributing hours and stop appearing
-- in anyone's derived task list).
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
  where t.status = 'ACTIVE'
) x;
