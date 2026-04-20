-- 13th Month Pay accrual + distribution flag
--
-- employees.accrued_thirteenth_month_basis : running sum of BASIC_PAY earned
-- since the employee's last 13th-month distribution. Ticks up on each
-- payroll release, zeroes when a distribution pays them out.
--
-- payroll_runs.is_thirteenth_month_distribution : marks the run where HR
-- clicked "Distribute 13th Month" so reports / exports can filter.

alter table employees
  add column if not exists accrued_thirteenth_month_basis
    numeric(12,2) not null default 0;

alter table payroll_runs
  add column if not exists is_thirteenth_month_distribution
    boolean not null default false;
