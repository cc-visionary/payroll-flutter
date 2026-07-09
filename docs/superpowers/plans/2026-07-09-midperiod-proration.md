# Mid-Period Pro-Rated Compensation Effective Dates — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a compensation change take effect on its effective date rather than for the whole pay period, so a raise effective July 17 pays the old rate July 1–16 and the new rate July 17–31.

**Architecture:** The payroll engine is already fully per-day — every rate path resolves through `getDayRates(rates, hpd, day.dailyRateOverride)`. So earnings proration is plumbing in `compute_service`: for each attendance day, resolve the compensation effective on that day and set `dailyRateOverride` when it differs from the period-end regime. Two small engine changes ride along: the MONTHLY basic-pay branch groups by rate (making the split visible), and the non-override tax basis switches from a notional `rate × workDays` to the actual computed pay.

**Tech Stack:** Flutter, Dart `decimal` (never `double` for money), `flutter_test`.

## Global Constraints

- Package import prefix is `package:payroll_flutter/…` (tests). `lib/` files use **relative** imports. Run tests with `flutter test <path>`.
- Repo gates on `flutter analyze` (0 errors). It has ~189 pre-existing info/warning lints — **add zero new ones**. Do NOT run `dart format`; match each file's surrounding style.
- Money is `Decimal` (`package:decimal/decimal.dart`), never `double`.
- Wage types are exactly `'MONTHLY' | 'DAILY' | 'HOURLY'`. Change statuses exactly `'SCHEDULED' | 'APPLIED' | 'CANCELLED'`.
- **INVARIANT 1 — `declared_wage_override` still wins.** In `compute_engine`'s tax block, the `if (employee.statutoryOverride != null)` branch must remain byte-for-byte unchanged in behavior, for BOTH statutory and tax. All tax changes are confined to the `else` branch.
- **INVARIANT 2 — no compensation rows ⇒ no behavior change.** An employee with no `compensation_changes` must produce `dailyRateOverride == null` on every day and therefore byte-identical payslips. The existing 590-test suite guards this.
- **INVARIANT 3 — manual per-day override wins.** `attendance_day_records.daily_rate_override` beats the compensation-derived rate.
- **INVARIANT 4 — single distinct rate ⇒ today's exact line.** The MONTHLY branch with one rate must emit the current single line (`'Basic Pay (Monthly)'` / `'Basic Pay (Semi-Monthly)'`, no `quantity`/`rate` fields).
- Statutory `monthlyGross = rates.msc` (`compute_engine.dart:335`) is **not modified**. `getDayRates` already preserves `msc` from the period-level rates.
- **The daily rate is the universal unit.** `getDayRates(rates, hpd, overrideDailyRate)` derives that day's hourly and minute rates from the override, so OT, night differential, and late/undertime automatically follow the day's rate for every wage type. Never add a parallel per-day rate mechanism.
- **There is no second basic-pay path.** `payslip_generator.generateBasicPayLine` and `wage_calculator.calculateBasicPay` are dead code (nothing calls them). `compute_engine` computes basic pay inline. Do not "fix" the dead functions.
- The only `wageType`-dependent *math* (besides rate derivation) is `compute_engine.dart:100` — paid-leave days count as workdays for MONTHLY only. Task 6's guard exists solely to avoid that edge; do not touch line 100.
- Multiple Claude sessions share this working dir — implement on an isolated git worktree/branch. No migration needed (no schema change).

Existing engine helpers you may use (all private, already in `compute_engine.dart`): `_round3`, `_fromInt(int)`, `_fromDouble(double)`, `_div(a,b)`, and `class _RateGroup` (`:554`).

---

### Task 1: Pure `dailyRateFrom` helper

**Files:**
- Create: `lib/features/payroll/engine/daily_rate.dart`
- Test: `test/engine/daily_rate_test.dart`

**Interfaces:**
- Produces: `Decimal dailyRateFrom({required Decimal baseSalary, required String wageType, required int workDaysPerMonth, required int hoursPerDay})` — MONTHLY → `baseSalary / workDaysPerMonth` (scale 10); DAILY → `baseSalary`; HOURLY → `baseSalary * hoursPerDay`. Mirrors the switch in `wage_calculator.dart` so the two cannot disagree. Returns an **unrounded** Decimal — `getDayRates` applies `_round3`.

- [ ] **Step 1: Write the failing test**

Create `test/engine/daily_rate_test.dart`:

```dart
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/payroll/engine/daily_rate.dart';

Decimal _d(String s) => Decimal.parse(s);

void main() {
  group('dailyRateFrom', () {
    test('MONTHLY divides by workDaysPerMonth', () {
      // 26000 / 26 = 1000 exactly — avoids scale ambiguity.
      expect(
        dailyRateFrom(
          baseSalary: _d('26000'),
          wageType: 'MONTHLY',
          workDaysPerMonth: 26,
          hoursPerDay: 8,
        ),
        _d('1000'),
      );
    });

    test('MONTHLY non-exact division keeps precision (scale 10)', () {
      final expected =
          (_d('30000') / Decimal.fromInt(26)).toDecimal(scaleOnInfinitePrecision: 10);
      expect(
        dailyRateFrom(
          baseSalary: _d('30000'),
          wageType: 'MONTHLY',
          workDaysPerMonth: 26,
          hoursPerDay: 8,
        ),
        expected,
      );
    });

    test('DAILY returns the base salary unchanged', () {
      expect(
        dailyRateFrom(
          baseSalary: _d('850'),
          wageType: 'DAILY',
          workDaysPerMonth: 26,
          hoursPerDay: 8,
        ),
        _d('850'),
      );
    });

    test('HOURLY multiplies by hoursPerDay', () {
      expect(
        dailyRateFrom(
          baseSalary: _d('100'),
          wageType: 'HOURLY',
          workDaysPerMonth: 26,
          hoursPerDay: 8,
        ),
        _d('800'),
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/engine/daily_rate_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '.../daily_rate.dart'`.

- [ ] **Step 3: Write the implementation**

Create `lib/features/payroll/engine/daily_rate.dart`:

```dart
import 'package:decimal/decimal.dart';

Decimal _div(Decimal a, Decimal b) =>
    (a / b).toDecimal(scaleOnInfinitePrecision: 10);

/// Daily rate implied by a compensation snapshot.
///
/// Mirrors the wage-type switch in `wage_calculator.dart` so the two cannot
/// disagree. Returns an UNROUNDED value — `getDayRates` applies `_round3`
/// when it consumes this as a per-day override.
Decimal dailyRateFrom({
  required Decimal baseSalary,
  required String wageType,
  required int workDaysPerMonth,
  required int hoursPerDay,
}) {
  switch (wageType) {
    case 'DAILY':
      return baseSalary;
    case 'HOURLY':
      return baseSalary * Decimal.fromInt(hoursPerDay);
    case 'MONTHLY':
    default:
      return _div(baseSalary, Decimal.fromInt(workDaysPerMonth));
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/engine/daily_rate_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Verify analyze + commit**

Run: `flutter analyze lib/features/payroll/engine/daily_rate.dart test/engine/daily_rate_test.dart`
Expected: `No issues found!`

```bash
git add lib/features/payroll/engine/daily_rate.dart test/engine/daily_rate_test.dart
git commit -m "feat(payroll): pure dailyRateFrom helper"
```

---

### Task 2: Pure `proratedDailyRateOverride` resolver

**Files:**
- Modify: `lib/features/payroll/engine/daily_rate.dart` (append)
- Test: `test/engine/prorated_override_test.dart`

**Interfaces:**
- Consumes: `dailyRateFrom(...)` (Task 1); `effectiveCompensation(List<CompensationChange>, DateTime)` from `lib/features/payroll/engine/effective_compensation.dart`; `CompensationChange` from `lib/data/models/compensation_change.dart`.
- Produces:
```dart
Decimal? proratedDailyRateOverride({
  required List<CompensationChange> comp,
  required DateTime attendanceDate,
  required DateTime periodEnd,
  required Decimal scorecardBaseSalary,
  required String scorecardWageType,
  required int workDaysPerMonth,
  required int hoursPerDay,
});
```
Returns `null` when the day's effective change is the **same regime** as the period-end effective change (compared by **identity**: `dayEff?.id == periodEndEff?.id`, so both-null ⇒ null). Otherwise returns the daily rate implied by the day's effective change (or by the scorecard when the day predates every change).

- [ ] **Step 1: Write the failing test**

Create `test/engine/prorated_override_test.dart`:

```dart
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/compensation_change.dart';
import 'package:payroll_flutter/features/payroll/engine/daily_rate.dart';

Decimal _d(String s) => Decimal.parse(s);

CompensationChange _change({
  required String id,
  required String effective,
  required String newSalary,
  String status = 'SCHEDULED',
  String wageType = 'MONTHLY',
  String created = '2026-07-01T00:00:00Z',
}) =>
    CompensationChange(
      id: id,
      companyId: 'CO1',
      employeeId: 'E1',
      changeType: 'SALARY_INCREASE',
      status: status,
      effectiveDate: DateTime.parse(effective),
      prevBaseSalary: _d('30000'),
      newBaseSalary: _d(newSalary),
      newWageType: wageType,
      initiatedById: 'U1',
      createdAt: DateTime.parse(created),
    );

Decimal? _resolve(List<CompensationChange> comp, String day) =>
    proratedDailyRateOverride(
      comp: comp,
      attendanceDate: DateTime.parse(day),
      periodEnd: DateTime.parse('2026-07-31'),
      scorecardBaseSalary: _d('30000'),
      scorecardWageType: 'MONTHLY',
      workDaysPerMonth: 26,
      hoursPerDay: 8,
    );

void main() {
  final raise = [_change(id: 'C1', effective: '2026-07-17', newSalary: '38000')];

  test('no compensation rows -> null on every day (invariant 2)', () {
    expect(_resolve(const [], '2026-07-05'), isNull);
    expect(_resolve(const [], '2026-07-31'), isNull);
  });

  test('day BEFORE the effective date overrides down to the old scorecard rate', () {
    final r = _resolve(raise, '2026-07-16');
    expect(r, isNotNull);
    expect(
      r,
      dailyRateFrom(
        baseSalary: _d('30000'),
        wageType: 'MONTHLY',
        workDaysPerMonth: 26,
        hoursPerDay: 8,
      ),
    );
  });

  test('the effective date itself uses the new rate -> null (matches standard)', () {
    // periodEnd resolves to C1 too, so the day is in the same regime.
    expect(_resolve(raise, '2026-07-17'), isNull);
  });

  test('day AFTER the effective date -> null (same regime as period end)', () {
    expect(_resolve(raise, '2026-07-31'), isNull);
  });

  test('CANCELLED change is ignored -> null everywhere', () {
    final cancelled = [
      _change(id: 'C1', effective: '2026-07-17', newSalary: '38000', status: 'CANCELLED'),
    ];
    expect(_resolve(cancelled, '2026-07-05'), isNull);
    expect(_resolve(cancelled, '2026-07-31'), isNull);
  });

  test('two changes in one period: each day resolves to its own regime', () {
    final comp = [
      _change(id: 'C1', effective: '2026-07-10', newSalary: '34000'),
      _change(id: 'C2', effective: '2026-07-20', newSalary: '38000'),
    ];
    // Before any change -> scorecard rate.
    expect(
      _resolve(comp, '2026-07-05'),
      dailyRateFrom(baseSalary: _d('30000'), wageType: 'MONTHLY', workDaysPerMonth: 26, hoursPerDay: 8),
    );
    // Between C1 and C2 -> C1's rate.
    expect(
      _resolve(comp, '2026-07-15'),
      dailyRateFrom(baseSalary: _d('34000'), wageType: 'MONTHLY', workDaysPerMonth: 26, hoursPerDay: 8),
    );
    // On/after C2 -> same regime as period end -> null.
    expect(_resolve(comp, '2026-07-25'), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/engine/prorated_override_test.dart`
Expected: FAIL — `proratedDailyRateOverride` is not defined.

- [ ] **Step 3: Append the implementation**

Append to `lib/features/payroll/engine/daily_rate.dart` (and add the two imports at the top of the file):

```dart
import '../../../data/models/compensation_change.dart';
import 'effective_compensation.dart';
```

```dart
/// The per-day `dailyRateOverride` implied by an employee's compensation
/// history, or `null` when the day belongs to the same compensation regime as
/// the period end (in which case the engine's period-level standard rate is
/// already correct).
///
/// Regimes are compared by change IDENTITY, not by rate value: two different
/// salaries can round to the same daily rate, and both sides get `_round3`-ed
/// downstream, so a value comparison would be fragile in both directions.
/// `dayEff == periodEndEff == null` (no compensation rows) yields `null`,
/// which is what preserves byte-identical payslips for untouched employees.
Decimal? proratedDailyRateOverride({
  required List<CompensationChange> comp,
  required DateTime attendanceDate,
  required DateTime periodEnd,
  required Decimal scorecardBaseSalary,
  required String scorecardWageType,
  required int workDaysPerMonth,
  required int hoursPerDay,
}) {
  final periodEndEff = effectiveCompensation(comp, periodEnd);
  final dayEff = effectiveCompensation(comp, attendanceDate);
  if (dayEff?.id == periodEndEff?.id) return null;

  if (dayEff == null) {
    // The day predates every change -> the pre-change (scorecard) rate.
    return dailyRateFrom(
      baseSalary: scorecardBaseSalary,
      wageType: scorecardWageType,
      workDaysPerMonth: workDaysPerMonth,
      hoursPerDay: hoursPerDay,
    );
  }
  return dailyRateFrom(
    baseSalary: dayEff.newBaseSalary ?? scorecardBaseSalary,
    wageType: dayEff.newWageType ?? scorecardWageType,
    workDaysPerMonth: workDaysPerMonth,
    hoursPerDay: hoursPerDay,
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/engine/prorated_override_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Verify analyze + commit**

Run: `flutter analyze lib/features/payroll/engine/daily_rate.dart test/engine/prorated_override_test.dart`
Expected: `No issues found!`

```bash
git add lib/features/payroll/engine/daily_rate.dart test/engine/prorated_override_test.dart
git commit -m "feat(payroll): per-day prorated rate override resolver"
```

---

### Task 3: Wire per-day overrides into `compute_service`

**Files:**
- Modify: `lib/features/payroll/runs/compute/compute_service.dart`

**Interfaces:**
- Consumes: `proratedDailyRateOverride(...)` (Task 2).
- Produces: `_attendanceFromRow` gains a `Decimal? Function(DateTime) compRateFor` parameter; each `AttendanceDayInput` now carries a compensation-derived `dailyRateOverride` when its day differs from the period-end regime. Manual `daily_rate_override` still wins.

- [ ] **Step 1: Add the import**

At the top of `lib/features/payroll/runs/compute/compute_service.dart`, alongside the existing `import '../../engine/effective_compensation.dart';`, add:

```dart
import '../../engine/daily_rate.dart';
```

- [ ] **Step 2: Build the per-day resolver inside `_buildEmployeeInput`**

`_buildEmployeeInput` (starts `:631`) already has `roleCard`, `comp`, `payPeriod`, and `hoursPerDay` in scope, and it resolves the period-end `effective` compensation. Immediately **before** the `attendanceInputs` construction (`:737`), add:

```dart
    // Per-day compensation regime -> pro-rated daily rate. Returns null when
    // the day shares the period-end regime (the engine's standard rate is then
    // already correct), which is always the case when the employee has no
    // compensation_changes rows.
    final scorecardBase =
        Decimal.tryParse((roleCard['base_salary'] ?? '0').toString()) ??
            Decimal.zero;
    final scorecardWageType = (roleCard['wage_type'] as String?) ?? 'DAILY';
    Decimal? compRateFor(DateTime day) => proratedDailyRateOverride(
          comp: comp,
          attendanceDate: day,
          periodEnd: payPeriod.endDate,
          scorecardBaseSalary: scorecardBase,
          scorecardWageType: scorecardWageType,
          workDaysPerMonth: 26,
          hoursPerDay: hoursPerDay,
        );
```

(`26` is the same `standardWorkDaysPerMonth` the profile is built with a few lines below — keep them consistent.)

- [ ] **Step 3: Pass the resolver into the row mapper**

Change the `attendanceInputs` construction (`:737`) from:

```dart
    final attendanceInputs =
        attendance
            .map((r) => _attendanceFromRow(r, shifts, defaultShift))
            .whereType<e.AttendanceDayInput>()
            .toList();
```

to:

```dart
    final attendanceInputs =
        attendance
            .map((r) => _attendanceFromRow(r, shifts, defaultShift, compRateFor))
            .whereType<e.AttendanceDayInput>()
            .toList();
```

- [ ] **Step 4: Apply the override in `_attendanceFromRow` (manual wins)**

In `_attendanceFromRow`, add the fourth positional parameter to its signature:

```dart
    Decimal? Function(DateTime) compRateFor,
```

Then find the existing manual-override block (`:972-979`):

```dart
    Decimal? dailyRateOverride;
    final rateRaw = r['daily_rate_override'];
    if (rateRaw != null) {
      final parsed = Decimal.tryParse(rateRaw.toString());
      if (parsed != null) dailyRateOverride = parsed;
    }
```

and append immediately after it:

```dart
    // Manual per-day override wins; otherwise fall back to the compensation-
    // derived rate for this day (null when the day matches the period-end rate).
    dailyRateOverride ??= compRateFor(attendanceDate);
```

Use the method's already-parsed attendance-date local. If it is named differently (e.g. `date`), use that name — do **not** re-parse `r['attendance_date']`.

- [ ] **Step 5: Verify no regression + analyze**

Run: `flutter analyze lib/features/payroll/runs/compute/compute_service.dart && flutter test test/engine/`
Expected: `No issues found!`, then all engine tests PASS. No fixture employee has compensation rows, so `compRateFor` returns `null` everywhere and payslips are unchanged (Invariant 2).

- [ ] **Step 6: Commit**

```bash
git add lib/features/payroll/runs/compute/compute_service.dart
git commit -m "feat(payroll): resolve per-day compensation rate overrides"
```

---

### Task 4: MONTHLY basic pay groups by rate

**Files:**
- Modify: `lib/features/payroll/engine/compute_engine.dart:111-150`
- Test: `test/engine/monthly_basic_pay_split_test.dart`

**Interfaces:**
- Produces: a new local `Decimal basicPayTotalActual` in `computePayroll`, accumulating the sum of every emitted `BASIC_PAY` line amount. **Task 5 consumes it.**
- With one distinct daily rate the MONTHLY branch emits today's exact single line (Invariant 4). With two or more it emits one line per rate, in first-occurrence (chronological) order.

- [ ] **Step 1: Write the failing test**

Create `test/engine/monthly_basic_pay_split_test.dart`. It drives the engine directly, setting `dailyRateOverride` on early days to simulate what `compute_service` now produces.

```dart
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/payroll/engine/compute_engine.dart';
import 'package:payroll_flutter/features/payroll/engine/statutory_tables.dart';
import 'package:payroll_flutter/features/payroll/engine/types.dart';

Decimal _d(String s) => Decimal.parse(s);

/// 22 workdays in July 2026; `overrideBefore` is applied to days < `switchDay`.
EmployeePayrollInput _employee({
  required Decimal baseRate,
  Decimal? overrideBefore,
  int switchDay = 17,
}) {
  final profile = PayProfileInput(
    employeeId: 'EMP-001',
    wageType: WageType.MONTHLY,
    baseRate: baseRate,
    payFrequency: PayFrequency.MONTHLY,
    standardWorkDaysPerMonth: 26,
    standardHoursPerDay: 8,
    isBenefitsEligible: true,
    isOtEligible: false,
    isNdEligible: false,
    riceSubsidy: Decimal.zero,
    clothingAllowance: Decimal.zero,
    laundryAllowance: Decimal.zero,
    medicalAllowance: Decimal.zero,
    transportationAllowance: Decimal.zero,
    mealAllowance: Decimal.zero,
    communicationAllowance: Decimal.zero,
  );

  final attendance = <AttendanceDayInput>[];
  for (var day = 1; day <= 22; day++) {
    attendance.add(AttendanceDayInput(
      id: 'A$day',
      attendanceDate: DateTime.utc(2026, 7, day),
      dayType: DayType.WORKDAY,
      hoursWorked: _d('8'),
      otMinutes: 0,
      deductionMinutes: 0,
      earlyInApproved: false,
      lateOutApproved: false,
      nightDiffMinutes: 0,
      isOnLeave: false,
      leaveIsPaid: false,
      dailyRateOverride: (overrideBefore != null && day < switchDay) ? overrideBefore : null,
    ));
  }

  return EmployeePayrollInput(
    profile: profile,
    regularization: null,
    attendance: attendance,
    manualAdjustments: const [],
    reimbursements: const [],
    cashAdvanceDeductions: const [],
    previousYtd: PreviousYtd(
      grossPay: Decimal.zero, taxableIncome: Decimal.zero, taxWithheld: Decimal.zero),
    taxOnFullEarnings: false,
    statutoryOverride: null,
    penaltyDeductions: const [],
  );
}

PayPeriodInput get _july => PayPeriodInput(
      id: 'PP-7',
      startDate: DateTime.utc(2026, 7, 1),
      endDate: DateTime.utc(2026, 7, 31),
      cutoffDate: DateTime.utc(2026, 7, 31),
      payDate: DateTime.utc(2026, 8, 5),
      periodNumber: 7,
      payFrequency: PayFrequency.MONTHLY,
    );

RulesetInput get _ruleset => RulesetInput(
      id: 'r', version: 1,
      sssTable: SSS_TABLE, philhealthTable: PHILHEALTH_TABLE,
      pagibigTable: PAGIBIG_TABLE, taxTable: TAX_TABLE,
    );

List<ComputedPayslipLine> _basicPayLines(EmployeePayrollInput emp) {
  final result = computePayroll(_july, _ruleset, [emp]);
  return result.payslips.single.lines
      .where((l) => l.category == PayslipLineCategory.BASIC_PAY)
      .toList();
}

void main() {
  test('single rate -> one line, no quantity/rate (invariant 4)', () {
    final lines = _basicPayLines(_employee(baseRate: _d('30000')));
    expect(lines, hasLength(1));
    expect(lines.single.description, 'Basic Pay (Monthly)');
    expect(lines.single.quantity, isNull);
    expect(lines.single.rate, isNull);
  });

  test('two rates -> two lines, old rate first, summing to the per-day total', () {
    // Standard = 38000/26; days 1..16 overridden to 30000/26.
    final oldRate = (_d('30000') / Decimal.fromInt(26))
        .toDecimal(scaleOnInfinitePrecision: 10);
    final lines = _basicPayLines(
      _employee(baseRate: _d('38000'), overrideBefore: oldRate, switchDay: 17),
    );

    expect(lines, hasLength(2));
    // First-occurrence order: the overridden (old) rate is day 1.
    expect(lines[0].quantity, Decimal.fromInt(16));
    expect(lines[1].quantity, Decimal.fromInt(6));
    expect(lines[0].description, 'Basic Pay (Monthly) — 16 days');
    expect(lines[1].description, 'Basic Pay (Monthly) — 6 days');
    // Old rate strictly below the new rate.
    expect(lines[0].rate! < lines[1].rate!, isTrue);

    final total = lines.fold<Decimal>(Decimal.zero, (a, l) => a + l.amount);
    final expected = lines[0].rate! * Decimal.fromInt(16) +
        lines[1].rate! * Decimal.fromInt(6);
    expect(total, expected);
  });
}
```

> Before running, open `lib/features/payroll/engine/types.dart` and confirm the exact constructor parameter names for `PayProfileInput`, `AttendanceDayInput`, `EmployeePayrollInput`, `PreviousYtd`, and `RulesetInput`, plus the shape of `computePayroll(...)`'s return (`result.payslips.single.lines`). Copy the fixture style from `test/engine/smoke_test.dart`, which already builds these. Adjust the fixture to the real names — do **not** invent parameters.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/engine/monthly_basic_pay_split_test.dart`
Expected: FAIL — the two-rate test gets 1 line (`hasLength(2)` fails), because the MONTHLY branch currently sums into a single blended line.

- [ ] **Step 3: Declare the accumulator**

In `compute_engine.dart`, immediately **before** `// 3. Basic pay lines` (`:111`), add:

```dart
  // Sum of every emitted BASIC_PAY line. Used by the tax block (step 14) so
  // withholding is based on what is actually paid when days carry different
  // rates (mid-period compensation changes, manual per-day overrides).
  Decimal basicPayTotalActual = Decimal.zero;
```

- [ ] **Step 4: Rewrite the MONTHLY branch and accumulate in both branches**

Replace the whole `if (profile.wageType == WageType.MONTHLY) { ... } else { ... }` block (`:112-150`) with:

```dart
  if (profile.wageType == WageType.MONTHLY) {
    final label = payPeriod.payFrequency == PayFrequency.SEMI_MONTHLY
        ? 'Semi-Monthly'
        : 'Monthly';

    // Group by effective daily rate, preserving first-occurrence (chronological)
    // order so the pre-change rate precedes the post-change rate.
    final rateGroups = <String, _RateGroup>{};
    for (final day in workDayAttendance) {
      final dayRates = getDayRates(rates, hpd, day.dailyRateOverride);
      final key = dayRates.dailyRate.toString();
      final g = rateGroups[key] ?? _RateGroup(dayRates.dailyRate, 0);
      rateGroups[key] = _RateGroup(dayRates.dailyRate, g.count + 1);
    }

    if (rateGroups.length <= 1) {
      // Invariant 4: one rate (or no workdays) -> today's exact single line.
      Decimal basicPayTotal = Decimal.zero;
      for (final day in workDayAttendance) {
        final dayRates = getDayRates(rates, hpd, day.dailyRateOverride);
        basicPayTotal += dayRates.dailyRate;
      }
      basicPayTotal = _round3(basicPayTotal);
      basicPayTotalActual += basicPayTotal;
      lines.add(ComputedPayslipLine(
        category: PayslipLineCategory.BASIC_PAY,
        description: 'Basic Pay ($label)',
        amount: basicPayTotal,
        sortOrder: 100,
        ruleCode: 'BASIC_PAY',
      ));
    } else {
      for (final g in rateGroups.values) {
        final amount = _round3(g.rate * _fromInt(g.count));
        basicPayTotalActual += amount;
        lines.add(ComputedPayslipLine(
          category: PayslipLineCategory.BASIC_PAY,
          description:
              'Basic Pay ($label) — ${g.count} day${g.count != 1 ? 's' : ''}',
          quantity: _fromInt(g.count),
          rate: g.rate,
          amount: amount,
          sortOrder: 100,
          ruleCode: 'BASIC_PAY',
        ));
      }
    }
  } else {
    // Group by effective daily rate
    final rateGroups = <String, _RateGroup>{};
    for (final day in workDayAttendance) {
      final dayRates = getDayRates(rates, hpd, day.dailyRateOverride);
      final key = dayRates.dailyRate.toString();
      final g = rateGroups[key] ?? _RateGroup(dayRates.dailyRate, 0);
      rateGroups[key] = _RateGroup(dayRates.dailyRate, g.count + 1);
    }
    for (final g in rateGroups.values) {
      final qty = g.count.toDouble();
      final amount = _round3(g.rate * _fromDouble(qty));
      basicPayTotalActual += amount;
      lines.add(ComputedPayslipLine(
        category: PayslipLineCategory.BASIC_PAY,
        description:
            'Basic Pay (${qty.toStringAsFixed(3)} day${g.count != 1 ? 's' : ''})',
        quantity: _fromDouble(qty),
        rate: g.rate,
        amount: amount,
        sortOrder: 100,
        ruleCode: 'BASIC_PAY',
      ));
    }
  }
```

- [ ] **Step 5: Run the new test + the whole engine suite**

Run: `flutter test test/engine/monthly_basic_pay_split_test.dart && flutter test test/engine/`
Expected: the new test PASSES (2 tests); the whole engine suite stays green — every existing fixture has a single rate, so the MONTHLY branch emits the identical line it did before.

- [ ] **Step 6: Verify analyze + commit**

Run: `flutter analyze lib/features/payroll/engine/compute_engine.dart`
Expected: `No issues found!`

```bash
git add lib/features/payroll/engine/compute_engine.dart test/engine/monthly_basic_pay_split_test.dart
git commit -m "feat(payroll): MONTHLY basic pay groups by rate"
```

---

### Task 5: Tax basis uses actual pay (non-override branch only)

**Files:**
- Modify: `lib/features/payroll/engine/compute_engine.dart:389-417`
- Test: `test/engine/tax_basis_actual_test.dart`

**Interfaces:**
- Consumes: `basicPayTotalActual` (Task 4) and the existing local `lateUtDeductionAmount` (`:180`, already per-day-rate aware via `:188`).
- Produces: in the `else` (no `statutoryOverride`) branch, `taxBasicPay` = actual summed BASIC_PAY, `taxLateUtDeduction` = actual late/UT deduction. The `statutoryOverride` branch is unchanged (Invariant 1).

- [ ] **Step 1: Write the failing test**

Create `test/engine/tax_basis_actual_test.dart`. Reuse the fixture shape from `test/engine/monthly_basic_pay_split_test.dart` (copy the `_employee` / `_july` / `_ruleset` helpers into this file — the engine tests are self-contained by convention), adding a `statutoryOverride` knob.

```dart
// ... same imports + _d + _july + _ruleset + _employee helpers as
// monthly_basic_pay_split_test.dart, but with `_employee({..., StatutoryOverride? statutoryOverride})`
// forwarded into EmployeePayrollInput.

void main() {
  test('no override: taxable basic pay equals the summed BASIC_PAY lines', () {
    final oldRate = (_d('30000') / Decimal.fromInt(26))
        .toDecimal(scaleOnInfinitePrecision: 10);
    final emp = _employee(baseRate: _d('38000'), overrideBefore: oldRate, switchDay: 17);
    final slip = computePayroll(_july, _ruleset, [emp]).payslips.single;

    final basicPay = slip.lines
        .where((l) => l.category == PayslipLineCategory.BASIC_PAY)
        .fold<Decimal>(Decimal.zero, (a, l) => a + l.amount);

    // Notional (wrong) figure would be 38000/26 * 22 workdays.
    final notional = _round3ForTest(
        (_d('38000') / Decimal.fromInt(26)).toDecimal(scaleOnInfinitePrecision: 10) *
            Decimal.fromInt(22));

    expect(basicPay < notional, isTrue,
        reason: 'pro-rated pay must be below the all-new-rate notional figure');
    // taxableIncome is derived from taxBasicPay; assert it tracks ACTUAL pay by
    // checking it moves when only the pre-change rate changes.
    expect(slip.taxableIncome, isNot(equals(Decimal.zero)));
  });

  test('statutoryOverride: statutory + tax unchanged by per-day overrides (invariant 1)', () {
    final oldRate = (_d('30000') / Decimal.fromInt(26))
        .toDecimal(scaleOnInfinitePrecision: 10);
    final override = StatutoryOverride(baseRate: _d('20000'), wageType: WageType.MONTHLY);

    final withProration = _employee(
        baseRate: _d('38000'), overrideBefore: oldRate, switchDay: 17,
        statutoryOverride: override);
    final withoutProration = _employee(
        baseRate: _d('38000'), statutoryOverride: override);

    final a = computePayroll(_july, _ruleset, [withProration]).payslips.single;
    final b = computePayroll(_july, _ruleset, [withoutProration]).payslips.single;

    expect(a.taxWithheld, b.taxWithheld);
    for (final cat in [
      PayslipLineCategory.SSS_EE, PayslipLineCategory.PHILHEALTH_EE, PayslipLineCategory.PAGIBIG_EE,
    ]) {
      Decimal sum(ComputedPayslip p) => p.lines
          .where((l) => l.category == cat)
          .fold<Decimal>(Decimal.zero, (x, l) => x + l.amount);
      expect(sum(a), sum(b), reason: '$cat must ignore per-day rates');
    }
  });
}
```

> Confirm the real names of `ComputedPayslip`, `slip.taxableIncome`, `slip.taxWithheld`, and `StatutoryOverride`'s constructor against `engine/types.dart` before running (`StatutoryOverride({required this.baseRate, required this.wageType})` per `types.dart:474`). Adjust the assertions to the real fields; keep the two behaviors being asserted. Add a tiny local `_round3ForTest` only if you actually need it — otherwise drop that line and compare against the raw product.

- [ ] **Step 2: Run test to verify the first case fails**

Run: `flutter test test/engine/tax_basis_actual_test.dart`
Expected: the invariant-1 test PASSES already; the actual-pay test FAILS or passes vacuously — before implementing, make the first test assert the concrete equality below so it genuinely goes RED.

Strengthen it to compare `taxBasicPay` indirectly through a **known-value** check: with `taxOnFullEarnings: false`, `taxableIncome` is derived from `taxBasicPay - taxLateUtDeduction - statutory`. Assert:

```dart
    // Before the fix, taxBasicPay = (38000/26) * 22 (notional, too high).
    // After the fix, taxBasicPay = summed BASIC_PAY (pro-rated, lower).
    // Therefore taxableIncome must drop by exactly (notional - basicPay).
```
Compute both runs — one with `overrideBefore` and one without — and assert the taxable-income delta equals the basic-pay delta. That is RED before Step 3 (deltas differ) and GREEN after.

- [ ] **Step 3: Rewrite the tax basis block**

Replace `compute_engine.dart:389-417` with:

```dart
    Decimal taxBasicPay;
    Decimal taxLateUtDeduction;
    if (employee.statutoryOverride != null) {
      // The BIR-declared salary ALWAYS replaces the scorecard rate for tax —
      // it is a declared figure, not a per-period actual. Unchanged.
      final workDaysPerMonth = profile.standardWorkDaysPerMonth;
      final hoursPerDay = profile.standardHoursPerDay;
      final o = employee.statutoryOverride!;
      Decimal taxDailyRate;
      switch (o.wageType) {
        case WageType.DAILY:
          taxDailyRate = o.baseRate;
          break;
        case WageType.HOURLY:
          taxDailyRate = o.baseRate * _fromInt(hoursPerDay);
          break;
        case WageType.MONTHLY:
          taxDailyRate = _div(o.baseRate, _fromInt(workDaysPerMonth));
          break;
      }
      final taxMinuteRate = _div(taxDailyRate, _fromInt(hoursPerDay * 60));
      taxBasicPay = _round3(taxDailyRate * _fromInt(workDays));
      taxLateUtDeduction =
          _round3(taxMinuteRate * _fromDouble(totalDeductionMinutes));
    } else {
      // No declared-wage override: tax the pay that was ACTUALLY computed.
      // When every day shares one rate this is arithmetically identical to the
      // old notional `rates.dailyRate * workDays`; when days differ (mid-period
      // compensation change, manual per-day override) it is the correct figure.
      taxBasicPay = basicPayTotalActual;
      taxLateUtDeduction = _round3(lateUtDeductionAmount);
    }
```

Note the old code wrapped this in a bare `{ ... }` block and declared `taxDailyRate`/`taxMinuteRate` outside the `if`. Those two locals are now only needed in the override branch — declare them there so the analyzer sees no unused variables.

- [ ] **Step 4: Run the test + the whole engine suite**

Run: `flutter test test/engine/tax_basis_actual_test.dart && flutter test test/engine/`
Expected: both new tests PASS; the whole engine suite stays green. For single-rate fixtures `basicPayTotalActual == _round3(rates.dailyRate * workDays)` and `lateUtDeductionAmount == _round3(rates.minuteRate * totalDeductionMinutes)`, so no existing payslip moves.

- [ ] **Step 5: Verify analyze + commit**

Run: `flutter analyze lib/features/payroll/engine/compute_engine.dart`
Expected: `No issues found!`

```bash
git add lib/features/payroll/engine/compute_engine.dart test/engine/tax_basis_actual_test.dart
git commit -m "feat(payroll): tax basis uses actual pay when no declared-wage override"
```

---

### Task 6: Block mid-period wage-type changes in the dialog

**Files:**
- Modify: `lib/features/employees/profile/widgets/compensation_change_dialog.dart` (`validateCompensationRequest`, `:84`)
- Test: `test/features/employees/compensation_change_dialog_test.dart` (append cases)

**Interfaces:**
- Produces: `validateCompensationRequest` gains `required String currentWageType`. When `newWageType != currentWageType` and `effectiveDate.day != 1`, it returns a `ValidationError('effectiveDate', 'A wage-type change must take effect on the 1st of a month')`.

- [ ] **Step 1: Write the failing tests**

Append to `test/features/employees/compensation_change_dialog_test.dart` (inside the existing `validateCompensationRequest` group, matching its existing helper style):

```dart
    test('wage-type change on a non-1st effective date is rejected', () {
      final errors = validateCompensationRequest(
        changeType: 'PROMOTION',
        currentSalary: Decimal.fromInt(30000),
        newSalary: Decimal.fromInt(38000),
        currentWageType: 'DAILY',
        newWageType: 'MONTHLY',
        newScorecardId: 'rc2',
        currentScorecardId: 'rc1',
        effectiveDate: DateTime(2026, 7, 17),
        reason: 'Promotion',
        employee: _employee,
        today: DateTime(2026, 7, 1),
      );
      expect(errors.map((e) => e.field), contains('effectiveDate'));
    });

    test('wage-type change on the 1st is accepted', () {
      final errors = validateCompensationRequest(
        changeType: 'PROMOTION',
        currentSalary: Decimal.fromInt(30000),
        newSalary: Decimal.fromInt(38000),
        currentWageType: 'DAILY',
        newWageType: 'MONTHLY',
        newScorecardId: 'rc2',
        currentScorecardId: 'rc1',
        effectiveDate: DateTime(2026, 8, 1),
        reason: 'Promotion',
        employee: _employee,
        today: DateTime(2026, 7, 1),
      );
      expect(errors.map((e) => e.field), isNot(contains('effectiveDate')));
    });

    test('same wage type on any date is accepted', () {
      final errors = validateCompensationRequest(
        changeType: 'SALARY_INCREASE',
        currentSalary: Decimal.fromInt(30000),
        newSalary: Decimal.fromInt(38000),
        currentWageType: 'MONTHLY',
        newWageType: 'MONTHLY',
        newScorecardId: null,
        currentScorecardId: 'rc1',
        effectiveDate: DateTime(2026, 7, 17),
        reason: 'Merit',
        employee: _employee,
        today: DateTime(2026, 7, 1),
      );
      expect(errors.map((e) => e.field), isNot(contains('effectiveDate')));
    });
```

Reuse the file's existing `_employee` fixture. Every other existing call to `validateCompensationRequest` in this test file must gain `currentWageType: '<matching value>'` — update them so the file compiles.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/employees/compensation_change_dialog_test.dart`
Expected: FAIL — `validateCompensationRequest` has no named parameter `currentWageType`.

- [ ] **Step 3: Add the parameter and the rule**

In `compensation_change_dialog.dart`, add `required String currentWageType,` to `validateCompensationRequest`'s parameter list (`:84`). Then, in the layered-rules section (after the existing direction/date checks), add:

```dart
  // Rates pro-rate fine for any wage type (the daily rate is the universal unit
  // — getDayRates derives hourly/minute from it). The ONE wageType-dependent
  // divergence is compute_engine.dart:100: paid-leave days count as workdays
  // only for MONTHLY employees. A DAILY->MONTHLY switch mid-period would apply
  // that rule to the whole period, over-counting leave taken before the switch.
  // Forcing such changes onto the 1st removes that edge.
  if (newWageType != currentWageType && effectiveDate.day != 1) {
    errors.add(const ValidationError(
      'effectiveDate',
      'A wage-type change must take effect on the 1st of a month',
    ));
  }
```

- [ ] **Step 4: Update the dialog's call site**

In the same file, the dialog's `_confirm()` calls `validateCompensationRequest(...)`. Pass the employee's current wage type — the dialog already receives `currentCard` (a `RoleScorecard?`):

```dart
    currentWageType: widget.currentCard?.wageType ?? 'MONTHLY',
```

Use the same expression the dialog already uses to seed its wage-type dropdown default, so the two cannot disagree.

- [ ] **Step 5: Run the test file + analyze**

Run: `flutter test test/features/employees/compensation_change_dialog_test.dart && flutter analyze lib/features/employees/profile/widgets/compensation_change_dialog.dart`
Expected: all tests PASS (existing 15 + 3 new); `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/features/employees/profile/widgets/compensation_change_dialog.dart test/features/employees/compensation_change_dialog_test.dart
git commit -m "feat(comp): wage-type changes must take effect on the 1st"
```

---

### Task 7: Headline scenario + invariants + full verification

**Files:**
- Test: `test/engine/midperiod_proration_test.dart`

**Interfaces:**
- Consumes: everything from Tasks 1–6.

- [ ] **Step 1: Write the scenario tests**

Create `test/engine/midperiod_proration_test.dart`. Reuse the fixture helpers from `test/engine/monthly_basic_pay_split_test.dart` (copy them in — engine tests are self-contained by convention). Cover:

```dart
void main() {
  test('HEADLINE: ₱30k -> ₱38k effective Jul 17 pro-rates a Jul 1-31 monthly run', () {
    final oldRate = (_d('30000') / Decimal.fromInt(26))
        .toDecimal(scaleOnInfinitePrecision: 10);
    final slip = computePayroll(
      _july, _ruleset,
      [_employee(baseRate: _d('38000'), overrideBefore: oldRate, switchDay: 17)],
    ).payslips.single;

    final basic = slip.lines
        .where((l) => l.category == PayslipLineCategory.BASIC_PAY)
        .toList();

    // Two lines: 16 days at the old rate, 6 at the new.
    expect(basic, hasLength(2));
    expect(basic[0].quantity, Decimal.fromInt(16));
    expect(basic[1].quantity, Decimal.fromInt(6));

    // Total is strictly between "all old" and "all new".
    final total = basic.fold<Decimal>(Decimal.zero, (a, l) => a + l.amount);
    final allOld = _round3ish(oldRate * Decimal.fromInt(22));
    final newRate = (_d('38000') / Decimal.fromInt(26))
        .toDecimal(scaleOnInfinitePrecision: 10);
    final allNew = _round3ish(newRate * Decimal.fromInt(22));
    expect(total > allOld, isTrue);
    expect(total < allNew, isTrue);
  });

  test('INVARIANT 2: no per-day overrides -> basic pay is exactly rate x workDays', () {
    // Do NOT compare two identical runs — that asserts nothing. Assert the
    // concrete pre-existing formula still holds.
    final slip = computePayroll(_july, _ruleset, [_employee(baseRate: _d('30000'))])
        .payslips.single;
    final basic = slip.lines
        .where((l) => l.category == PayslipLineCategory.BASIC_PAY)
        .toList();

    expect(basic, hasLength(1));
    expect(basic.single.description, 'Basic Pay (Monthly)');
    expect(basic.single.quantity, isNull);
    expect(basic.single.rate, isNull);

    // wage_calculator _round3's the standard daily rate: 30000/26 -> 1153.846.
    // The engine sums that rate over 22 workdays.
    final dailyRate = _d('1153.846');
    expect(basic.single.amount, dailyRate * Decimal.fromInt(22));
  });

  test('ENGINE honors a per-day override on every day', () {
    // NOTE: manual-vs-compensation PRECEDENCE lives in compute_service's `??=`
    // and is not unit-tested (Supabase-row mapper; repo convention). This test
    // asserts only what the engine guarantees: whatever dailyRateOverride it is
    // handed drives that day's rate.
    final manual = _d('999');
    final slip = computePayroll(
      _july, _ruleset,
      [_employee(baseRate: _d('30000'), overrideBefore: manual, switchDay: 23)],
    ).payslips.single;
    final basic = slip.lines
        .where((l) => l.category == PayslipLineCategory.BASIC_PAY)
        .toList();

    // All 22 days overridden to 999 -> one group at the overridden rate,
    // NOT the 1153.846 standard rate.
    expect(basic, hasLength(1));
    expect(basic.single.amount, manual * Decimal.fromInt(22));
  });
}
```

> `_round3ish` is a local 3-dp rounding helper for the comparison bounds; write it inline (`Decimal r(Decimal v) => Decimal.parse(v.toStringAsFixed(3));`) or drop the rounding and compare the raw products — the strict `>` / `<` bounds hold either way. Confirm `slip.grossPay` / `slip.netPay` field names against `engine/types.dart`.

Also add a **semi-monthly** case: `PayPeriodInput` Jul 16–31, `PayFrequency.SEMI_MONTHLY`, override applied to day 16 only, `switchDay: 17` → two BASIC_PAY lines with quantities `1` and the rest, and descriptions using the `Semi-Monthly` label.

- [ ] **Step 2: Run the scenario tests**

Run: `flutter test test/engine/midperiod_proration_test.dart`
Expected: PASS (4 tests). If the headline test fails, the bug is in Task 4's grouping or Task 5's accumulator — fix there, not by weakening the assertion.

- [ ] **Step 3: Full verification**

Run: `flutter analyze`
Expected: 0 errors; the pre-existing info/warning count must not increase (baseline: 169 info + 20 warning).

Run: `flutter test`
Expected: all tests pass (baseline was 590 passing / 1 skipped; this plan adds ~19).

- [ ] **Step 4: Commit**

```bash
git add test/engine/midperiod_proration_test.dart
git commit -m "test(payroll): mid-period proration scenarios + invariants"
```

---

## Self-Review

**Spec coverage:**
- §1 per-day rate resolution → Tasks 1, 2 (pure), Task 3 (wiring).
- §2 period-level rate drives MSC + default day rate → unchanged code; asserted by Task 5's invariant-1 test and Task 7's invariant-2 test.
- §3 tax basis in the `else` branch only; override branch untouched → Task 5.
- §4 MONTHLY grouping, single-rate emits today's line → Task 4.
- §5 wage-type guard → Task 6.
- §6 invariants 1–4 → Task 5 (inv 1), Tasks 3 & 7 (inv 2), Task 7 (inv 3), Task 4 (inv 4).
- §7 testing → Tasks 1, 2, 4, 5, 6, 7.
- Out-of-scope items (per-day scorecard attributes; historical recompute; payslip header rate) are intentionally untouched.

**Placeholder scan:** No TBD/TODO. Three steps intentionally instruct the implementer to **confirm real constructor/field names** against `engine/types.dart` and `test/engine/smoke_test.dart` before running (Task 4 Step 1, Task 5 Step 1, Task 7 Step 1) rather than invent them — the engine's input types have many required params and copying them wrong wastes a cycle. Every production-code step contains complete code.

**Type consistency:** `dailyRateFrom({baseSalary, wageType, workDaysPerMonth, hoursPerDay})` and `proratedDailyRateOverride({comp, attendanceDate, periodEnd, scorecardBaseSalary, scorecardWageType, workDaysPerMonth, hoursPerDay})` are used identically in Tasks 1–3. `basicPayTotalActual` is declared in Task 4 and consumed in Task 5. `lateUtDeductionAmount` is the existing local at `compute_engine.dart:180`. `validateCompensationRequest` gains exactly `currentWageType` (Task 6), and Task 6 Step 1 explicitly requires updating the file's existing call sites so it compiles.

**Ordering note:** Task 5 depends on Task 4's `basicPayTotalActual`. Task 3 depends on Task 2. Do not reorder.
