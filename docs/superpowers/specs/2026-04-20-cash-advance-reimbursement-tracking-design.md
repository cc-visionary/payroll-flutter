# Cash Advance & Reimbursement Tracking + Employee Page Polish

**Date:** 2026-04-20
**Status:** Draft (pending user review)

## Summary

Bring cash advances and reimbursements to feature parity with penalties: per-run skip, visible deduction/payout tracking on the employee Financials tab, and a "Skip" action in the payslip breakdown. Two small UI polish items on the employee profile tabs ship alongside because they share the same surface.

## Motivation

Penalties already tell HR "this installment was deducted in run X on date Y, here's the payslip" and give a per-run Skip so a payroll manager can defer a deduction one period without cancelling the underlying record. Cash advances and reimbursements do not — their rows show only a static status, and there is no way to tell the compute to hold off for a single run. HR has to cancel and re-create, which loses history.

While we're in the employee profile screen, two UX nits:

- Payslip rows hide the PDF link unless the run is approved/released. Managers want to preview the draft PDF too.
- The Role & Responsibilities tab shows both a "WORK SCHEDULE" card and a "HOURS" card rendering identical data.

## Scope (in)

1. Employee → Payslips tab: PDF link on every payslip row regardless of approval status.
2. Employee → Role & Responsibilities tab: remove the redundant HOURS card and adjust the grid for 3 remaining cards.
3. Database: add per-run skip tracking to `cash_advances` and `reimbursements`.
4. Compute service: honor the new skip arrays when building payroll runs.
5. Repository: `setCashAdvanceSkip` and `setReimbursementSkip` methods mirroring `setPenaltyInstallmentSkip`.
6. Payslip breakdown tab: extend the Skip action to cash advance and reimbursement lines.
7. Employee Financials tab: replace the generic card for cash advances and reimbursements with a richer card that shows deduction/payout status, deduction date, and a link to the payslip that consumed the record.

## Scope (out)

- Populating `cash_advances.payslip_line_id` / `reimbursements.payslip_line_id` at release. These columns exist but are unused today; we resolve the payslip via a separate `payslip_lines` query instead of broadening the release transaction.
- Manual creation of cash advances and reimbursements from the UI — they still originate from Lark approvals.
- Penalty changes. The existing penalty flow stays untouched.

## Piece 1 — PDF link on every payslip row

**File:** `lib/features/employees/profile/tabs/payslips_tab.dart:464`

Delete the `if (released)` gate so the OutlinedButton.icon("PDF") renders on every row. The target route `/payslips/:id` already handles any approval status — the same approvals tab at `lib/features/payroll/runs/detail/tabs/approvals_tab.dart:859` navigates there unconditionally.

**Verification:** Open an employee with draft-in-review payslips → each row shows the PDF button → tapping it opens the preview screen for that payslip.

## Piece 2 — Remove redundant HOURS card on Role tab

**File:** `lib/features/employees/profile/tabs/role_tab.dart:124-143`

Delete the HOURS card (values identical to WORK SCHEDULE: `${card.workHoursPerDay}h / day` + `card.workDaysPerWeek`). The grid at `:92-97` is sized for 4 columns at ≥920px; rebalance so three cards fill the row cleanly:

- `c.maxWidth >= 920` → `(c.maxWidth - 2 * 12) / 3` (3 cols, was 4)
- `c.maxWidth >= 600` → `(c.maxWidth - 12) / 2` (2 cols, unchanged)
- else → `c.maxWidth` (1 col, unchanged)

**Verification:** Role tab at desktop width shows three cards in one row (Position · Base Salary · Work Schedule) with no trailing whitespace.

## Piece 3 — Database migration

**File:** `supabase/migrations/20260420000003_ca_reimbursement_skip.sql`

Mirrors `20260418000009_penalty_installment_skip.sql`:

```sql
alter table cash_advances
  add column if not exists skipped_payroll_run_ids uuid[] not null default '{}';

create index if not exists idx_cash_advances_skipped
  on cash_advances using gin (skipped_payroll_run_ids);

alter table reimbursements
  add column if not exists skipped_payroll_run_ids uuid[] not null default '{}';

create index if not exists idx_reimbursements_skipped
  on reimbursements using gin (skipped_payroll_run_ids);
```

Array column + GIN index. Arrays keep this a zero-join design that round-trips cleanly through the Supabase Dart client.

## Piece 4 — Compute service filter

**File:** `lib/features/payroll/runs/compute/compute_service.dart`

The cash-advance loader (around `:429-445`) and reimbursement loader (around `:446-470`) currently filter on `status='PENDING'` + `lark_approval_status='APPROVED'` + date. Add a guard identical to the penalty-installment pattern at `:503-508`:

```dart
final skipped = r['skipped_payroll_run_ids'];
if (skipped is List && skipped.contains(runId)) continue;
```

Applied after the query in the loop that groups rows by employee. Reason for client-side filtering (same as penalty path): the `status='PENDING'` filter happens at query time; the skip-membership check is cheap in Dart and keeps the SQL simple.

## Piece 5 — Repository skip methods

**File:** `lib/data/repositories/payroll_repository.dart`

Add two methods mirroring `setPenaltyInstallmentSkip` (around `:298-330`):

```dart
Future<void> setCashAdvanceSkip({
  required String advanceId,
  required String runId,
  required bool skip,
});

Future<void> setReimbursementSkip({
  required String reimbursementId,
  required String runId,
  required bool skip,
});
```

Each reads the current `skipped_payroll_run_ids`, adds or removes `runId`, and writes back. Same defensive read-modify-write pattern the existing penalty method uses — avoids a race with a concurrent release path.

## Piece 6 — Skip action in the breakdown tab

**File:** `lib/features/payroll/payslips/detail/tabs/breakdown_tab.dart`

Two touch points — deductions and earnings — because cash advances surface as deductions and reimbursements surface as earnings.

**Deductions card (`_DeductionsCard`, `:288`).** Extend `_skipAction` at `:367` (today only branches on `penalty_installment_id`) to also handle `line['cash_advance_id']`. Route to `setCashAdvanceSkip` when present. Leave the penalty branch first so the existing flow keeps its semantics.

**Earnings card (`_EarningsCard`, `:225`).** Currently a `StatelessWidget` with no runId/runStatus. Convert to `ConsumerWidget`, accept `runId` and `runStatus` like `_DeductionsCard` does, and render the same Skip button on lines where `line['reimbursement_id'] != null`. Wire it up through the two call sites at `:56` and `:73`.

**Dialog copy** (mirrors the existing penalty dialog at `:388-394`):

- CA: title `"Skip this cash advance?"`, body `"This defers the cash advance deduction to the next pay period. The payslip needs to be recomputed for the change to take effect."`
- Reimbursement: title `"Skip this reimbursement?"`, body `"This defers the reimbursement payout to the next pay period. The payslip needs to be recomputed for the change to take effect."`

**Gating:** `_canSkip` already checks `runStatus == 'REVIEW'`. Reuse the same predicate on `_EarningsCard`.

## Piece 7 — Financials tab: rich card for CA / Reimbursement

**Files:**
- `lib/features/employees/profile/providers.dart` — enrich `financialsByEmployeeProvider`
- `lib/features/employees/profile/tabs/financials_tab.dart` — replace `_buildGenericCard` (`:591-646`)

**Provider change.** After the primary query returns cash advances or reimbursements, collect the ids of rows with `is_deducted=true` (or `is_paid=true`). Issue one follow-up query against `payslip_lines` filtered by those ids, selecting `id, cash_advance_id, reimbursement_id, payslip_id`. Fold the result into a `Map<String, String>` (record id → payslip id) and attach it to each row under a synthetic key like `_payslip_id`. No schema change; one extra roundtrip only when deducted rows exist.

**Card layout.** The new CA/Reimbursement card shows:

- Title row: description + status chip
  - CA status: `DEDUCTED` (green) when `is_deducted=true`, else the row's `status` (PENDING/CANCELLED)
  - Reimbursement status: `PAID` (green) when `is_paid=true`, else the row's `status`
- Amount (right-aligned)
- Sub-line when deducted/paid: `"{Deducted|Paid} on {date}"` using `deducted_at` / `paid_at`
- Link row when `_payslip_id` is present: `"View payslip →"` → navigates `/payslips/:id` via `go_router`

No progress bar (unlike penalties — CA and reimbursements are single-shot).

**Status chip tone.** Extend `toneForStatus` if needed to cover `DEDUCTED` / `PAID` as success-toned — check the shared widget first; prefer re-using existing tones over adding new ones.

## Data flow recap

1. HR records or Lark sync inserts a `cash_advance` / `reimbursement` with `status='PENDING'`, `is_deducted|is_paid=false`.
2. Compute service picks it up for the next eligible run → generates a `payslip_line` linked via `cash_advance_id` / `reimbursement_id`.
3. If the manager hits Skip in the breakdown tab, the record's `skipped_payroll_run_ids` gains this `runId`. Recompute → the compute service excludes the record for this run only.
4. On release: `is_deducted|is_paid` flip to true, `deducted_at|paid_at` and `payroll_run_id` get stamped.
5. Employee Financials tab queries the record + resolves its payslip via `payslip_lines`. The rich card displays status and the "View payslip" link.

## Testing

- **Migration:** apply locally → confirm columns exist, default is `'{}'`, index is created.
- **Compute unit:** extend `supabase/tests/` (if a compute harness lives there) or add a Dart test that stubs the CA/Reimbursement row list and asserts a skipped run is excluded.
- **UI smoke:** manual — draft a run, open a payslip with CA and reimbursement lines, hit Skip on each, recompute, confirm lines disappear; release next run, confirm lines reappear and Financials tab shows "View payslip" links resolving correctly.
- **Regressions:** penalty Skip path untouched — re-run an existing penalty skip smoke.

## Open questions

None at design time. Verify at plan time whether `toneForStatus` already maps `DEDUCTED` and `PAID` — if it treats only `PAID` as success, `DEDUCTED` will need a thin addition.
