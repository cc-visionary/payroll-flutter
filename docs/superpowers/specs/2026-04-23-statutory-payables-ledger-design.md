# Statutory Payables Ledger — Design

**Date:** 2026-04-23
**Status:** Draft, awaiting review
**Owner:** Donald
**Replaces:** `lib/features/compliance/compliance_screen.dart` (currently a coming-soon placeholder)

## Goal

Give Luxium HQ a single screen that answers, for any month and any brand:

1. How much do we owe each agency (SSS, PhilHealth, Pag-IBIG, BIR 1601-C) and for employee loan remittances?
2. Has it been paid? When, by whom, with what reference?
3. Export the underlying employee-level breakdown to XLSX, one sheet per brand, with a `Brand` column on every row so single-sheet pivots still work.

The screen replaces the existing `Compliance` coming-soon. HMO and other employer-paid benefits with per-employee enrollment are explicitly **out of scope** — that needs its own spec because it requires a vendor + plan + enrollment model that does not exist in the codebase yet.

## Non-goals

- HMO, group life, and other vendor benefits (separate spec).
- Disambiguating SSS-loan vs Pag-IBIG-loan remittances. v1 lumps all `LOAN_DEDUCTION` lines into one "Employee Loan Remittances" row per (brand × month). A follow-up can add a `loan_type` enum on `payslip_lines`.
- Auto-filing to SSS/BIR portals. The export is a working file HR uses to file manually.
- Generating BIR 1601-C / 2316 / alphalist forms. The compliance coming-soon copy lists those — they remain future work.
- DOLE 201 file checklist, policy library, compliance calendar (also from the coming-soon copy).

## Domain background

In the Philippines, employer statutory remittances are monthly, even though payroll cutoffs are semi-monthly. Each month HR must remit to:

- **SSS** — sum of employee + employer shares for everyone enrolled, paid via PRN.
- **PhilHealth** — sum of employee + employer shares.
- **Pag-IBIG (HDMF)** — sum of employee + employer shares.
- **BIR 1601-C** — withholding tax on compensation.
- **Loan repayments** — SSS salary loan and Pag-IBIG MPL/calamity loan deductions, remitted alongside or separately depending on agency portal flow.

Luxium operates multiple legal entities (`hiring_entities`) — each brand pays its own remittances. So the natural grouping is `(hiring_entity, month, agency)`.

## Data model

### Existing tables we read from

- `payslips` — per-employee per-run snapshot. Already stores `sss_ee`, `sss_er`, `philhealth_ee`, `philhealth_er`, `pagibig_ee`, `pagibig_er`, `withholding_tax`.
- `payslip_lines` — per-line breakdown. We aggregate `category = 'LOAN_DEDUCTION'` lines for the loans payable.
- `employees.hiring_entity_id` — the brand link.
- `payroll_runs.pay_period_id` → `pay_periods.end_date` — used to assign a payslip to its remittance month. **Decision:** the cutoff *paid in* a given month is what remits in that month's filing window, so we assign by `pay_periods.end_date.month`.
- `hiring_entities` — brand metadata for grouping/labels.

We only consider payslips whose parent `payroll_runs.status` is `RELEASED`. Draft and approved (but unreleased) runs are excluded — you can't owe a remittance you haven't actually paid out.

### New table: `statutory_payments`

Append-only ledger. One row = one cheque/transfer to one agency for one brand for one month.

```sql
create type statutory_agency as enum (
  'SSS_CONTRIBUTION',
  'PHILHEALTH_CONTRIBUTION',
  'PAGIBIG_CONTRIBUTION',
  'BIR_WITHHOLDING',
  'EMPLOYEE_LOAN'
);

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

create index on statutory_payments
  (hiring_entity_id, period_year, period_month, agency)
  where voided_at is null;

create trigger _statutory_payments_updated
  before update on statutory_payments
  for each row execute function set_updated_at();
```

Notes:

- **Append-only with soft-void.** Edits create a new row; the wrong row gets voided with a reason. This keeps the ledger audit-clean and matches how `audit` already works elsewhere in the app.
- **No unique constraint** on `(hiring_entity_id, period_year, period_month, agency)`. Real life has split payments (e.g., regular + arrears, or two PRNs in one month). The UI shows the sum of non-voided payments versus amount due.
- **`amount_paid` may differ from amount due** — that's normal (penalties, rounding adjustments). Variance is shown in the UI.

### New view: `statutory_payables_due_v`

Live aggregation of what's owed.

```sql
create view statutory_payables_due_v as
with payslip_period as (
  select
    p.id              as payslip_id,
    p.employee_id,
    e.hiring_entity_id,
    extract(year  from pp.end_date)::smallint  as period_year,
    extract(month from pp.end_date)::smallint  as period_month,
    p.sss_ee, p.sss_er,
    p.philhealth_ee, p.philhealth_er,
    p.pagibig_ee, p.pagibig_er,
    p.withholding_tax
  from payslips p
  join payroll_runs   pr on pr.id = p.payroll_run_id and pr.status = 'RELEASED'
  join pay_periods    pp on pp.id = pr.pay_period_id
  join employees      e  on e.id  = p.employee_id
  where e.hiring_entity_id is not null
)
select hiring_entity_id, period_year, period_month,
       'SSS_CONTRIBUTION'::statutory_agency as agency,
       sum(sss_ee + sss_er) as amount_due,
       sum(sss_ee) as ee_share, sum(sss_er) as er_share,
       count(distinct payslip_id) as payslip_count,
       count(distinct employee_id) as employee_count
from payslip_period
group by hiring_entity_id, period_year, period_month
having sum(sss_ee + sss_er) > 0
union all
-- … same shape for PHILHEALTH, PAGIBIG, BIR (er_share = 0 for BIR), and loans
;
```

Loan rows aggregate `payslip_lines.amount` filtered to `category = 'LOAN_DEDUCTION'`, joined back through `payslip_id → payslips → payroll_runs (RELEASED) → pay_periods → employees`. EE share = total, ER share = 0.

A second view, `statutory_payables_paid_v`, sums non-voided `statutory_payments` rows by the same grain. The Flutter repository fetches both and joins client-side — keeps the SQL simple and matches the existing `responsive_table` data-loading patterns.

### Employees with no `hiring_entity_id`

The view's `where e.hiring_entity_id is not null` excludes them from the rollup. The UI surfaces a separate "Unassigned" warning chip with a count and a deep-link to the affected employee profiles, so HR can fix the data instead of silently undercounting.

## UI

### Route and shell

- Route stays `/compliance`.
- Nav label changes from "Compliance" (with `comingSoon: true`) to "Compliance" without the flag.
- Visibility unchanged: `_hrOrAdmin`.

### Screen layout

Top toolbar (uses existing `responsive_table` width budget — max 1100px):

- **Period picker.** Default = month picker (current month). Toggle to "Custom range" reveals start/end date pickers (reuses the attendance range selector pattern shipped recently).
- **Brand filter.** Multi-select of `hiring_entities` ordered by name. Default = all.
- **Agency filter.** Multi-select chips: SSS, PhilHealth, Pag-IBIG, BIR, Loans. Default = all.
- **Export button.** Dropdown: "Export current view (multi-sheet)" and "Export selected brand only" (enabled when exactly one brand is filtered).

Body table — one row per `(brand, month, agency)`:

| Brand | Month | Agency | Employees | Amount Due | Paid? | Paid On | Reference | Amount Paid | Variance | Actions |
|---|---|---|---|---|---|---|---|---|---|---|

- **Paid?** chip uses Luxium status-chip rules (`.impeccable.md`): tinted bg + darker text, no border. States: `Unpaid` (neutral), `Partial` (warning), `Paid` (success), `Overpaid` (info). State derived from `sum(amount_paid) vs amount_due`.
- **Variance** = `amount_paid_total - amount_due`. Mono font (Geist Mono).
- **Actions:** "Mark as Paid" (opens dialog) for unpaid/partial; "View Payments" for paid/partial/overpaid; "Export sheet" for one-row export.
- Click a row → side drawer with per-employee breakdown (Last, First, MI, Employee ID, EE Share, ER Share, Total). This is the same data the XLSX export uses — single source so they stay in sync.

### Mark-as-Paid dialog

Captures: `paid_on` (date, defaults to today), `reference_no` (text, optional), `amount_paid` (decimal, defaults to amount due, editable), `paid_by` (auto = current user, hidden), `notes` (text, optional). Submit → insert into `statutory_payments`. Toast confirms.

### View Payments dialog

Lists all non-voided `statutory_payments` for the row, with Edit / Void buttons. Edit creates a new row + voids the prior; Void prompts for `void_reason`. Always-editable; permission: `_hrOrAdmin` only.

## Export format

XLSX, multi-sheet workbook. **One sheet per brand.** Sheet names clamp to Excel's 31-char limit per `_clampSheetName` (already in `disbursement_export.dart`).

Each sheet:

```
Row 1: Brand: HAVIT Philippines        Period: March 2026         Generated: 2026-04-23
Row 2: (blank)
Row 3: SSS Contribution
Row 4: Brand | Last Name | First Name | MI | Employee ID | EE Share | ER Share | Total
Rows 5..N: employee rows
Row N+1: TOTAL — SSS Contribution            Σ EE Share | Σ ER Share | Σ Total
Row N+2: (blank)
Row N+3: PhilHealth Contribution
…repeat…
Row last-1: (blank)
Row last:  GRAND TOTAL                                  Σ EE        | Σ ER        | Σ Total
```

- `Brand` column appears on every employee row (per the ask) so the workbook can be flattened with a pivot table without losing the entity.
- All money cells are `DoubleCellValue` (matches existing exporter).
- All text cells are `TextCellValue`.
- Filename: per-brand single-sheet → `Statutory Payables - {Brand} - {Month YYYY}.xlsx`. Multi-brand workbook → `Statutory Payables - All Brands - {Month YYYY}.xlsx`. Custom range → `Statutory Payables - {Brand|All Brands} - {Mar 1, 2026 to Mar 31, 2026}.xlsx`. Sanitised via the existing `_safeFileName`.
- Mobile uses share-sheet flow; desktop uses save dialog. Reuses the helpers in `disbursement_export.dart`.

## File / module layout

New files:

- `supabase/migrations/20260423000001_statutory_payables.sql` — enum, table, indexes, view(s), RLS.
- `supabase/tests/statutory_payables_test.ts` — view correctness across cutoffs/months/brands.
- `lib/data/models/statutory_payment.dart` — model + JSON codec.
- `lib/data/models/statutory_payable.dart` — view-row model (brand+month+agency+amounts+counts).
- `lib/data/repositories/statutory_payables_repository.dart` — fetch payables + payments, mark paid, edit, void.
- `lib/features/compliance/compliance_screen.dart` — REWRITE. Replaces coming-soon.
- `lib/features/compliance/widgets/payables_filter_bar.dart` — period/brand/agency controls.
- `lib/features/compliance/widgets/payables_table.dart` — main table.
- `lib/features/compliance/widgets/mark_as_paid_dialog.dart`.
- `lib/features/compliance/widgets/view_payments_dialog.dart`.
- `lib/features/compliance/widgets/payable_breakdown_drawer.dart` — per-employee detail.
- `lib/features/compliance/payables_export.dart` — XLSX builder. Mirrors the conventions in `disbursement_export.dart` (sheet name clamping, file name sanitising, mobile share / desktop save split).
- `lib/features/compliance/providers.dart` — Riverpod state for filters + data.

Modified:

- `lib/app/shell.dart` — drop `comingSoon: true` from the Compliance nav item.

## Permissions / RLS

- Read `statutory_payments`: any authenticated user with `is_hr_or_admin`.
- Insert/update `statutory_payments`: `is_hr_or_admin`.
- View `statutory_payables_due_v` already inherits its RLS from `payslips`/`employees`.

## Audit

`statutory_payments` insert/update events log to the existing `audit` feature (`audit/`) via the same trigger pattern used by other ledger tables. Void events include `void_reason` in the audit row.

## Testing

Deno tests (`supabase/tests/statutory_payables_test.ts`):

1. View returns one row per (brand × month × agency) when payslips exist; zero rows when none.
2. Draft/approved-but-unreleased runs are excluded.
3. Loan-line aggregation only counts `LOAN_DEDUCTION` rows.
4. `period_year`/`period_month` derived from `pay_periods.end_date`.
5. Employees with `hiring_entity_id IS NULL` are excluded from the view.
6. `statutory_payments` insert with `voided_at` set is excluded from "paid" totals.

Flutter widget tests (`test/`):

1. Mark-as-Paid dialog defaults `amount_paid` to `amount_due`.
2. Variance chip switches state at boundaries (0, > 0, < 0).
3. Filter bar sums show correct counts across multi-select.

Manual:

1. Open Compliance with no released runs in current month → empty state copy ("No statutory payables for {Month}.") + suggested action ("Try a different period or release a payroll run").
2. Mark a partial payment, verify chip becomes "Partial" and variance reflects the gap.
3. Export per-brand and multi-brand workbooks; verify sheet count, totals row math, and filename format.

## Open questions / risks

1. **Loans split.** v1 doesn't separate SSS-loan from Pag-IBIG-loan. If HR objects, the follow-up is `payslip_lines.loan_type` enum + a recompute. Logged here, deferred.
2. **Period assignment by `pay_periods.end_date.month`.** Edge case: a Mar 16 – Mar 31 cutoff with `pay_date = April 5` would file in April per BIR/SSS. We're using `end_date.month` (= March) which matches HR's "for the period of March" convention. If HR files differently, we switch the column to `pay_date` — single-line change.
3. **Performance.** View aggregates over `payslips` + `payslip_lines`; expected row counts (~50 employees × 2 cutoffs × 12 months × N years) are well within Postgres territory. Indexes on `payroll_runs(status)` and `payslips(payroll_run_id)` already exist.
4. **Re-releasing a run.** If HR un-releases and re-releases a run, the view amount_due changes but recorded payments don't. UI should highlight when a paid row's amount_due drifts from its amount_paid (the "Variance" column already does this).

## Out of scope, future specs

- HMO and other employer-paid benefits with per-employee enrollment.
- Loan-type disambiguation on `payslip_lines`.
- BIR 1601-C / 2316 / alphalist form generation.
- DOLE 201 checklist.
- Compliance calendar with deadline reminders.
- E-acknowledgement trail for policies.
