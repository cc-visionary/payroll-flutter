# SIL Leave Balances, Paid Leave in Payroll, Year-End Conversion — Design

**Date:** 2026-07-31
**Status:** Approved by user (brainstorming session)

## Purpose

Make Service Incentive Leave (SIL) work end-to-end:

1. Leave balances in the app reflect Lark's (how many days are left).
2. An absence covered by an approved paid leave (SIL) is PAID in payroll,
   not deducted.
3. At year-end, unused SIL is paid out together with the 13th month.
4. Balances are visible in the app (employee profile).

## Decisions (user-confirmed)

- **Lark owns leave balances.** Lark Attendance already accrues SIL by
  tenure and deducts on approved leaves (admin Leave Balance page). The app
  mirrors balances read-only via a new sync. No accrual engine in the app.
- **Paid leave = separate earning line** on the payslip for DAILY/HOURLY
  employees; MONTHLY employees get no deduction plus a zero-amount info
  line. Which types are paid is driven by `leave_types.is_paid`
  (SIL = paid; other types default unpaid, editable).
- **Year-end SIL payout is combined with the 13th month**: the existing
  Distribute 13th Month dialog computes both and applies ONE combined
  payslip line; the dialog previews the per-employee split before apply,
  and the split is recorded in line metadata.

## Current state (verified in code)

- Tables exist and are RLS'd: `leave_types` (accrual config, `is_paid`,
  `is_convertible`, `conversion_rate`, `lark_leave_type_id`),
  `leave_balances` (opening/accrued/used/forfeited/converted/adjusted/
  carry-over per employee × type × year), `leave_requests`
  (`balance_deducted`, `leave_balance_id`, status enum
  PENDING/APPROVED/REJECTED/CANCELLED). Migration `20260414000008_leave.sql`.
- `sync-lark-leaves` edge function upserts APPROVED Lark leaves into
  `leave_requests`, auto-creating `leave_types` from Lark's
  `leave_type_id`/`uniq_id`.
- `sync-lark-attendance` marks day records `ON_LEAVE` but does not link
  `leave_request_id`.
- **Nothing writes `leave_balances`.** The employee profile Attendance tab
  already reads it (`leaveBalancesProvider`, employees/profile/providers.dart:144).
- Payroll: `compute_service.dart:1060-1061` sets
  `isOnLeave: status.contains('LEAVE')`, `leaveIsPaid: false` (hardcoded).
  Engine (`compute_engine.dart:100`) counts a paid-leave day as a work day
  ONLY for MONTHLY wage types; DAILY/HOURLY paid leave is currently
  impossible.
- 13th month: `Distribute13thDialog`
  (payroll/runs/detail/widgets/distribute_13th_dialog.dart) attaches a
  13th-month line to a run's payslips.

## Component 1 — Balance sync (Lark → app)

New edge function `supabase/functions/sync-lark-leave-balances/index.ts`,
same conventions as sibling syncs (POST `{company_id}`, `lark_sync_logs`
start/finish, service-role client, `_shared/lark.ts` auth):

- For each active employee with a Lark user id, query Lark's attendance
  leave-balance API for the current year's balances per leave type.
  (Primary candidate endpoints: attendance v1 leave balance /
  `leave_employ_expire_records`; exact endpoint confirmed at
  implementation — the Lark tenant is international `larksuite.com`.)
- Map Lark leave type → `leave_types` via `lark_leave_type_id` (reuse the
  auto-create logic pattern from `sync-lark-leaves`).
- Upsert `leave_balances` on (employee_id, leave_type_id, year):
  `accrued` = granted days, `used` = used days, `last_accrual_date` =
  sync date. Remaining is always derived:
  `accrued + opening_balance + carried_over_from_previous + adjusted
  - used - forfeited - converted`.
- **Fallback** if the balance API is unavailable on our tenant: an
  admin-facing XLSX import dialog in the app that parses Lark's Leave
  Balance page Export file into the same `leave_balances` upsert. The
  downstream behavior (display, payout) is identical either way.
- Trigger: from the app's Lark settings screen alongside the other sync
  buttons (same UI pattern), plus whatever scheduled flow the other syncs
  participate in.

One data migration: set `is_paid = true`, `is_convertible = true` on the
SIL leave type (matched by its Lark name/code) and default `is_paid =
false` on auto-created types going forward (already the sync's insert
behavior — verify).

## Component 2 — Paid leave in payroll

- `compute_service` loads, per run period, all APPROVED `leave_requests`
  overlapping the period with their `leave_types` (`is_paid`, `code`,
  `name`), keyed by employee.
- For each attendance day input: `isOnLeave` stays as today;
  `leaveIsPaid` = the day falls inside an APPROVED request whose type has
  `is_paid = true`. Half-day handling: if the request's `start_half`/
  `end_half`/`leave_days` imply a half day on that date, the day carries
  0.5 paid-leave weight (engine input gains a `paidLeaveFraction` —
  1.0 or 0.5 — instead of a plain bool where needed).
- Engine changes:
  - New earning line category `PAID_LEAVE`: for DAILY/HOURLY wage types,
    amount = paid-leave days × daily rate (fraction-aware), description
    `Paid Leave — <TYPE> (N day/s)`. Sorted with the other earnings.
  - MONTHLY wage types: keep the existing no-deduction behavior
    (`compute_engine.dart:100`) and add a zero-amount `PAID_LEAVE` info
    line so the payslip shows the leave was paid.
  - Unpaid leave types: unchanged (day stays unpaid).
- New run **warning** (warnings.dart pattern): "N ON_LEAVE day(s) with no
  matching approved leave request" — fires per employee/date when an
  attendance ON_LEAVE day has no covering APPROVED request; non-blocking.

## Component 3 — In-app access

Employee profile Attendance tab: upgrade the existing balance display to a
card per leave type showing granted (`accrued`), used, **remaining**
(derived), and the last-synced date (`leave_balances.updated_at`). No new
screen; Lark's admin page remains the management UI. HR edits happen in
Lark and flow in via sync.

## Component 4 — Year-end SIL conversion (combined with 13th month)

`Distribute13thDialog` gains the SIL conversion:

- Preview table adds columns: remaining SIL days (from `leave_balances`,
  current year, convertible paid types), daily rate (actual, current), SIL
  amount = remaining × daily rate × `conversion_rate`, and total =
  13th + SIL.
- Apply writes ONE line per payslip: description
  `13th Month Pay + SIL Conversion`, amount = combined total; the line's
  stored metadata records both components (13th amount, SIL days, SIL
  amount) for audit.
- Employees with zero remaining SIL simply get the plain 13th-month
  amount (same line description only when SIL > 0; otherwise the existing
  13th-month description is kept).
- **Stale-balance guard:** if the newest `leave_balances.updated_at` for
  the company is older than 7 days, the dialog shows a warning and
  requires an explicit checkbox to proceed.
- On the run reaching RELEASED, `leave_balances.converted` += the
  converted days for each paid-out employee (recorded app-side; Lark's
  own year-end reset is Lark-configured and untouched).

## Error handling

- Sync failures: logged to `lark_sync_logs` like the sibling syncs;
  partial per-employee errors collected and returned, not fatal.
- Payroll: unmatched ON_LEAVE days produce warnings, never block compute.
- 13th dialog: stale-balance guard above; apply failures surface in the
  dialog like the existing 13th-month errors.

## Testing

- Engine unit tests (pure): paid SIL day for DAILY/HOURLY/MONTHLY wage
  types (line amounts, no-deduction), half-day paid leave (0.5), unpaid
  type unchanged, combined 13th+SIL line composition and metadata.
- `compute_service` leave-matching: day-in-request coverage, APPROVED-only,
  is_paid gating (testable pure helper).
- Sync function: Deno test with mocked Lark payload → `leave_balances`
  upsert shape (`deno test supabase/tests/`; note: no local Supabase —
  tests are written to run against mocks, live smoke deferred).
- GUI smoke: profile balance card, run warning on unmatched leave day,
  13th+SIL preview and apply on a test run.

## Out of scope

- No accrual computation in the app (Lark owns it).
- No leave request creation/approval UI in the app (Lark owns it).
- No push of balances app → Lark.
- Carry-over policy changes, other leave types' payout rules.
