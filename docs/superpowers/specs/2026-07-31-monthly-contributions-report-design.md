# Monthly Contributions Report (Compliance) — Design

**Date:** 2026-07-31
**Status:** Approved by user (brainstorming session)

## Purpose

A monthly XLSX report sent to the external accountant who handles government
benefit remittances (SSS / PhilHealth / Pag-IBIG). It presents each employee's
**declared** monthly salary (the statutory/declared wage, not the actual
scorecard rate) next to the contributions actually deducted that month, plus
whether each agency has been paid. It is a reference document — it does not
change any payroll or compliance computation.

This replaces the accountant's use of the existing agency-sectioned payables
export, which the user finds unintuitive. The existing export stays.

## Where it lives

**Compliance screen** (`lib/features/compliance/`). The current Export button
becomes a two-option menu:

1. **Statutory Payables (by agency)** — the existing export, unchanged.
2. **Monthly Contributions Report** — new.

Choosing the new option opens a small dialog:

- **Month picker** — single calendar month, defaults to the previous month.
  Independent of the on-screen period filter.
- **Brand selector** — optional multi-select of hiring entities; default all.
- **Partial-month warning** — if the selected month has fewer than 2 released
  payroll runs (period_end within the month, status = RELEASED), show an
  inline warning: the report may be missing a cutoff. Export still allowed.

The Compliance screen is already HR/Admin-gated; no new access rules.

## Workbook layout

One sheet per brand (statutory entity), named after the brand (Excel-safe,
clamped to 31 chars — reuse `_clampSheetName`). Filename:
`Monthly Contributions - <Brand|All Brands> - <Month Year>.xlsx`.

Each sheet:

```
Row 1: Brand: <name>    Month: July 2026    Generated: 2026-07-31
Row 2: (blank)
Row 3: header row
Rows 4..N: one row per employee
Row N+1: TOTALS row
Row N+2: (blank)
Rows N+3...: Remittance Status block
```

Header / employee columns:

| Month | Employee ID | Last Name | First Name | Monthly Salary | SSS EE | SSS ER | PhilHealth EE | PhilHealth ER | Pag-IBIG EE | Pag-IBIG ER | W/H Tax | Total EE | Total ER | Total |

- **Month** — same label on every row (e.g. "July 2026"); explicit per user
  request so pasted rows stay self-describing.
- **Monthly Salary** — the declared monthly (see derivation below).
- Contribution cells — summed actual deductions for that employee across all
  released runs in the month (both cutoffs). Zero when the employee has no
  row for that agency.
- **W/H Tax** — BIR withholding (EE-only; ER = 0).
- **Total EE / Total ER / Total** — row sums across the four agencies.
- **TOTALS row** — column sums for the sheet.
- Employees sorted by last name, then first name (matches existing export).

Remittance Status block (below totals), one line per agency:

```
Remittance Status
SSS           Due <sheet SSS total>    Paid <amount> on <date(s)>    PAID | PARTIAL | UNPAID
PhilHealth    ...
Pag-IBIG      ...
BIR W/H Tax   ...
```

Status text comes from the existing `classifyPayable` logic (Unpaid /
Partial / Paid; Overpaid rendered as PAID with the paid amount visible).
When several payments exist, show the latest payment date and the summed
amount. Agencies with zero due render `—`.

**Employee loans (`EMPLOYEE_LOAN`) are excluded** — this report is for the
benefits accountant only.

## Declared monthly salary derivation

Mirrors the engine's statutory base formula (`compute_engine.dart`, statutory
override block):

1. If the employee has a declared-wage override (`declared_wage_override` > 0
   AND `declared_wage_type` set), use it; otherwise fall back to the actual
   scorecard rate (`role_scorecards.base_salary` + `wage_type`).
2. Convert to a daily rate: DAILY → as-is; HOURLY → rate ×
   `work_hours_per_day` (scorecard, default 8); MONTHLY → rate ÷ 26.
3. Monthly Salary = daily rate × 26.

(For MONTHLY wage types the round-trip ÷26 ×26 returns the original monthly
amount.) Implemented as a small pure helper so it is unit-testable and cannot
drift from the export.

The value is read from the employee's **current** record — declared-wage
history is not stored. If the declared wage changed mid-month the contribution
sum reflects what was actually deducted (the two halves differ), and the
mismatch against the salary column is visible by design.

## Data sources (no migration required)

- `statutory_payable_breakdown_v` — per (entity, year, month, agency,
  employee) sums of released payslips' stored EE/ER amounts. Already excludes
  non-released runs and groups both cutoffs into one employee-month row.
  Entity = `coalesce(statutory_entity_id, hiring_entity_id)`.
- `employees` — one `inFilter` fetch for the breakdown's employee ids:
  names, employee_number, declared wage fields, `role_scorecard_id`.
- `role_scorecards` — base_salary, wage_type, work_hours_per_day for the
  fallback and hourly conversion.
- Existing paid summaries (`listPaidSummaries`) + `classifyPayable` for the
  Remittance Status block; `listPayments` for payment dates.
- `payroll_runs` — count of RELEASED runs with `period_end` in the selected
  month, for the partial-month warning.

Known behaviour (accepted):

- The view emits rows only where an agency's total > 0, so an employee with
  zero contributions for the whole month simply doesn't appear.
- Months with no released runs export nothing; the dialog warning covers this.
- Attendance never affects the numbers — contributions are declared-rate-based
  (matches engine behaviour and PH practice; heavy absences do not prorate).

## New/changed code

- `lib/features/compliance/monthly_contributions_export.dart` — NEW: row
  assembly, declared-monthly helper, workbook builder, save/share plumbing
  (mirror `payables_export.dart` helpers).
- `lib/features/compliance/widgets/monthly_contributions_dialog.dart` — NEW:
  month picker + brand selector + warning + export action.
- `lib/features/compliance/compliance_screen.dart` — Export button becomes a
  `PopupMenuButton`/menu anchoring both exports.
- `lib/data/repositories/statutory_payables_repository.dart` — small addition
  if the existing breakdown/paid-summary listing needs a month-scoped variant;
  reuse existing methods where they already fit.

## Error handling

- Empty month (no breakdown rows after filters) → snackbar "No released
  contributions for <month>", no file written.
- Save dialog cancelled → silent no-op (match existing exports).
- Any fetch/build failure → red snackbar with the error (match existing
  exports).

## Testing

- Unit tests (pure Dart, no Supabase): declared-monthly conversion for all
  three wage types, override vs scorecard fallback, and row assembly
  (grouping agency rows into one employee row, totals, loan exclusion,
  employees missing an agency).
- Manual GUI smoke: export a month with 2 released cutoffs, a partial month
  (1 cutoff), and a month with payments marked (status block shows
  PAID/PARTIAL/UNPAID correctly).
