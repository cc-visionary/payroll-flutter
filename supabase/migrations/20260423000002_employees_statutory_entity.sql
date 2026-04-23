-- =============================================================================
-- Statutory Employer-of-Record override on employees
-- =============================================================================
--
-- Brand allocation (`employees.hiring_entity_id`) was being reused for two
-- different concerns: which brand a person rolls up to in P&L reports, and
-- which legal entity remits their statutory contributions to the agencies.
--
-- For most staff these match. For a handful — typically people whose work
-- is brand-allocated to one entity but whose SSS / PhilHealth / Pag-IBIG /
-- BIR registration sits with another (e.g. shared-services hires kept on
-- the HQ payroll for compliance simplicity) — the two diverge.
--
-- This migration adds an explicit override column,
-- `employees.statutory_entity_id`, that overrides `hiring_entity_id` only
-- for the statutory views. Brand allocation, payroll grouping, and
-- disbursement export are unchanged — they still read `hiring_entity_id`.
--
-- The two views recreated below (`statutory_payables_due_v` and
-- `statutory_payable_breakdown_v`) keep their output column named
-- `hiring_entity_id` so the Flutter repository / models / screens don't
-- need to change. Internally they now group by
--   coalesce(e.statutory_entity_id, e.hiring_entity_id)
-- and surface that as `hiring_entity_id` in the row shape.
--
-- `statutory_payments_paid_v` is unaffected — payments are written against
-- whichever entity HR chose at remittance time, so the paid totals already
-- key off the correct entity.

-- =============================================================================
-- 1. Add the column + index.
-- =============================================================================
alter table employees
  add column statutory_entity_id uuid
    references hiring_entities(id) on delete restrict;

create index employees_statutory_entity_id_idx
  on employees (statutory_entity_id)
  where statutory_entity_id is not null;

comment on column employees.statutory_entity_id is
  'Override entity for statutory remittance grouping (SSS / PhilHealth / '
  'Pag-IBIG / BIR / employee loans). When NULL, the statutory views fall '
  'back to hiring_entity_id. Brand allocation and disbursement grouping '
  'always use hiring_entity_id regardless of this column.';

-- =============================================================================
-- 2. Recreate statutory_payables_due_v with coalesce(statutory_entity_id,
--    hiring_entity_id) as the grouping key. Output column name is unchanged.
-- =============================================================================
create or replace view statutory_payables_due_v as
with released_payslip as (
  select
    p.id                                          as payslip_id,
    p.employee_id,
    coalesce(e.statutory_entity_id, e.hiring_entity_id) as hiring_entity_id,
    extract(year  from pr.period_end)::smallint   as period_year,
    extract(month from pr.period_end)::smallint   as period_month,
    p.sss_ee, p.sss_er,
    p.philhealth_ee, p.philhealth_er,
    p.pagibig_ee, p.pagibig_er,
    p.withholding_tax
  from payslips p
  join payroll_runs pr on pr.id = p.payroll_run_id and pr.status = 'RELEASED'
  join employees    e  on e.id  = p.employee_id
  where coalesce(e.statutory_entity_id, e.hiring_entity_id) is not null
    and pr.period_end is not null
),
loan_lines as (
  select
    rp.hiring_entity_id,
    rp.period_year,
    rp.period_month,
    rp.payslip_id,
    rp.employee_id,
    sum(pl.amount) as loan_amount
  from released_payslip rp
  join payslip_lines pl on pl.payslip_id = rp.payslip_id
  where pl.category = 'LOAN_DEDUCTION'
  group by rp.hiring_entity_id, rp.period_year, rp.period_month,
           rp.payslip_id, rp.employee_id
)
-- SSS
select
  hiring_entity_id, period_year, period_month,
  'SSS_CONTRIBUTION'::statutory_agency as agency,
  sum(sss_ee + sss_er)::numeric(14,2) as amount_due,
  sum(sss_ee)::numeric(14,2)         as ee_share,
  sum(sss_er)::numeric(14,2)         as er_share,
  count(distinct payslip_id)         as payslip_count,
  count(distinct employee_id)        as employee_count
from released_payslip
group by hiring_entity_id, period_year, period_month
having sum(sss_ee + sss_er) > 0

union all

-- PhilHealth
select
  hiring_entity_id, period_year, period_month,
  'PHILHEALTH_CONTRIBUTION'::statutory_agency,
  sum(philhealth_ee + philhealth_er)::numeric(14,2),
  sum(philhealth_ee)::numeric(14,2),
  sum(philhealth_er)::numeric(14,2),
  count(distinct payslip_id),
  count(distinct employee_id)
from released_payslip
group by hiring_entity_id, period_year, period_month
having sum(philhealth_ee + philhealth_er) > 0

union all

-- Pag-IBIG
select
  hiring_entity_id, period_year, period_month,
  'PAGIBIG_CONTRIBUTION'::statutory_agency,
  sum(pagibig_ee + pagibig_er)::numeric(14,2),
  sum(pagibig_ee)::numeric(14,2),
  sum(pagibig_er)::numeric(14,2),
  count(distinct payslip_id),
  count(distinct employee_id)
from released_payslip
group by hiring_entity_id, period_year, period_month
having sum(pagibig_ee + pagibig_er) > 0

union all

-- BIR (er_share = 0)
select
  hiring_entity_id, period_year, period_month,
  'BIR_WITHHOLDING'::statutory_agency,
  sum(withholding_tax)::numeric(14,2),
  sum(withholding_tax)::numeric(14,2),
  0::numeric(14,2),
  count(distinct payslip_id),
  count(distinct employee_id)
from released_payslip
group by hiring_entity_id, period_year, period_month
having sum(withholding_tax) > 0

union all

-- Employee loans (er_share = 0)
select
  hiring_entity_id, period_year, period_month,
  'EMPLOYEE_LOAN'::statutory_agency,
  sum(loan_amount)::numeric(14,2),
  sum(loan_amount)::numeric(14,2),
  0::numeric(14,2),
  count(distinct payslip_id),
  count(distinct employee_id)
from loan_lines
group by hiring_entity_id, period_year, period_month
having sum(loan_amount) > 0;

comment on view statutory_payables_due_v is
  'Per (entity, period, agency) totals owed, computed from released '
  'payslips. Entity = coalesce(employees.statutory_entity_id, '
  'employees.hiring_entity_id) so an employee whose statutory remittance '
  'is handled by a different brand than their P&L allocation is grouped '
  'with the correct legal entity. Excludes employees where both columns '
  'are NULL.';

-- =============================================================================
-- 3. Recreate statutory_payable_breakdown_v with the same coalesce. Output
--    column name unchanged.
-- =============================================================================
create or replace view statutory_payable_breakdown_v as
with released_payslip as (
  select
    p.id                                          as payslip_id,
    p.employee_id,
    coalesce(e.statutory_entity_id, e.hiring_entity_id) as hiring_entity_id,
    extract(year  from pr.period_end)::smallint   as period_year,
    extract(month from pr.period_end)::smallint   as period_month,
    p.sss_ee, p.sss_er,
    p.philhealth_ee, p.philhealth_er,
    p.pagibig_ee, p.pagibig_er,
    p.withholding_tax
  from payslips p
  join payroll_runs pr on pr.id = p.payroll_run_id and pr.status = 'RELEASED'
  join employees    e  on e.id  = p.employee_id
  where coalesce(e.statutory_entity_id, e.hiring_entity_id) is not null
    and pr.period_end is not null
)
select
  rp.hiring_entity_id,
  rp.period_year,
  rp.period_month,
  'SSS_CONTRIBUTION'::statutory_agency as agency,
  rp.payslip_id,
  rp.employee_id,
  sum(rp.sss_ee)::numeric(14,2)               as ee_share,
  sum(rp.sss_er)::numeric(14,2)               as er_share,
  sum(rp.sss_ee + rp.sss_er)::numeric(14,2)   as total_amount
from released_payslip rp
group by rp.hiring_entity_id, rp.period_year, rp.period_month, rp.payslip_id, rp.employee_id
having sum(rp.sss_ee + rp.sss_er) > 0
union all
select
  rp.hiring_entity_id, rp.period_year, rp.period_month,
  'PHILHEALTH_CONTRIBUTION'::statutory_agency,
  rp.payslip_id, rp.employee_id,
  sum(rp.philhealth_ee)::numeric(14,2),
  sum(rp.philhealth_er)::numeric(14,2),
  sum(rp.philhealth_ee + rp.philhealth_er)::numeric(14,2)
from released_payslip rp
group by rp.hiring_entity_id, rp.period_year, rp.period_month, rp.payslip_id, rp.employee_id
having sum(rp.philhealth_ee + rp.philhealth_er) > 0
union all
select
  rp.hiring_entity_id, rp.period_year, rp.period_month,
  'PAGIBIG_CONTRIBUTION'::statutory_agency,
  rp.payslip_id, rp.employee_id,
  sum(rp.pagibig_ee)::numeric(14,2),
  sum(rp.pagibig_er)::numeric(14,2),
  sum(rp.pagibig_ee + rp.pagibig_er)::numeric(14,2)
from released_payslip rp
group by rp.hiring_entity_id, rp.period_year, rp.period_month, rp.payslip_id, rp.employee_id
having sum(rp.pagibig_ee + rp.pagibig_er) > 0
union all
select
  rp.hiring_entity_id, rp.period_year, rp.period_month,
  'BIR_WITHHOLDING'::statutory_agency,
  rp.payslip_id, rp.employee_id,
  sum(rp.withholding_tax)::numeric(14,2),
  0::numeric(14,2),
  sum(rp.withholding_tax)::numeric(14,2)
from released_payslip rp
group by rp.hiring_entity_id, rp.period_year, rp.period_month, rp.payslip_id, rp.employee_id
having sum(rp.withholding_tax) > 0
union all
select
  rp.hiring_entity_id, rp.period_year, rp.period_month,
  'EMPLOYEE_LOAN'::statutory_agency,
  rp.payslip_id, rp.employee_id,
  sum(pl.amount)::numeric(14,2),
  0::numeric(14,2),
  sum(pl.amount)::numeric(14,2)
from released_payslip rp
join payslip_lines pl on pl.payslip_id = rp.payslip_id and pl.category = 'LOAN_DEDUCTION'
group by rp.hiring_entity_id, rp.period_year, rp.period_month, rp.payslip_id, rp.employee_id
having sum(pl.amount) > 0;

comment on view statutory_payable_breakdown_v is
  'Per (entity, period, agency, payslip) employee-level breakdown. Entity '
  '= coalesce(employees.statutory_entity_id, employees.hiring_entity_id). '
  'Drives the on-screen drawer and the XLSX export.';

-- Re-grant — recreate-or-replace preserves grants for `create or replace`,
-- but be defensive in case the view was dropped + recreated by some prior
-- step.
grant select on statutory_payables_due_v       to authenticated;
grant select on statutory_payable_breakdown_v  to authenticated;
