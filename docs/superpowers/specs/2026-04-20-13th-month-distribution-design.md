# 13th Month Pay — Accrual & Distribution

**Status:** Draft · 2026-04-20
**Owner:** payroll-flutter
**DOLE reference:** PD 851 (13th-Month Pay Law)

## Context

PH labor law requires employers to pay rank-and-file employees a 13th-month
bonus equal to `sum(basic salary over the calendar year) / 12`, released not
later than December 24. Many Luxium-area companies split the payout 50/50
between May and December, so the app needs to support multiple partial
distributions that add up to the statutory total.

The app today tracks **no 13th-month accrual** — the enum value
`THIRTEENTH_MONTH_PAY` exists in the `payslip_line_category` enum but is
never written to or read from. The existing payroll engine already
calculates `BASIC_PAY` correctly (= days attended × daily rate, net of
late / UT deductions), which is exactly the input PD 851 wants summed.

This design adds the missing pieces: a running per-employee accrual
counter that advances on every payroll release, plus a one-click
"Distribute 13th Month" action inside each payroll run that pays out the
accrued balance and resets the counter.

## Formula (DOLE-aligned)

```
payout_this_distribution = accrued_basis_since_last_reset / 12
```

Multiple distributions in the same calendar year sum to:

```
(sum of BASIC_PAY across the whole year) / 12
```

which is exactly what PD 851 defines. Basic pay excludes overtime, holiday
premium, night differential, allowances, commissions, and reimbursements —
same as the statute.

## Data model

**Migration:** `supabase/migrations/20260420000001_thirteenth_month_accrual.sql`

```sql
-- Running sum of basic pay since the employee's last 13th-month distribution.
-- Ticks up on every payroll release; zeroes when a distribution includes them.
alter table employees
  add column accrued_thirteenth_month_basis numeric(12,2) not null default 0;

-- Flags the run where HR clicked "Distribute 13th Month". Used by reports
-- and export filters — "show every 13th-month distribution this year".
alter table payroll_runs
  add column is_thirteenth_month_distribution boolean not null default false;
```

No new tables. Distribution payouts live as existing `payslip_lines` rows
with `category = 'THIRTEENTH_MONTH_PAY'`.

## Accrual — how the counter advances

Hook into the existing "release" flow in `compute_service.dart`
(`releaseRun(runId)` or equivalent). Inside a single SQL transaction, for
each payslip in the run:

```sql
update employees e
   set accrued_thirteenth_month_basis =
       e.accrued_thirteenth_month_basis + <basic_pay_this_run>
 where e.id = <employee_id>;
```

`<basic_pay_this_run>` = sum of `payslip_lines.amount` where
`category = 'BASIC_PAY'` for that payslip. Use the amount, not gross, so
holiday premium / OT / ND don't leak into the 13th-month basis.

Idempotency: re-releasing the same run is already blocked by the
`payroll_runs.status` state machine (`REVIEW → RELEASED` only once), so no
double-tick risk. Cancelling a released run is an open flow we'll address
in a follow-up if / when it's wired up.

## Distribution — the "..." action

### Entry point

In `lib/features/payroll/runs/detail/payroll_run_detail_screen.dart`,
extend `_ActionBar` with a kebab `PopupMenuButton` next to the existing
`Recompute`, `Release`, `Cancel Run`, `Export Payslips` buttons. Menu items
for V1:

- **Distribute 13th Month** — primary action this spec adds
- (future space for other run-level actions without crowding the row)

Enabled when:
- `run.status == 'REVIEW'` (same gate as Release; distribution must happen
  BEFORE release so the payslip totals pick up the new line, and so the
  accrual column hasn't already ticked for this run yet)
- `profile.canRunPayroll` (same gate as Recompute / Release)

### Dialog

New widget: `lib/features/payroll/runs/detail/widgets/distribute_13th_dialog.dart`.

Layout:

```
Distribute 13th Month — 2026-03-31 → 2026-04-14
─────────────────────────────────────────────────
This adds a "13th Month Pay" line to each selected
employee's payslip on this run, then resets their
accrued basis.

[x] Del Mundo, Brixter   Basis ₱154,830.00 → Pay ₱12,902.50
[x] Ong, Marvin          Basis ₱155,390.00 → Pay ₱12,949.17
[x] Chua, Marjory        Basis ₱ 77,800.00 → Pay  ₱6,483.33
[ ] Biason, Christian    Basis ₱      0.00 → Not eligible (greyed)
...

Total to distribute: ₱45,883.21
                            [Cancel]   [Distribute]
```

Per-row checkbox state:
- **Default ticked** when `basis > 0` AND employee doesn't already have a
  `THIRTEENTH_MONTH_PAY` line on this run's payslip.
- **Disabled + "Not eligible"** when `basis == 0`.
- **Disabled + "Already distributed on this run"** when a line already
  exists on this run's payslip.

### On confirm

In a single transaction-ish sequence (PostgREST doesn't expose real
transactions from the client, so we use the same serial-with-best-effort
pattern the rest of the app uses):

1. For each selected employee, insert into `payslip_lines`:
   ```
   payslip_id        = <employee's payslip on this run>
   category          = 'THIRTEENTH_MONTH_PAY'
   description       = '13th Month Pay (distribution)'
   amount            = basis / 12   (rounded to 2dp, half-up)
   quantity          = 1
   rate              = basis / 12
   multiplier        = null
   sort_order        = 450   -- between regular earnings (100-400) and deductions (1000+)
   ```
2. Zero out `employees.accrued_thirteenth_month_basis` for each of those
   employees.
3. Update `payroll_runs.is_thirteenth_month_distribution = true` for this run.
4. Re-totalize each touched payslip: `gross_pay += payout`, `net_pay += payout`.
5. Invalidate `payslipListForRunProvider`, `payrollRunDetailProvider`,
   `payslipApprovalCountsProvider` so Summary / Payslips tabs refresh live.
6. SnackBar: `"Distributed 13th month to N employees. Total ₱X."`

### Repository wiring

New method on `PayrollRepository`:

```dart
Future<DistributeThirteenthMonthResult> distributeThirteenthMonth({
  required String runId,
  required List<String> employeeIds,
});
```

Returns counts + total payout for the success toast. All writes happen via
Supabase client calls; RLS already restricts writes to HR/Admin.

## Edge cases

| Case | Behavior |
|---|---|
| Employee with `basis = 0` | Greyed out in dialog, skipped on confirm. |
| Already distributed on this run | Greyed out with "Already distributed" note, skipped. |
| Recompute after distribution | Engine-generated lines get wiped and rebuilt, but the `THIRTEENTH_MONTH_PAY` line has a distinct `category` and was written outside the engine path — guard the engine's delete step to preserve it. (Or: re-apply on recompute by reading `is_thirteenth_month_distribution`.) |
| Mid-year new hire | Basis starts from their first released run. First distribution pays only what they've earned. ✓ |
| Resigned employee | Accrual freezes on separation (no more runs include them). Final run can include one last distribution to zero the balance. |
| Double-release attempt | Already blocked by the run state machine; no change. |

## Explicitly out of scope (V1)

- **₱90,000 tax-exempt threshold.** PD 851 + BIR exempt the first ₱90,000
  of combined 13th-month + other bonuses from income tax; any excess is
  taxable. V1 posts the line with no tax adjustment. HR can Recompute to
  re-run the YTD tax math; the new earning flows into gross and the tax
  table handles the rest. Proper threshold enforcement is a follow-up.
- **Backfilling the accrual column.** Migration defaults existing
  employees to `0`. If the user wants a year-to-date initial basis,
  a one-shot SQL will sum historical basic pay into the column — tracked
  separately.
- **"13th-month only" payroll runs.** User chose to attach distributions
  to regular runs via the kebab action. A dedicated distribution-only
  run type is out of scope.
- **Multi-distribution reporting dashboard.** The flag on `payroll_runs`
  makes future queries trivial; no UI dashboard for V1.

## Files touched

**New:**
- `supabase/migrations/<ts>_thirteenth_month_accrual.sql`
- `lib/features/payroll/runs/detail/widgets/distribute_13th_dialog.dart`

**Modified:**
- `lib/data/repositories/payroll_repository.dart` — `distributeThirteenthMonth`, release-hook accrual tick-up
- `lib/features/payroll/runs/compute/compute_service.dart` — accrual write on release; preserve `THIRTEENTH_MONTH_PAY` lines across recompute
- `lib/features/payroll/runs/detail/payroll_run_detail_screen.dart` — overflow kebab in `_ActionBar` with "Distribute 13th Month" item
- `lib/data/models/employee.dart` — expose `accruedThirteenthMonthBasis`
- `lib/data/models/payroll_run.dart` — expose `isThirteenthMonthDistribution`

## Verification

1. Apply the migration. `\d employees` shows the new column at `0` default.
   `\d payroll_runs` shows the new flag defaulting `false`.
2. Release an existing REVIEW run. Check any included employee's
   `accrued_thirteenth_month_basis` — it equals the run's `BASIC_PAY` line
   amount for that employee.
3. Create a new REVIEW run, open it, click "..." → "Distribute 13th
   Month". Dialog shows all employees with their current basis and
   projected payout. Untick one, hit Distribute.
4. Run detail Summary refreshes: Total Gross Pay jumped by the sum of
   distributed payouts. Payslips tab shows the new line on each selected
   employee's payslip.
5. `select accrued_thirteenth_month_basis from employees where id = ...`
   returns 0 for distributed employees, unchanged for the one that was
   unticked.
6. `select is_thirteenth_month_distribution from payroll_runs where id =
   ...` returns `true`.
7. Click Recompute. `THIRTEENTH_MONTH_PAY` lines survive on the payslips.
8. Release the run. No double-accrual (the `BASIC_PAY` lines on this run
   add to the (already-reset) basis as normal; the `THIRTEENTH_MONTH_PAY`
   line is explicitly excluded from the accrual calc).
9. In December, click Distribute again. Payout = basis / 12 of the
   Jun-Dec accumulation; first + second distribution ≈ year-basic / 12.
10. Non-admin user: kebab menu shows the item but tapping errors with
    "Admins only" (RLS-enforced).
