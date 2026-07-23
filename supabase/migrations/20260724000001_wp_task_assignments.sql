-- Shared accountability: a task's ownership becomes first-class assignment rows.
-- One PRIMARY (Accountable) per task; CONTRIBUTORs (Responsible) added later.
-- A row targets EITHER a role card (the position) OR a specific employee (the
-- exception override) -- exactly one, enforced by one_target.

create table wp_task_assignments (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null references companies(id) on delete cascade,
  task_id           uuid not null references wp_tasks(id) on delete cascade,
  role_scorecard_id uuid references role_scorecards(id) on delete cascade,
  employee_id       uuid references employees(id) on delete cascade,
  assignment_role   text not null default 'CONTRIBUTOR'
                    check (assignment_role in ('PRIMARY','CONTRIBUTOR')),
  allocation_pct    numeric not null default 0
                    check (allocation_pct >= 0 and allocation_pct <= 100),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint one_target check ((role_scorecard_id is null) != (employee_id is null))
);

create unique index wp_task_assignments_card
  on wp_task_assignments (task_id, role_scorecard_id) where role_scorecard_id is not null;
create unique index wp_task_assignments_person
  on wp_task_assignments (task_id, employee_id) where employee_id is not null;
-- At most one PRIMARY per task.
create unique index wp_task_assignments_one_primary
  on wp_task_assignments (task_id) where assignment_role = 'PRIMARY';
create index wp_task_assignments_task on wp_task_assignments (task_id);

-- RLS: company-scoped read; SUPER_ADMIN/ADMIN/HR write (mirrors wp_tasks).
alter table wp_task_assignments enable row level security;
create policy wp_task_assignments_select on wp_task_assignments for select
  using (company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN');
create policy wp_task_assignments_write on wp_task_assignments for all
  using (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR')
         and (company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN'))
  with check (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR')
         and (company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN'));

-- Backfill: current ownership -> exactly one PRIMARY assignment @100%.
-- (a) explicit owner -> person PRIMARY. Idempotent via NOT EXISTS + the
--     one_primary index. Covers all statuses so a restored task keeps it.
insert into wp_task_assignments (company_id, task_id, employee_id, assignment_role, allocation_pct)
select t.company_id, t.id, t.owner_employee_id, 'PRIMARY', 100
from wp_tasks t
where t.owner_employee_id is not null
  and not exists (select 1 from wp_task_assignments a
                  where a.task_id = t.id and a.assignment_role = 'PRIMARY');

-- (b) no owner, has a card -> card PRIMARY.
insert into wp_task_assignments (company_id, task_id, role_scorecard_id, assignment_role, allocation_pct)
select t.company_id, t.id, t.role_scorecard_id, 'PRIMARY', 100
from wp_tasks t
where t.owner_employee_id is null and t.role_scorecard_id is not null
  and not exists (select 1 from wp_task_assignments a
                  where a.task_id = t.id and a.assignment_role = 'PRIMARY');

comment on table wp_task_assignments is
  'First-class accountability assignments. One PRIMARY per task; targets a role '
  'card OR an employee. allocation_pct scales the task hours in wp_person_load.';
