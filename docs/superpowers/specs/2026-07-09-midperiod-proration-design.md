# Mid-Period Pro-Rated Compensation Effective Dates — Design

**Date:** 2026-07-09
**Status:** Draft, pending user review
**Owner:** payroll-flutter

## Summary

Make a compensation change take effect **on its effective date**, not for the whole pay period
containing it. Today a raise effective **July 17** applied to a July 1–31 run pays the *entire
month* at the new rate. After this change, July 1–16 pay the old rate and July 17–31 pay the new
one, with the split visible on the payslip.

The payroll engine is already fully per-day — every rate path (basic pay, OT, night differential,
holiday, rest-day, and the payslip generator) resolves through
`getDayRates(rates, hpd, day.dailyRateOverride)`. So earnings proration is **plumbing in
`compute_service`**, not an engine redesign. Two small engine changes ride along: the MONTHLY
basic-pay branch groups by rate (so the split is visible), and the non-override tax basis switches
from a notional figure to actual computed pay.

## Motivation

`compute_service._buildEmployeeInput` resolves **one** compensation row for the whole period via
`effectiveCompensation(comp, payPeriod.endDate)` and hands the engine a single `profile.baseRate`.
Consequences:

- July 1–31 run + raise effective July 17 → `effectiveCompensation(comp, Jul 31)` returns the
  raise → **the whole month is paid at the new rate** (overpays Jul 1–16).
- Semi-monthly Jul 16–31 + effective Jul 17 → Jul 16 is overpaid by one day.
- It only *looks* correct today because the change dialog defaults the effective date to the 1st of
  next month, which lands on a period boundary.

This is a real overpayment bug in the shipped
`docs/superpowers/specs/2026-07-08-compensation-role-change-workflow-design.md` feature. That spec
assumed boundary-aligned effective dates and never addressed proration.

## What already exists (and needs no change)

- **`AttendanceDayInput.dailyRateOverride`** (`engine/types.dart:141`) — an optional per-day daily
  rate.
- **`getDayRates(standardRates, hoursPerDay, overrideDailyRate)`** (`engine/wage_calculator.dart:72`)
  — when an override is present it recomputes `dailyRate`/`hourlyRate`/`minuteRate` from it, and
  **deliberately preserves `monthlyRate` and `msc` from the period-level rates**. This is why
  per-day rates can never leak into statutory contributions.
- Every engine rate path already calls `getDayRates(...)`: basic pay (both branches), OT
  (`compute_engine.dart:184`), ND/holiday (`:223`), and `payslip_generator.dart` (5 sites).
- `compute_service:974` already populates `dailyRateOverride` per day from
  `attendance_day_records.daily_rate_override` (the manual batch-edit escape hatch).
- `compute_service._buildEmployeeInput` (`:631`) already receives the employee's `comp`
  (`List<CompensationChange>`) and builds `attendanceInputs` (`:737`) — both the data and the seam
  are already in scope.

## Decisions locked from brainstorm

1. **Proration is per-day and the effective date is inclusive.** A change effective July 17 pays the
   new rate *on* July 17.
2. **Manual per-day `daily_rate_override` wins** over the compensation-derived rate. It is an
   explicit human edit; the comp-derived rate is the default for days without one.
3. **Statutory MSC uses the rate effective at period END** (the new salary) — standard PH practice,
   contributions track current salary.
4. **Tax basic pay becomes the ACTUAL computed basic pay** (not the notional `taxDailyRate ×
   workDays`), so withholding matches what is really paid. This also fixes a pre-existing mismatch
   that already occurs whenever a manual per-day override is used.
5. **`declared_wage_override` (the `statutoryOverride` path) still wins for BOTH statutory and tax.**
   Decisions 3 and 4 apply **only** in the `else` branch (no override). The override branch is
   untouched. (User-stated invariant.)
6. **Mid-period `wage_type` changes are blocked.** If a change switches `wage_type`, the effective
   date must be the 1st of a month. Pay-only and same-wage-type role changes may land on any day.
7. **The MONTHLY basic-pay branch groups by rate**, emitting one line per distinct daily rate — like
   the DAILY/HOURLY branch already does — so a mid-period raise is self-documenting on the payslip.
   With a single rate (the normal case) it emits **exactly today's single line, unchanged**.

## Design

### 1. Per-day rate resolution (`compute_service`)

New pure, Supabase-free helper (unit-testable in isolation):

```dart
/// Daily rate implied by a compensation snapshot.
Decimal dailyRateFrom({
  required Decimal baseSalary,
  required String wageType,        // 'MONTHLY' | 'DAILY' | 'HOURLY'
  required int workDaysPerMonth,   // 26
  required int hoursPerDay,
});
// MONTHLY -> baseSalary / workDaysPerMonth
// DAILY   -> baseSalary
// HOURLY  -> baseSalary * hoursPerDay
```

Mirrors the switch already in `wage_calculator.dart` so the two cannot disagree.

When mapping each attendance row → `AttendanceDayInput` (inside `_buildEmployeeInput`, at the
`attendanceInputs` construction, `:737`):

1. If the row has a manual `daily_rate_override` → **use it verbatim** (decision 2). Done.
2. Else resolve `final eff = effectiveCompensation(comp, attendanceDate)`.
   - `eff != null` → `dayRate = dailyRateFrom(eff.newBaseSalary!, eff.newWageType!, ...)`
   - `eff == null` → `dayRate = dailyRateFrom(scorecard.base_salary, scorecard.wage_type, ...)`
     (the existing fallback).
3. Set `dailyRateOverride = dayRate` **only when the day's resolved change differs from the
   period-end resolved change** — compared by *identity*, not by rate value:

   ```dart
   final periodEndEff = effectiveCompensation(comp, payPeriod.endDate); // may be null
   final dayEff       = effectiveCompensation(comp, attendanceDate);    // may be null
   final differs = dayEff?.id != periodEndEff?.id;   // null-safe; both-null => false
   ```

   If `differs` is false, leave `dailyRateOverride = null` (the day uses the period-level standard
   rate). This avoids comparing rounded `Decimal` rates, which would be fragile — `dailyRateFrom`
   and `wage_calculator` both `_round3`, and a value comparison could spuriously differ or
   spuriously match (e.g. two different salaries that round to the same daily rate).

Step 3's identity rule is what guarantees the no-comp-rows case (`dayEff == periodEndEff == null`)
produces `null` everywhere and therefore byte-identical payslips.

Multiple changes inside one period resolve naturally, because each day asks the resolver
independently. `effectiveCompensation` already skips CANCELLED and soft-deleted rows.

### 2. Period-level rate (unchanged behavior, restated)

`profile.baseRate` / `profile.wageType` continue to come from
`effectiveCompensation(comp, payPeriod.endDate)`, falling back to the scorecard. This is the
"standard rate" and it drives:

- `rates.msc` → **statutory contributions** (decision 3: the post-change rate),
- the default rate for any day without an override,
- the payslip snapshot's displayed `baseRate`.

Because the period-end rate is the *new* rate, days **on/after** the change match the standard rate
and need no override; days **before** the change get an override **down** to the old rate.

### 3. Tax basis (`compute_engine`, `else` branch only)

Inside the tax block (`compute_engine.dart:395-420`), the `if (employee.statutoryOverride != null)`
branch is **untouched** (decision 5). Only the `else` branch changes:

- `taxBasicPay`: was `_round3(taxDailyRate * workDays)` → becomes the **sum of the emitted
  `BASIC_PAY` line amounts**.
- `taxLateUtDeduction`: was `_round3(taxMinuteRate * totalDeductionMinutes)` → becomes the **sum of
  the emitted `LATE_DEDUCTION` + `UNDERTIME_DEDUCTION` + `LATE_UT_DEDUCTION` line amounts**.

For an employee with no per-day overrides these are *arithmetically identical* to today's values
(the actual lines are computed from the same single rate), so existing payslips do not move. The
`taxOnFullEarnings` (GROSS PAY) mode consumes `taxBasicPay` and inherits the fix for free.

Statutory (`compute_engine.dart:335`, `monthlyGross = rates.msc`) is **not modified** —
`getDayRates` already preserves `msc`, so per-day rates cannot affect contributions.

### 4. MONTHLY basic-pay line grouping (`compute_engine.dart:112-127`)

Replace the single accumulator with the same rate-grouping the DAILY branch uses, keyed by the day's
effective daily rate and preserving **first-occurrence order** (so the old-rate line precedes the
new-rate line, chronologically):

- **Exactly one distinct rate** (the normal case) → emit **today's line verbatim**: description
  `'Basic Pay (Monthly)'` / `'Basic Pay (Semi-Monthly)'`, `amount` = total, **no** `quantity`/`rate`
  fields. Byte-identical to current output.
- **Two or more distinct rates** → emit one line per rate:
  `description: 'Basic Pay (Monthly) — N days'` (or `(Semi-Monthly)`), `quantity: N`,
  `rate: <daily rate>`, `amount: _round3(rate * N)`, `sortOrder: 100`, `ruleCode: 'BASIC_PAY'`.

No rounding drift: each day's rate is already `_round3`-ed, so `Σ(rate_g × count_g)` equals the
per-day `Σ rate_i` exactly.

### 5. Wage-type change guard (`compensation_change_dialog.dart`)

Extend the pure `validateCompensationRequest(...)`: when the request's `newWageType` differs from the
employee's current wage type, the `effectiveDate` must have `day == 1`, else a validation error
("A wage-type change must take effect on the 1st of a month"). This keeps the engine's
single-branch-per-period assumption sound (decision 6).

### 6. Invariants (regression safety)

1. **No `compensation_changes` rows** → step 1.3 never sets an override → every payslip is
   byte-identical to today. Guarded by the existing 590-test suite.
2. **`declared_wage_override` set** → statutory and tax are computed exactly as today (decision 5).
3. **Manual `daily_rate_override` on a day** → that day uses it, ignoring the comp-derived rate.
4. **Single distinct rate** → the MONTHLY branch emits one line identical to today's.

## Scope (in)

1. Pure `dailyRateFrom(...)` helper + unit tests.
2. `compute_service`: per-day `dailyRateOverride` resolution from `comp` (manual override wins).
3. `compute_engine`: MONTHLY branch groups by rate; `else`-branch tax basis uses actual lines.
4. `compensation_change_dialog`: wage-type-change effective-date guard.
5. Tests (below).

## Scope (out / follow-ons)

- **Per-day scorecard attributes.** `work_hours_per_day` / `work_days_per_week` / department come
  from the single joined `role_scorecards` row (via the employee's current pointer), not per-day. A
  promotion that also changes the work schedule mid-period uses the new schedule for the whole
  period. Documented limitation; follow-up if it bites.
- The historical-recompute limitation already documented in `compute_service` (a prior period
  recomputed after a later change was APPLIED falls back to the current scorecard) is **unchanged**
  by this spec.
- Payslip PDF header shows the single period-end `baseRate`; the per-rate detail lives in the
  BASIC_PAY lines. Not changing the header.

## Testing

- **`dailyRateFrom`** (pure): MONTHLY → `base/26`; DAILY → `base`; HOURLY → `base × hoursPerDay`.
- **Per-day resolution** (pure, over a fake attendance list): raise effective mid-period sets the
  override only on days *before* the effective date; the effective date itself gets the new (standard)
  rate; a manual override wins; a CANCELLED change is ignored; two changes in one period each apply
  from their own date.
- **Engine scenario — the headline case.** MONTHLY ₱30,000 → ₱38,000 effective **Jul 17**, period
  Jul 1–31: BASIC_PAY splits into two lines (old-rate days, new-rate days) whose sum equals the
  per-day sum; `msc` derives from ₱38,000; `taxBasicPay == ` the summed BASIC_PAY.
- **Semi-monthly**: period Jul 16–31 with effective Jul 17 → Jul 16 at the old rate, the rest new.
- **Invariant tests**: (a) no comp rows → payslip identical to a golden computed from the scorecard;
  (b) `statutoryOverride` set → statutory + tax identical to today regardless of proration;
  (c) manual `daily_rate_override` beats the comp-derived rate; (d) single-rate MONTHLY emits one
  line with no `quantity`/`rate`.
- **Dialog validation**: wage-type change + non-1st effective date → error; wage-type change + 1st →
  ok; same wage type + any date → ok.
- `flutter analyze` clean (0 errors, no new lints). Full suite green.

## Files (anticipated)

**New**
- `lib/features/payroll/engine/daily_rate.dart` (pure `dailyRateFrom`)
- `test/engine/daily_rate_test.dart`
- `test/engine/midperiod_proration_test.dart` (engine scenarios + invariants)

**Modified**
- `lib/features/payroll/runs/compute/compute_service.dart` (per-day override resolution)
- `lib/features/payroll/engine/compute_engine.dart` (MONTHLY grouping; `else`-branch tax basis)
- `lib/features/employees/profile/widgets/compensation_change_dialog.dart` (wage-type guard)
- `test/features/employees/compensation_change_dialog_test.dart` (guard cases)

## Concurrency / deploy notes

Multiple Claude sessions share this working dir — implement on an isolated git worktree/branch. No
migration is required (no schema change). Depends on migration `20260708000001_compensation_changes`
already being a prod-deploy gate from the prior spec.
