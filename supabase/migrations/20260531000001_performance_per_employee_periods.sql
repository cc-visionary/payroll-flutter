-- Support per-employee probationary review periods. The existing
-- check_in_periods table is company-scoped (one period per Q1/Q2/Q3/Q4
-- for the whole company). Probationary reviews are individual milestones
-- tied to each employee's hire_date (month 1, 3, 5 from hire), so we
-- need employee-specific periods alongside the company-wide quarterly ones.

-- Add the three probationary period types to the existing check_in_type enum.
alter type check_in_type add value if not exists 'PROBATION_1M';
alter type check_in_type add value if not exists 'PROBATION_3M';
alter type check_in_type add value if not exists 'PROBATION_5M';

-- Nullable employee FK on the period. Null = company-wide (existing
-- behavior, used for quarterly cycles). Non-null = scoped to that one
-- employee (used for the 3 probationary milestones).
alter table check_in_periods
  add column target_employee_id uuid references employees(id) on delete cascade;

-- Replace the company+name unique with a 3-column unique so company-wide
-- periods (target_employee_id = null) still get a single row per name,
-- AND per-employee periods can reuse names like "Probation 1M" across
-- different employees.
alter table check_in_periods drop constraint check_in_periods_company_id_name_key;
alter table check_in_periods
  add constraint check_in_periods_company_name_target_unique
  unique (company_id, name, target_employee_id);
create index on check_in_periods (target_employee_id);
