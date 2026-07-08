-- 20260708000001_compensation_changes.sql
--
-- Per-employee, effective-dated source of truth for an individual's pay/role.
-- role_scorecards.base_salary stays as the role's reference/band; payroll
-- resolves the current effective compensation_changes row and falls back to
-- the scorecard when none exists (see compute_service.dart). Text+check
-- columns (not new enum types) — mirrors the job_listings.status idiom.

create table compensation_changes (
  id                  uuid primary key default gen_random_uuid(),
  company_id          uuid not null references companies(id),
  employee_id         uuid not null references employees(id),
  change_type         text not null
    check (change_type in ('SALARY_INCREASE','SALARY_DECREASE','PROMOTION','LATERAL_TRANSFER','DEMOTION')),
  status              text not null default 'SCHEDULED'
    check (status in ('SCHEDULED','APPLIED','CANCELLED')),
  effective_date      date not null,
  prev_base_salary    numeric(14,2),
  new_base_salary     numeric(14,2),
  prev_wage_type      text check (prev_wage_type in ('MONTHLY','DAILY','HOURLY')),
  new_wage_type       text check (new_wage_type in ('MONTHLY','DAILY','HOURLY')),
  prev_scorecard_id   uuid references role_scorecards(id),
  new_scorecard_id    uuid references role_scorecards(id),
  reason              text not null default '',
  workflow_id         uuid references workflow_instances(id),
  document_id         uuid references employee_documents(id),
  initiated_by_id     uuid not null references users(id),
  applied_at          timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  deleted_at          timestamptz
);

-- Payroll resolver lookup: newest effective row per employee.
create index idx_comp_changes_employee_effective
  on compensation_changes (employee_id, effective_date)
  where deleted_at is null;

-- "apply due" sweep: scheduled rows past their effective date.
create index idx_comp_changes_status
  on compensation_changes (status)
  where deleted_at is null;

create index idx_comp_changes_workflow
  on compensation_changes (workflow_id)
  where workflow_id is not null;

create trigger _compensation_changes_updated before update on compensation_changes
  for each row execute function set_updated_at();

-- RLS — mirrors job_listings (company-scoped + role-gated).
alter table compensation_changes enable row level security;

create policy compensation_changes_company_select on compensation_changes for select
  using (company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN');

create policy compensation_changes_company_write on compensation_changes for all
  using (
    (company_id = auth_company_id() and auth_app_role() in ('ADMIN', 'HR'))
    or auth_app_role() = 'SUPER_ADMIN'
  )
  with check (
    (company_id = auth_company_id() and auth_app_role() in ('ADMIN', 'HR'))
    or auth_app_role() = 'SUPER_ADMIN'
  );
