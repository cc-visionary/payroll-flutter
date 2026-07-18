-- Phase 2 of KPI tracking: per-employee subset of their role card's KPIs.
-- No target/frequency here — those live on role_scorecard_kpis. Zero rows for an
-- employee means "tracked on the full role set" (see generate_employee_review).

create table employee_kpis (
  id           uuid primary key default gen_random_uuid(),
  employee_id  uuid not null references employees(id) on delete cascade,
  kpi_id       uuid not null references kpis(id) on delete cascade,
  created_at   timestamptz not null default now(),
  unique (employee_id, kpi_id)
);
create index employee_kpis_employee on employee_kpis (employee_id);
create index employee_kpis_kpi on employee_kpis (kpi_id);

alter table employee_kpis enable row level security;
create policy employee_kpis_read on employee_kpis for select using (
  auth_is_performance_admin_for_employee(employee_id)
  or employee_id = auth_employee_id()
  or exists (
    select 1 from employees e
    where e.id = employee_id and e.reports_to_id = auth_employee_id()
  )
);
create policy employee_kpis_write on employee_kpis for all
  using (auth_is_performance_admin_for_employee(employee_id))
  with check (auth_is_performance_admin_for_employee(employee_id));
