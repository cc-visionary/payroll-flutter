-- Role-first task allocation (spec 2026-09-28-simple-task-allocation-design.md).
-- Every task belongs to exactly one role; its hours split across the role's
-- ACTIVE holders in proportion to capacity. owner_employee_id and
-- wp_task_assignments are KEPT (rollback = restore 20260724000003's view) but
-- no longer read by wp_person_load.

alter table wp_tasks add column if not exists allocation_review_note text;

-- 1) Tasks with assignment rows: resolve to ONE role.
with ranked as (
  select distinct on (a.task_id)
         a.task_id,
         coalesce(a.role_scorecard_id, e.role_scorecard_id) as role_id,
         count(*) over (partition by a.task_id)            as n_rows
  from wp_task_assignments a
  left join employees e on e.id = a.employee_id
  order by a.task_id,
           (a.assignment_role = 'PRIMARY') desc,
           a.allocation_pct desc
),
was as (
  select a.task_id,
         'was: ' || string_agg(
           coalesce(rs.job_title, e.first_name || ' ' || e.last_name, '?')
             || ' ' || round(a.allocation_pct)::text || '%',
           ', ' order by a.allocation_pct desc) as note
  from wp_task_assignments a
  left join role_scorecards rs on rs.id = a.role_scorecard_id
  left join employees       e  on e.id  = a.employee_id
  group by a.task_id
)
update wp_tasks t
set role_scorecard_id = coalesce(r.role_id, t.role_scorecard_id),
    allocation_review_note = case
      when r.n_rows > 1
        or r.role_id is null
        or r.role_id is distinct from t.role_scorecard_id
      then w.note end
from ranked r
join was w on w.task_id = r.task_id
where t.id = r.task_id
  and t.status = 'ACTIVE';

-- 2) No assignment rows, no role, but an explicit owner: take the owner's role.
update wp_tasks t
set role_scorecard_id = e.role_scorecard_id,
    allocation_review_note = case when e.role_scorecard_id is null
      then 'was: owned by ' || e.first_name || ' ' || e.last_name
           || ' (who has no role)' end
from employees e
where e.id = t.owner_employee_id
  and t.role_scorecard_id is null
  and t.status = 'ACTIVE'
  and not exists (select 1 from wp_task_assignments a where a.task_id = t.id);

-- 3) wp_person_load: role only, capacity-weighted.
create or replace view wp_person_load with (security_invoker = true) as
with holders as (
  select e.id as employee_id, e.company_id, e.role_scorecard_id,
         coalesce(ov.capacity_hours, cfg.default_capacity_hours, 160) as cap
  from employees e
  left join wp_capacity_overrides ov  on ov.employee_id = e.id
  left join wp_config             cfg on cfg.company_id = e.company_id
  where e.employment_status = 'ACTIVE' and e.deleted_at is null
    and e.role_scorecard_id is not null
),
role_cap as (
  select role_scorecard_id, sum(cap) as total_cap
  from holders group by role_scorecard_id
),
attributed as (
  select h.employee_id, tc.task_id,
         tc.hours_per_month_base * h.cap / rc.total_cap as hours,
         tc.is_growing
  from wp_task_computed tc
  join wp_tasks t   on t.id = tc.task_id
  join holders  h   on h.role_scorecard_id = t.role_scorecard_id
  join role_cap rc  on rc.role_scorecard_id = h.role_scorecard_id
  where rc.total_cap > 0
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
