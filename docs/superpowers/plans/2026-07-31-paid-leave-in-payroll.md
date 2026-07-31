# Paid Leave in Payroll Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When an employee's attendance day is ON_LEAVE and covered by an APPROVED paid leave request (e.g. SIL), pay that day in payroll — a separate "Paid Leave — <TYPE>" earning line for DAILY/HOURLY employees, no deduction (already paid via basic) plus a zero-amount info line for MONTHLY employees — and warn when an ON_LEAVE day has no matching approved paid request.

**Architecture:** A new pure helper resolves, per attendance day, whether it is covered by an approved paid leave and at what fraction (1.0 / 0.5). `compute_service` loads the period's approved leave requests once and feeds that resolution into each `AttendanceDayInput` (new fields `paidLeaveFraction`, `leaveTypeName`). The pure engine emits the `PAID_LEAVE` line from those fields. A run-warnings scan (reusing the same pure matcher) flags ON_LEAVE days with no covering approved paid request.

**Tech Stack:** Flutter/Dart, Riverpod, Supabase (Postgres enum migration + PostgREST reads), `decimal`. This is Plan 1 of the SIL work (spec `docs/superpowers/specs/2026-07-31-sil-leave-sync-design.md`, Component 2 + its warning); the Lark balance sync, profile display, and year-end SIL conversion are a separate later plan.

## Global Constraints

- Execute in a git worktree (superpowers:using-git-worktrees), based on local `main` — the repo is shared by concurrent sessions.
- Do NOT run `dart format` on whole files; match each file's surrounding style. Gate on `flutter analyze` only.
- Run Dart tests with `flutter test <path>` from the repo/worktree root.
- Package import prefix: `package:payroll_flutter/`.
- Currency is `Decimal` (package `decimal`); division uses `(a / b).toDecimal(scaleOnInfinitePrecision: 10)`.
- Paid-vs-unpaid is driven by `leave_types.is_paid` (never hardcode SIL).
- A `PayslipLineCategory` value serializes to the DB via `.name` (see `compute_service.dart:348` `'category': l.category.name`), so the Dart enum name must equal the Postgres enum label exactly: `PAID_LEAVE`.
- Paid-leave DAILY/HOURLY amount = `dailyRate × paidLeaveFraction`; MONTHLY paid-leave day is already counted as a work day in basic pay (`compute_engine.dart:100`), so its `PAID_LEAVE` line is a zero-amount info line — never a second payment.
- Only PURE leave days (attendance `workedMinutes == 0`) get an auto paid-leave earning for DAILY/HOURLY. A day that is ON_LEAVE **and** has worked minutes is a mixed day: emit no paid-leave earning and raise a warning instead (avoids double-paying, since any worked minutes already yield a full basic day).

---

### Task 1: `PAID_LEAVE` payslip-line category (DB enum + Dart enum + earning classification)

**Files:**
- Create: `supabase/migrations/20260731000001_payslip_line_category_paid_leave.sql`
- Modify: `lib/features/payroll/engine/types.dart` (enum `PayslipLineCategory`, ~line 18)
- Modify: `lib/features/payroll/engine/compute_engine.dart` (`_earningCategories` set, ~line 734)
- Test: `test/engine/paid_leave_category_test.dart`

**Interfaces:**
- Produces: `PayslipLineCategory.PAID_LEAVE` (Dart), Postgres enum label `'PAID_LEAVE'`, and membership of `PAID_LEAVE` in `_earningCategories` so it counts toward gross earnings (but NOT in `_grossPayExtraTaxableCategories` — paid leave is not extra taxable OT-type income).

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260731000001_payslip_line_category_paid_leave.sql`:

```sql
-- Add PAID_LEAVE to payslip_line_category. Paid leave (e.g. SIL) covered by
-- an approved leave request is paid as a distinct earning line for daily/
-- hourly employees; monthly employees carry a zero-amount info line (the day
-- is already paid via basic). `add value if not exists` is idempotent and
-- cannot run inside a txn block with other enum uses, so it stands alone.
alter type payslip_line_category add value if not exists 'PAID_LEAVE';
```

- [ ] **Step 2: Write the failing Dart test**

Create `test/engine/paid_leave_category_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/payroll/engine/types.dart';

void main() {
  test('PAID_LEAVE enum value exists and serializes to the DB label', () {
    expect(PayslipLineCategory.PAID_LEAVE.name, 'PAID_LEAVE');
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `flutter test test/engine/paid_leave_category_test.dart`
Expected: FAIL — `PAID_LEAVE` is not a member of `PayslipLineCategory`.

- [ ] **Step 4: Add the enum value + earning classification**

In `lib/features/payroll/engine/types.dart`, add `PAID_LEAVE` to the `PayslipLineCategory` enum immediately after `BASIC_PAY` (line 19):

```dart
enum PayslipLineCategory {
  BASIC_PAY,
  PAID_LEAVE,
  OVERTIME_REGULAR,
```

In `lib/features/payroll/engine/compute_engine.dart`, add `PAID_LEAVE` to the `_earningCategories` set (after `BASIC_PAY`, ~line 735):

```dart
const _earningCategories = <PayslipLineCategory>{
  PayslipLineCategory.BASIC_PAY,
  PayslipLineCategory.PAID_LEAVE,
  PayslipLineCategory.OVERTIME_REGULAR,
```

Do NOT add it to `_grossPayExtraTaxableCategories` or `_deductionCategories`.

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/engine/paid_leave_category_test.dart`
Expected: PASS.

- [ ] **Step 6: Analyze and commit**

Run: `flutter analyze lib/features/payroll/engine/types.dart lib/features/payroll/engine/compute_engine.dart test/engine/paid_leave_category_test.dart`
Expected: No issues.

```bash
git add supabase/migrations/20260731000001_payslip_line_category_paid_leave.sql lib/features/payroll/engine/types.dart lib/features/payroll/engine/compute_engine.dart test/engine/paid_leave_category_test.dart
git commit -m "feat(payroll): add PAID_LEAVE payslip line category (enum + migration)"
```

Note: the migration is applied to prod later via `supabase db push` — not part of this task's local test loop (there is no local Supabase). Flag in the task report that the migration is unapplied.

---

### Task 2: Engine emits the `PAID_LEAVE` line

**Files:**
- Modify: `lib/features/payroll/engine/types.dart` (`AttendanceDayInput`, fields ~line 137 + constructor ~line 161)
- Modify: `lib/features/payroll/engine/compute_engine.dart` (new step after basic pay, after line 188)
- Test: `test/engine/paid_leave_line_test.dart`

**Interfaces:**
- Consumes: `PayslipLineCategory.PAID_LEAVE` (Task 1).
- Produces: two new optional `AttendanceDayInput` fields —
  `final Decimal paidLeaveFraction` (default `Decimal.zero`; 0.0 = not a paid-leave day, 0.5 = half, 1.0 = full) and
  `final String? leaveTypeName` (label for the line, e.g. `"SIL"`).
  Engine behavior: for each attendance day with `isOnLeave == true && leaveIsPaid == true && paidLeaveFraction > 0 && workedMinutes == 0`, a `PAID_LEAVE` line is emitted — amount `getDayRates(...).dailyRate × paidLeaveFraction` for DAILY/HOURLY, amount `Decimal.zero` for MONTHLY. Grouped by `leaveTypeName` into one line per type with summed day-fractions.

- [ ] **Step 1: Write the failing tests**

Create `test/engine/paid_leave_line_test.dart`. Reuse the existing engine test harness style (see `test/engine/benefit_eligibility_override_test.dart` for `_payPeriod`, `_ruleset`, profile builders). Full self-contained harness:

```dart
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/payroll/engine/compute_engine.dart';
import 'package:payroll_flutter/features/payroll/engine/statutory_tables.dart';
import 'package:payroll_flutter/features/payroll/engine/types.dart';

Decimal _d(String s) => Decimal.parse(s);

PayPeriodInput _payPeriod() => PayPeriodInput(
      id: 'PP-1',
      startDate: DateTime.utc(2026, 1, 1),
      endDate: DateTime.utc(2026, 1, 15),
      cutoffDate: DateTime.utc(2026, 1, 15),
      payDate: DateTime.utc(2026, 1, 20),
      periodNumber: 1,
      payFrequency: PayFrequency.SEMI_MONTHLY,
    );

RulesetInput _ruleset() => RulesetInput(
      id: 'R-2026',
      version: 1,
      sssTable: SSS_TABLE,
      philhealthTable: PHILHEALTH_TABLE,
      pagibigTable: PAGIBIG_TABLE,
      taxTable: TAX_TABLE,
    );

PayProfileInput _profile(WageType wt, Decimal rate) => PayProfileInput(
      employeeId: 'EMP-1',
      wageType: wt,
      baseRate: rate,
      payFrequency: PayFrequency.SEMI_MONTHLY,
      standardWorkDaysPerMonth: 26,
      standardHoursPerDay: 8,
      isBenefitsEligible: true,
      isOtEligible: false,
      isNdEligible: false,
      sssEligibilityOverride: false,
      philhealthEligibilityOverride: false,
      pagibigEligibilityOverride: false,
      riceSubsidy: Decimal.zero,
      clothingAllowance: Decimal.zero,
      laundryAllowance: Decimal.zero,
      medicalAllowance: Decimal.zero,
      transportationAllowance: Decimal.zero,
      mealAllowance: Decimal.zero,
      communicationAllowance: Decimal.zero,
    );

AttendanceDayInput _day({
  required String id,
  required DateTime date,
  double worked = 480,
  bool onLeave = false,
  bool leavePaid = false,
  Decimal? paidFraction,
  String? leaveTypeName,
}) =>
    AttendanceDayInput(
      id: id,
      attendanceDate: date,
      dayType: DayType.WORKDAY,
      workedMinutes: worked,
      deductionMinutes: 0,
      absentMinutes: 0,
      otMinutes: 0,
      otEarlyInMinutes: 0,
      otLateOutMinutes: 0,
      overtimeRestDayMinutes: 0,
      overtimeHolidayMinutes: 0,
      earlyInApproved: false,
      lateOutApproved: false,
      nightDiffMinutes: 0,
      isOnLeave: onLeave,
      leaveIsPaid: leavePaid,
      paidLeaveFraction: paidFraction ?? Decimal.zero,
      leaveTypeName: leaveTypeName,
    );

EmployeePayrollInput _employee(PayProfileInput p, List<AttendanceDayInput> att) =>
    EmployeePayrollInput(
      profile: p,
      regularization: EmployeeRegularizationInput(
        employeeId: p.employeeId,
        employmentType: EmploymentType.REGULAR,
        hireDate: DateTime.utc(2020, 1, 1),
        regularizationDate: DateTime.utc(2020, 7, 1),
      ),
      attendance: att,
      manualAdjustments: const [],
      reimbursements: const [],
      cashAdvanceDeductions: const [],
      previousYtd: null,
    );

ComputedPayslip _run(PayProfileInput p, List<AttendanceDayInput> att) =>
    computeEmployeePayslip(_payPeriod(), _ruleset(), _employee(p, att));

Iterable<ComputedPayslipLine> _paidLeave(ComputedPayslip ps) =>
    ps.lines.where((l) => l.category == PayslipLineCategory.PAID_LEAVE);

void main() {
  test('DAILY: full paid leave day emits a PAID_LEAVE earning at daily rate', () {
    final p = _profile(WageType.DAILY, _d('1000'));
    final ps = _run(p, [
      _day(id: 'w1', date: DateTime.utc(2026, 1, 5)),
      _day(
        id: 'l1',
        date: DateTime.utc(2026, 1, 6),
        worked: 0,
        onLeave: true,
        leavePaid: true,
        paidFraction: _d('1.0'),
        leaveTypeName: 'SIL',
      ),
    ]);
    final lines = _paidLeave(ps).toList();
    expect(lines, hasLength(1));
    expect(lines.first.amount, _d('1000'));
    expect(lines.first.description, contains('SIL'));
  });

  test('DAILY: half-day paid leave pays half the daily rate', () {
    final p = _profile(WageType.DAILY, _d('1000'));
    final ps = _run(p, [
      _day(
        id: 'l1',
        date: DateTime.utc(2026, 1, 6),
        worked: 0,
        onLeave: true,
        leavePaid: true,
        paidFraction: _d('0.5'),
        leaveTypeName: 'SIL',
      ),
    ]);
    expect(_paidLeave(ps).single.amount, _d('500'));
  });

  test('DAILY: unpaid leave emits no PAID_LEAVE line', () {
    final p = _profile(WageType.DAILY, _d('1000'));
    final ps = _run(p, [
      _day(
        id: 'l1',
        date: DateTime.utc(2026, 1, 6),
        worked: 0,
        onLeave: true,
        leavePaid: false,
        paidFraction: Decimal.zero,
      ),
    ]);
    expect(_paidLeave(ps), isEmpty);
  });

  test('DAILY: ON_LEAVE day with worked minutes (mixed) emits no PAID_LEAVE line', () {
    final p = _profile(WageType.DAILY, _d('1000'));
    final ps = _run(p, [
      _day(
        id: 'm1',
        date: DateTime.utc(2026, 1, 6),
        worked: 240,
        onLeave: true,
        leavePaid: true,
        paidFraction: _d('0.5'),
        leaveTypeName: 'SIL',
      ),
    ]);
    expect(_paidLeave(ps), isEmpty);
  });

  test('MONTHLY: paid leave day emits a zero-amount PAID_LEAVE info line', () {
    final p = _profile(WageType.MONTHLY, _d('26000'));
    final ps = _run(p, [
      _day(id: 'w1', date: DateTime.utc(2026, 1, 5)),
      _day(
        id: 'l1',
        date: DateTime.utc(2026, 1, 6),
        worked: 0,
        onLeave: true,
        leavePaid: true,
        paidFraction: _d('1.0'),
        leaveTypeName: 'SIL',
      ),
    ]);
    final lines = _paidLeave(ps).toList();
    expect(lines, hasLength(1));
    expect(lines.first.amount, Decimal.zero);
  });

  test('two paid leave days of the same type collapse into one line', () {
    final p = _profile(WageType.DAILY, _d('1000'));
    final ps = _run(p, [
      _day(id: 'l1', date: DateTime.utc(2026, 1, 6), worked: 0, onLeave: true, leavePaid: true, paidFraction: _d('1.0'), leaveTypeName: 'SIL'),
      _day(id: 'l2', date: DateTime.utc(2026, 1, 7), worked: 0, onLeave: true, leavePaid: true, paidFraction: _d('1.0'), leaveTypeName: 'SIL'),
    ]);
    final lines = _paidLeave(ps).toList();
    expect(lines, hasLength(1));
    expect(lines.first.amount, _d('2000'));
    expect(lines.first.quantity, _d('2'));
  });
}
```

(If any harness type name here — `EmploymentType.REGULAR`, `ComputedPayslip.lines`, constructor params — does not match the current code, fix the harness to match the real types; do not change production types to satisfy the harness. Cross-check against `test/engine/benefit_eligibility_override_test.dart` and `lib/features/payroll/engine/types.dart`.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/engine/paid_leave_line_test.dart`
Expected: FAIL — `AttendanceDayInput` has no `paidLeaveFraction`/`leaveTypeName`, and no `PAID_LEAVE` line is produced.

- [ ] **Step 3: Add the `AttendanceDayInput` fields**

In `lib/features/payroll/engine/types.dart`, add two fields near the existing leave fields (`isOnLeave`, `leaveIsPaid`, `leaveHours`, ~line 137-139):

```dart
  final bool isOnLeave;
  final bool leaveIsPaid;
  final Decimal? leaveHours;

  /// Fraction of the day covered by an APPROVED paid leave (0.0 = none,
  /// 0.5 = half, 1.0 = full). Set by compute_service from the matched
  /// leave request; drives the PAID_LEAVE earning line.
  final Decimal paidLeaveFraction;

  /// Display name of the covering paid leave type (e.g. "SIL"), used in the
  /// PAID_LEAVE line description. Null when [paidLeaveFraction] is zero.
  final String? leaveTypeName;
```

Add to the constructor (near line 161-163), with defaults so every existing call site keeps compiling:

```dart
    required this.isOnLeave,
    required this.leaveIsPaid,
    this.leaveHours,
    this.paidLeaveFraction = const Decimal.fromInt(0) == const Decimal.fromInt(0) ? Decimal.zero : Decimal.zero,
    this.leaveTypeName,
```

Note: `Decimal.zero` is not a `const` expression, so it cannot be a default parameter value directly. Instead make `paidLeaveFraction` nullable-with-getter OR default via a nullable field. Use this pattern instead — declare the field nullable and expose a non-null getter:

```dart
  final Decimal? _paidLeaveFraction;
  Decimal get paidLeaveFraction => _paidLeaveFraction ?? Decimal.zero;
```

with constructor param `Decimal? paidLeaveFraction` assigned `_paidLeaveFraction = paidLeaveFraction`. Keep `leaveTypeName` a plain `final String?`. (This mirrors how other optional Decimal fields like `holidayMultiplier`/`dailyRateOverride` are nullable here.)

- [ ] **Step 4: Emit the `PAID_LEAVE` line in the engine**

In `lib/features/payroll/engine/compute_engine.dart`, add a new step immediately after the basic-pay block (after line 188, before the `// 4. Deductions` comment). Insert:

```dart
  // 3b. Paid leave (e.g. SIL). A day covered by an APPROVED paid leave that
  // the employee did NOT also work (workedMinutes == 0) is paid here.
  //   - DAILY/HOURLY: not counted as a work day above (step 2 gate at
  //     line ~100 only admits MONTHLY paid-leave days into basic), so we
  //     pay dailyRate × fraction as a distinct earning line.
  //   - MONTHLY: the day IS already a work day in basic pay, so we emit a
  //     zero-amount info line only — never a second payment.
  // Mixed days (ON_LEAVE with worked minutes) are skipped; a run warning
  // surfaces them for manual handling.
  final paidLeaveByType = <String, ({Decimal days, Decimal amount})>{};
  for (final day in attendance) {
    if (!day.isOnLeave || !day.leaveIsPaid) continue;
    if (day.paidLeaveFraction <= Decimal.zero) continue;
    if (day.workedMinutes > 0) continue; // mixed day → warning path, not paid here
    final typeName = day.leaveTypeName ?? 'Leave';
    final dayRates = getDayRates(rates, hpd, day.dailyRateOverride);
    final amount = profile.wageType == WageType.MONTHLY
        ? Decimal.zero
        : _round3(dayRates.dailyRate * day.paidLeaveFraction);
    final prev = paidLeaveByType[typeName] ??
        (days: Decimal.zero, amount: Decimal.zero);
    paidLeaveByType[typeName] = (
      days: prev.days + day.paidLeaveFraction,
      amount: prev.amount + amount,
    );
  }
  paidLeaveByType.forEach((typeName, agg) {
    final dayLabel = agg.days == Decimal.one ? 'day' : 'days';
    lines.add(ComputedPayslipLine(
      category: PayslipLineCategory.PAID_LEAVE,
      description: 'Paid Leave — $typeName (${agg.days} $dayLabel)',
      quantity: agg.days,
      amount: agg.amount,
      sortOrder: 150,
      ruleCode: 'PAID_LEAVE',
    ));
  });
```

(If `getDayRates`, `_round3`, `ComputedPayslipLine`, or `rates`/`hpd` names differ in the surrounding scope, use the exact names already in `computeEmployeePayslip` — they are all in scope in the basic-pay block just above. `sortOrder: 150` slots paid leave right after `BASIC_PAY` (100) and before overtime (200).)

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/engine/paid_leave_line_test.dart`
Expected: PASS (all six).

- [ ] **Step 6: Run the full engine suite (regression) + analyze**

Run: `flutter test test/engine/`
Expected: PASS — no existing engine test regressed (new fields default to zero fraction, so existing behavior is unchanged).

Run: `flutter analyze lib/features/payroll/engine/ test/engine/paid_leave_line_test.dart`
Expected: No issues.

- [ ] **Step 7: Commit**

```bash
git add lib/features/payroll/engine/types.dart lib/features/payroll/engine/compute_engine.dart test/engine/paid_leave_line_test.dart
git commit -m "feat(payroll): emit PAID_LEAVE earning line from approved paid leave"
```

---

### Task 3: `compute_service` loads approved leaves and resolves paid-leave per day

**Files:**
- Create: `lib/features/payroll/leave/paid_leave_matcher.dart`
- Modify: `lib/features/payroll/runs/compute/compute_service.dart` (leave load in the per-employee build ~line 755-820; `_attendanceFromRow` ~line 819-1065, the `isOnLeave/leaveIsPaid` construction ~line 1059-1061)
- Test: `test/features/payroll/paid_leave_matcher_test.dart`

**Interfaces:**
- Consumes: the `AttendanceDayInput.paidLeaveFraction` / `leaveTypeName` fields (Task 2).
- Produces:
  - `class ApprovedLeaveDay { final DateTime start; final DateTime end; final bool isPaid; final String typeName; final Decimal leaveDays; const ApprovedLeaveDay({...}); }`
  - `PaidLeaveResolution resolvePaidLeaveForDay({required DateTime date, required bool statusIsLeave, required List<ApprovedLeaveDay> approved})` returning `class PaidLeaveResolution { final bool isPaid; final Decimal fraction; final String? typeName; final bool covered; }` — `covered` = an approved request (paid or not) spans `date`; `isPaid`/`fraction`/`typeName` filled only when a PAID request covers it. Fraction = `0.5` when the covering paid request is single-date with `leaveDays <= 0.5`, else `1.0`.

- [ ] **Step 1: Write the failing tests**

Create `test/features/payroll/paid_leave_matcher_test.dart`:

```dart
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/payroll/leave/paid_leave_matcher.dart';

Decimal _d(String s) => Decimal.parse(s);
DateTime _u(int y, int m, int d) => DateTime.utc(y, m, d);

ApprovedLeaveDay _lv({
  required DateTime start,
  required DateTime end,
  required bool paid,
  String type = 'SIL',
  String days = '1',
}) =>
    ApprovedLeaveDay(
      start: start,
      end: end,
      isPaid: paid,
      typeName: type,
      leaveDays: _d(days),
    );

void main() {
  test('paid single-day request covering the date → paid, full day', () {
    final r = resolvePaidLeaveForDay(
      date: _u(2026, 1, 6),
      statusIsLeave: true,
      approved: [_lv(start: _u(2026, 1, 6), end: _u(2026, 1, 6), paid: true)],
    );
    expect(r.covered, isTrue);
    expect(r.isPaid, isTrue);
    expect(r.fraction, _d('1.0'));
    expect(r.typeName, 'SIL');
  });

  test('single-day half-day paid request → 0.5 fraction', () {
    final r = resolvePaidLeaveForDay(
      date: _u(2026, 1, 6),
      statusIsLeave: true,
      approved: [_lv(start: _u(2026, 1, 6), end: _u(2026, 1, 6), paid: true, days: '0.5')],
    );
    expect(r.fraction, _d('0.5'));
    expect(r.isPaid, isTrue);
  });

  test('multi-day paid request covers an interior date at full day', () {
    final r = resolvePaidLeaveForDay(
      date: _u(2026, 1, 7),
      statusIsLeave: true,
      approved: [_lv(start: _u(2026, 1, 6), end: _u(2026, 1, 9), paid: true, days: '4')],
    );
    expect(r.covered, isTrue);
    expect(r.fraction, _d('1.0'));
  });

  test('unpaid request covering the date → covered but not paid', () {
    final r = resolvePaidLeaveForDay(
      date: _u(2026, 1, 6),
      statusIsLeave: true,
      approved: [_lv(start: _u(2026, 1, 6), end: _u(2026, 1, 6), paid: false)],
    );
    expect(r.covered, isTrue);
    expect(r.isPaid, isFalse);
    expect(r.fraction, Decimal.zero);
  });

  test('ON_LEAVE day with no covering request → not covered, not paid', () {
    final r = resolvePaidLeaveForDay(
      date: _u(2026, 1, 6),
      statusIsLeave: true,
      approved: [_lv(start: _u(2026, 1, 10), end: _u(2026, 1, 10), paid: true)],
    );
    expect(r.covered, isFalse);
    expect(r.isPaid, isFalse);
  });

  test('non-leave day is never paid even if a request overlaps', () {
    final r = resolvePaidLeaveForDay(
      date: _u(2026, 1, 6),
      statusIsLeave: false,
      approved: [_lv(start: _u(2026, 1, 6), end: _u(2026, 1, 6), paid: true)],
    );
    expect(r.isPaid, isFalse);
    expect(r.covered, isFalse);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/features/payroll/paid_leave_matcher_test.dart`
Expected: FAIL — `paid_leave_matcher.dart` does not exist.

- [ ] **Step 3: Write the matcher**

Create `lib/features/payroll/leave/paid_leave_matcher.dart`:

```dart
import 'package:decimal/decimal.dart';

/// One APPROVED leave request, reduced to what paid-leave resolution needs.
/// `start`/`end` are inclusive calendar dates (UTC midnight).
class ApprovedLeaveDay {
  final DateTime start;
  final DateTime end;
  final bool isPaid;
  final String typeName;
  final Decimal leaveDays;
  const ApprovedLeaveDay({
    required this.start,
    required this.end,
    required this.isPaid,
    required this.typeName,
    required this.leaveDays,
  });
}

/// Result of resolving a single attendance date against approved leaves.
class PaidLeaveResolution {
  /// An approved request (paid or unpaid) spans this date.
  final bool covered;

  /// A PAID approved request spans this date.
  final bool isPaid;

  /// Paid fraction for the day: 0.0, 0.5, or 1.0.
  final Decimal fraction;

  /// Name of the covering paid type (null unless [isPaid]).
  final String? typeName;

  const PaidLeaveResolution({
    required this.covered,
    required this.isPaid,
    required this.fraction,
    required this.typeName,
  });

  static const none = PaidLeaveResolution(
    covered: false,
    isPaid: false,
    fraction: _zero,
    typeName: null,
  );
}

const Decimal _zero = Decimal.zero;

bool _spans(ApprovedLeaveDay r, DateTime date) {
  final d = DateTime.utc(date.year, date.month, date.day);
  final s = DateTime.utc(r.start.year, r.start.month, r.start.day);
  final e = DateTime.utc(r.end.year, r.end.month, r.end.day);
  return !d.isBefore(s) && !d.isAfter(e);
}

/// Resolve whether [date] is a paid leave day. Only ON_LEAVE attendance days
/// ([statusIsLeave] true) are ever considered covered/paid here — the
/// attendance status is authoritative for "was the person on leave," and the
/// approved request supplies the paid flag, type, and fraction.
///
/// Fraction rule: a covering PAID request that is single-date with
/// leaveDays <= 0.5 pays half; everything else pays a full day. (Multi-day
/// half-day spans are rare and treated as full days — refined only if needed.)
PaidLeaveResolution resolvePaidLeaveForDay({
  required DateTime date,
  required bool statusIsLeave,
  required List<ApprovedLeaveDay> approved,
}) {
  if (!statusIsLeave) return PaidLeaveResolution.none;
  ApprovedLeaveDay? covering;
  for (final r in approved) {
    if (_spans(r, date)) {
      covering = r;
      // Prefer a paid covering request if multiple overlap.
      if (r.isPaid) break;
    }
  }
  if (covering == null) return PaidLeaveResolution.none;
  if (!covering.isPaid) {
    return const PaidLeaveResolution(
      covered: true,
      isPaid: false,
      fraction: _zero,
      typeName: null,
    );
  }
  final half = _sameDate(covering.start, covering.end) &&
      covering.leaveDays <= Decimal.parse('0.5');
  return PaidLeaveResolution(
    covered: true,
    isPaid: true,
    fraction: half ? Decimal.parse('0.5') : Decimal.one,
    typeName: covering.typeName,
  );
}

bool _sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
```

Note: if `const PaidLeaveResolution(... fraction: _zero ...)` fails to compile because `Decimal.zero` is not a `const` — replace the `none`/unpaid constants with non-const factory constructors or a top-level `final` and drop `const`. Verify `Decimal.zero`/`Decimal.one` const-ness against the `decimal` package version in `pubspec.lock`; if not const, make `none` a `static final` and the unpaid branch a plain (non-const) constructor.

- [ ] **Step 4: Run the matcher tests to verify they pass**

Run: `flutter test test/features/payroll/paid_leave_matcher_test.dart`
Expected: PASS (all six).

- [ ] **Step 5: Wire the matcher into `compute_service`**

In `lib/features/payroll/runs/compute/compute_service.dart`:

(a) In the per-employee build (the method that produces `EmployeePayrollInput`, around line 700-818), load the employee's APPROVED leave requests overlapping the period, joined with their type's `is_paid` and `name`, and build `List<ApprovedLeaveDay>`. Add near the other per-employee loads:

```dart
    // Approved paid/unpaid leaves overlapping the period — drives the
    // PAID_LEAVE line + the unmatched-leave warning.
    final leaveRows = await _client
        .from('leave_requests')
        .select('start_date, end_date, leave_days, '
            'leave_types!inner(is_paid, name, code)')
        .eq('employee_id', employeeId)
        .eq('status', 'APPROVED')
        .lte('start_date', payPeriod.endDate.toIso8601String().substring(0, 10))
        .gte('end_date', payPeriod.startDate.toIso8601String().substring(0, 10));
    final approvedLeaves = <ApprovedLeaveDay>[
      for (final r in (leaveRows as List).cast<Map<String, dynamic>>())
        ApprovedLeaveDay(
          start: DateTime.parse(r['start_date'] as String),
          end: DateTime.parse(r['end_date'] as String),
          isPaid: (r['leave_types'] as Map<String, dynamic>?)?['is_paid'] as bool? ?? false,
          typeName: ((r['leave_types'] as Map<String, dynamic>?)?['name'] as String?) ??
              ((r['leave_types'] as Map<String, dynamic>?)?['code'] as String?) ??
              'Leave',
          leaveDays: Decimal.tryParse((r['leave_days'] ?? '1').toString()) ?? Decimal.one,
        ),
    ];
```

Add the import at the top of the file:

```dart
import '../../leave/paid_leave_matcher.dart';
```

(b) Thread `approvedLeaves` into `_attendanceFromRow`. Change the map call (around line 762) to pass it, and add the parameter to `_attendanceFromRow`'s signature:

```dart
    final attendanceInputs = attendance
        .map((r) => _attendanceFromRow(r, shifts, defaultShift, compRateFor, approvedLeaves))
        .whereType<e.AttendanceDayInput>()
        .toList();
```

```dart
  e.AttendanceDayInput? _attendanceFromRow(
    Map<String, dynamic> r,
    Map<String, Map<String, dynamic>> shifts,
    Map<String, dynamic>? defaultShift,
    Decimal? Function(DateTime) compRateFor,
    List<ApprovedLeaveDay> approvedLeaves,
  ) {
```

(c) Replace the hardcoded leave fields at the `AttendanceDayInput` return (currently `isOnLeave: status.contains('LEAVE'), leaveIsPaid: false,`, ~line 1059-1061) with:

```dart
      isOnLeave: status.contains('LEAVE'),
      leaveIsPaid: _paidLeaveFor(attendanceDate, status, approvedLeaves).isPaid,
      paidLeaveFraction: _paidLeaveFor(attendanceDate, status, approvedLeaves).fraction,
      leaveTypeName: _paidLeaveFor(attendanceDate, status, approvedLeaves).typeName,
```

To avoid resolving three times, compute once above the return:

```dart
    final leaveRes = resolvePaidLeaveForDay(
      date: attendanceDate,
      statusIsLeave: status.contains('LEAVE'),
      approved: approvedLeaves,
    );
```

and use `leaveRes.isPaid` / `leaveRes.fraction` / `leaveRes.typeName` in the return. (`attendanceDate` and `status` are already in scope in `_attendanceFromRow`.)

- [ ] **Step 6: Analyze the changed service (no new unit test for the I/O wiring)**

Run: `flutter analyze lib/features/payroll/runs/compute/compute_service.dart lib/features/payroll/leave/paid_leave_matcher.dart`
Expected: No issues. (The matcher's behavior is covered by Step 1's unit tests; the Supabase query + wiring is verified in the GUI smoke at the end of Task 4, matching the repo's convention for untested I/O glue.)

- [ ] **Step 7: Commit**

```bash
git add lib/features/payroll/leave/paid_leave_matcher.dart lib/features/payroll/runs/compute/compute_service.dart test/features/payroll/paid_leave_matcher_test.dart
git commit -m "feat(payroll): resolve approved paid leave per attendance day in compute_service"
```

---

### Task 4: Run warning for ON_LEAVE days with no matching approved paid request

**Files:**
- Modify: `lib/features/payroll/runs/detail/warnings.dart` (`WarningType` enum ~line 6, `detectWarnings` ~line 36+)
- Modify: the warnings provider/call site that invokes `detectWarnings` (find via `grep -rn detectWarnings lib/`)
- Test: `test/features/payroll/leave_warning_test.dart`

**Interfaces:**
- Consumes: `ApprovedLeaveDay`, `resolvePaidLeaveForDay` (Task 3); `AttendanceDay.attendanceStatus`.
- Produces: a new `WarningType.leaveWithoutApprovedRequest` and warnings emitted by `detectWarnings` for any attendance record whose `attendanceStatus` contains `LEAVE` but which `resolvePaidLeaveForDay(...).covered == false`. `detectWarnings` gains a parameter `Map<String, List<ApprovedLeaveDay>> approvedLeavesByEmployee = const {}` (default empty → no leave warnings, so existing callers/tests are unaffected until wired).

- [ ] **Step 1: Write the failing test**

Create `test/features/payroll/leave_warning_test.dart`. Inspect `test/` for an existing `detectWarnings` test to copy the `AttendanceDay`/`ShiftTemplate` builders; if none exists, build minimal fixtures from the real models. Skeleton:

```dart
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/attendance_day.dart';
import 'package:payroll_flutter/features/payroll/leave/paid_leave_matcher.dart';
import 'package:payroll_flutter/features/payroll/runs/detail/warnings.dart';

// Build an AttendanceDay with attendance_status ON_LEAVE for `empId`/`date`.
// (Match the real AttendanceDay constructor — see lib/data/models/attendance_day.dart.)

void main() {
  test('ON_LEAVE day with no covering approved request yields a warning', () {
    final rec = /* AttendanceDay: employeeId 'e1', date 2026-01-06, status 'ON_LEAVE' */;
    final warnings = detectWarnings(
      records: [rec],
      shiftsById: const {},
      today: DateTime.utc(2026, 2, 1),
      approvedLeavesByEmployee: const {}, // no approvals → warning
    );
    expect(
      warnings.where((w) => w.type == WarningType.leaveWithoutApprovedRequest),
      hasLength(1),
    );
  });

  test('ON_LEAVE day covered by an approved request yields no leave warning', () {
    final rec = /* AttendanceDay: employeeId 'e1', date 2026-01-06, status 'ON_LEAVE' */;
    final warnings = detectWarnings(
      records: [rec],
      shiftsById: const {},
      today: DateTime.utc(2026, 2, 1),
      approvedLeavesByEmployee: {
        'e1': [
          ApprovedLeaveDay(
            start: DateTime.utc(2026, 1, 6),
            end: DateTime.utc(2026, 1, 6),
            isPaid: true,
            typeName: 'SIL',
            leaveDays: Decimal.one,
          ),
        ],
      },
    );
    expect(
      warnings.where((w) => w.type == WarningType.leaveWithoutApprovedRequest),
      isEmpty,
    );
  });
}
```

Fill the two `AttendanceDay` fixtures with the real constructor before running.

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/payroll/leave_warning_test.dart`
Expected: FAIL — `WarningType.leaveWithoutApprovedRequest` and the `approvedLeavesByEmployee` parameter don't exist.

- [ ] **Step 3: Extend `detectWarnings`**

In `lib/features/payroll/runs/detail/warnings.dart`:

Add the enum value:

```dart
enum WarningType {
  missingClockOut,
  missingClockIn,
  invalidWorkedTime,
  unapprovedOvertime,
  leaveWithoutApprovedRequest,
}
```

Add the parameter and the scan. Add `import '../../leave/paid_leave_matcher.dart';` and the `data/models/attendance_day.dart` import if not present. Extend the signature:

```dart
List<RunWarning> detectWarnings({
  required List<AttendanceDay> records,
  required Map<String, ShiftTemplate> shiftsById,
  required DateTime today,
  int unapprovedOtThresholdMinutes = kUnapprovedOtThresholdMinutes,
  Map<String, List<ApprovedLeaveDay>> approvedLeavesByEmployee = const {},
}) {
```

Inside the per-record loop (after the existing future-day skip), add:

```dart
    final status = r.attendanceStatus.toUpperCase();
    if (status.contains('LEAVE')) {
      final approved = approvedLeavesByEmployee[r.employeeId] ?? const [];
      final res = resolvePaidLeaveForDay(
        date: r.attendanceDate,
        statusIsLeave: true,
        approved: approved,
      );
      if (!res.covered) {
        out.add(RunWarning(
          employeeId: r.employeeId,
          employeeLabel: /* existing label expression used by other warnings */,
          date: r.attendanceDate,
          type: WarningType.leaveWithoutApprovedRequest,
          message: 'On leave with no matching approved leave request — '
              'pay treatment cannot be determined.',
        ));
      }
    }
```

(Use the same `employeeLabel` source the other `RunWarning`s in this function use — copy that expression verbatim. `r.employeeId`/`r.attendanceDate`/`r.attendanceStatus` are real `AttendanceDay` fields; verify names against `lib/data/models/attendance_day.dart`.)

- [ ] **Step 4: Wire approved leaves into the warnings call site**

Find the provider/widget that calls `detectWarnings` (`grep -rn detectWarnings lib/features/payroll/runs/detail/`). At that call site, fetch the run period's APPROVED leaves grouped by employee and pass `approvedLeavesByEmployee`. Reuse the same query shape as Task 3 Step 5(a) but for all employees in the run (drop the `.eq('employee_id', …)` filter; group client-side by `employee_id`). If the call site is a synchronous pure function fed by a provider, add a sibling `FutureProvider` that loads the grouped leaves and combine it where the warnings are built. Keep the default empty-map behavior so any other caller is unaffected.

- [ ] **Step 5: Run the leave-warning test + full warnings/engine regression**

Run: `flutter test test/features/payroll/leave_warning_test.dart`
Expected: PASS (both).

Run: `flutter test test/engine/ test/features/payroll/`
Expected: PASS — no regressions.

Run: `flutter analyze lib/features/payroll/`
Expected: No issues.

- [ ] **Step 6: Commit**

```bash
git add lib/features/payroll/runs/detail/warnings.dart test/features/payroll/leave_warning_test.dart <warnings call-site file>
git commit -m "feat(payroll): warn on ON_LEAVE days without a matching approved leave request"
```

- [ ] **Step 7: Manual GUI smoke (run the app)**

Run: `flutter run -d linux --dart-define-from-file=env/prod.json`

Checklist:
1. Pick/create a run whose period contains an employee with an APPROVED **paid** leave (SIL) day (sync leaves first if needed via Lark settings). Recompute the run.
2. DAILY/HOURLY employee: payslip shows a "Paid Leave — SIL (N day/s)" earning line at the daily rate; net pay reflects it; no absence deduction for that day.
3. MONTHLY employee: basic pay unchanged (full period), a zero-amount "Paid Leave — SIL" info line present, no deduction.
4. An employee with an ON_LEAVE attendance day but NO approved leave request: the run's Warnings tab shows "On leave with no matching approved leave request."
5. An UNPAID-type approved leave: no paid-leave earning line, existing behavior unchanged.

Report results honestly; fix any failure before closing out. Note in the report that migration `20260731000001` must be applied to prod (`supabase db push`) before the PAID_LEAVE line can persist on a released run.

---

## Self-Review (completed)

- **Spec coverage (Component 2 + warning):** PAID_LEAVE category → Task 1; separate earning line for DAILY/HOURLY + zero-amount info line for MONTHLY + is_paid-driven + half-day → Task 2; approved-leave load and per-day resolution (replacing hardcoded `leaveIsPaid:false`) → Task 3; unmatched ON_LEAVE warning → Task 4. Balance sync, profile display, and year-end SIL conversion are explicitly out of this plan (separate plan, per the split decision). ✔
- **Placeholder scan:** the two `AttendanceDay` fixtures in Task 4 Step 1 and the `employeeLabel`/call-site references are marked to fill from the real model/function — these are intentional "match the real constructor" instructions with the exact source named, not vague placeholders. All engine/matcher code is complete. ✔
- **Type consistency:** `paidLeaveFraction` (Decimal, via nullable field + getter), `leaveTypeName` (String?), `ApprovedLeaveDay`, `PaidLeaveResolution` (`covered`/`isPaid`/`fraction`/`typeName`), `resolvePaidLeaveForDay`, `WarningType.leaveWithoutApprovedRequest`, `PayslipLineCategory.PAID_LEAVE` used identically across tasks. Const-ness of `Decimal.zero`/`Decimal.one` flagged as a verify-at-implementation point in Tasks 2 and 3. ✔
- **Known limitation (documented, in scope by decision):** mixed days (ON_LEAVE + worked minutes) are not auto-paid; they surface via basic pay (worked portion) and can be flagged. Half-day paid leave is handled only for single-date requests. ✔
