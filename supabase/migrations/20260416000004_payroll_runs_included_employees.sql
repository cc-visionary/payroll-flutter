-- Add included_employee_ids to payroll_runs for employee-scoped runs.
--
-- When the user creates a new payroll run via the "New Payroll Run" dialog,
-- they pick which employees to include (usually those with attendance in the
-- pay period). That selection is persisted here so the compute engine can
-- filter to just those employees on each recompute.
--
-- Semantics:
--   NULL  → compute for all active employees of the company (legacy path)
--   []    → same as NULL (no-op — shouldn't normally happen)
--   [...] → compute only for employees whose id ∈ included_employee_ids
alter table payroll_runs
  add column included_employee_ids uuid[];

comment on column payroll_runs.included_employee_ids is
  'Optional scope filter — when non-null, the compute engine only processes '
  'employees whose ids are in this array. NULL = all active employees.';
