-- The ingestion boundary: where manually-reported KPI data lands. Results
-- (kpi_results, 20260814000004) are DERIVED and never hand-written; these two
-- tables are the raw material the compute engine (Task 7) reads to derive
-- them.
--
-- Two shapes, deliberately not one table behind a `kind` column:
--   kpi_exceptions -- one occurrence: a purchasing error, a confirmed
--     fulfillment error, a piece of technical rework. (kpi, subject,
--     occurred_on, quantity, note).
--   kpi_readings   -- a number someone counted for a whole period: "8 of 10
--     campaigns on time this month". (kpi, scope, period, numerator,
--     denominator, note).
--
-- `reported_via` and `external_ref` exist on both from day one even though
-- only one surface (the app) will ever write them at first -- provenance
-- cannot be retrofitted onto rows already collected. A future Lark sync
-- would be another caller of the same repository methods, matching
-- supabase/functions/sync-lark-self-evals, using external_ref to make a
-- re-sync idempotent.

create table if not exists kpi_exceptions (
  id            uuid primary key default gen_random_uuid(),
  company_id    uuid not null references companies(id) on delete cascade,
  kpi_id        uuid not null references kpis(id) on delete cascade,
  employee_id   uuid references employees(id) on delete cascade,
  department_id uuid references departments(id) on delete cascade,
  occurred_on   date not null,
  quantity      numeric not null default 1,
  note          text,
  reported_by   uuid references users(id) on delete set null,
  reported_via  text not null default 'APP' check (reported_via in ('APP','LARK')),
  external_ref  text,
  confirmed_at  timestamptz,
  confirmed_by  uuid references users(id) on delete set null,
  created_at    timestamptz not null default now()
);

-- A Lark re-sync resubmitting the same source record must not double-count
-- the exception. Partial (WHERE external_ref is not null) so app-entered
-- rows, which never carry one, are never forced to collide.
create unique index if not exists kpi_exceptions_external_ref
  on kpi_exceptions (kpi_id, external_ref)
  where external_ref is not null;

create index if not exists kpi_exceptions_kpi_period
  on kpi_exceptions (kpi_id, occurred_on);
create index if not exists kpi_exceptions_employee
  on kpi_exceptions (employee_id, occurred_on);

create table if not exists kpi_readings (
  id            uuid primary key default gen_random_uuid(),
  company_id    uuid not null references companies(id) on delete cascade,
  kpi_id        uuid not null references kpis(id) on delete cascade,
  period        text not null,
  scope         text not null check (scope in ('PERSONAL','DEPARTMENT','COMPANY')),
  employee_id   uuid references employees(id) on delete cascade,
  department_id uuid references departments(id) on delete cascade,
  numerator     numeric,
  denominator   numeric,
  note          text,
  reported_by   uuid references users(id) on delete set null,
  reported_via  text not null default 'APP' check (reported_via in ('APP','LARK')),
  external_ref  text,
  created_at    timestamptz not null default now()
);

-- Same coalesce-based identity as kpi_results (20260814000004): Postgres
-- treats NULLs as distinct in a unique index, so a plain unique constraint
-- over the nullable scope columns would allow unlimited duplicate COMPANY
-- rows. This is a functional (expression) index -- PostgREST's `onConflict`
-- cannot target it, so the Dart repository must find-then-insert/update
-- here too, exactly as KpiResultRepository.upsertAll already does.
create unique index if not exists kpi_readings_identity
  on kpi_readings (
    kpi_id, period, scope,
    coalesce(employee_id, '00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(department_id, '00000000-0000-0000-0000-000000000000'::uuid)
  );

create index if not exists kpi_readings_period on kpi_readings (company_id, period);
create index if not exists kpi_readings_employee on kpi_readings (employee_id, period);

alter table kpi_exceptions enable row level security;
alter table kpi_readings enable row level security;

-- Read and write for SUPER_ADMIN/ADMIN/HR/HR_ADMIN (via auth_is_hr_or_admin(),
-- 20260423000004_rls_recognize_new_roles.sql -- not a hardcoded role list,
-- which would silently exclude PAYROLL_ADMIN/FINANCE_MANAGER today and drift
-- again the next time an admin-ish role is added), company-scoped, plus a
-- manager for their own reports on rows that name an employee.
--
-- Deliberately NOT employee_kpis's shape (20260718000005): that table's
-- policies let an employee read AND write their own row (`employee_id =
-- auth_employee_id()`), which fits a per-employee KPI *assignment* an
-- employee may reasonably see. It is wrong here -- an exception or a period
-- reading is a report ABOUT someone, not something of theirs to read or
-- edit, so no self clause appears in either policy below. Only HR/admin and
-- that person's manager can see or touch these rows.
drop policy if exists kpi_exceptions_read on kpi_exceptions;
create policy kpi_exceptions_read on kpi_exceptions for select using (
  (auth_is_hr_or_admin() and company_id = auth_company_id())
  or (
    employee_id is not null
    and exists (
      select 1 from employees e
      where e.id = employee_id and e.reports_to_id = auth_employee_id()
    )
  )
);

drop policy if exists kpi_exceptions_write on kpi_exceptions;
create policy kpi_exceptions_write on kpi_exceptions for all
  using (
    (auth_is_hr_or_admin() and company_id = auth_company_id())
    or (
      employee_id is not null
      and exists (
        select 1 from employees e
        where e.id = employee_id and e.reports_to_id = auth_employee_id()
      )
    )
  )
  with check (
    (auth_is_hr_or_admin() and company_id = auth_company_id())
    or (
      employee_id is not null
      and exists (
        select 1 from employees e
        where e.id = employee_id and e.reports_to_id = auth_employee_id()
      )
    )
  );

drop policy if exists kpi_readings_read on kpi_readings;
create policy kpi_readings_read on kpi_readings for select using (
  (auth_is_hr_or_admin() and company_id = auth_company_id())
  or (
    employee_id is not null
    and exists (
      select 1 from employees e
      where e.id = employee_id and e.reports_to_id = auth_employee_id()
    )
  )
);

drop policy if exists kpi_readings_write on kpi_readings;
create policy kpi_readings_write on kpi_readings for all
  using (
    (auth_is_hr_or_admin() and company_id = auth_company_id())
    or (
      employee_id is not null
      and exists (
        select 1 from employees e
        where e.id = employee_id and e.reports_to_id = auth_employee_id()
      )
    )
  )
  with check (
    (auth_is_hr_or_admin() and company_id = auth_company_id())
    or (
      employee_id is not null
      and exists (
        select 1 from employees e
        where e.id = employee_id and e.reports_to_id = auth_employee_id()
      )
    )
  );
