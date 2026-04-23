-- =============================================================================
-- Collapse statutory_payable_breakdown_v rows from per-payslip to per-employee
-- =============================================================================
--
-- The previous shape grouped by (entity, year, month, agency, payslip_id,
-- employee_id) which produced one row per cutoff per employee. For
-- semi-monthly payroll that meant every employee appeared TWICE in the
-- breakdown drawer and the XLSX export sheet — visually noisy and not how
-- PH HR actually files (R-3 / RF-1 / M1-1 are per-employee monthly totals).
--
-- This recreates the view to group by employee_id only, summing across all
-- payslips in the month. Loan rows still join `payslip_lines` but aggregate
-- across both cutoffs into a single per-employee row.
--
-- The column shape stays identical EXCEPT `payslip_id` is removed. The Dart
-- model `StatutoryPayableBreakdownRow` was updated in the same change so the
-- repository keeps parsing rows correctly.

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
-- SSS
select
  rp.hiring_entity_id,
  rp.period_year,
  rp.period_month,
  'SSS_CONTRIBUTION'::statutory_agency as agency,
  rp.employee_id,
  sum(rp.sss_ee)::numeric(14,2)             as ee_share,
  sum(rp.sss_er)::numeric(14,2)             as er_share,
  sum(rp.sss_ee + rp.sss_er)::numeric(14,2) as total_amount
from released_payslip rp
group by rp.hiring_entity_id, rp.period_year, rp.period_month, rp.employee_id
having sum(rp.sss_ee + rp.sss_er) > 0

union all

-- PhilHealth
select
  rp.hiring_entity_id, rp.period_year, rp.period_month,
  'PHILHEALTH_CONTRIBUTION'::statutory_agency,
  rp.employee_id,
  sum(rp.philhealth_ee)::numeric(14,2),
  sum(rp.philhealth_er)::numeric(14,2),
  sum(rp.philhealth_ee + rp.philhealth_er)::numeric(14,2)
from released_payslip rp
group by rp.hiring_entity_id, rp.period_year, rp.period_month, rp.employee_id
having sum(rp.philhealth_ee + rp.philhealth_er) > 0

union all

-- Pag-IBIG
select
  rp.hiring_entity_id, rp.period_year, rp.period_month,
  'PAGIBIG_CONTRIBUTION'::statutory_agency,
  rp.employee_id,
  sum(rp.pagibig_ee)::numeric(14,2),
  sum(rp.pagibig_er)::numeric(14,2),
  sum(rp.pagibig_ee + rp.pagibig_er)::numeric(14,2)
from released_payslip rp
group by rp.hiring_entity_id, rp.period_year, rp.period_month, rp.employee_id
having sum(rp.pagibig_ee + rp.pagibig_er) > 0

union all

-- BIR (er_share = 0)
select
  rp.hiring_entity_id, rp.period_year, rp.period_month,
  'BIR_WITHHOLDING'::statutory_agency,
  rp.employee_id,
  sum(rp.withholding_tax)::numeric(14,2),
  0::numeric(14,2),
  sum(rp.withholding_tax)::numeric(14,2)
from released_payslip rp
group by rp.hiring_entity_id, rp.period_year, rp.period_month, rp.employee_id
having sum(rp.withholding_tax) > 0

union all

-- Employee loans (er_share = 0)
select
  rp.hiring_entity_id, rp.period_year, rp.period_month,
  'EMPLOYEE_LOAN'::statutory_agency,
  rp.employee_id,
  sum(pl.amount)::numeric(14,2),
  0::numeric(14,2),
  sum(pl.amount)::numeric(14,2)
from released_payslip rp
join payslip_lines pl on pl.payslip_id = rp.payslip_id and pl.category = 'LOAN_DEDUCTION'
group by rp.hiring_entity_id, rp.period_year, rp.period_month, rp.employee_id
having sum(pl.amount) > 0;

comment on view statutory_payable_breakdown_v is
  'Per (entity, period, agency, employee) breakdown — one row per employee '
  'per agency per month, summed across all cutoffs. Drives the on-screen '
  'drawer and the XLSX export. Entity = coalesce(statutory_entity_id, '
  'hiring_entity_id).';

grant select on statutory_payable_breakdown_v to authenticated;
