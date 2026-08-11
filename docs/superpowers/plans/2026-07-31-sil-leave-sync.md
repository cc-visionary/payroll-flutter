# SIL Leave Balances + Paid Leave + Year-End Conversion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Absences covered by approved paid leave (SIL) get paid in payroll instead of deducted; leave balances mirror Lark; unused SIL pays out combined with the 13th month.

**Architecture:** Lark stays the system of record for leave filing, approval, and balance accrual. The app: (1) mirrors balances into the existing `leave_balances` table via a new edge function (granted quotas from Lark + used days from already-synced `leave_requests`), with an XLSX-import fallback; (2) replaces the hardcoded `leaveIsPaid: false` in `compute_service` with a lookup against approved `leave_requests` + `leave_types.is_paid`, and the engine emits a new `PAID_LEAVE` earning line; (3) warns on ON_LEAVE days with no matching approved request; (4) extends the Distribute-13th flow with SIL conversion as one combined line, recording `converted` on release.

**Tech Stack:** Flutter/Dart (Riverpod), Supabase Postgres + Edge Functions (Deno/TypeScript), Lark OpenAPI (international `larksuite.com`), `decimal`, `excel`, `file_picker`.

**Spec:** `docs/superpowers/specs/2026-07-31-sil-leave-sync-design.md`

## Global Constraints

- Repo is shared by concurrent Claude sessions — execute this plan in a git worktree and merge back when done.
- Do NOT run `dart format` on whole files; match each file's surrounding style. Gate on `flutter analyze` only.
- Run Dart tests with `flutter test <path>`; Deno tests with `deno test supabase/tests/<name>_test.ts` (pure/mocked only — there is NO local Supabase; never try to start one).
- Do NOT deploy anything: no `supabase db push`, no `supabase functions deploy`. Migrations and function deploys happen at release, by the user.
- Package import prefix is `package:payroll_flutter/`.
- Decimal division must use `(a / b).toDecimal(scaleOnInfinitePrecision: 10)` (existing `_div` helpers).
- Payslip line categories are BOTH a Dart enum (`PayslipLineCategory` in `lib/features/payroll/engine/types.dart:18`) and a Postgres enum (`payslip_line_category`); DB writes use `category.name` (`compute_service.dart:348`). A new value needs BOTH.
- `alter type ... add value` must live in its own migration file — never in the same file (transaction) as statements that use the new value.
- Only APPROVED `leave_requests` count, and only types with `is_paid = true` pay.
- Engine tests mirror the harness style of `test/engine/benefit_eligibility_override_test.dart` (build `PayProfileInput` / `PayPeriodInput` / `RulesetInput` / `AttendanceDayInput` literals, call the engine, assert on `ComputedPayslipLine`s).

---

### Task 1: Migrations + `PAID_LEAVE` category (both enums)

**Files:**
- Create: `supabase/migrations/20260731000001_paid_leave_category.sql`
- Create: `supabase/migrations/20260731000002_sil_leave_type_flags.sql`
- Modify: `lib/features/payroll/engine/types.dart` (the `PayslipLineCategory` enum, line ~18)

**Interfaces:**
- Produces: `PayslipLineCategory.PAID_LEAVE` (Dart) + `'PAID_LEAVE'` (Postgres enum value) used by Tasks 2–3; `leave_types.is_paid/is_convertible = true` on the SIL type used by Tasks 3, 5, 6, 8.

- [ ] **Step 1: Write migration 20260731000001_paid_leave_category.sql**

```sql
-- New payslip line category for approved paid leaves (SIL etc.).
-- Own file: ADD VALUE cannot share a transaction with statements that
-- use the value (mirrors 20260418000007_payslip_line_category_tax_refund.sql).
alter type payslip_line_category add value if not exists 'PAID_LEAVE';
```

- [ ] **Step 2: Write migration 20260731000002_sil_leave_type_flags.sql**

```sql
-- Mark Service Incentive Leave as paid + convertible (year-end payout).
-- The type row was auto-created by sync-lark-leaves from Lark's display
-- name, so match by name; `SIL` code kept for a manually-seeded type.
update leave_types
set is_paid = true, is_convertible = true
where name ilike '%service incentive%' or code = 'SIL';
```

- [ ] **Step 3: Add the Dart enum value**

In `lib/features/payroll/engine/types.dart`, first run
`grep -rn "\.index" lib/ --include="*.dart" | grep -i "category"` — if any
hit uses `PayslipLineCategory`'s positional index, append `PAID_LEAVE` at
the END of the enum; otherwise insert it after `REST_DAY_PAY` with this
doc comment:

```dart
  /// Approved paid leave (e.g. Service Incentive Leave). DAILY/HOURLY:
  /// pays fraction × daily rate as an earning. MONTHLY: zero-amount info
  /// line (the day already counts as a work day — no deduction).
  PAID_LEAVE,
```

- [ ] **Step 4: Analyze + full engine test regression**

Run: `flutter analyze lib/features/payroll/`
Expected: No issues.
Run: `flutter test test/engine/`
Expected: all existing tests PASS (enum addition is non-breaking).

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260731000001_paid_leave_category.sql supabase/migrations/20260731000002_sil_leave_type_flags.sql lib/features/payroll/engine/types.dart
git commit -m "feat(leave): PAID_LEAVE payslip category + SIL paid/convertible flags"
```

---

### Task 2: Engine — paid-leave earning lines

**Files:**
- Modify: `lib/features/payroll/engine/types.dart` (`AttendanceDayInput` — add field)
- Modify: `lib/features/payroll/engine/compute_engine.dart` (after the basic-pay block, step "3")
- Test: `test/engine/paid_leave_test.dart` (create)

**Interfaces:**
- Consumes: `PayslipLineCategory.PAID_LEAVE` (Task 1); existing `AttendanceDayInput.isOnLeave/leaveIsPaid/leaveHours` (types.dart:137–139); `getDayRates`, `_round3`, `_div`, `_fromInt` (compute_engine.dart).
- Produces: `AttendanceDayInput.leaveTypeName` (`String?`, optional ctor param) — Task 3 sets it. Engine behavior contract for Task 3's wiring:
  - DAILY/HOURLY + `isOnLeave && leaveIsPaid`: one `PAID_LEAVE` line per leave type name, `amount = Σ fraction × dailyRate`, `quantity` = day count, `sortOrder: 105`, `ruleCode: 'PAID_LEAVE'`, description `Paid Leave — <type> (N day/s)`.
  - MONTHLY + paid leave: day counts as work day (existing compute_engine.dart:100) AND a zero-amount `PAID_LEAVE` info line, description `Paid Leave — <type> (N day/s, included in salary)`.
  - `fraction` = `leaveHours == null ? 1 : leaveHours / standardHoursPerDay`.
  - Paid-leave amounts are EXCLUDED from `basicPayTotalActual` (tax basic-pay base) — deliberate: same treatment as OT/holiday premiums in basic-pay-only tax mode.
  - Unpaid leave (`leaveIsPaid == false`): behavior unchanged.

- [ ] **Step 1: Write the failing tests**

Create `test/engine/paid_leave_test.dart`. Copy the harness helpers
(`_payPeriod()`, `_ruleset()`, profile builder, attendance builder) from
`test/engine/benefit_eligibility_override_test.dart`, adjusting: a DAILY
profile (`wageType: WageType.DAILY, baseRate: _d('600')`) and a MONTHLY
profile (`baseRate: _d('26000')`). Add an attendance-day builder that
takes `{bool isOnLeave = false, bool leaveIsPaid = false, String? leaveTypeName, Decimal? leaveHours}`.
Then these tests (adapt the engine entry-point call to the one the copied
harness uses):

```dart
void main() {
  group('paid leave — DAILY wage', () {
    test('paid SIL day emits PAID_LEAVE line at daily rate', () {
      // attendance: 1 worked day + 1 paid-leave day (SIL)
      final result = _compute(dailyProfile, [
        _workedDay(day: 5),
        _leaveDay(day: 6, leaveIsPaid: true, leaveTypeName: 'Service Incentive'),
      ]);
      final line = result.lines.singleWhere(
          (l) => l.category == PayslipLineCategory.PAID_LEAVE);
      expect(line.amount, _d('600'));
      expect(line.quantity, Decimal.one);
      expect(line.description, contains('Service Incentive'));
      expect(line.ruleCode, 'PAID_LEAVE');
    });

    test('half-day paid leave pays 0.5 × daily rate', () {
      final result = _compute(dailyProfile, [
        _leaveDay(day: 6, leaveIsPaid: true, leaveTypeName: 'Service Incentive',
            leaveHours: _d('4')),
      ]);
      final line = result.lines.singleWhere(
          (l) => l.category == PayslipLineCategory.PAID_LEAVE);
      expect(line.amount, _d('300'));
    });

    test('unpaid leave day emits no PAID_LEAVE line and no pay', () {
      final result = _compute(dailyProfile, [
        _leaveDay(day: 6, leaveIsPaid: false),
      ]);
      expect(
        result.lines.where((l) => l.category == PayslipLineCategory.PAID_LEAVE),
        isEmpty,
      );
    });

    test('two paid types produce one line each', () {
      final result = _compute(dailyProfile, [
        _leaveDay(day: 6, leaveIsPaid: true, leaveTypeName: 'Service Incentive'),
        _leaveDay(day: 7, leaveIsPaid: true, leaveTypeName: 'Sick Leave'),
      ]);
      final lines = result.lines
          .where((l) => l.category == PayslipLineCategory.PAID_LEAVE)
          .toList();
      expect(lines, hasLength(2));
    });

    test('paid leave amount is excluded from tax basic-pay base', () {
      // Statutory-ineligible profile → withholding path exercised via
      // basicPayTotalActual; assert gross includes the leave pay while
      // the BASIC_PAY line total does not.
      final result = _compute(dailyProfile, [
        _workedDay(day: 5),
        _leaveDay(day: 6, leaveIsPaid: true, leaveTypeName: 'Service Incentive'),
      ]);
      final basic = result.lines
          .where((l) => l.category == PayslipLineCategory.BASIC_PAY)
          .fold(Decimal.zero, (s, l) => s + l.amount);
      expect(basic, _d('600')); // 1 worked day only
    });
  });

  group('paid leave — MONTHLY wage', () {
    test('paid leave day counts as work day + zero info line', () {
      final withLeave = _compute(monthlyProfile, [
        _workedDay(day: 5),
        _leaveDay(day: 6, leaveIsPaid: true, leaveTypeName: 'Service Incentive'),
      ]);
      final withoutLeave = _compute(monthlyProfile, [
        _workedDay(day: 5),
      ]);
      final basicWith = withLeave.lines
          .where((l) => l.category == PayslipLineCategory.BASIC_PAY)
          .fold(Decimal.zero, (s, l) => s + l.amount);
      final basicWithout = withoutLeave.lines
          .where((l) => l.category == PayslipLineCategory.BASIC_PAY)
          .fold(Decimal.zero, (s, l) => s + l.amount);
      expect(basicWith > basicWithout, isTrue); // leave day paid in salary
      final info = withLeave.lines.singleWhere(
          (l) => l.category == PayslipLineCategory.PAID_LEAVE);
      expect(info.amount, Decimal.zero);
      expect(info.description, contains('included in salary'));
    });
  });
}
```

(`_compute` wraps the engine entry point exactly as the copied harness
calls it; `result.lines` is whatever collection of `ComputedPayslipLine`
that entry point returns — match the existing test file's access pattern.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/engine/paid_leave_test.dart`
Expected: FAIL — `leaveTypeName` named parameter undefined / no PAID_LEAVE lines emitted.

- [ ] **Step 3: Implement**

3a. `types.dart` — add to `AttendanceDayInput`, next to `leaveIsPaid`:

```dart
  /// Display name of the covering approved leave type (e.g. "Service
  /// Incentive"); null when not on leave or no matching request.
  final String? leaveTypeName;
```

and `this.leaveTypeName,` in the constructor (optional, after `leaveIsPaid`).

3b. `compute_engine.dart` — insert AFTER the basic-pay block (the
`if (profile.wageType == WageType.MONTHLY) { ... } else { ... }` that emits
BASIC_PAY lines) and BEFORE the next numbered step:

```dart
  // 3b. Paid leave earnings — ON_LEAVE days covered by an APPROVED
  // paid-type request (leaveIsPaid set by ComputeService). DAILY/HOURLY:
  // fraction × daily rate per day, one line per leave type. MONTHLY: the
  // day already entered workDayAttendance (see the isOnLeave clause in
  // step 2), so emit a zero-amount info line only. Deliberately NOT added
  // to basicPayTotalActual — the basic-pay-only tax base treats this like
  // the other premium lines.
  final paidLeaveByType = <String, List<AttendanceDayInput>>{};
  for (final a in attendance) {
    if (a.isOnLeave && a.leaveIsPaid) {
      paidLeaveByType.putIfAbsent(a.leaveTypeName ?? 'Leave', () => []).add(a);
    }
  }
  for (final entry in paidLeaveByType.entries) {
    Decimal dayCount = Decimal.zero;
    Decimal amount = Decimal.zero;
    for (final d in entry.value) {
      final frac = d.leaveHours == null
          ? Decimal.one
          : _round3(_div(d.leaveHours!, _fromInt(hpd)));
      dayCount += frac;
      if (profile.wageType != WageType.MONTHLY) {
        final dayRates = getDayRates(rates, hpd, d.dailyRateOverride);
        amount += dayRates.dailyRate * frac;
      }
    }
    amount = _round3(amount);
    final isMonthly = profile.wageType == WageType.MONTHLY;
    final dayLabel =
        '${dayCount == Decimal.one ? '1 day' : '$dayCount days'}';
    lines.add(ComputedPayslipLine(
      category: PayslipLineCategory.PAID_LEAVE,
      description: isMonthly
          ? 'Paid Leave — ${entry.key} ($dayLabel, included in salary)'
          : 'Paid Leave — ${entry.key} ($dayLabel)',
      quantity: dayCount,
      amount: isMonthly ? Decimal.zero : amount,
      sortOrder: 105,
      ruleCode: 'PAID_LEAVE',
    ));
  }
```

3c. Find where the engine computes `totalEarnings` / `grossPay` (the
totals step near the end of the same function). If earnings are summed by
an explicit category allowlist, add `PayslipLineCategory.PAID_LEAVE` to it;
if they're summed as "everything that isn't a deduction category," verify
PAID_LEAVE lands on the earnings side and note which in your report.

3d. Check `lib/features/payroll/payslips/payslip_pdf.dart` — the earnings
table (`_earningsTable`, ~line 279) vs the deduction category list (~line
274). PAID_LEAVE must render in EARNINGS. If earnings are "all lines not
in the deduction set," no change needed — verify and say so.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/engine/paid_leave_test.dart && flutter test test/engine/`
Expected: new tests PASS, zero regressions.

- [ ] **Step 5: Analyze + commit**

Run: `flutter analyze lib/features/payroll/ test/engine/paid_leave_test.dart`
Expected: No issues.

```bash
git add lib/features/payroll/engine/types.dart lib/features/payroll/engine/compute_engine.dart test/engine/paid_leave_test.dart
git commit -m "feat(engine): PAID_LEAVE earning lines for approved paid leaves"
```

---

### Task 3: ComputeService — match ON_LEAVE days to approved requests

**Files:**
- Create: `lib/features/payroll/runs/compute/leave_day_index.dart`
- Modify: `lib/features/payroll/runs/compute/compute_service.dart` (fetch + `_attendanceFromRow`, lines ~1035–1065)
- Modify: `lib/data/repositories/payroll_repository.dart` (`thirteenthMonthPayoutsForRun`, line ~561 — include PAID_LEAVE in the basic sum)
- Test: `test/features/payroll/leave_day_index_test.dart` (create)

**Interfaces:**
- Consumes: Task 2's `AttendanceDayInput.leaveTypeName`; existing `leave_requests` schema (`employee_id, start_date, end_date, leave_days, status`) + `leave_types(is_paid, name)`.
- Produces:
  - `class LeaveDayInfo { final bool isPaid; final String typeName; final double fraction; }`
  - `class LeaveDayIndex { LeaveDayInfo? lookup(String employeeId, DateTime date); factory LeaveDayIndex.fromRequestRows(List<Map<String, dynamic>> rows); }`
  - Used by Task 4's warning wiring too.

- [ ] **Step 1: Write the failing tests**

Create `test/features/payroll/leave_day_index_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/payroll/runs/compute/leave_day_index.dart';

Map<String, dynamic> _row({
  required String empId,
  required String start,
  required String end,
  double days = 1,
  bool isPaid = true,
  String name = 'Service Incentive',
}) =>
    {
      'employee_id': empId,
      'start_date': start,
      'end_date': end,
      'leave_days': days,
      'leave_types': {'is_paid': isPaid, 'name': name},
    };

void main() {
  test('single-day paid request covers that date', () {
    final idx = LeaveDayIndex.fromRequestRows(
        [_row(empId: 'e1', start: '2026-07-06', end: '2026-07-06')]);
    final info = idx.lookup('e1', DateTime(2026, 7, 6));
    expect(info, isNotNull);
    expect(info!.isPaid, isTrue);
    expect(info.typeName, 'Service Incentive');
    expect(info.fraction, 1.0);
  });

  test('multi-day range covers every date inclusive with fraction 1', () {
    final idx = LeaveDayIndex.fromRequestRows(
        [_row(empId: 'e1', start: '2026-07-06', end: '2026-07-08', days: 3)]);
    expect(idx.lookup('e1', DateTime(2026, 7, 7)), isNotNull);
    expect(idx.lookup('e1', DateTime(2026, 7, 9)), isNull);
  });

  test('same-day half request carries fraction 0.5', () {
    final idx = LeaveDayIndex.fromRequestRows([
      _row(empId: 'e1', start: '2026-07-06', end: '2026-07-06', days: 0.5)
    ]);
    expect(idx.lookup('e1', DateTime(2026, 7, 6))!.fraction, 0.5);
  });

  test('unpaid type reported with isPaid false', () {
    final idx = LeaveDayIndex.fromRequestRows([
      _row(empId: 'e1', start: '2026-07-06', end: '2026-07-06',
          isPaid: false, name: 'Unpaid Personal')
    ]);
    expect(idx.lookup('e1', DateTime(2026, 7, 6))!.isPaid, isFalse);
  });

  test('other employees and dates return null', () {
    final idx = LeaveDayIndex.fromRequestRows(
        [_row(empId: 'e1', start: '2026-07-06', end: '2026-07-06')]);
    expect(idx.lookup('e2', DateTime(2026, 7, 6)), isNull);
  });

  test('paid request wins over an overlapping unpaid one', () {
    final idx = LeaveDayIndex.fromRequestRows([
      _row(empId: 'e1', start: '2026-07-06', end: '2026-07-06',
          isPaid: false, name: 'Unpaid'),
      _row(empId: 'e1', start: '2026-07-06', end: '2026-07-06'),
    ]);
    expect(idx.lookup('e1', DateTime(2026, 7, 6))!.isPaid, isTrue);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/payroll/leave_day_index_test.dart`
Expected: FAIL — file/class not found.

- [ ] **Step 3: Implement `leave_day_index.dart`**

```dart
/// Day-level index of APPROVED leave requests for a pay period. Built once
/// per compute from a single leave_requests fetch, then consulted per
/// attendance day to decide whether an ON_LEAVE day is paid (drives the
/// engine's PAID_LEAVE line) and which leave type covers it.
class LeaveDayInfo {
  final bool isPaid;
  final String typeName;

  /// 1.0 for full days; a same-day request with leave_days < 1 carries the
  /// fractional value (e.g. 0.5 half-day, 0.625 partial-hours).
  final double fraction;
  const LeaveDayInfo({
    required this.isPaid,
    required this.typeName,
    required this.fraction,
  });
}

class LeaveDayIndex {
  // employeeId -> 'yyyy-mm-dd' -> info
  final Map<String, Map<String, LeaveDayInfo>> _byEmpDate;
  const LeaveDayIndex._(this._byEmpDate);

  static String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  LeaveDayInfo? lookup(String employeeId, DateTime date) =>
      _byEmpDate[employeeId]?[_key(date)];

  /// [rows] come from a Supabase select on leave_requests with an embedded
  /// `leave_types(is_paid, name)`. Ranges are expanded inclusively. When
  /// two requests cover the same day, a paid one wins over an unpaid one
  /// (a paid grant should never be masked by a stray unpaid record).
  factory LeaveDayIndex.fromRequestRows(List<Map<String, dynamic>> rows) {
    final out = <String, Map<String, LeaveDayInfo>>{};
    for (final r in rows) {
      final empId = r['employee_id'] as String?;
      final startRaw = r['start_date'] as String?;
      final endRaw = r['end_date'] as String?;
      if (empId == null || startRaw == null || endRaw == null) continue;
      final start = DateTime.parse(startRaw);
      final end = DateTime.parse(endRaw);
      if (end.isBefore(start)) continue;
      final lt = r['leave_types'] as Map<String, dynamic>?;
      final isPaid = (lt?['is_paid'] as bool?) ?? false;
      final typeName = ((lt?['name'] as String?) ?? 'Leave').trim();
      final days = (r['leave_days'] as num?)?.toDouble() ?? 1.0;
      final sameDay = start.year == end.year &&
          start.month == end.month &&
          start.day == end.day;
      final fraction = sameDay && days > 0 && days < 1 ? days : 1.0;

      final empMap = out.putIfAbsent(empId, () => {});
      var cursor = DateTime(start.year, start.month, start.day);
      final last = DateTime(end.year, end.month, end.day);
      while (!cursor.isAfter(last)) {
        final k = _key(cursor);
        final existing = empMap[k];
        if (existing == null || (isPaid && !existing.isPaid)) {
          empMap[k] = LeaveDayInfo(
            isPaid: isPaid,
            typeName: typeName,
            fraction: fraction,
          );
        }
        cursor = cursor.add(const Duration(days: 1));
      }
    }
    return LeaveDayIndex._(out);
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/payroll/leave_day_index_test.dart`
Expected: PASS.

- [ ] **Step 5: Wire into compute_service**

5a. In `compute_service.dart`, locate the main compute path where
employees + attendance are fetched for the period (the code that
ultimately calls `_attendanceFromRow`, call sites near line 765). Add ONE
fetch before the per-employee loop (`isoDate` helper exists in the
attendance layer; if not imported here, format with the same
yyyy-MM-dd padding as `LeaveDayIndex._key`):

```dart
    // Approved leaves overlapping the period — drives paid-leave matching.
    // Overlap test: starts on/before period end AND ends on/after period start.
    final leaveRows = await _client
        .from('leave_requests')
        .select('employee_id, start_date, end_date, leave_days, '
            'leave_types!inner(is_paid, name)')
        .eq('status', 'APPROVED')
        .lte('start_date', _iso(payPeriod.endDate))
        .gte('end_date', _iso(payPeriod.startDate));
    final leaveIndex = LeaveDayIndex.fromRequestRows(
        (leaveRows as List<dynamic>).cast<Map<String, dynamic>>());
```

Thread `leaveIndex` down to `_attendanceFromRow` as a parameter (follow
how other per-run context like shifts/holidays already reaches it).

5b. In `_attendanceFromRow` (lines ~1035–1065), replace

```dart
      isOnLeave: status.contains('LEAVE'),
      leaveIsPaid: false,
```

with

```dart
      isOnLeave: status.contains('LEAVE'),
      leaveIsPaid: leaveInfo?.isPaid ?? false,
      leaveTypeName: leaveInfo?.typeName,
      leaveHours: leaveInfo != null && leaveInfo.fraction < 1.0
          ? Decimal.parse((leaveInfo.fraction * 8).toStringAsFixed(2))
          : null,
```

where `leaveInfo` is computed at the top of the function:

```dart
    final leaveInfo = (r['attendance_status'] as String? ?? '')
            .toUpperCase()
            .contains('LEAVE')
        ? leaveIndex.lookup(employeeId, attendanceDate)
        : null;
```

(`employeeId` must be in scope in `_attendanceFromRow` — thread it as a
parameter if the function only receives the row today. The `* 8` matches
the engine's `hpd` default; if the function has the employee's
`work_hours_per_day` in scope, use that instead of 8 and note it.)

5c. In `payroll_repository.dart` `thirteenthMonthPayoutsForRun` (~561):
find where BASIC_PAY line amounts are summed into the 13th-month basis and
include `'PAID_LEAVE'` amounts in the same "basic" sum (PH 13th-month
basis includes paid leave). Zero-amount MONTHLY info lines add nothing, so
this is safe for all wage types.

- [ ] **Step 6: Regression + analyze + commit**

Run: `flutter test test/engine/ test/features/payroll/`
Expected: PASS.
Run: `flutter analyze lib/features/payroll/ lib/data/repositories/payroll_repository.dart`
Expected: No issues.

```bash
git add lib/features/payroll/runs/compute/leave_day_index.dart lib/features/payroll/runs/compute/compute_service.dart lib/data/repositories/payroll_repository.dart test/features/payroll/leave_day_index_test.dart
git commit -m "feat(payroll): match ON_LEAVE days to approved leave requests (paid leave)"
```

---

### Task 4: Run warning — ON_LEAVE day with no approved request

**Files:**
- Modify: `lib/features/payroll/runs/detail/warnings.dart` (`WarningType`, `detectWarnings`)
- Modify: the `detectWarnings` caller (find with `grep -rn "detectWarnings(" lib/` — it's in the run-detail providers; thread the new argument there and fetch the period's approved requests the same way Task 3's compute does)
- Test: extend the existing warnings test (find with `grep -rln "detectWarnings" test/`; if none exists, create `test/features/payroll/warnings_leave_test.dart` with the harness below)

**Interfaces:**
- Consumes: `AttendanceDay.attendanceStatus` (`lib/data/models/attendance_day.dart:10`); `LeaveDayIndex` (Task 3).
- Produces: `WarningType.unmatchedLeave`; `detectWarnings` gains optional `LeaveDayIndex? leaveIndex` (default null = feature off, existing callers/tests unaffected).

- [ ] **Step 1: Write the failing test**

```dart
// In the warnings test file. Follow the existing test's builder for
// AttendanceDay records (or construct AttendanceDay directly with
// attendanceStatus: 'ON_LEAVE').
test('ON_LEAVE day with no approved request warns', () {
  final warnings = detectWarnings(
    records: [_onLeaveDay(empId: 'e1', date: DateTime(2026, 7, 6))],
    shiftsById: const {},
    today: DateTime(2026, 7, 20),
    leaveIndex: LeaveDayIndex.fromRequestRows(const []),
  );
  expect(warnings.single.type, WarningType.unmatchedLeave);
});

test('ON_LEAVE day covered by approved request does not warn', () {
  final warnings = detectWarnings(
    records: [_onLeaveDay(empId: 'e1', date: DateTime(2026, 7, 6))],
    shiftsById: const {},
    today: DateTime(2026, 7, 20),
    leaveIndex: LeaveDayIndex.fromRequestRows([
      {
        'employee_id': 'e1',
        'start_date': '2026-07-06',
        'end_date': '2026-07-06',
        'leave_days': 1,
        'leave_types': {'is_paid': true, 'name': 'Service Incentive'},
      }
    ]),
  );
  expect(warnings, isEmpty);
});

test('null leaveIndex disables the check', () {
  final warnings = detectWarnings(
    records: [_onLeaveDay(empId: 'e1', date: DateTime(2026, 7, 6))],
    shiftsById: const {},
    today: DateTime(2026, 7, 20),
  );
  expect(warnings.where((w) => w.type == WarningType.unmatchedLeave), isEmpty);
});
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test <warnings test file>`
Expected: FAIL — `unmatchedLeave` / `leaveIndex` undefined.

- [ ] **Step 3: Implement**

In `warnings.dart`: add `unmatchedLeave` to `WarningType`; add
`LeaveDayIndex? leaveIndex` parameter to `detectWarnings` (import the
Task 3 file); inside the per-record loop add:

```dart
    if (leaveIndex != null &&
        r.attendanceStatus.toUpperCase().contains('LEAVE') &&
        leaveIndex.lookup(r.employeeId, r.attendanceDate) == null) {
      out.add(RunWarning(
        employeeId: r.employeeId,
        employeeLabel: label,   // reuse however existing warnings build it
        date: r.attendanceDate,
        type: WarningType.unmatchedLeave,
        message: 'On leave with no approved leave request in Lark — '
            'day treated as UNPAID. Run the Leaves sync or fix the '
            'approval in Lark, then recompute.',
      ));
    }
```

(Adapt field access to the actual `AttendanceDay` model / existing loop
variables. Note: place the check BEFORE the existing "skip today+future"
guard only if that guard would wrongly suppress past leave days — it
won't; leave the ordering as the existing checks have it.)

In the caller (run-detail providers): fetch approved leave_requests for
the run period (same query as Task 3 step 5a, via the client available
there) and pass `leaveIndex:`. Check the Warnings tab badge/count updates
automatically (it derives from the same list).

- [ ] **Step 4: Run tests + analyze + commit**

Run: `flutter test <warnings test file> && flutter analyze lib/features/payroll/`
Expected: PASS / No issues.

```bash
git add lib/features/payroll/runs/detail/warnings.dart <caller file> <test file>
git commit -m "feat(payroll): warn on ON_LEAVE days without an approved leave request"
```

---

### Task 5: Edge function `sync-lark-leave-balances` + repo + settings button

**Files:**
- Create: `supabase/functions/sync-lark-leave-balances/index.ts`
- Modify: `supabase/functions/_shared/lark.ts` (add `queryLeaveGrantRecords`)
- Modify: `lib/features/lark/lark_repository.dart` (~line 222, add `syncLeaveBalances`)
- Modify: `lib/features/lark/lark_settings_screen.dart` (~line 160, add a `_SyncCard`)
- Test: `supabase/tests/leave_balance_sync_test.ts` (create)

**Interfaces:**
- Consumes: `_shared/lark.ts` `authFromEnv`, `tenantAccessToken`, `larkRequest`, `logSyncStart`, `logSyncFinish`, `userIdFromAuthHeader`, `json`; `employees.lark_user_id`; `leave_types.lark_leave_type_id`; `leave_requests` (APPROVED, current year) for `used`.
- Produces: edge function POST `{company_id}` → upserts `leave_balances(employee_id, leave_type_id, year)` setting `accrued`, `used`, `last_accrual_date`; `LarkRepository.syncLeaveBalances(String companyId)`; pure helper `computeBalanceUpserts` exported for the Deno test.

**Endpoint note (from the spec):** the granted-quota endpoint is Lark
attendance's leave issuance records API (`leave_employ_expire_records` /
leave accrual records family). Verify the exact path + request shape
against the Lark OpenAPI docs for international tenants
(https://open.larksuite.com/document/) while implementing; wrap it in
`queryLeaveGrantRecords` so the function body doesn't care. If the tenant
rejects the endpoint (404/permission), the function must return
`{ ok: false, error: 'leave balance API unavailable: <detail>' }` after
logging — the Task 6 XLSX import is the operative fallback. Do NOT let
endpoint uncertainty stall the task: the pure upsert math + plumbing is
the deliverable; the probe result gets recorded in your report.

- [ ] **Step 1: Write the failing Deno test**

`supabase/tests/leave_balance_sync_test.ts`:

```ts
import { assertEquals } from 'https://deno.land/std@0.208.0/assert/mod.ts';
import { computeBalanceUpserts } from '../functions/sync-lark-leave-balances/index.ts';

Deno.test('grants + used roll up into one upsert per employee/type', () => {
  const upserts = computeBalanceUpserts({
    year: 2026,
    grants: [
      { employeeId: 'e1', leaveTypeId: 'lt-sil', grantedDays: 5 },
      { employeeId: 'e1', leaveTypeId: 'lt-sil', grantedDays: 2 },
    ],
    usedDaysByEmpType: new Map([['e1|lt-sil', 1.5]]),
    syncDate: '2026-07-31',
  });
  assertEquals(upserts.length, 1);
  assertEquals(upserts[0], {
    employee_id: 'e1',
    leave_type_id: 'lt-sil',
    year: 2026,
    accrued: 7,
    used: 1.5,
    last_accrual_date: '2026-07-31',
  });
});

Deno.test('employee with grants but no usage gets used 0', () => {
  const upserts = computeBalanceUpserts({
    year: 2026,
    grants: [{ employeeId: 'e2', leaveTypeId: 'lt-sil', grantedDays: 5 }],
    usedDaysByEmpType: new Map(),
    syncDate: '2026-07-31',
  });
  assertEquals(upserts[0].used, 0);
});

Deno.test('usage with no grant still produces a row (accrued 0)', () => {
  const upserts = computeBalanceUpserts({
    year: 2026,
    grants: [],
    usedDaysByEmpType: new Map([['e3|lt-sil', 1]]),
    syncDate: '2026-07-31',
  });
  assertEquals(upserts[0].accrued, 0);
  assertEquals(upserts[0].used, 1);
});
```

- [ ] **Step 2: Run to verify failure**

Run: `deno test supabase/tests/leave_balance_sync_test.ts`
Expected: FAIL — module/function not found.

- [ ] **Step 3: Implement the edge function**

`supabase/functions/sync-lark-leave-balances/index.ts` (structure mirrors
`sync-lark-leaves/index.ts` — auth, logging, per-employee mapping via
`lark_user_id`):

```ts
// Edge Function: sync-lark-leave-balances
// Mirrors Lark's leave balances into leave_balances (read-only mirror —
// Lark owns accrual + deduction). accrued = Σ granted quota days for the
// year from Lark's leave issuance records; used = Σ APPROVED
// leave_requests days for the year (already synced by sync-lark-leaves).
// Remaining is always derived downstream, never stored.
//
// Input (POST JSON): { "company_id": "uuid" }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import {
  authFromEnv,
  queryLeaveGrantRecords,
  logSyncStart,
  logSyncFinish,
  userIdFromAuthHeader,
  json,
} from '../_shared/lark.ts';

export interface GrantInput {
  employeeId: string;
  leaveTypeId: string;
  grantedDays: number;
}

export interface BalanceUpsert {
  employee_id: string;
  leave_type_id: string;
  year: number;
  accrued: number;
  used: number;
  last_accrual_date: string;
}

/** Pure rollup — exported for tests. */
export function computeBalanceUpserts(args: {
  year: number;
  grants: GrantInput[];
  usedDaysByEmpType: Map<string, number>;
  syncDate: string;
}): BalanceUpsert[] {
  const acc = new Map<string, BalanceUpsert>();
  const keyOf = (e: string, t: string) => `${e}|${t}`;
  for (const g of args.grants) {
    const k = keyOf(g.employeeId, g.leaveTypeId);
    const row = acc.get(k) ?? {
      employee_id: g.employeeId,
      leave_type_id: g.leaveTypeId,
      year: args.year,
      accrued: 0,
      used: 0,
      last_accrual_date: args.syncDate,
    };
    row.accrued += g.grantedDays;
    acc.set(k, row);
  }
  for (const [k, used] of args.usedDaysByEmpType) {
    const [employeeId, leaveTypeId] = k.split('|');
    const row = acc.get(k) ?? {
      employee_id: employeeId,
      leave_type_id: leaveTypeId,
      year: args.year,
      accrued: 0,
      used: 0,
      last_accrual_date: args.syncDate,
    };
    row.used = used;
    acc.set(k, row);
  }
  return [...acc.values()];
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method not allowed' }, 405);
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } },
  );
  let body: { company_id?: string } = {};
  try { body = await req.json(); } catch (_) { /* keep {} */ }
  const companyId = body.company_id;
  if (!companyId) return json({ error: 'company_id required' }, 400);

  const year = new Date().getFullYear();
  const syncDate = new Date().toISOString().slice(0, 10);
  const errors: string[] = [];
  const logId = await logSyncStart(supabase, {
    companyId,
    syncType: 'LEAVE_BALANCE',
    dateFrom: `${year}-01-01`,
    dateTo: syncDate,
    syncedById: userIdFromAuthHeader(req),
  });

  try {
    // 1. Employees with a Lark identity.
    const { data: emps, error: empErr } = await supabase
      .from('employees')
      .select('id, lark_user_id')
      .eq('company_id', companyId)
      .not('lark_user_id', 'is', null)
      .is('deleted_at', null);
    if (empErr) throw empErr;
    const empByLarkId = new Map<string, string>();
    for (const e of emps ?? []) {
      if (e.lark_user_id) empByLarkId.set(e.lark_user_id as string, e.id as string);
    }

    // 2. Leave type mapping (Lark id → local id).
    const { data: types, error: ltErr } = await supabase
      .from('leave_types')
      .select('id, lark_leave_type_id')
      .eq('company_id', companyId);
    if (ltErr) throw ltErr;
    const ltByLarkId = new Map<string, string>();
    for (const lt of types ?? []) {
      if (lt.lark_leave_type_id) {
        ltByLarkId.set(lt.lark_leave_type_id as string, lt.id as string);
      }
    }

    // 3. Granted quotas from Lark.
    const auth = authFromEnv();
    const grants: GrantInput[] = [];
    const grantRecords = await queryLeaveGrantRecords(auth, {
      larkUserIds: [...empByLarkId.keys()],
      yearStart: `${year}-01-01`,
      yearEnd: `${year}-12-31`,
    });
    for (const rec of grantRecords) {
      const empId = empByLarkId.get(rec.larkUserId);
      const ltId = ltByLarkId.get(rec.larkLeaveTypeId);
      if (!empId || !ltId) continue; // unmapped — skip silently, counted below
      grants.push({ employeeId: empId, leaveTypeId: ltId, grantedDays: rec.grantedDays });
    }

    // 4. Used days from already-synced APPROVED requests, current year.
    const { data: reqs, error: reqErr } = await supabase
      .from('leave_requests')
      .select('employee_id, leave_type_id, leave_days')
      .eq('status', 'APPROVED')
      .gte('start_date', `${year}-01-01`)
      .lte('start_date', `${year}-12-31`);
    if (reqErr) throw reqErr;
    const usedDaysByEmpType = new Map<string, number>();
    for (const r of reqs ?? []) {
      const k = `${r.employee_id}|${r.leave_type_id}`;
      usedDaysByEmpType.set(k, (usedDaysByEmpType.get(k) ?? 0) + Number(r.leave_days ?? 0));
    }

    // 5. Roll up + upsert.
    const upserts = computeBalanceUpserts({ year, grants, usedDaysByEmpType, syncDate });
    let updated = 0;
    for (const u of upserts) {
      const { error } = await supabase
        .from('leave_balances')
        .upsert(u, { onConflict: 'employee_id,leave_type_id,year' });
      if (error) errors.push(`${u.employee_id}/${u.leave_type_id}: ${error.message}`);
      else updated++;
    }

    await logSyncFinish(supabase, logId, {
      total: upserts.length, created: 0, updated, skipped: 0, errors,
    });
    return json({ ok: true, total: upserts.length, updated, errors });
  } catch (e) {
    errors.push(String(e));
    await logSyncFinish(supabase, logId, { total: 0, created: 0, updated: 0, skipped: 0, errors });
    return json({ ok: false, error: `leave balance sync failed: ${String(e)}` }, 500);
  }
});
```

In `_shared/lark.ts` add `queryLeaveGrantRecords(auth, {larkUserIds, yearStart, yearEnd})`
returning `Array<{larkUserId: string; larkLeaveTypeId: string; grantedDays: number}>`,
implemented against the verified endpoint (see the Endpoint note). Follow
the pagination/token pattern of the neighboring `queryUserApprovals`. If
the endpoint is confirmed unavailable, make the helper throw
`new Error('leave balance API unavailable: <status/detail>')` so the
function's catch path reports it cleanly.

**Deno import caveat:** `index.ts` top-level imports `_shared/lark.ts`
(which reads env at call time, not import time) and `Deno.serve` runs on
import — guard the serve call if the test import triggers it (pattern:
export the pure function ABOVE `Deno.serve`; `deno test` importing the
module will execute `Deno.serve`, which is legal in tests but if it errors
locally wrap it: `if (!Deno.env.get('DENO_TEST')) Deno.serve(...)` is NOT
the repo's pattern — check how the existing test files import function
code: `ls supabase/tests/` and mirror `statutory_payables_test.ts` /
`parse_holiday_summary_test.ts` (they may import from a separate module
file instead). If those tests import a standalone helper module, move
`computeBalanceUpserts` + interfaces into
`supabase/functions/sync-lark-leave-balances/rollup.ts` and have both
`index.ts` and the test import THAT — adjust the test import path
accordingly.)

- [ ] **Step 4: Run the Deno test**

Run: `deno test supabase/tests/leave_balance_sync_test.ts`
Expected: PASS (3 tests).

- [ ] **Step 5: Dart plumbing**

`lark_repository.dart` (next to `syncLeaves`, ~line 222):

```dart
  Future<LarkSyncResult> syncLeaveBalances(String companyId) =>
      _invoke('sync-lark-leave-balances', {'company_id': companyId});
```

`lark_settings_screen.dart` — after the "Synced Leaves" `_SyncCard`
(~line 166), add:

```dart
          const SizedBox(height: 16),

          _SyncCard(
            title: 'Leave Balances',
            subtitle:
                'Mirror Lark leave balances (granted − used) for the current year',
            onSync: () => _run(() => repo.syncLeaveBalances(cid), 'Leave balances'),
            child: const _LeaveBalancesSummary(),
          ),
```

with a minimal summary widget in the same file (mirror the style of the
existing tables in this screen):

```dart
class _LeaveBalancesSummary extends ConsumerWidget {
  const _LeaveBalancesSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_leaveBalancesSummaryProvider);
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(12),
        child: Text('Error: $e', style: const TextStyle(color: Colors.red)),
      ),
      data: (s) => Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          s == null
              ? 'No balances synced yet.'
              : '${s.employeeCount} employees with ${s.year} balances · '
                  'last synced ${s.lastSynced}',
        ),
      ),
    );
  }
}

final _leaveBalancesSummaryProvider = FutureProvider.autoDispose((ref) async {
  final rows = await Supabase.instance.client
      .from('leave_balances')
      .select('employee_id, updated_at')
      .eq('year', DateTime.now().year);
  final list = (rows as List<dynamic>).cast<Map<String, dynamic>>();
  if (list.isEmpty) return null;
  DateTime last = DateTime.fromMillisecondsSinceEpoch(0);
  final emps = <String>{};
  for (final r in list) {
    emps.add(r['employee_id'] as String);
    final u = DateTime.tryParse((r['updated_at'] ?? '') as String);
    if (u != null && u.isAfter(last)) last = u;
  }
  return (
    employeeCount: emps.length,
    year: DateTime.now().year,
    lastSynced: '${last.year}-${last.month.toString().padLeft(2, '0')}-${last.day.toString().padLeft(2, '0')}',
  );
});
```

(Adapt imports/`Supabase` access to what the file already uses.)

- [ ] **Step 6: Analyze + commit**

Run: `flutter analyze lib/features/lark/`
Expected: No issues.

```bash
git add supabase/functions/sync-lark-leave-balances/ supabase/functions/_shared/lark.ts supabase/tests/leave_balance_sync_test.ts lib/features/lark/lark_repository.dart lib/features/lark/lark_settings_screen.dart
git commit -m "feat(lark): sync-lark-leave-balances edge function + settings sync card"
```

---

### Task 6: XLSX balance import fallback

**Files:**
- Create: `lib/features/lark/leave_balance_import_dialog.dart`
- Modify: `lib/features/lark/lark_settings_screen.dart` (add an "Import from XLSX" `TextButton` inside the Leave Balances `_SyncCard` child area added in Task 5)
- Test: `test/features/lark/leave_balance_import_test.dart` (create — tests the pure parser)

**Interfaces:**
- Consumes: `excel` + `file_picker` packages (already project deps — verify in `pubspec.yaml`, add nothing new); `employees` list; SIL `leave_types` row (`is_paid = true and is_convertible = true`).
- Produces: `List<ParsedBalanceRow> parseLeaveBalanceXlsx(List<int> bytes)` — pure, testable; `LeaveBalanceImportDialog` widget.

- [ ] **Step 1: Write the failing parser test**

```dart
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/lark/leave_balance_import_dialog.dart';

List<int> _workbook(List<List<dynamic>> rows) {
  final excel = Excel.createExcel();
  final ws = excel[excel.getDefaultSheet()!];
  for (final r in rows) {
    ws.appendRow([
      for (final c in r)
        c == null
            ? null
            : c is num
                ? DoubleCellValue(c.toDouble())
                : TextCellValue(c.toString())
    ]);
  }
  return excel.save()!;
}

void main() {
  test('parses name + days column from a Lark-style export', () {
    final bytes = _workbook([
      ['Name', 'Department', 'Date joined', 'Service Incentive (days)'],
      ['Marvin Ong', 'LCT Operations', '2023-05-01', 5],
      ['Christian Dale', 'LCT Operations', '2024-10-01', 4.5],
    ]);
    final rows = parseLeaveBalanceXlsx(bytes);
    expect(rows, hasLength(2));
    expect(rows[0].name, 'Marvin Ong');
    expect(rows[0].days, 5.0);
    expect(rows[1].days, 4.5);
  });

  test('header row found even with preamble rows above it', () {
    final bytes = _workbook([
      ['Exported 2026-07-31'],
      [],
      ['Name', 'Service Incentive (days)'],
      ['Marvin Ong', 5],
    ]);
    expect(parseLeaveBalanceXlsx(bytes).single.days, 5.0);
  });

  test('rows with None/empty days are skipped', () {
    final bytes = _workbook([
      ['Name', 'Service Incentive (days)'],
      ['Ron Gonzales', 'None'],
      ['Marvin Ong', 5],
    ]);
    expect(parseLeaveBalanceXlsx(bytes), hasLength(1));
  });

  test('throws a clear error when no days column exists', () {
    final bytes = _workbook([
      ['Name', 'Department'],
      ['Marvin Ong', 'LCT Operations'],
    ]);
    expect(() => parseLeaveBalanceXlsx(bytes), throwsFormatException);
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/lark/leave_balance_import_test.dart`
Expected: FAIL — file not found.

- [ ] **Step 3: Implement**

`leave_balance_import_dialog.dart` — two parts.

Pure parser (top of file):

```dart
/// One parsed row from Lark's Leave Balance page export.
class ParsedBalanceRow {
  final String name;
  final double days;
  const ParsedBalanceRow({required this.name, required this.days});
}

/// Parse Lark's Leave Balance export: finds the header row (first row
/// whose first non-empty cell is exactly "Name", case-insensitive), takes
/// the first column whose header contains "(days)", and reads rows below.
/// Non-numeric day cells ("None", blank) are skipped. Throws
/// [FormatException] when no Name header or no "(days)" column is found —
/// the dialog surfaces that as "not a Lark Leave Balance export".
List<ParsedBalanceRow> parseLeaveBalanceXlsx(List<int> bytes) {
  final excel = Excel.decodeBytes(bytes);
  for (final sheetName in excel.tables.keys) {
    final sheet = excel.tables[sheetName]!;
    for (var i = 0; i < sheet.maxRows; i++) {
      final row = sheet.rows[i];
      String cellText(int c) =>
          c < row.length ? (row[c]?.value?.toString() ?? '').trim() : '';
      final first = row.indexWhere(
          (c) => (c?.value?.toString() ?? '').trim().isNotEmpty);
      if (first < 0) continue;
      if (cellText(first).toLowerCase() != 'name') continue;
      var daysCol = -1;
      for (var c = first + 1; c < row.length; c++) {
        if (cellText(c).toLowerCase().contains('(days)')) {
          daysCol = c;
          break;
        }
      }
      if (daysCol < 0) {
        throw const FormatException(
            'Found a Name column but no "(days)" column — not a Lark '
            'Leave Balance export.');
      }
      final out = <ParsedBalanceRow>[];
      for (var r = i + 1; r < sheet.maxRows; r++) {
        final dataRow = sheet.rows[r];
        String dText(int c) =>
            c < dataRow.length ? (dataRow[c]?.value?.toString() ?? '').trim() : '';
        final name = dText(first);
        if (name.isEmpty) continue;
        final days = double.tryParse(dText(daysCol));
        if (days == null) continue;
        out.add(ParsedBalanceRow(name: name, days: days));
      }
      return out;
    }
  }
  throw const FormatException('No "Name" header row found in any sheet.');
}
```

Dialog widget (same file): `LeaveBalanceImportDialog extends ConsumerStatefulWidget`:
1. On open: `FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx'], withData: true)`; parse; on `FormatException` show the message and a Close button.
2. Match rows to employees: fetch `employees` (`id, first_name, last_name`) via the client; matcher tries, case-insensitive and trimmed: `'$first $last'`, `'$last, $first'`, and `'$first $last'` with middle tokens of the sheet name dropped (Lark truncates: also accept a sheet name that is a PREFIX of `'$first $last'` when ≥ 8 chars). Ambiguous (2+ employees match) counts as unmatched.
3. Resolve the SIL leave type: `leave_types` where `is_paid = true` and `is_convertible = true`, first row; if none → error text "No SIL leave type found — run the Leaves sync first (it auto-creates types), then re-run the migration flagging SIL."
4. Preview list: matched rows (name → employee, days) and an unmatched section; Import button disabled when zero matched.
5. On Import, for each matched row upsert `leave_balances` `{employee_id, leave_type_id, year: DateTime.now().year, accrued: days, used: <sum of current-year APPROVED leave_requests days for that employee+type>, last_accrual_date: today}` with `onConflict: 'employee_id,leave_type_id,year'` (one `leave_requests` fetch for all matched employees, summed client-side, mirroring Task 5's rollup semantics: Lark's export "days" is the granted quota).
6. Success snackbar with counts; `Navigator.pop(true)`; caller invalidates `_leaveBalancesSummaryProvider`.

In `lark_settings_screen.dart`, inside the Leave Balances card child column, add under the summary:

```dart
        TextButton.icon(
          icon: const Icon(Icons.upload_file_outlined, size: 16),
          label: const Text('Import from XLSX (Lark export)'),
          onPressed: () async {
            final changed = await showDialog<bool>(
              context: context,
              builder: (_) => const LeaveBalanceImportDialog(),
            );
            if (changed == true) ref.invalidate(_leaveBalancesSummaryProvider);
          },
        ),
```

(Adjust to the card child's actual widget shape from Task 5.)

- [ ] **Step 4: Run tests + analyze + commit**

Run: `flutter test test/features/lark/leave_balance_import_test.dart && flutter analyze lib/features/lark/`
Expected: PASS / No issues.

```bash
git add lib/features/lark/leave_balance_import_dialog.dart lib/features/lark/lark_settings_screen.dart test/features/lark/leave_balance_import_test.dart
git commit -m "feat(lark): XLSX leave-balance import fallback"
```

---

### Task 7: Profile leave-balance card — remaining + last synced

**Files:**
- Modify: `lib/features/employees/profile/tabs/attendance_tab.dart` (`_LeaveBalances` ~line 947 and `_LeaveCard` below it)

**Interfaces:**
- Consumes: `leaveBalancesProvider` rows (all `leave_balances` columns + embedded `leave_types(code, name)`).
- Produces: user-visible card only; no new API.

- [ ] **Step 1: Update `_LeaveCard`**

Read the existing `_LeaveCard` implementation (directly below
`_LeaveBalances`). Rework it to show, per leave type:

- Title: `leave_types.name`
- Big number: **Remaining** = `opening_balance + accrued + carried_over_from_previous + adjusted − used − forfeited − converted` (parse all as `Decimal`, default `0`)
- Sub-row: `Granted <accrued> · Used <used>` (+ `· Converted <converted>` only when non-zero)
- Footer, small/muted: `Synced <yyyy-MM-dd of updated_at>` — or `Never synced` when `updated_at` is null/unparseable

Match the existing card's visual container (border, radius, padding,
GeistMono for the numbers per the design system). No layout redesign —
content swap only.

- [ ] **Step 2: Analyze + visual sanity**

Run: `flutter analyze lib/features/employees/`
Expected: No issues.
(Behavioral check happens in the plan-final GUI smoke; there are no
existing widget tests for this tab — do not add a test harness for a
display-only change.)

- [ ] **Step 3: Commit**

```bash
git add lib/features/employees/profile/tabs/attendance_tab.dart
git commit -m "feat(profile): leave balance card shows remaining + last synced"
```

---

### Task 8: 13th month + SIL conversion (combined line + release hook)

**Files:**
- Modify: `lib/data/repositories/payroll_repository.dart` (`distributeThirteenthMonth` ~line 689; the run-release method — find with `grep -n "'RELEASED'" lib/data/repositories/payroll_repository.dart`; add `silConversionCandidatesForRun`)
- Modify: `lib/features/payroll/runs/detail/widgets/distribute_13th_dialog.dart`
- Test: `test/features/payroll/sil_conversion_test.dart` (create — pure math helper)

**Interfaces:**
- Consumes: `leave_balances` (current year, types with `is_convertible = true and is_paid = true`) + `leave_types.conversion_rate`; employee scorecard rate (`role_scorecards.base_salary`, `wage_type`, `work_hours_per_day`) for the daily rate (same conversion as the engine: MONTHLY ÷ 26, HOURLY × hours, DAILY as-is).
- Produces:
  - `class SilConversionCandidate { final String employeeId; final Decimal remainingDays; final Decimal dailyRate; final Decimal amount; final DateTime? lastSyncedAt; final String leaveTypeId; }`
  - `Decimal silConversionAmount({required Decimal remainingDays, required Decimal dailyRate, required Decimal conversionRate})` — pure, tested.
  - `distributeThirteenthMonth` gains `Map<String, SilConversionCandidate>? silByEmployee`; combined line: category `THIRTEENTH_MONTH_PAY`, description `13th Month Pay + SIL Conversion`, `quantity` = SIL days, `rate` = daily rate, `rule_code` = `'THIRTEENTH_MONTH_PLUS_SIL'`, `rule_description` = `'13th: <a>; SIL: <n> d @ <r> = <s>'`, amount = 13th + SIL. Employees with zero remaining SIL keep today's exact line (description `13th Month Pay (distribution)`, rule_code unchanged).
  - Release hook: on the run-release path, for payslip lines with `rule_code = 'THIRTEENTH_MONTH_PLUS_SIL'`, `leave_balances.converted += quantity` for (employee, leaveTypeId from the candidate — store `penalty_installment_id`-style linkage is NOT available, so resolve the leave type at release time: the convertible+paid type, same rule as candidates).

- [ ] **Step 1: Write the failing test**

`test/features/payroll/sil_conversion_test.dart`:

```dart
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/repositories/payroll_repository.dart';

Decimal _d(String s) => Decimal.parse(s);

void main() {
  test('remaining days × daily rate × conversion rate', () {
    expect(
      silConversionAmount(
        remainingDays: _d('3'),
        dailyRate: _d('600'),
        conversionRate: _d('1.0'),
      ),
      _d('1800.00'),
    );
  });

  test('fractional remaining days round to centavos', () {
    expect(
      silConversionAmount(
        remainingDays: _d('2.5'),
        dailyRate: _d('645'),
        conversionRate: _d('1.0'),
      ),
      _d('1612.50'),
    );
  });

  test('zero remaining yields zero', () {
    expect(
      silConversionAmount(
        remainingDays: Decimal.zero,
        dailyRate: _d('600'),
        conversionRate: _d('1.0'),
      ),
      Decimal.zero,
    );
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/payroll/sil_conversion_test.dart`
Expected: FAIL — `silConversionAmount` undefined.

- [ ] **Step 3: Implement repository side**

In `payroll_repository.dart` (top-level, near `LiveThirteenthMonth`):

```dart
/// remaining × dailyRate × conversionRate, rounded to centavos.
Decimal silConversionAmount({
  required Decimal remainingDays,
  required Decimal dailyRate,
  required Decimal conversionRate,
}) {
  final raw = remainingDays * dailyRate * conversionRate;
  return Decimal.parse(raw.toStringAsFixed(2));
}

class SilConversionCandid