-- Results are DERIVED. Every column here is reproducible from inputs plus a
-- KPI definition, which is why manual entry lives in kpi_readings instead:
-- anything hand-written into this table would be destroyed by the next
-- recompute, or would force the recompute to guess which rows are safe.

create table if not exists kpi_results (
  id                  uuid primary key default gen_random_uuid(),
  company_id          uuid not null references companies(id) on delete cascade,
  kpi_id              uuid not null references kpis(id) on delete cascade,
  period              text not null,
  scope               text not null check (scope in ('PERSONAL','DEPARTMENT','COMPANY')),
  employee_id         uuid references employees(id) on delete cascade,
  department_id       uuid references departments(id) on delete cascade,
  numerator           numeric,
  denominator         numeric,
  value               numeric,
  target_snapshot     numeric,
  target_max_snapshot numeric,
  direction_snapshot  text check (direction_snapshot is null or direction_snapshot in ('GTE','LTE','EQ','BETWEEN')),
  status              text not null check (status in ('ON_TRACK','OFF_TRACK','NO_DATA')),
  source_completeness text not null default 'COMPLETE'
    check (source_completeness in ('COMPLETE','MISSING_SOURCE')),
  computed_at         timestamptz not null default now(),
  created_at          timestamptz not null default now()
);

-- Postgres treats NULLs as distinct in a unique index, so a plain unique
-- constraint over the nullable scope columns would allow unlimited duplicate
-- COMPANY rows. coalesce to a fixed uuid to make the key total.
--
-- This is a functional (expression) index. PostgREST's `onConflict` can only
-- name a plain unique constraint or index by its column list, not an
-- expression index — so the Dart repository CANNOT use `.upsert(...,
-- onConflict: '...')` against this table. See KpiResultRepository.upsertAll,
-- which reads the period's rows once and does find-then-insert/update
-- instead. role_scorecard_repository.dart hit this exact trap first, on the
-- kpis library-name index.
create unique index if not exists kpi_results_identity
  on kpi_results (
    kpi_id, period, scope,
    coalesce(employee_id, '00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(department_id, '00000000-0000-0000-0000-000000000000'::uuid)
  );

create index if not exists kpi_results_period on kpi_results (company_id, period);
create index if not exists kpi_results_employee on kpi_results (employee_id, period);

alter table kpi_results enable row level security;

-- Company-wide read: a scorecard everyone can see is the point of a cascade.
-- Personal rows are the exception -- an employee's own number is theirs and
-- their manager's, not the company's.
drop policy if exists kpi_results_read on kpi_results;
create policy kpi_results_read on kpi_results for select using (
  company_id = auth_company_id()
  and (
    scope <> 'PERSONAL'
    or auth_is_performance_admin_for_employee(employee_id)
    or employee_id = auth_employee_id()
    or exists (
      select 1 from employees e
      where e.id = employee_id and e.reports_to_id = auth_employee_id()
    )
  )
);

-- Writes come from the compute service, run by HR/admin.
--
-- auth_is_hr_or_admin() (20260423000004_rls_recognize_new_roles.sql), not an
-- inline ('SUPER_ADMIN','ADMIN','HR','HR_ADMIN') list: a hardcoded list here
-- would silently exclude PAYROLL_ADMIN/FINANCE_MANAGER today and drift again
-- the next time an admin-ish role is added, the same failure
-- 20260423000004 and role_outcomes (20260814000002) were written to prevent.
drop policy if exists kpi_results_write on kpi_results;
create policy kpi_results_write on kpi_results for all
  using (auth_is_hr_or_admin() and company_id = auth_company_id())
  with check (auth_is_hr_or_admin() and company_id = auth_company_id());
