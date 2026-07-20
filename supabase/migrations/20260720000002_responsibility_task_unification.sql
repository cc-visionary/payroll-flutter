-- !! SINGLE-APPLY ONLY !!
-- Promotion is idempotent only against UNEDITED rows: the NOT EXISTS check keys on
-- the CURRENT (area, name). If a promoted responsibility is renamed in the app and
-- this file is re-applied (manual psql / DR replay / reused as a template), the
-- check misses the original name and re-inserts a DUPLICATE — both rows then count
-- toward the role's hours and silently inflate load. Supabase's migration ledger
-- runs this once per environment; never re-run it by hand after go-live.

-- Unify role-card responsibilities with wp_tasks: a responsibility IS a task.
-- 1) ordering columns (the card PDF + contract prefill render in authored order)
-- 2) promote EVERY card's (active or not) key_responsibilities into wp_tasks
--    (uncosted) — an inactive/superseded card still needs its Annex A to
--    resolve (payslip PDFs, dashboards, and employment contracts all read
--    inactive cards via list(onlyActive: false)/byId()), and
--    RoleScorecard.fromRow treats a present-but-empty wp_tasks embed as
--    authoritative, so promoting only active cards would leave every
--    inactive card's responsibilities permanently empty.
-- 3) wp_person_load attributes hours: explicit owner -> else split across role
--    holders -> else unattributed. Column list is UNCHANGED so Dart is unaffected.

alter table wp_tasks
  add column if not exists area_sort int not null default 0,
  add column if not exists task_sort int not null default 0;

-- Promotion. Idempotent on (role_scorecard_id, lower(trim(area)), lower(trim(name))).
do $$
declare c record; a jsonb; t jsonb; ai int; ti int;
begin
  for c in select id, company_id, key_responsibilities from role_scorecards loop
    ai := 0;
    for a in select * from jsonb_array_elements(coalesce(c.key_responsibilities, '[]'::jsonb)) loop
      ti := 0;
      for t in select * from jsonb_array_elements(coalesce(a->'tasks', '[]'::jsonb)) loop
        insert into wp_tasks (company_id, name, role_scorecard_id, responsibility_area,
                              area_sort, task_sort, times_source, minutes_source)
        select c.company_id, trim(t #>> '{}'), c.id, trim(a->>'area'), ai, ti, 'manual', 'manual'
        where trim(coalesce(t #>> '{}', '')) <> ''
          and not exists (
            select 1 from wp_tasks w
            where w.role_scorecard_id = c.id
              and lower(trim(coalesce(w.responsibility_area, ''))) = lower(trim(coalesce(a->>'area', '')))
              and lower(trim(w.name)) = lower(trim(t #>> '{}'))
          );
        ti := ti + 1;
      end loop;
      ai := ai + 1;
    end loop;
  end loop;
end $$;

-- Attribution rewrite.
create or replace view wp_person_load with (security_invoker = true) as
with holders as (
  select e.id as employee_id, e.role_scorecard_id,
         count(*) over (partition by e.role_scorecard_id) as holder_count
  from employees e
  where e.employment_status = 'ACTIVE' and e.deleted_at is null
    and e.role_scorecard_id is not null
),
attributed as (
  -- explicit owner carries the full hours
  select tc.owner_employee_id as employee_id, tc.task_id,
         tc.hours_per_month_base as hours, tc.is_growing
  from wp_task_computed tc
  where tc.owner_employee_id is not null
  union all
  -- else split evenly across the holders of the task's role card
  select h.employee_id, tc.task_id,
         tc.hours_per_month_base / h.holder_count, tc.is_growing
  from wp_task_computed tc
  join wp_tasks t on t.id = tc.task_id
  join holders  h on h.role_scorecard_id = t.role_scorecard_id
  where tc.owner_employee_id is null and t.role_scorecard_id is not null
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
