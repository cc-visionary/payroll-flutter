-- =============================================================================
-- Statutory Payables Ledger — agency enum, payments table, due-aggregation view
-- =============================================================================
--
-- Surfaces what each hiring entity owes the PH statutory agencies (SSS,
-- PhilHealth, Pag-IBIG, BIR 1601-C) plus employee loan remittances, per
-- (brand × month). Period is derived from `payroll_runs.period_end.month`
-- (the pay_periods table was dropped in 20260418000006 and the dates are now
-- denormalized onto payroll_runs).
--
-- statutory_payments is append-only with a soft-void model: edits insert a new
-- row and mark the prior one voided (with reason) so the audit trail stays
-- intact. There is intentionally no UNIQUE constraint on
-- (hiring_entity_id, period_year, period_month, agency) — split payments
-- (regular + arrears, two PRNs in one month) are real and supported.
--
-- The view excludes employees with hiring_entity_id IS NULL (the UI surfaces
-- them as a separate "Unassigned" warning so HR can backfill the data).

-- =============================================================================
-- ENUM
-- =============================================================================
create type statutory_agency as enum (
  'SSS_CONTRIBUTION',
  'PHILHEALTH_CONTRIBUTION',
  'PAGIBIG_CONTRIBUTION',
  'BIR_WITHHOLDING',
  'EMPLOYEE_LOAN'
);

-- =============================================================================
-- TABLE: statutory_payments
-- =============================================================================
create table statutory_payments (
  id                 uuid primary key default gen_random_uuid(),
  hiring_entity_id   uuid not null references hiring_entities(id) on delete restrict,
  period_year        smallint not null,
  period_month       smallint not null check (period_month between 1 and 12),
  agency             statutory_agency not null,
  paid_on            date not null,
  reference_no       varchar(100),
  amount_paid        numeric(14,2) not null,
  paid_by_id         uuid references users(id),
  notes              text,
  voided_at          timestamptz,
  voided_by_id       uuid references users(id),
  void_reason        text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

-- Partial index — non-voided lookups by (brand, period, agency) drive every
-- "Paid?" / variance read on the screen.
create index statutory_payments_active_lookup
  on statutory_payments (hiring_entity_id, period_year, period_month, agency)
  where voided_at is null;

-- Reuse the project-wide updated-at trigger from migration 1.
create trigger _statutory_payments_updated
  before update on statutory_payments
  for each row execute function set_updated_at();

comment on table statutory_payments is
  'Append-only ledger of statutory remittances. Edits insert a new row and '
  'soft-void the prior one (voided_at + voided_by_id + void_reason).';

-- =============================================================================
-- VIEW: statutory_payables_due_v
-- One row per (brand × month × agency) summarising what is owed, derived from
-- released payslips. SSS/PhilHealth/Pag-IBIG total = EE + ER share; BIR uses
-- withholding_tax with er_share = 0; loans aggregate payslip_lines where
-- category = 'LOAN_DEDUCTION', also with er_share = 0.
-- =============================================================================
create view statutory_payables_due_v as
with released_payslip as (
  select
    p.id                                          as payslip_id,
    p.employee_id,
    e.hiring_entity_id,
    extract(year  from pr.period_end)::smallint   as period_year,
    extract(month from pr.period_end)::smallint   as period_month,
    p.sss_ee, p.sss_er,
    p.philhealth_ee, p.philhealth_er,
    p.pagibig_ee, p.pagibig_er,
    p.withholding_tax
  from payslips p
  join payroll_runs pr on pr.id = p.payroll_run_id and pr.status = 'RELEASED'
  join employees    e  on e.id  = p.employee_id
  where e.hiring_entity_id is not null
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
  'Per (hiring_entity, period, agency) totals owed, computed from released '
  'payslips. Excludes employees with NULL hiring_entity_id.';

-- =============================================================================
-- VIEW: statutory_payments_paid_v
-- Sum of non-voided payments by the same grain as the dues view; the Flutter
-- repository joins these client-side. Splitting the views keeps the SQL
-- simple and lets the UI fetch payment-row detail separately for the
-- "View Payments" dialog.
-- =============================================================================
create view statutory_payments_paid_v as
select
  hiring_entity_id,
  period_year,
  period_month,
  agency,
  sum(amount_paid)::numeric(14,2) as amount_paid,
  count(*)                        as payment_count,
  max(paid_on)                    as last_paid_on
from statutory_payments
where voided_at is null
group by hiring_entity_id, period_year, period_month, agency;

comment on view statutory_payments_paid_v is
  'Per (hiring_entity, period, agency) totals already remitted. Excludes '
  'voided payments.';

-- =============================================================================
-- Per-payslip employee-level breakdown view (drives the on-screen drawer +
-- the XLSX export — single source so they stay in sync).
-- =============================================================================
create view statutory_payable_breakdown_v as
with released_payslip as (
  select
    p.id                                          as payslip_id,
    p.employee_id,
    e.hiring_entity_id,
    extract(year  from pr.period_end)::smallint   as period_year,
    extract(month from pr.period_end)::smallint   as period_month,
    p.sss_ee, p.sss_er,
    p.philhealth_ee, p.philhealth_er,
    p.pagibig_ee, p.pagibig_er,
    p.withholding_tax
  from payslips p
  join payroll_runs pr on pr.id = p.payroll_run_id and pr.status = 'RELEASED'
  join employees    e  on e.id  = p.employee_id
  where e.hiring_entity_id is not null
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
  'Per (hiring_entity, period, agency, payslip) employee-level breakdown. '
  'Drives the on-screen drawer and the XLSX export.';

-- =============================================================================
-- RLS: HR / admins can read + write payments. Reads on the views inherit
-- their RLS from the underlying tables (payslips / employees / payroll_runs)
-- so no extra policy is needed there.
-- =============================================================================
alter table statutory_payments enable row level security;

create policy statutory_payments_hr_read
  on statutory_payments for select
  using (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR'));

create policy statutory_payments_hr_write
  on statutory_payments for all
  using (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR'))
  with check (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR'));

-- PostgREST needs explicit grants on views to the authenticated role so the
-- Flutter client can SELECT them. RLS on the underlying tables remains the
-- security boundary.
grant select on statutory_payables_due_v       to authenticated;
grant select on statutory_payments_paid_v      to authenticated;
grant select on statutory_payable_breakdown_v  to authenticated;
