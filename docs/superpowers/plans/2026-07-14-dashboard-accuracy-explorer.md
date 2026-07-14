# Dashboard Accuracy + Month/Year Explorer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the HR dashboard's attendance, late/undertime, OT, leave, and movement figures tie out to payslips; add a Month (default) / Year period filter; replace the bottom section with a click-to-filter Monthly Explorer.

**Architecture:** The dashboard fetches one whole calendar year of data in a single provider, then derives 12 month buckets plus a year total in a pure, unit-tested module. Attendance math is *not reimplemented* — it calls `buildAttendanceRows` + `AttendanceStats.from` from `lib/features/attendance/attendance_row_vm.dart`, the same engine the payslip PDF uses. Switching months is a pure re-slice of the already-fetched year, so it needs no refetch. A shared pagination helper removes the silent `max_rows = 1000` truncation from the dashboard, the attendance repository, and payroll compute.

**Tech Stack:** Flutter, Riverpod (`StateProvider` / `FutureProvider` / `Provider`), Supabase Postgrest (`.range()` paging), `decimal`, `fl_chart`, `intl`.

**Spec:** `docs/superpowers/specs/2026-07-14-dashboard-accuracy-explorer-design.md`

## Global Constraints

- **Never run `dart format`.** This repo has mixed old/new formatter style and is NOT gated on it. Match the surrounding style of whatever file you edit.
- **Measured baseline on this branch (`ddd2cd9`), before any of this work:**
  - `flutter analyze` → **189 issues: 0 errors, 20 warnings, 169 infos.** All pre-existing.
  - `flutter test` → **655 pass, 1 skip, 0 fail.**
- The verification gate is therefore: **zero `error`-severity analyzer issues, and no NEW warnings or infos attributable to your files** (compare against the 189 baseline — do not try to drive it to zero, and do not "fix" unrelated pre-existing lints). Full `flutter test` must stay at **655+ passing, 0 failing**; every test you add is additive on top.
- Run tests with `flutter test <path>` — not `dart test`.
- The Dart package name for test imports is **`payroll_flutter`** (e.g. `import 'package:payroll_flutter/data/pagination.dart';`).
- Tables must be wrapped in `ResponsiveTable` (`lib/widgets/responsive_table.dart`).
- Design tokens come from `lib/app/tokens.dart` (`LuxiumColors.of(context)`, `LuxiumSpacing`, `LuxiumRadius`). Single CTA colour is Luxium purple; never introduce cyan/sky-blue accents. Numbers/IDs/dates/currency use the `GeistMono` font family.
- Riverpod rule already learned the hard way in this file: **subscribe to every reactive dependency with `ref.watch` BEFORE the first `await`**, otherwise the subscription never registers and the provider silently stops invalidating.
- Attendance semantics are owned by `lib/features/attendance/attendance_row_vm.dart`. Do not duplicate or re-derive late/OT/rest-day rules anywhere else.
- No schema migration and no Edge Function change in this plan. Pure Flutter.

---

### Task 1: Shared pagination helper

Postgrest caps every response at `max_rows = 1000` (`supabase/config.toml:18`). Several queries in this repo fetch unbounded ranges and are silently truncated. Extract the paging loop once, as a pure higher-order function, so it can be unit-tested without mocking Supabase's fluent query builder.

**Files:**
- Create: `lib/data/pagination.dart`
- Test: `test/data/pagination_test.dart`

**Interfaces:**
- Produces: `Future<List<T>> fetchAllPages<T>(Future<List<T>> Function(int from, int to) page, {int pageSize = 1000, int maxPages = 200})`

- [ ] **Step 1: Write the failing test**

Create `test/data/pagination_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/pagination.dart';

/// Fake page source over a fixed list. Records the (from, to) ranges it was
/// asked for so we can assert the loop walks them correctly.
class _FakeSource {
  final List<int> rows;
  final List<List<int>> ranges = [];
  _FakeSource(int count) : rows = List.generate(count, (i) => i);

  Future<List<int>> page(int from, int to) async {
    ranges.add([from, to]);
    if (from >= rows.length) return const [];
    final end = (to + 1) > rows.length ? rows.length : to + 1;
    return rows.sublist(from, end);
  }
}

void main() {
  group('fetchAllPages', () {
    test('single short page stops after one request', () async {
      final src = _FakeSource(3);
      final out = await fetchAllPages<int>(src.page, pageSize: 1000);
      expect(out.length, 3);
      expect(src.ranges, [
        [0, 999],
      ]);
    });

    test('empty result stops after one request', () async {
      final src = _FakeSource(0);
      final out = await fetchAllPages<int>(src.page, pageSize: 1000);
      expect(out, isEmpty);
      expect(src.ranges.length, 1);
    });

    test('walks past the 1000-row cap and returns every row', () async {
      final src = _FakeSource(2500);
      final out = await fetchAllPages<int>(src.page, pageSize: 1000);
      expect(out.length, 2500);
      expect(out.first, 0);
      expect(out.last, 2499);
      expect(src.ranges, [
        [0, 999],
        [1000, 1999],
        [2000, 2999],
      ]);
    });

    test('exact multiple of pageSize needs a trailing empty page', () async {
      final src = _FakeSource(2000);
      final out = await fetchAllPages<int>(src.page, pageSize: 1000);
      expect(out.length, 2000);
      // Full page at 1000-1999 is indistinguishable from "more to come",
      // so the loop must probe once more and get an empty page.
      expect(src.ranges, [
        [0, 999],
        [1000, 1999],
        [2000, 2999],
      ]);
    });

    test('respects a custom pageSize', () async {
      final src = _FakeSource(5);
      final out = await fetchAllPages<int>(src.page, pageSize: 2);
      expect(out.length, 5);
      expect(src.ranges, [
        [0, 1],
        [2, 3],
        [4, 5],
      ]);
    });

    test('maxPages guard prevents an infinite loop on a misbehaving source',
        () async {
      // A source that always returns a full page would loop forever.
      Future<List<int>> alwaysFull(int from, int to) async =>
          List.generate(to - from + 1, (i) => from + i);
      final out =
          await fetchAllPages<int>(alwaysFull, pageSize: 10, maxPages: 3);
      expect(out.length, 30);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/data/pagination_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'payroll_flutter/data/pagination.dart'` / "fetchAllPages isn't defined".

- [ ] **Step 3: Write the implementation**

Create `lib/data/pagination.dart`:

```dart
/// Postgrest caps every response at `max_rows` (1000 — see
/// supabase/config.toml). Any query that can exceed that must page, or it
/// silently returns a truncated slice and every downstream aggregate is
/// wrong. This walks `.range()` windows until a short page comes back.
///
/// [page] receives an inclusive (from, to) row range and returns that slice.
/// [maxPages] is a runaway guard — a source that always returns a full page
/// would otherwise loop forever.
Future<List<T>> fetchAllPages<T>(
  Future<List<T>> Function(int from, int to) page, {
  int pageSize = 1000,
  int maxPages = 200,
}) async {
  final out = <T>[];
  for (var i = 0; i < maxPages; i++) {
    final from = i * pageSize;
    final rows = await page(from, from + pageSize - 1);
    out.addAll(rows);
    if (rows.length < pageSize) break;
  }
  return out;
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/data/pagination_test.dart`
Expected: PASS — 6 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/data/pagination.dart test/data/pagination_test.dart
git commit -m "feat(data): add fetchAllPages helper for postgrest max_rows paging"
```

---

### Task 2: Apply pagination to attendance reads

`AttendanceRepository.listByRange` and `ComputeService._loadAttendance` both fetch unbounded attendance ranges. A monthly payroll run at 40+ staff is ~1,240 rows — past the cap, so **payroll currently computes on truncated attendance**. Both call sites get the helper from Task 1.

**Files:**
- Modify: `lib/data/repositories/attendance_repository.dart:74-102` (`listByRange`)
- Modify: `lib/features/payroll/runs/compute/compute_service.dart:436-447` (`_loadAttendance`)

**Interfaces:**
- Consumes: `fetchAllPages` from `lib/data/pagination.dart` (Task 1).
- Produces: no signature change. `listByRange` keeps its exact parameters (`start`, `end`, `employeeId`, `companyId`) and return type `Future<List<AttendanceDay>>`. Every existing caller (attendance screen, `runWarningsProvider`, payslip PDF, payslip detail) is corrected with no call-site edit.

- [ ] **Step 1: Rewrite `listByRange` to page**

In `lib/data/repositories/attendance_repository.dart`, add the import at the top of the file (after the existing imports):

```dart
import '../pagination.dart';
```

Replace the body of `listByRange` (currently lines 74-102) with:

```dart
  /// Fetch every attendance row in [start]..[end], paging past postgrest's
  /// `max_rows` cap. A month at ~40 staff already exceeds 1000 rows, so an
  /// unpaged read here silently truncates and every consumer — payroll
  /// compute, run warnings, the dashboard — computes on a partial slice.
  Future<List<AttendanceDay>> listByRange({
    required DateTime start,
    required DateTime end,
    String? employeeId,
    String? companyId,
  }) async {
    final startIso = start.toIso8601String().substring(0, 10);
    final endIso = end.toIso8601String().substring(0, 10);

    final rows = await fetchAllPages<Map<String, dynamic>>((from, to) async {
      var q = _client
          .from('attendance_day_records')
          .select('*, employees!inner(employee_number, first_name, last_name)')
          .gte('attendance_date', startIso)
          .lte('attendance_date', endIso);
      if (employeeId != null) q = q.eq('employee_id', employeeId);
      // Restrict to one company by filtering the inner-joined employee.
      // `!inner` makes this an effective WHERE on the embedded resource.
      if (companyId != null) q = q.eq('employees.company_id', companyId);
      // Order by a stable unique key so page boundaries can't drop or
      // duplicate rows — attendance_date alone is not unique.
      final page = await q
          .order('attendance_date', ascending: false)
          .order('id', ascending: false)
          .range(from, to);
      return (page as List<dynamic>).cast<Map<String, dynamic>>();
    });

    final out = <AttendanceDay>[];
    for (final r in rows) {
      try {
        out.add(AttendanceDay.fromRow(r));
      } catch (e) {
        // ignore: avoid_print
        print('AttendanceDay.fromRow failed for ${r['id']}: $e\nrow=$r');
      }
    }
    return out;
  }
```

Note the added `.order('id')` — paging over a non-unique sort key lets Postgres return rows in an arbitrary order *within* ties, which can duplicate or drop rows across page boundaries. The composite ordering makes the sort total.

- [ ] **Step 2: Rewrite `_loadAttendance` in compute_service to page**

In `lib/features/payroll/runs/compute/compute_service.dart`, add the import alongside the other relative imports:

```dart
import '../../../../data/pagination.dart';
```

Replace the `_loadAttendance` query (currently around lines 436-447 — the method containing `.from('attendance_day_records')`) so the fetch pages:

```dart
    final rows = await fetchAllPages<Map<String, dynamic>>((from, to) async {
      final page = await _client
          .from('attendance_day_records')
          .select()
          .inFilter('employee_id', employeeIds)
          .gte('attendance_date', start.toIso8601String().substring(0, 10))
          .lte('attendance_date', end.toIso8601String().substring(0, 10))
          .order('id', ascending: true)
          .range(from, to);
      return (page as List<dynamic>).cast<Map<String, dynamic>>();
    });
    return _groupBy(rows, 'employee_id');
```

Keep the enclosing method signature and the `_groupBy` call exactly as they are. If the surrounding code names the client differently than `_client`, use whatever identifier that method already uses.

- [ ] **Step 3: Verify the analyzer gained no new issues**

Run: `flutter analyze`
Expected: **189 issues (0 errors)** — unchanged from the baseline in Global Constraints. Any new `error` is a blocker. Do not attempt to reduce the 189.

- [ ] **Step 4: Verify the existing engine tests still pass**

Run: `flutter test test/engine/`
Expected: PASS. These cover payroll computation; the pagination change must not alter results for any run small enough to have fit under the cap.

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/attendance_repository.dart lib/features/payroll/runs/compute/compute_service.dart
git commit -m "fix(attendance): page past postgrest max_rows in listByRange and payroll compute

A monthly run at 40+ staff is ~1240 attendance rows, past the 1000-row
cap, so payroll silently computed on a truncated slice. Both readers now
page. Sort keys made total (id tiebreak) so page boundaries can't drop or
duplicate rows."
```

---

### Task 3: Dashboard period model

**Files:**
- Create: `lib/features/dashboard/dashboard_period.dart`
- Test: `test/features/dashboard/dashboard_period_test.dart`

**Interfaces:**
- Produces:
  - `enum DashboardPeriodMode { month, year }`
  - `class DashboardPeriod` with `final DashboardPeriodMode mode; final int year; final int month;` (month is 1..12, ignored when `mode == year`), value equality, `DashboardPeriod copyWith({DashboardPeriodMode? mode, int? year, int? month})`, `DateTime get start`, `DateTime endOn(DateTime today)`, `String get label`.
  - `DashboardPeriod.now(DateTime today)` — month mode, today's year/month.
  - `final dashboardPeriodProvider = StateProvider<DashboardPeriod>(...)` defaulting to `DashboardPeriod.now(DateTime.now())`.
- Replaces: `dashboardYearProvider` (deleted in Task 6).

- [ ] **Step 1: Write the failing test**

Create `test/features/dashboard/dashboard_period_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/dashboard/dashboard_period.dart';

void main() {
  group('DashboardPeriod', () {
    test('month mode spans the calendar month', () {
      const p = DashboardPeriod(
          mode: DashboardPeriodMode.month, year: 2026, month: 2);
      expect(p.start, DateTime(2026, 2, 1));
      // 2026 is not a leap year — February ends on the 28th.
      expect(p.endOn(DateTime(2026, 7, 14)), DateTime(2026, 2, 28));
    });

    test('year mode spans the calendar year', () {
      const p = DashboardPeriod(
          mode: DashboardPeriodMode.year, year: 2025, month: 1);
      expect(p.start, DateTime(2025, 1, 1));
      expect(p.endOn(DateTime(2026, 7, 14)), DateTime(2025, 12, 31));
    });

    test('an in-progress month clamps its end to today', () {
      const p = DashboardPeriod(
          mode: DashboardPeriodMode.month, year: 2026, month: 7);
      expect(p.endOn(DateTime(2026, 7, 14)), DateTime(2026, 7, 14));
    });

    test('an in-progress year clamps its end to today', () {
      const p = DashboardPeriod(
          mode: DashboardPeriodMode.year, year: 2026, month: 1);
      expect(p.endOn(DateTime(2026, 7, 14)), DateTime(2026, 7, 14));
    });

    test('a fully past month does not clamp', () {
      const p = DashboardPeriod(
          mode: DashboardPeriodMode.month, year: 2026, month: 6);
      expect(p.endOn(DateTime(2026, 7, 14)), DateTime(2026, 6, 30));
    });

    test('label reflects the mode', () {
      const m = DashboardPeriod(
          mode: DashboardPeriodMode.month, year: 2026, month: 7);
      const y = DashboardPeriod(
          mode: DashboardPeriodMode.year, year: 2026, month: 7);
      expect(m.label, 'July 2026');
      expect(y.label, '2026');
    });

    test('DashboardPeriod.now defaults to month mode on today', () {
      final p = DashboardPeriod.now(DateTime(2026, 7, 14));
      expect(p.mode, DashboardPeriodMode.month);
      expect(p.year, 2026);
      expect(p.month, 7);
    });

    test('value equality holds so Riverpod does not spuriously rebuild', () {
      const a = DashboardPeriod(
          mode: DashboardPeriodMode.month, year: 2026, month: 7);
      const b = DashboardPeriod(
          mode: DashboardPeriodMode.month, year: 2026, month: 7);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.copyWith(month: 8), isNot(a));
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/dashboard/dashboard_period_test.dart`
Expected: FAIL — package `dashboard_period.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Create `lib/features/dashboard/dashboard_period.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:intl/intl.dart';

enum DashboardPeriodMode { month, year }

/// The dashboard's selected reporting window. Month is the default — HR
/// reads this screen against the current payroll month far more often than
/// against a whole year. Year mode aggregates all 12 months.
///
/// [month] is always carried (1..12) even in year mode, so toggling back to
/// month mode returns you to the month you were last looking at.
class DashboardPeriod {
  final DashboardPeriodMode mode;
  final int year;
  final int month;

  const DashboardPeriod({
    required this.mode,
    required this.year,
    required this.month,
  });

  factory DashboardPeriod.now(DateTime today) => DashboardPeriod(
        mode: DashboardPeriodMode.month,
        year: today.year,
        month: today.month,
      );

  bool get isYear => mode == DashboardPeriodMode.year;

  DateTime get start =>
      isYear ? DateTime(year, 1, 1) : DateTime(year, month, 1);

  /// Inclusive last day of the period, clamped to [today] when the period is
  /// still in progress. Clamping matters: an unclamped end would count the
  /// rest of the month as scheduled-but-absent work days.
  DateTime endOn(DateTime today) {
    // Day 0 of the following month == last day of this one.
    final natural =
        isYear ? DateTime(year, 12, 31) : DateTime(year, month + 1, 0);
    final t = DateTime(today.year, today.month, today.day);
    return natural.isAfter(t) ? t : natural;
  }

  String get label => isYear
      ? '$year'
      : DateFormat('MMMM yyyy').format(DateTime(year, month, 1));

  DashboardPeriod copyWith({
    DashboardPeriodMode? mode,
    int? year,
    int? month,
  }) =>
      DashboardPeriod(
        mode: mode ?? this.mode,
        year: year ?? this.year,
        month: month ?? this.month,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DashboardPeriod &&
          other.mode == mode &&
          other.year == year &&
          other.month == month);

  @override
  int get hashCode => Object.hash(mode, year, month);
}

/// Drives every figure on the Dashboard. Defaults to the current month.
final dashboardPeriodProvider =
    StateProvider<DashboardPeriod>((ref) => DashboardPeriod.now(DateTime.now()));
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/dashboard/dashboard_period_test.dart`
Expected: PASS — 8 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/features/dashboard/dashboard_period.dart test/features/dashboard/dashboard_period_test.dart
git commit -m "feat(dashboard): add DashboardPeriod (month default / year) model + provider"
```

---

### Task 4: Leave-day expansion

Leave must come from `leave_requests`, not from `ON_LEAVE` attendance rows: attendance rows count whole days (so a half-day reads as 1.0) and miss approved leave that never got an attendance record. Expanding a request day-by-day also lets a request straddling a month boundary split across both buckets.

**Files:**
- Create: `lib/features/dashboard/leave_expansion.dart`
- Test: `test/features/dashboard/leave_expansion_test.dart`

**Interfaces:**
- Produces:
  - `class LeaveDayAllocation { final String employeeId; final DateTime date; final double days; final String leaveType; }` (value equality)
  - `List<LeaveDayAllocation> expandLeaveRequest({required String employeeId, required DateTime startDate, required DateTime endDate, required double leaveDays, String? startHalf, String? endHalf, required String leaveType})`
- Consumed by: Task 5 (`dashboard_metrics.dart`).

- [ ] **Step 1: Write the failing test**

Create `test/features/dashboard/leave_expansion_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/dashboard/leave_expansion.dart';

void main() {
  group('expandLeaveRequest', () {
    test('a plain 3-day request yields 1.0 per day', () {
      final out = expandLeaveRequest(
        employeeId: 'e1',
        startDate: DateTime(2026, 7, 6),
        endDate: DateTime(2026, 7, 8),
        leaveDays: 3.0,
        leaveType: 'Vacation Leave',
      );
      expect(out.length, 3);
      expect(out.map((a) => a.days), everyElement(1.0));
      expect(out.first.date, DateTime(2026, 7, 6));
      expect(out.last.date, DateTime(2026, 7, 8));
      expect(out.first.employeeId, 'e1');
      expect(out.first.leaveType, 'Vacation Leave');
    });

    test('a single-day half-day request is 0.5, not 1.0', () {
      final out = expandLeaveRequest(
        employeeId: 'e1',
        startDate: DateTime(2026, 7, 6),
        endDate: DateTime(2026, 7, 6),
        leaveDays: 0.5,
        startHalf: 'AM',
        leaveType: 'Sick Leave',
      );
      expect(out.length, 1);
      expect(out.single.days, 0.5);
    });

    test('a single day with BOTH halves marked is still one whole day', () {
      // Degenerate input: some sources set both halves on a 1-day request.
      // Naively adding 0.5 + 0.5 on the same date would double-count.
      final out = expandLeaveRequest(
        employeeId: 'e1',
        startDate: DateTime(2026, 7, 6),
        endDate: DateTime(2026, 7, 6),
        leaveDays: 1.0,
        startHalf: 'AM',
        endHalf: 'PM',
        leaveType: 'Sick Leave',
      );
      expect(out.length, 1);
      expect(out.single.days, 1.0);
    });

    test('half start and half end trim both ends of a multi-day request', () {
      final out = expandLeaveRequest(
        employeeId: 'e1',
        startDate: DateTime(2026, 7, 6),
        endDate: DateTime(2026, 7, 8),
        leaveDays: 2.0,
        startHalf: 'PM',
        endHalf: 'AM',
        leaveType: 'Vacation Leave',
      );
      expect(out.map((a) => a.days).toList(), [0.5, 1.0, 0.5]);
      expect(out.fold<double>(0, (s, a) => s + a.days), 2.0);
    });

    test('a request straddling a month boundary splits across both months',
        () {
      final out = expandLeaveRequest(
        employeeId: 'e1',
        startDate: DateTime(2026, 7, 30),
        endDate: DateTime(2026, 8, 2),
        leaveDays: 4.0,
        leaveType: 'Vacation Leave',
      );
      final july = out.where((a) => a.date.month == 7);
      final august = out.where((a) => a.date.month == 8);
      expect(july.fold<double>(0, (s, a) => s + a.days), 2.0);
      expect(august.fold<double>(0, (s, a) => s + a.days), 2.0);
    });

    test('per-day values are scaled to reconcile with a disagreeing leave_days',
        () {
      // Stored leave_days says 2.0 but the span is 4 calendar days (e.g. the
      // source excluded weekends). Scale so the request still contributes
      // exactly 2.0 — bad data must not inflate the month bucket.
      final out = expandLeaveRequest(
        employeeId: 'e1',
        startDate: DateTime(2026, 7, 6),
        endDate: DateTime(2026, 7, 9),
        leaveDays: 2.0,
        leaveType: 'Vacation Leave',
      );
      expect(out.length, 4);
      expect(out.fold<double>(0, (s, a) => s + a.days), closeTo(2.0, 1e-9));
      expect(out.every((a) => a.days == 0.5), isTrue);
    });

    test('leaveDays of 0 yields no allocations', () {
      final out = expandLeaveRequest(
        employeeId: 'e1',
        startDate: DateTime(2026, 7, 6),
        endDate: DateTime(2026, 7, 6),
        leaveDays: 0,
        leaveType: 'Vacation Leave',
      );
      expect(out, isEmpty);
    });

    test('an inverted range (end before start) yields no allocations', () {
      final out = expandLeaveRequest(
        employeeId: 'e1',
        startDate: DateTime(2026, 7, 9),
        endDate: DateTime(2026, 7, 6),
        leaveDays: 2.0,
        leaveType: 'Vacation Leave',
      );
      expect(out, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/dashboard/leave_expansion_test.dart`
Expected: FAIL — `leave_expansion.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Create `lib/features/dashboard/leave_expansion.dart`:

```dart
/// One employee-day's worth of approved leave, attributed to a specific
/// calendar date so it can be bucketed by month.
class LeaveDayAllocation {
  final String employeeId;
  final DateTime date;
  final double days; // 0.5 or 1.0, or a scaled value after reconciliation
  final String leaveType;

  const LeaveDayAllocation({
    required this.employeeId,
    required this.date,
    required this.days,
    required this.leaveType,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LeaveDayAllocation &&
          other.employeeId == employeeId &&
          other.date == date &&
          other.days == days &&
          other.leaveType == leaveType);

  @override
  int get hashCode => Object.hash(employeeId, date, days, leaveType);
}

/// Expand a leave request into per-date allocations.
///
/// Why not just read `ON_LEAVE` attendance rows? Two reasons: those count
/// whole days (a half-day leave reads as 1.0), and approved leave that never
/// received an attendance record is invisible to them entirely.
///
/// `start_half` / `end_half` mark a partial first/last day (0.5). A
/// single-day request with either half set is 0.5 — and with *both* set is
/// still 1.0, not 0.5+0.5 on the same date.
///
/// The reconstructed total is reconciled against the stored [leaveDays]: if
/// they disagree (e.g. the source excluded weekends from its own count),
/// every per-day value is scaled so the request contributes exactly
/// [leaveDays]. Bad data must not silently inflate a month bucket.
List<LeaveDayAllocation> expandLeaveRequest({
  required String employeeId,
  required DateTime startDate,
  required DateTime endDate,
  required double leaveDays,
  String? startHalf,
  String? endHalf,
  required String leaveType,
}) {
  if (leaveDays <= 0) return const [];

  final start = DateTime(startDate.year, startDate.month, startDate.day);
  final end = DateTime(endDate.year, endDate.month, endDate.day);
  if (end.isBefore(start)) return const [];

  final dates = <DateTime>[];
  for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
    dates.add(d);
  }

  final hasStartHalf = startHalf != null && startHalf.isNotEmpty;
  final hasEndHalf = endHalf != null && endHalf.isNotEmpty;
  final single = dates.length == 1;

  final raw = <double>[];
  for (var i = 0; i < dates.length; i++) {
    var v = 1.0;
    if (single) {
      // Both halves on a one-day request means the whole day, not two
      // stacked halves on the same date.
      if (hasStartHalf != hasEndHalf) v = 0.5;
    } else {
      if (i == 0 && hasStartHalf) v = 0.5;
      if (i == dates.length - 1 && hasEndHalf) v = 0.5;
    }
    raw.add(v);
  }

  final rawTotal = raw.fold<double>(0, (s, v) => s + v);
  final scale = (rawTotal > 0 && (rawTotal - leaveDays).abs() > 1e-9)
      ? leaveDays / rawTotal
      : 1.0;

  return [
    for (var i = 0; i < dates.length; i++)
      LeaveDayAllocation(
        employeeId: employeeId,
        date: dates[i],
        days: raw[i] * scale,
        leaveType: leaveType,
      ),
  ];
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/dashboard/leave_expansion_test.dart`
Expected: PASS — 8 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/features/dashboard/leave_expansion.dart test/features/dashboard/leave_expansion_test.dart
git commit -m "feat(dashboard): expand approved leave requests into per-date allocations

Half-days, month-straddling requests, and requests whose day count
disagrees with stored leave_days all resolve correctly. Replaces counting
whole-day ON_LEAVE attendance rows."
```

---

### Task 5: Pure metrics module

The heart of the change. Everything here is pure — no Supabase, no Flutter widgets — so it can be tested directly. Attendance is delegated to `AttendanceRowVm` / `AttendanceStats`; this module only slices, buckets, and sums.

**Files:**
- Create: `lib/features/dashboard/dashboard_metrics.dart`
- Test: `test/features/dashboard/dashboard_metrics_test.dart`

**Interfaces:**
- Consumes: `LeaveDayAllocation` (Task 4); `buildAttendanceRows`, `AttendanceStats`, `isoDate` from `lib/features/attendance/attendance_row_vm.dart`; models `Employee`, `RoleScorecard`, `ShiftTemplate`, `CalendarEvent`, `AttendanceDay`, `Applicant`.
- Produces:
  - `class DashboardPayslip { final String employeeId; final DateTime payDate; final Decimal grossPay, sssEe, philhealthEe, pagibigEe, withholdingTax; }`
  - `class DashboardYearInput { final int year; final List<Employee> employees; final Map<String, RoleScorecard> scorecardsById; final Map<String, ShiftTemplate> shiftsById; final Map<String, String> departmentNames; final Map<String, String> hiringEntityNames; final Map<String, CalendarEvent> holidaysByDate; final List<AttendanceDay> attendance; final List<LeaveDayAllocation> leaveDays; final List<DashboardPayslip> payslips; final List<Applicant> applicants; final DateTime today; }`
  - `class MonthMetrics` — see fields in Step 3.
  - `class SnapshotMetrics` — see fields in Step 3.
  - `List<MonthMetrics> computeMonthMetrics(DashboardYearInput input)` → exactly 12 entries, index 0 = January.
  - `MonthMetrics aggregateMonths(List<MonthMetrics> months, int year)` → the year total (`month == null`).
  - `SnapshotMetrics computeSnapshot(DashboardYearInput input, DateTime asOf)`
  - `bool isActiveAsOf(Employee e, DateTime asOf)`

**Definitional note (a tightening of the spec, deliberate):** the spec wrote attendance rate as `present ÷ (work days − on-leave days)`. Implemented as **`present ÷ (present + absent)`**, which is the same intent but exactly defined: `AttendanceStats` only increments `present`/`absent` on non-leave work days, so this denominator can never be polluted by a leave day or by a work day carrying some other status.

- [ ] **Step 1: Write the failing test**

Create `test/features/dashboard/dashboard_metrics_test.dart`:

```dart
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/attendance_day.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/models/shift_template.dart';
import 'package:payroll_flutter/features/dashboard/dashboard_metrics.dart';
import 'package:payroll_flutter/features/dashboard/leave_expansion.dart';

// ---------------------------------------------------------------------------
// Builders. The models carry many required fields that are irrelevant here;
// these keep each test to the two or three fields it actually exercises.
// ---------------------------------------------------------------------------

Employee _emp({
  required String id,
  required DateTime hireDate,
  DateTime? separationDate,
  String employmentStatus = 'ACTIVE',
  DateTime? deletedAt,
  String employmentType = 'REGULAR',
  String? roleScorecardId = 'sc1',
  String? departmentId,
  String? hiringEntityId,
}) {
  return Employee(
    id: id,
    companyId: 'c1',
    employeeNumber: id,
    firstName: 'Test',
    lastName: id,
    employmentType: employmentType,
    employmentStatus: employmentStatus,
    hireDate: hireDate,
    separationDate: separationDate,
    deletedAt: deletedAt,
    roleScorecardId: roleScorecardId,
    departmentId: departmentId,
    hiringEntityId: hiringEntityId,
    isRankAndFile: true,
    isOtEligible: true,
    isNdEligible: true,
    isHolidayPayEligible: true,
    taxOnFullEarnings: false,
  );
}

/// 08:00-17:00 with a 60-minute break => 480 expected work minutes.
ShiftTemplate _shift() => const ShiftTemplate(
      id: 'sh1',
      companyId: 'c1',
      code: 'DAY',
      name: 'Day',
      startTime: '08:00:00',
      endTime: '17:00:00',
      isOvernight: false,
      breakType: 'AUTO_DEDUCT',
      breakMinutes: 60,
      graceMinutesLate: 0,
      graceMinutesEarlyOut: 0,
      scheduledWorkMinutes: 480,
    );

RoleScorecard _scorecard() => RoleScorecard(
      id: 'sc1',
      companyId: 'c1',
      jobTitle: 'Staff',
      missionStatement: '',
      responsibilities: const [],
      kpis: const [],
      wageType: 'MONTHLY',
      workHoursPerDay: 8,
      workDaysPerWeek: 'Monday to Friday',
      isActive: true,
      effectiveDate: DateTime(2020, 1, 1),
      shiftTemplateId: 'sh1',
    );

AttendanceDay _day({
  required String employeeId,
  required DateTime date,
  String? timeIn,
  String? timeOut,
  String status = 'PRESENT',
  String dayType = 'WORKDAY',
  String? shiftTemplateId = 'sh1',
  int? approvedOtMinutes,
}) {
  DateTime? at(String? hhmm) {
    if (hhmm == null) return null;
    final p = hhmm.split(':');
    return DateTime(date.year, date.month, date.day,
        int.parse(p[0]), int.parse(p[1]));
  }

  return AttendanceDay(
    id: '$employeeId-${date.toIso8601String()}',
    employeeId: employeeId,
    attendanceDate: date,
    dayType: dayType,
    actualTimeIn: at(timeIn),
    actualTimeOut: at(timeOut),
    attendanceStatus: status,
    sourceType: 'MANUAL',
    earlyInApproved: false,
    lateOutApproved: false,
    lateInApproved: false,
    earlyOutApproved: false,
    approvedOtMinutes: approvedOtMinutes,
    shiftTemplateId: shiftTemplateId,
    isLocked: false,
  );
}

DashboardYearInput _input({
  required List<Employee> employees,
  List<AttendanceDay> attendance = const [],
  List<LeaveDayAllocation> leaveDays = const [],
  List<DashboardPayslip> payslips = const [],
  DateTime? today,
}) {
  return DashboardYearInput(
    year: 2026,
    employees: employees,
    scorecardsById: {'sc1': _scorecard()},
    shiftsById: {'sh1': _shift()},
    departmentNames: const {'d1': 'Engineering'},
    hiringEntityNames: const {'h1': 'Luxium HQ'},
    holidaysByDate: const {},
    attendance: attendance,
    leaveDays: leaveDays,
    payslips: payslips,
    applicants: const [],
    today: today ?? DateTime(2026, 12, 31),
  );
}

void main() {
  group('computeMonthMetrics — attendance', () {
    test('returns exactly 12 buckets, January first', () {
      final months = computeMonthMetrics(
          _input(employees: [_emp(id: 'e1', hireDate: DateTime(2020, 1, 1))]));
      expect(months.length, 12);
      expect(months.first.month, 1);
      expect(months.last.month, 12);
    });

    test('an on-time full day is present with no late and no OT', () {
      // 2026-07-06 is a Monday.
      final months = computeMonthMetrics(_input(
        employees: [_emp(id: 'e1', hireDate: DateTime(2020, 1, 1))],
        attendance: [
          _day(
              employeeId: 'e1',
              date: DateTime(2026, 7, 6),
              timeIn: '08:00',
              timeOut: '17:00'),
        ],
        today: DateTime(2026, 7, 6),
      ));
      final july = months[6];
      expect(july.presentDays, 1);
      expect(july.lateUndertimeMinutes, 0);
      expect(july.overtimeMinutes, 0);
    });

    test('clocking in 30m late registers 30 late minutes', () {
      final months = computeMonthMetrics(_input(
        employees: [_emp(id: 'e1', hireDate: DateTime(2020, 1, 1))],
        attendance: [
          _day(
              employeeId: 'e1',
              date: DateTime(2026, 7, 6),
              timeIn: '08:30',
              timeOut: '17:00'),
        ],
        today: DateTime(2026, 7, 6),
      ));
      expect(months[6].lateUndertimeMinutes, closeTo(30, 0.01));
    });

    test('leaving 30m early registers as late/UT too (undertime)', () {
      // The old dashboard missed this entirely — it only looked at clock-in.
      final months = computeMonthMetrics(_input(
        employees: [_emp(id: 'e1', hireDate: DateTime(2020, 1, 1))],
        attendance: [
          _day(
              employeeId: 'e1',
              date: DateTime(2026, 7, 6),
              timeIn: '08:00',
              timeOut: '16:30'),
        ],
        today: DateTime(2026, 7, 6),
      ));
      expect(months[6].lateUndertimeMinutes, closeTo(30, 0.01));
    });

    test('approved OT absorbs late minutes (net late = 0)', () {
      final months = computeMonthMetrics(_input(
        employees: [_emp(id: 'e1', hireDate: DateTime(2020, 1, 1))],
        attendance: [
          _day(
              employeeId: 'e1',
              date: DateTime(2026, 7, 6),
              timeIn: '08:30',
              timeOut: '17:00',
              approvedOtMinutes: 60),
        ],
        today: DateTime(2026, 7, 6),
      ));
      final july = months[6];
      expect(july.lateUndertimeMinutes, 0);
      expect(july.overtimeMinutes, closeTo(30, 0.01)); // 60 OT - 30 late
    });

    test('a mid-year hire accrues no absences before the hire date', () {
      // Hired 1 July. If the window were not clipped, Jan-Jun would fill with
      // scheduled-but-absent work days.
      final months = computeMonthMetrics(_input(
        employees: [_emp(id: 'e1', hireDate: DateTime(2026, 7, 1))],
        today: DateTime(2026, 7, 31),
      ));
      expect(months[0].workDays, 0); // January
      expect(months[0].absentDays, 0);
      expect(months[5].workDays, 0); // June
      expect(months[6].workDays, greaterThan(0)); // July
    });

    test('attendance rate is present / (present + absent)', () {
      final months = computeMonthMetrics(_input(
        employees: [_emp(id: 'e1', hireDate: DateTime(2020, 1, 1))],
        attendance: [
          _day(
              employeeId: 'e1',
              date: DateTime(2026, 7, 6),
              timeIn: '08:00',
              timeOut: '17:00'),
          _day(
              employeeId: 'e1',
              date: DateTime(2026, 7, 7),
              status: 'ABSENT'),
        ],
        today: DateTime(2026, 7, 7),
      ));
      final july = months[6];
      expect(july.presentDays, 1);
      expect(july.absentDays, 1);
      expect(july.attendanceRatePct, closeTo(50.0, 0.01));
    });

    test('a scheduled-off day with no record is a rest day, not an absence',
        () {
      // The scorecard says Monday-Friday. 2026-07-11 is a Saturday with no
      // attendance record at all. It must not read as a no-show.
      final months = computeMonthMetrics(_input(
        employees: [_emp(id: 'e1', hireDate: DateTime(2020, 1, 1))],
        today: DateTime(2026, 7, 11),
      ));
      final july = months[6];
      expect(july.restDays, greaterThan(0));
      // Jul 1-10 are unrecorded weekdays => absent; the weekend days are not.
      // What matters is that Saturday/Sunday never landed in `absent`.
      expect(july.absentDays, july.workDays);
    });

    test('rates return 0 rather than NaN when the denominator is empty', () {
      final months = computeMonthMetrics(
          _input(employees: [_emp(id: 'e1', hireDate: DateTime(2020, 1, 1))]));
      expect(months[0].attendanceRatePct, 0);
      expect(months[0].avgLateMinutesPerWorkDay, 0);
      expect(months[0].avgGrossPerEmployee, Decimal.zero);
    });
  });

  group('computeMonthMetrics — leave', () {
    test('half-day leave contributes 0.5 to the month bucket', () {
      final months = computeMonthMetrics(_input(
        employees: [_emp(id: 'e1', hireDate: DateTime(2020, 1, 1))],
        leaveDays: [
          LeaveDayAllocation(
              employeeId: 'e1',
              date: DateTime(2026, 7, 6),
              days: 0.5,
              leaveType: 'Sick Leave'),
        ],
      ));
      expect(months[6].leaveDays, 0.5);
      expect(months[6].leaveDaysByType['Sick Leave'], 0.5);
    });

    test('leave lands in the month of its date, not the request start', () {
      final months = computeMonthMetrics(_input(
        employees: [_emp(id: 'e1', hireDate: DateTime(2020, 1, 1))],
        leaveDays: [
          LeaveDayAllocation(
              employeeId: 'e1',
              date: DateTime(2026, 7, 31),
              days: 1.0,
              leaveType: 'Vacation Leave'),
          LeaveDayAllocation(
              employeeId: 'e1',
              date: DateTime(2026, 8, 1),
              days: 1.0,
              leaveType: 'Vacation Leave'),
        ],
      ));
      expect(months[6].leaveDays, 1.0); // July
      expect(months[7].leaveDays, 1.0); // August
    });
  });

  group('computeMonthMetrics — movement', () {
    test('new hires land in their hire month', () {
      final months = computeMonthMetrics(_input(
        employees: [
          _emp(id: 'e1', hireDate: DateTime(2026, 3, 15)),
          _emp(id: 'e2', hireDate: DateTime(2026, 3, 20)),
          _emp(id: 'e3', hireDate: DateTime(2025, 1, 1)), // prior year
        ],
      ));
      expect(months[2].newHires, 2); // March
      expect(months[0].newHires, 0);
    });

    test('a separated AND archived employee still counts in the month they left',
        () {
      // Separation sets deleted_at (the "archive on separate" option). A
      // `deleted_at is null` filter would hide the separation entirely —
      // which is exactly what the old dashboard did.
      final months = computeMonthMetrics(_input(
        employees: [
          _emp(
            id: 'e1',
            hireDate: DateTime(2024, 1, 1),
            separationDate: DateTime(2026, 5, 10),
            employmentStatus: 'RESIGNED',
            deletedAt: DateTime(2026, 5, 10),
          ),
        ],
      ));
      expect(months[4].separations, 1); // May
      expect(months[4].voluntarySeparations, 1);
      expect(months[4].involuntarySeparations, 0);
    });

    test('RESIGNED and RETIRED are voluntary; TERMINATED, END_OF_CONTRACT, '
        'AWOL and DECEASED are involuntary', () {
      final months = computeMonthMetrics(_input(
        employees: [
          for (final s in ['RESIGNED', 'RETIRED'])
            _emp(
                id: 'v-$s',
                hireDate: DateTime(2024, 1, 1),
                separationDate: DateTime(2026, 5, 10),
                employmentStatus: s),
          for (final s in ['TERMINATED', 'END_OF_CONTRACT', 'AWOL', 'DECEASED'])
            _emp(
                id: 'i-$s',
                hireDate: DateTime(2024, 1, 1),
                separationDate: DateTime(2026, 5, 10),
                employmentStatus: s),
        ],
      ));
      expect(months[4].voluntarySeparations, 2);
      expect(months[4].involuntarySeparations, 4);
      expect(months[4].separations, 6);
    });

    test('an ACTIVE employee with a separation_date is not a separation', () {
      final months = computeMonthMetrics(_input(
        employees: [
          _emp(
              id: 'e1',
              hireDate: DateTime(2024, 1, 1),
              separationDate: DateTime(2026, 5, 10),
              employmentStatus: 'ACTIVE'),
        ],
      ));
      expect(months[4].separations, 0);
    });
  });

  group('computeMonthMetrics — payroll', () {
    test('payslips bucket by pay_date and avg gross divides by DISTINCT '
        'employees, not payslip count', () {
      // Two semi-monthly payslips for the same employee. Dividing by payslip
      // count would report an average half-month as a salary.
      Decimal d(String s) => Decimal.parse(s);
      final months = computeMonthMetrics(_input(
        employees: [_emp(id: 'e1', hireDate: DateTime(2020, 1, 1))],
        payslips: [
          DashboardPayslip(
              employeeId: 'e1',
              payDate: DateTime(2026, 7, 15),
              grossPay: d('15000'),
              sssEe: d('675'),
              philhealthEe: d('375'),
              pagibigEe: d('100'),
              withholdingTax: d('500')),
          DashboardPayslip(
              employeeId: 'e1',
              payDate: DateTime(2026, 7, 31),
              grossPay: d('15000'),
              sssEe: d('675'),
              philhealthEe: d('375'),
              pagibigEe: d('100'),
              withholdingTax: d('500')),
        ],
      ));
      final july = months[6];
      expect(july.payrollGross, d('30000'));
      expect(july.payrollEmployeeIds.length, 1);
      expect(july.avgGrossPerEmployee, d('30000'));
      expect(july.sssTotal, d('1350'));
    });
  });

  group('aggregateMonths', () {
    test('additive metrics sum and the year total carries a null month', () {
      final months = computeMonthMetrics(_input(
        employees: [
          _emp(id: 'e1', hireDate: DateTime(2026, 3, 1)),
          _emp(id: 'e2', hireDate: DateTime(2026, 9, 1)),
        ],
        leaveDays: [
          LeaveDayAllocation(
              employeeId: 'e1',
              date: DateTime(2026, 4, 1),
              days: 1.0,
              leaveType: 'Vacation Leave'),
          LeaveDayAllocation(
              employeeId: 'e1',
              date: DateTime(2026, 5, 1),
              days: 0.5,
              leaveType: 'Sick Leave'),
        ],
      ));
      final year = aggregateMonths(months, 2026);
      expect(year.month, isNull);
      expect(year.newHires, 2);
      expect(year.leaveDays, 1.5);
      expect(year.leaveDaysByType['Vacation Leave'], 1.0);
      expect(year.leaveDaysByType['Sick Leave'], 0.5);
      expect(year.workDays,
          months.fold<int>(0, (s, m) => s + m.workDays));
    });

    test('payroll employees are UNIONed across months, not summed', () {
      Decimal d(String s) => Decimal.parse(s);
      final months = computeMonthMetrics(_input(
        employees: [_emp(id: 'e1', hireDate: DateTime(2020, 1, 1))],
        payslips: [
          DashboardPayslip(
              employeeId: 'e1',
              payDate: DateTime(2026, 6, 30),
              grossPay: d('30000'),
              sssEe: Decimal.zero,
              philhealthEe: Decimal.zero,
              pagibigEe: Decimal.zero,
              withholdingTax: Decimal.zero),
          DashboardPayslip(
              employeeId: 'e1',
              payDate: DateTime(2026, 7, 31),
              grossPay: d('30000'),
              sssEe: Decimal.zero,
              philhealthEe: Decimal.zero,
              pagibigEe: Decimal.zero,
              withholdingTax: Decimal.zero),
        ],
      ));
      final year = aggregateMonths(months, 2026);
      // One employee paid in two months is one employee, not two.
      expect(year.payrollEmployeeIds.length, 1);
      expect(year.payrollGross, d('60000'));
      expect(year.avgGrossPerEmployee, d('60000'));
    });
  });

  group('computeSnapshot / isActiveAsOf', () {
    test('an employee hired after the as-of date is not yet active', () {
      final e = _emp(id: 'e1', hireDate: DateTime(2026, 8, 1));
      expect(isActiveAsOf(e, DateTime(2026, 7, 31)), isFalse);
      expect(isActiveAsOf(e, DateTime(2026, 8, 1)), isTrue);
    });

    test('a separated employee is active up to and including their last day',
        () {
      final e = _emp(
        id: 'e1',
        hireDate: DateTime(2024, 1, 1),
        separationDate: DateTime(2026, 5, 10),
        employmentStatus: 'RESIGNED',
        deletedAt: DateTime(2026, 5, 10),
      );
      expect(isActiveAsOf(e, DateTime(2026, 5, 10)), isTrue);
      expect(isActiveAsOf(e, DateTime(2026, 5, 11)), isFalse);
    });

    test('an admin-archived employee who was never separated is excluded', () {
      final e = _emp(
        id: 'e1',
        hireDate: DateTime(2024, 1, 1),
        deletedAt: DateTime(2026, 3, 1),
      );
      expect(isActiveAsOf(e, DateTime(2026, 7, 1)), isFalse);
    });

    test('snapshot buckets by department name via the scorecard, then the '
        'employee, then Unassigned', () {
      final input = _input(employees: [
        _emp(id: 'e1', hireDate: DateTime(2020, 1, 1), departmentId: 'd1'),
        _emp(
            id: 'e2',
            hireDate: DateTime(2020, 1, 1),
            departmentId: null,
            roleScorecardId: null),
      ]);
      final snap = computeSnapshot(input, DateTime(2026, 7, 31));
      expect(snap.activeEmployees, 2);
      expect(snap.headcountByDepartment['Engineering'], 1);
      expect(snap.headcountByDepartment['Unassigned'], 1);
      expect(snap.asOf, DateTime(2026, 7, 31));
    });

    test('separated employee drops out of the following month snapshot', () {
      final input = _input(employees: [
        _emp(
          id: 'e1',
          hireDate: DateTime(2024, 1, 1),
          separationDate: DateTime(2026, 5, 10),
          employmentStatus: 'RESIGNED',
          deletedAt: DateTime(2026, 5, 10),
        ),
      ]);
      expect(computeSnapshot(input, DateTime(2026, 5, 31)).activeEmployees, 0);
      expect(computeSnapshot(input, DateTime(2026, 4, 30)).activeEmployees, 1);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/dashboard/dashboard_metrics_test.dart`
Expected: FAIL — `dashboard_metrics.dart` does not exist.

If any *builder* in the test fails to compile because a model's constructor requires a field this plan didn't list, add that field with an obviously-inert value (empty string, `false`, `Decimal.zero`) — do not change the model.

- [ ] **Step 3: Write the implementation**

Create `lib/features/dashboard/dashboard_metrics.dart`:

```dart
import 'package:decimal/decimal.dart';

import '../../data/models/applicant.dart';
import '../../data/models/attendance_day.dart';
import '../../data/models/calendar_event.dart';
import '../../data/models/employee.dart';
import '../../data/models/role_scorecard.dart';
import '../../data/models/shift_template.dart';
import '../attendance/attendance_row_vm.dart';
import 'leave_expansion.dart';

/// Payslip fields the dashboard needs, flattened with the run's `pay_date`
/// (which lives on payroll_runs, not payslips).
class DashboardPayslip {
  final String employeeId;
  final DateTime payDate;
  final Decimal grossPay;
  final Decimal sssEe;
  final Decimal philhealthEe;
  final Decimal pagibigEe;
  final Decimal withholdingTax;

  const DashboardPayslip({
    required this.employeeId,
    required this.payDate,
    required this.grossPay,
    required this.sssEe,
    required this.philhealthEe,
    required this.pagibigEe,
    required this.withholdingTax,
  });
}

/// Everything the dashboard fetched for one calendar year. [employees]
/// deliberately INCLUDES soft-deleted rows: separating an employee can stamp
/// `deleted_at`, so filtering them out here would hide the separations we
/// need to report. `isActiveAsOf` does the filtering that headcount wants.
class DashboardYearInput {
  final int year;
  final List<Employee> employees;
  final Map<String, RoleScorecard> scorecardsById;
  final Map<String, ShiftTemplate> shiftsById;
  final Map<String, String> departmentNames; // departmentId -> name
  final Map<String, String> hiringEntityNames; // hiringEntityId -> name
  final Map<String, CalendarEvent> holidaysByDate; // iso yyyy-MM-dd -> event
  final List<AttendanceDay> attendance;
  final List<LeaveDayAllocation> leaveDays;
  final List<DashboardPayslip> payslips;
  final List<Applicant> applicants;
  final DateTime today;

  const DashboardYearInput({
    required this.year,
    required this.employees,
    required this.scorecardsById,
    required this.shiftsById,
    required this.departmentNames,
    required this.hiringEntityNames,
    required this.holidaysByDate,
    required this.attendance,
    required this.leaveDays,
    required this.payslips,
    required this.applicants,
    required this.today,
  });
}

/// Period-scoped metrics for one month, or for a whole year when [month] is
/// null. Only additive, period-scoped figures live here — headcount, tenure
/// and employment-type distributions are point-in-time snapshots that do not
/// sum across months, so they live in [SnapshotMetrics] instead.
class MonthMetrics {
  final int year;
  final int? month; // 1..12; null = full-year aggregate

  // Attendance — all delegated to AttendanceStats (the payroll engine).
  final int workDays;
  final int presentDays;
  final int absentDays;
  final int restDays;
  final int regularHolidays;
  final int specialHolidays;
  final double lateUndertimeMinutes; // net of OT absorption
  final double overtimeMinutes; // net of late absorption

  // Leave — from leave_requests, not attendance rows.
  final double leaveDays;
  final Map<String, double> leaveDaysByType;

  // Movement — from employees.hire_date / separation_date.
  final int newHires;
  final int separations;
  final int voluntarySeparations;
  final int involuntarySeparations;

  // Payroll — RELEASED payslips bucketed by pay_date.
  final Decimal payrollGross;
  final Decimal sssTotal;
  final Decimal philhealthTotal;
  final Decimal pagibigTotal;
  final Decimal withholdingTaxTotal;

  /// Distinct employees paid in this period. Stored as a set, not a count,
  /// so the year aggregate can UNION rather than sum — an employee paid in
  /// twelve months is one employee, not twelve.
  final Set<String> payrollEmployeeIds;

  final int newApplicants;

  const MonthMetrics({
    required this.year,
    required this.month,
    required this.workDays,
    required this.presentDays,
    required this.absentDays,
    required this.restDays,
    required this.regularHolidays,
    required this.specialHolidays,
    required this.lateUndertimeMinutes,
    required this.overtimeMinutes,
    required this.leaveDays,
    required this.leaveDaysByType,
    required this.newHires,
    required this.separations,
    required this.voluntarySeparations,
    required this.involuntarySeparations,
    required this.payrollGross,
    required this.sssTotal,
    required this.philhealthTotal,
    required this.pagibigTotal,
    required this.withholdingTaxTotal,
    required this.payrollEmployeeIds,
    required this.newApplicants,
  });

  /// Present out of the days the employee was expected in and NOT on leave.
  /// AttendanceStats only increments present/absent on non-leave work days,
  /// so this denominator cannot be polluted by leave or by a work day
  /// carrying some other status.
  double get attendanceRatePct {
    final chargeable = presentDays + absentDays;
    if (chargeable <= 0) return 0;
    return (presentDays / chargeable) * 100.0;
  }

  /// Late/UT spread over every scheduled work day. The old "avg late minutes"
  /// divided by the number of *late samples*, so it went UP when fewer people
  /// were late.
  double get avgLateMinutesPerWorkDay {
    if (workDays <= 0) return 0;
    return lateUndertimeMinutes / workDays;
  }

  double get overtimeHours => overtimeMinutes / 60.0;

  int get payrollEmployeeCount => payrollEmployeeIds.length;

  Decimal get avgGrossPerEmployee {
    final n = payrollEmployeeIds.length;
    if (n == 0) return Decimal.zero;
    return (payrollGross / Decimal.fromInt(n))
        .toDecimal(scaleOnInfinitePrecision: 2);
  }

  bool get isEmpty =>
      workDays == 0 &&
      presentDays == 0 &&
      absentDays == 0 &&
      leaveDays == 0 &&
      newHires == 0 &&
      separations == 0 &&
      payrollGross == Decimal.zero;
}

/// Point-in-time distributions, valid only "as of" a given date.
class SnapshotMetrics {
  final DateTime asOf;
  final int activeEmployees;
  final int totalEmployees;
  final double avgTenureMonths;
  final Map<String, int> headcountByDepartment;
  final Map<String, int> employmentTypeCounts;
  final Map<String, int> hiringEntityCounts;
  final Map<String, int> tenureBuckets;

  const SnapshotMetrics({
    required this.asOf,
    required this.activeEmployees,
    required this.totalEmployees,
    required this.avgTenureMonths,
    required this.headcountByDepartment,
    required this.employmentTypeCounts,
    required this.hiringEntityCounts,
    required this.tenureBuckets,
  });
}

const _kVoluntary = {'RESIGNED', 'RETIRED'};

/// AWOL is treated as employer-side: in practice abandonment resolves to
/// termination for cause.
const _kInvoluntary = {
  'TERMINATED',
  'END_OF_CONTRACT',
  'AWOL',
  'DECEASED',
};

/// An employee counts toward headcount "as of" [asOf] when they were hired on
/// or before that date and had not yet separated. Rows that were
/// administratively archived (`deleted_at`) without ever being separated are
/// excluded — those are data cleanups, not people.
bool isActiveAsOf(Employee e, DateTime asOf) {
  final hire = DateTime(e.hireDate.year, e.hireDate.month, e.hireDate.day);
  final d = DateTime(asOf.year, asOf.month, asOf.day);
  if (hire.isAfter(d)) return false;
  final sep = e.separationDate;
  if (sep != null) {
    final s = DateTime(sep.year, sep.month, sep.day);
    return s.isAfter(d);
  }
  return e.deletedAt == null;
}

double _tenureMonths(DateTime hire, DateTime asOf) =>
    asOf.difference(hire).inDays / 30.4375;

String _tenureBucket(double months) {
  if (months < 12) return '< 1 year';
  if (months < 24) return '1-2 years';
  if (months < 60) return '2-5 years';
  return '5+ years';
}

/// Department name for an employee. The role scorecard's department is the
/// source of truth for "who belongs where"; fall back to the employee's own
/// link, then 'Unassigned'.
String _departmentNameFor(Employee e, DashboardYearInput input) {
  final scId = e.roleScorecardId;
  if (scId != null) {
    final deptId = input.scorecardsById[scId]?.departmentId;
    if (deptId != null) {
      final name = input.departmentNames[deptId];
      if (name != null) return name;
    }
  }
  final own = e.departmentId;
  if (own != null) {
    final name = input.departmentNames[own];
    if (name != null) return name;
  }
  return 'Unassigned';
}

/// Bucket a year's raw data into 12 months. Index 0 is January.
///
/// Attendance is NOT recomputed here — it is delegated to
/// `buildAttendanceRows` + `AttendanceStats.from`, the same engine the
/// payslip PDF and the employee Attendance tab use. That is the whole point:
/// a figure on this dashboard must equal the figure on the payslip.
List<MonthMetrics> computeMonthMetrics(DashboardYearInput input) {
  final year = input.year;
  final yearStart = DateTime(year, 1, 1);
  final yearEnd = DateTime(year, 12, 31);
  final today = DateTime(input.today.year, input.today.month, input.today.day);

  // Per-month accumulators.
  final workDays = List<int>.filled(12, 0);
  final present = List<int>.filled(12, 0);
  final absent = List<int>.filled(12, 0);
  final rest = List<int>.filled(12, 0);
  final regHol = List<int>.filled(12, 0);
  final specHol = List<int>.filled(12, 0);
  final lateMin = List<double>.filled(12, 0);
  final otMin = List<double>.filled(12, 0);
  final leave = List<double>.filled(12, 0);
  final leaveByType = List.generate(12, (_) => <String, double>{});
  final hires = List<int>.filled(12, 0);
  final seps = List<int>.filled(12, 0);
  final vol = List<int>.filled(12, 0);
  final invol = List<int>.filled(12, 0);
  final gross = List<Decimal>.filled(12, Decimal.zero);
  final sss = List<Decimal>.filled(12, Decimal.zero);
  final ph = List<Decimal>.filled(12, Decimal.zero);
  final pg = List<Decimal>.filled(12, Decimal.zero);
  final wh = List<Decimal>.filled(12, Decimal.zero);
  final payEmp = List.generate(12, (_) => <String>{});
  final applicants = List<int>.filled(12, 0);

  // ---- Attendance, per employee, over their employment window ----
  final byEmployee = <String, List<AttendanceDay>>{};
  for (final r in input.attendance) {
    (byEmployee[r.employeeId] ??= []).add(r);
  }

  for (final e in input.employees) {
    final sc = e.roleScorecardId == null
        ? null
        : input.scorecardsById[e.roleScorecardId!];
    final workDaysPerWeek = sc?.workDaysPerWeek;
    final defaultShift = sc?.shiftTemplateId == null
        ? null
        : input.shiftsById[sc!.shiftTemplateId!];

    // Clip the window to employment. Without this, a July hire would accrue
    // six months of scheduled-but-absent days.
    final hire = DateTime(e.hireDate.year, e.hireDate.month, e.hireDate.day);
    var start = hire.isAfter(yearStart) ? hire : yearStart;
    var end = yearEnd;
    final sep = e.separationDate;
    if (sep != null) {
      final s = DateTime(sep.year, sep.month, sep.day);
      if (s.isBefore(end)) end = s;
    }
    if (today.isBefore(end)) end = today;
    if (end.isBefore(start)) continue;

    final rows = buildAttendanceRows(
      start: start,
      end: end,
      records: byEmployee[e.id] ?? const [],
      shifts: input.shiftsById,
      holidays: input.holidaysByDate,
      defaultShift: defaultShift,
      workDaysPerWeek: workDaysPerWeek,
    );

    // Group this employee's rows by month, then hand each month's rows to
    // AttendanceStats so its work-day / holiday / rest-day rules apply.
    final rowsByMonth = List.generate(12, (_) => <AttendanceRowVm>[]);
    for (final row in rows) {
      rowsByMonth[row.date.month - 1].add(row);
    }
    for (var m = 0; m < 12; m++) {
      if (rowsByMonth[m].isEmpty) continue;
      final st = AttendanceStats.from(
        rowsByMonth[m],
        workDaysPerWeek: workDaysPerWeek,
      );
      workDays[m] += st.workDays;
      present[m] += st.present;
      absent[m] += st.absent;
      rest[m] += st.restDays;
      regHol[m] += st.regularHoliday;
      specHol[m] += st.specialHoliday;
      lateMin[m] += st.lateUndertimeMinutes;
      otMin[m] += st.otMinutes;
    }
  }

  // ---- Leave (already expanded to per-date allocations) ----
  for (final a in input.leaveDays) {
    if (a.date.year != year) continue;
    final m = a.date.month - 1;
    leave[m] += a.days;
    leaveByType[m][a.leaveType] = (leaveByType[m][a.leaveType] ?? 0) + a.days;
  }

  // ---- Movement, from employees (NOT employment_events) ----
  for (final e in input.employees) {
    if (e.hireDate.year == year) hires[e.hireDate.month - 1]++;
    final sep = e.separationDate;
    final status = e.employmentStatus.toUpperCase();
    if (sep != null && sep.year == year && status != 'ACTIVE') {
      final m = sep.month - 1;
      seps[m]++;
      if (_kVoluntary.contains(status)) {
        vol[m]++;
      } else if (_kInvoluntary.contains(status)) {
        invol[m]++;
      }
    }
  }

  // ---- Payroll ----
  for (final p in input.payslips) {
    if (p.payDate.year != year) continue;
    final m = p.payDate.month - 1;
    gross[m] += p.grossPay;
    sss[m] += p.sssEe;
    ph[m] += p.philhealthEe;
    pg[m] += p.pagibigEe;
    wh[m] += p.withholdingTax;
    payEmp[m].add(p.employeeId);
  }

  // ---- Applicants ----
  for (final a in input.applicants) {
    if (a.appliedAt.year == year) applicants[a.appliedAt.month - 1]++;
  }

  return [
    for (var m = 0; m < 12; m++)
      MonthMetrics(
        year: year,
        month: m + 1,
        workDays: workDays[m],
        presentDays: present[m],
        absentDays: absent[m],
        restDays: rest[m],
        regularHolidays: regHol[m],
        specialHolidays: specHol[m],
        lateUndertimeMinutes: lateMin[m],
        overtimeMinutes: otMin[m],
        leaveDays: leave[m],
        leaveDaysByType: Map.unmodifiable(leaveByType[m]),
        newHires: hires[m],
        separations: seps[m],
        voluntarySeparations: vol[m],
        involuntarySeparations: invol[m],
        payrollGross: gross[m],
        sssTotal: sss[m],
        philhealthTotal: ph[m],
        pagibigTotal: pg[m],
        withholdingTaxTotal: wh[m],
        payrollEmployeeIds: Set.unmodifiable(payEmp[m]),
        newApplicants: applicants[m],
      ),
  ];
}

/// Roll 12 months into the year total. Everything additive sums; payroll
/// employees UNION (one person paid in twelve months is one person).
MonthMetrics aggregateMonths(List<MonthMetrics> months, int year) {
  final leaveByType = <String, double>{};
  final payEmp = <String>{};
  var workDays = 0,
      present = 0,
      absent = 0,
      rest = 0,
      regHol = 0,
      specHol = 0,
      hires = 0,
      seps = 0,
      vol = 0,
      invol = 0,
      applicants = 0;
  var lateMin = 0.0, otMin = 0.0, leave = 0.0;
  var gross = Decimal.zero,
      sss = Decimal.zero,
      ph = Decimal.zero,
      pg = Decimal.zero,
      wh = Decimal.zero;

  for (final m in months) {
    workDays += m.workDays;
    present += m.presentDays;
    absent += m.absentDays;
    rest += m.restDays;
    regHol += m.regularHolidays;
    specHol += m.specialHolidays;
    lateMin += m.lateUndertimeMinutes;
    otMin += m.overtimeMinutes;
    leave += m.leaveDays;
    m.leaveDaysByType.forEach((k, v) {
      leaveByType[k] = (leaveByType[k] ?? 0) + v;
    });
    hires += m.newHires;
    seps += m.separations;
    vol += m.voluntarySeparations;
    invol += m.involuntarySeparations;
    gross += m.payrollGross;
    sss += m.sssTotal;
    ph += m.philhealthTotal;
    pg += m.pagibigTotal;
    wh += m.withholdingTaxTotal;
    payEmp.addAll(m.payrollEmployeeIds);
    applicants += m.newApplicants;
  }

  return MonthMetrics(
    year: year,
    month: null,
    workDays: workDays,
    presentDays: present,
    absentDays: absent,
    restDays: rest,
    regularHolidays: regHol,
    specialHolidays: specHol,
    lateUndertimeMinutes: lateMin,
    overtimeMinutes: otMin,
    leaveDays: leave,
    leaveDaysByType: Map.unmodifiable(leaveByType),
    newHires: hires,
    separations: seps,
    voluntarySeparations: vol,
    involuntarySeparations: invol,
    payrollGross: gross,
    sssTotal: sss,
    philhealthTotal: ph,
    pagibigTotal: pg,
    withholdingTaxTotal: wh,
    payrollEmployeeIds: Set.unmodifiable(payEmp),
    newApplicants: applicants,
  );
}

/// Point-in-time distributions as of [asOf].
SnapshotMetrics computeSnapshot(DashboardYearInput input, DateTime asOf) {
  final dept = <String, int>{};
  final type = <String, int>{};
  final entity = <String, int>{};
  final tenure = <String, int>{
    '< 1 year': 0,
    '1-2 years': 0,
    '2-5 years': 0,
    '5+ years': 0,
  };
  final tenures = <double>[];
  var active = 0;

  for (final e in input.employees) {
    if (!isActiveAsOf(e, asOf)) continue;
    active++;

    final months = _tenureMonths(e.hireDate, asOf);
    tenures.add(months);
    final bucket = _tenureBucket(months);
    tenure[bucket] = (tenure[bucket] ?? 0) + 1;

    final deptName = _departmentNameFor(e, input);
    dept[deptName] = (dept[deptName] ?? 0) + 1;

    final t = e.employmentType.isEmpty ? 'UNKNOWN' : e.employmentType;
    type[t] = (type[t] ?? 0) + 1;

    final entId = e.hiringEntityId;
    final entName =
        (entId == null ? null : input.hiringEntityNames[entId]) ?? 'Unassigned';
    entity[entName] = (entity[entName] ?? 0) + 1;
  }

  final avgTenure = tenures.isEmpty
      ? 0.0
      : tenures.reduce((a, b) => a + b) / tenures.length;

  return SnapshotMetrics(
    asOf: asOf,
    activeEmployees: active,
    // "Total" = every non-archived employee row, separated or not.
    totalEmployees:
        input.employees.where((e) => e.deletedAt == null).length,
    avgTenureMonths: avgTenure,
    headcountByDepartment: Map.unmodifiable(dept),
    employmentTypeCounts: Map.unmodifiable(type),
    hiringEntityCounts: Map.unmodifiable(entity),
    tenureBuckets: Map.unmodifiable(tenure),
  );
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/dashboard/dashboard_metrics_test.dart`
Expected: PASS — all groups green.

If a test fails on an attendance figure, **do not adjust the expected value to match the code.** The expectations encode the payroll engine's contract (a 30-minute late clock-in is 30 late minutes; OT absorbs late). A mismatch means the wiring into `buildAttendanceRows` is wrong — most likely the shift is not resolving, so check that `defaultShift` and the record's `shiftTemplateId` both point at `sh1`.

- [ ] **Step 5: Run the analyzer**

Run: `flutter analyze`
Expected: no new issues.

- [ ] **Step 6: Commit**

```bash
git add lib/features/dashboard/dashboard_metrics.dart test/features/dashboard/dashboard_metrics_test.dart
git commit -m "feat(dashboard): pure metrics module bucketing a year into 12 months

Attendance/late/OT delegate to AttendanceRowVm + AttendanceStats so the
dashboard ties out to payslips. Movement reads employees.hire_date /
separation_date instead of employment_events (whose enum values the old
code never matched). Snapshots are as-of, not always-today."
```

---

### Task 6: Rewrite the data provider

Replace the hand-rolled aggregation in `dashboard_providers.dart` with a year-wide fetch that feeds Task 5. This is where `dashboardYearProvider` dies.

**Files:**
- Rewrite: `lib/features/dashboard/dashboard_providers.dart` (entire file — the old `DashboardData` class and `dashboardDataProvider` are replaced)

**Interfaces:**
- Consumes: `DashboardPeriod` / `dashboardPeriodProvider` (Task 3); `expandLeaveRequest` (Task 4); `DashboardYearInput`, `DashboardPayslip`, `MonthMetrics`, `SnapshotMetrics`, `computeMonthMetrics`, `aggregateMonths`, `computeSnapshot` (Task 5); `fetchAllPages` (Task 1).
- Produces:
  - `class DashboardYearData { final int year; final List<MonthMetrics> months; final MonthMetrics yearTotal; final DashboardYearInput input; final int openApplicants; final DateTime generatedAt; }`
  - `final dashboardYearDataProvider = FutureProvider<DashboardYearData>(...)` — fetches; **keyed on the year only.**
  - `class DashboardView { final DashboardPeriod period; final MonthMetrics metrics; final SnapshotMetrics snapshot; final List<MonthMetrics> months; final MonthMetrics yearTotal; final int openApplicants; final DateTime generatedAt; }`
  - `final dashboardViewProvider = Provider<AsyncValue<DashboardView>>(...)` — pure re-slice; changing month does NOT refetch.
- Removed: `dashboardYearProvider`, `DashboardData`, `_safePayslipsForPeriod`, `_isoDate`, `_tenureMonths`, `_tenureBucket`.

- [ ] **Step 1: Replace the file wholesale**

Write `lib/features/dashboard/dashboard_providers.dart`:

```dart
import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/models/applicant.dart';
import '../../data/models/attendance_day.dart';
import '../../data/models/calendar_event.dart';
import '../../data/models/department.dart';
import '../../data/models/employee.dart';
import '../../data/models/hiring_entity.dart';
import '../../data/models/role_scorecard.dart';
import '../../data/models/shift_template.dart';
import '../../data/pagination.dart';
import '../../data/repositories/attendance_repository.dart';
import '../../data/repositories/department_repository.dart';
import '../../data/repositories/hiring_entity_repository.dart';
import '../../data/repositories/holiday_repository.dart';
import '../../data/repositories/role_scorecard_repository.dart';
import '../../data/repositories/shift_template_repository.dart';
import '../auth/profile_provider.dart';
import 'dashboard_metrics.dart';
import 'dashboard_period.dart';
import 'leave_expansion.dart';

/// Everything the dashboard derived for one calendar year. Fetched once per
/// year; the selected month is a pure slice of this (see
/// [dashboardViewProvider]) so month-switching never hits the network.
class DashboardYearData {
  final int year;
  final List<MonthMetrics> months; // 12, January first
  final MonthMetrics yearTotal;
  final DashboardYearInput input;
  final int openApplicants;
  final DateTime generatedAt;

  const DashboardYearData({
    required this.year,
    required this.months,
    required this.yearTotal,
    required this.input,
    required this.openApplicants,
    required this.generatedAt,
  });
}

const _kClosedApplicantStatuses = {
  'HIRED',
  'REJECTED',
  'WITHDRAWN',
  'OFFER_DECLINED',
};

/// Fetch + derive one calendar year.
///
/// Keyed on the YEAR only — `.select((p) => p.year)` — so changing the month
/// re-slices without refetching. Watching the whole period here would refetch
/// the entire year on every month click.
final dashboardYearDataProvider = FutureProvider<DashboardYearData>((ref) async {
  // Subscribe to every reactive dependency BEFORE the first await. Riverpod
  // only registers `ref.watch` calls that run synchronously on the first
  // pass; a watch after an await never subscribes, and the provider silently
  // stops invalidating. (This exact bug shipped once already, with the year
  // dropdown not refiltering.)
  final year = ref.watch(dashboardPeriodProvider.select((p) => p.year));
  final attendanceRepo = ref.watch(attendanceRepositoryProvider);
  final shiftRepo = ref.watch(shiftTemplateRepositoryProvider);
  final scorecardRepo = ref.watch(roleScorecardRepositoryProvider);
  final deptRepo = ref.watch(departmentRepositoryProvider);
  final entityRepo = ref.watch(hiringEntityRepositoryProvider);
  final holidayRepo = ref.watch(holidayRepositoryProvider);

  final profile = await ref.watch(userProfileProvider.future);
  final companyId = profile?.companyId;
  if (companyId == null || companyId.isEmpty) {
    throw StateError('No company on profile');
  }

  final client = Supabase.instance.client;
  final yearStart = DateTime(year, 1, 1);
  final yearEnd = DateTime(year, 12, 31);
  final startIso = _iso(yearStart);
  final endIso = _iso(yearEnd);

  final results = await Future.wait<dynamic>([
    // 0: employees — INCLUDING soft-deleted. Separation can stamp
    //    deleted_at, so filtering here would hide the separations we report.
    _fetchEmployees(client, companyId),
    // 1: attendance for the whole year (paginated inside the repository).
    attendanceRepo.listByRange(
        start: yearStart, end: yearEnd, companyId: companyId),
    // 2: shifts
    shiftRepo.list(),
    // 3: scorecards — onlyActive:false, or a separated employee's superseded
    //    scorecard won't resolve and their shift/work-days go missing.
    scorecardRepo.list(onlyActive: false),
    // 4: departments
    deptRepo.list(companyId),
    // 5: hiring entities
    entityRepo.list(companyId),
    // 6: approved leave requests overlapping the year
    _fetchLeave(client, companyId, startIso, endIso),
    // 7: payslips of RELEASED runs paid within the year
    _fetchPayslips(client, companyId, startIso, endIso),
    // 8: applicants
    _fetchApplicants(client, companyId),
    // 9: holidays for the year
    _fetchHolidays(holidayRepo, companyId, year),
  ]);

  final employees = results[0] as List<Employee>;
  final attendance = results[1] as List<AttendanceDay>;
  final shifts = results[2] as List<ShiftTemplate>;
  final scorecards = results[3] as List<RoleScorecard>;
  final departments = results[4] as List<Department>;
  final entities = results[5] as List<HiringEntity>;
  final leaveDays = results[6] as List<LeaveDayAllocation>;
  final payslips = results[7] as List<DashboardPayslip>;
  final applicants = results[8] as List<Applicant>;
  final holidays = results[9] as List<CalendarEvent>;

  final input = DashboardYearInput(
    year: year,
    employees: employees,
    scorecardsById: {for (final s in scorecards) s.id: s},
    shiftsById: {for (final s in shifts) s.id: s},
    departmentNames: {for (final d in departments) d.id: d.name},
    hiringEntityNames: {for (final e in entities) e.id: e.name},
    holidaysByDate: {for (final h in holidays) _iso(h.date): h},
    attendance: attendance,
    leaveDays: leaveDays,
    payslips: payslips,
    applicants: applicants,
    today: DateTime.now(),
  );

  final months = computeMonthMetrics(input);
  final openApplicants = applicants
      .where((a) =>
          !_kClosedApplicantStatuses.contains(a.status.toUpperCase()))
      .length;

  return DashboardYearData(
    year: year,
    months: months,
    yearTotal: aggregateMonths(months, year),
    input: input,
    openApplicants: openApplicants,
    generatedAt: DateTime.now(),
  );
});

/// What the screen renders. A pure re-slice of [dashboardYearDataProvider] —
/// clicking a month in the explorer costs nothing.
class DashboardView {
  final DashboardPeriod period;
  final MonthMetrics metrics; // selected month, or the year total
  final SnapshotMetrics snapshot;
  final List<MonthMetrics> months; // for the explorer
  final MonthMetrics yearTotal;
  final int openApplicants;
  final DateTime generatedAt;

  const DashboardView({
    required this.period,
    required this.metrics,
    required this.snapshot,
    required this.months,
    required this.yearTotal,
    required this.openApplicants,
    required this.generatedAt,
  });
}

final dashboardViewProvider = Provider<AsyncValue<DashboardView>>((ref) {
  final period = ref.watch(dashboardPeriodProvider);
  final async = ref.watch(dashboardYearDataProvider);
  return async.whenData((d) {
    final metrics =
        period.isYear ? d.yearTotal : d.months[period.month - 1];
    final asOf = period.endOn(DateTime.now());
    return DashboardView(
      period: period,
      metrics: metrics,
      snapshot: computeSnapshot(d.input, asOf),
      months: d.months,
      yearTotal: d.yearTotal,
      openApplicants: d.openApplicants,
      generatedAt: d.generatedAt,
    );
  });
});

// ---------------------------------------------------------------------------
// Fetch helpers
// ---------------------------------------------------------------------------

String _iso(DateTime d) => d.toIso8601String().substring(0, 10);

Decimal _dec(Object? v) => Decimal.parse((v ?? '0').toString());

Future<List<Employee>> _fetchEmployees(
    SupabaseClient client, String companyId) async {
  final rows = await fetchAllPages<Map<String, dynamic>>((from, to) async {
    final page = await client
        .from('employees')
        .select()
        .eq('company_id', companyId)
        .order('id')
        .range(from, to);
    return (page as List<dynamic>).cast<Map<String, dynamic>>();
  });
  final out = <Employee>[];
  for (final r in rows) {
    try {
      out.add(Employee.fromRow(r));
    } catch (_) {
      // A single unparseable row must not blank the whole dashboard.
    }
  }
  return out;
}

/// Approved leave overlapping the year, expanded to per-date allocations.
/// Overlap (not containment) so a request straddling Dec→Jan still lands.
Future<List<LeaveDayAllocation>> _fetchLeave(
  SupabaseClient client,
  String companyId,
  String startIso,
  String endIso,
) async {
  try {
    final rows = await fetchAllPages<Map<String, dynamic>>((from, to) async {
      final page = await client
          .from('leave_requests')
          .select(
              'employee_id, start_date, end_date, leave_days, start_half, '
              'end_half, status, leave_types(name, code), '
              'employees!inner(company_id)')
          .eq('employees.company_id', companyId)
          .eq('status', 'APPROVED')
          .lte('start_date', endIso)
          .gte('end_date', startIso)
          .order('id')
          .range(from, to);
      return (page as List<dynamic>).cast<Map<String, dynamic>>();
    });

    final out = <LeaveDayAllocation>[];
    for (final r in rows) {
      final t = r['leave_types'] as Map?;
      final typeName =
          (t?['name'] ?? t?['code'] ?? 'Leave').toString();
      out.addAll(expandLeaveRequest(
        employeeId: r['employee_id'] as String,
        startDate: DateTime.parse(r['start_date'] as String),
        endDate: DateTime.parse(r['end_date'] as String),
        leaveDays:
            double.tryParse((r['leave_days'] ?? '0').toString()) ?? 0,
        startHalf: r['start_half'] as String?,
        endHalf: r['end_half'] as String?,
        leaveType: typeName,
      ));
    }
    return out;
  } catch (_) {
    // Degrade to zero leave rather than blanking the page.
    return const [];
  }
}

Future<List<DashboardPayslip>> _fetchPayslips(
  SupabaseClient client,
  String companyId,
  String startIso,
  String endIso,
) async {
  try {
    final rows = await fetchAllPages<Map<String, dynamic>>((from, to) async {
      final page = await client
          .from('payslips')
          .select('employee_id, gross_pay, sss_ee, philhealth_ee, '
              'pagibig_ee, withholding_tax, '
              'payroll_runs!inner(company_id, status, pay_date)')
          .eq('payroll_runs.company_id', companyId)
          .eq('payroll_runs.status', 'RELEASED')
          .gte('payroll_runs.pay_date', startIso)
          .lte('payroll_runs.pay_date', endIso)
          .order('id')
          .range(from, to);
      return (page as List<dynamic>).cast<Map<String, dynamic>>();
    });
    return [
      for (final r in rows)
        DashboardPayslip(
          employeeId: r['employee_id'] as String,
          payDate: DateTime.parse(
              (r['payroll_runs'] as Map)['pay_date'] as String),
          grossPay: _dec(r['gross_pay']),
          sssEe: _dec(r['sss_ee']),
          philhealthEe: _dec(r['philhealth_ee']),
          pagibigEe: _dec(r['pagibig_ee']),
          withholdingTax: _dec(r['withholding_tax']),
        ),
    ];
  } catch (_) {
    // Older schemas may lack payroll_runs.pay_date. Zeroed payroll KPIs beat
    // a dead dashboard.
    return const [];
  }
}

Future<List<Applicant>> _fetchApplicants(
    SupabaseClient client, String companyId) async {
  try {
    final rows = await fetchAllPages<Map<String, dynamic>>((from, to) async {
      final page = await client
          .from('applicants')
          .select()
          .eq('company_id', companyId)
          .isFilter('deleted_at', null)
          .order('id')
          .range(from, to);
      return (page as List<dynamic>).cast<Map<String, dynamic>>();
    });
    final out = <Applicant>[];
    for (final r in rows) {
      try {
        out.add(Applicant.fromRow(r));
      } catch (_) {}
    }
    return out;
  } catch (_) {
    return const [];
  }
}

Future<List<CalendarEvent>> _fetchHolidays(
  HolidayRepository repo,
  String companyId,
  int year,
) async {
  try {
    final cal = await repo.byYear(companyId, year);
    if (cal == null) return const [];
    return await repo.events(cal.id);
  } catch (_) {
    return const [];
  }
}
```

- [ ] **Step 2: Reconcile against the real model APIs**

The exact constructor / factory names above are taken from the repo, but verify each compiles:

Run: `flutter analyze lib/features/dashboard/dashboard_providers.dart`

Fix any mismatch by reading the model, **not** by loosening a type:
- `Applicant.fromRow` and its `status` / `appliedAt` fields → `lib/data/models/applicant.dart`
- `HolidayRepository.byYear(companyId, year)` / `.events(calendarId)` → `lib/data/repositories/holiday_repository.dart`
- `departmentRepositoryProvider` / `hiringEntityRepositoryProvider` `.list(companyId)` → the two repository files

Expected once reconciled: the file analyzes clean. `dashboard_screen.dart` will still be red — it references the deleted `dashboardYearProvider` / `DashboardData`. Task 7 fixes that.

- [ ] **Step 3: Commit**

```bash
git add lib/features/dashboard/dashboard_providers.dart
git commit -m "feat(dashboard): fetch a year once, slice by period

Year-keyed FutureProvider + a pure Provider that re-slices per month, so
switching months costs no network. Employees are fetched INCLUDING
soft-deleted rows (separation stamps deleted_at, which is why the old
movement tiles could never see a separation). employment_events is no
longer read."
```

---

### Task 7: Screen — header, KPI row, snapshot stamps

**Files:**
- Modify: `lib/features/dashboard/dashboard_screen.dart` (header + `_DashboardBody` + KPI row + section titles)

**Interfaces:**
- Consumes: `dashboardViewProvider`, `DashboardView` (Task 6); `dashboardPeriodProvider`, `DashboardPeriod`, `DashboardPeriodMode` (Task 3).
- Preserved unchanged: `_ResponsiveRow`, `_SectionCard`, `_KpiCard`, `_DeptBars`, `_DeptBarRow`, `_BarTrack`, `_DonutWithLegend`, `_TenureBars`, `_StatTile`. Do not rewrite these.
- Removed: `_MovementBlock`, `_MovementTile` (movement now lives only in the explorer), `_RingGauge` (replaced in Task 8).

- [ ] **Step 1: Swap the watched provider and rebuild the header**

Add the period import alongside the existing ones at the top of `dashboard_screen.dart` (the file already imports `dashboard_providers.dart`, `intl`, `flutter_riverpod`, and `../../app/tokens.dart`):

```dart
import 'dashboard_period.dart';
```

In `DashboardScreen.build`, replace `ref.watch(dashboardDataProvider)` with `ref.watch(dashboardViewProvider)`, and the `RefreshIndicator`'s `onRefresh` with `ref.invalidate(dashboardYearDataProvider)`. Change `_DashboardBody`'s field from `DashboardData data` to `DashboardView view`.

Replace the header block inside `_DashboardBody.build` with:

```dart
    final period = ref.watch(dashboardPeriodProvider);
    final thisYear = DateTime.now().year;
    final yearOptions = [for (var y = thisYear; y >= thisYear - 4; y--) y];
    final updatedLabel =
        DateFormat('MMM d, yyyy, h:mm a').format(view.generatedAt);
    final mobile = isMobile(context);

    final headerTitle = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Dashboard',
            style: TextStyle(
                fontSize: mobile ? 22 : 28, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('HR Analytics · ${period.label}',
            style: const TextStyle(color: Colors.grey)),
      ],
    );

    final headerMeta = Column(
      crossAxisAlignment:
          mobile ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<DashboardPeriodMode>(
              segments: const [
                ButtonSegment(
                    value: DashboardPeriodMode.month, label: Text('Month')),
                ButtonSegment(
                    value: DashboardPeriodMode.year, label: Text('Year')),
              ],
              selected: {period.mode},
              showSelectedIcon: false,
              onSelectionChanged: (s) {
                ref.read(dashboardPeriodProvider.notifier).state =
                    period.copyWith(mode: s.first);
              },
            ),
            const SizedBox(width: LuxiumSpacing.md),
            if (!period.isYear) ...[
              DropdownButton<int>(
                value: period.month,
                isDense: true,
                underline: const SizedBox.shrink(),
                items: [
                  for (var m = 1; m <= 12; m++)
                    DropdownMenuItem(
                      value: m,
                      child: Text(
                          DateFormat('MMMM').format(DateTime(2000, m, 1))),
                    ),
                ],
                onChanged: (m) {
                  if (m == null) return;
                  ref.read(dashboardPeriodProvider.notifier).state =
                      period.copyWith(month: m);
                },
              ),
              const SizedBox(width: LuxiumSpacing.sm),
            ],
            DropdownButton<int>(
              value: yearOptions.contains(period.year)
                  ? period.year
                  : yearOptions.first,
              isDense: true,
              underline: const SizedBox.shrink(),
              items: [
                for (final y in yearOptions)
                  DropdownMenuItem(value: y, child: Text('$y')),
              ],
              onChanged: (y) {
                if (y == null) return;
                ref.read(dashboardPeriodProvider.notifier).state =
                    period.copyWith(year: y);
              },
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text('Last updated: $updatedLabel',
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
```

- [ ] **Step 2: Rebuild the KPI row**

`Avg Tenure` leaves the KPI row (it becomes the Tenure card's subtitle in Step 3). `Open Applicants` takes its slot. Late/UT, Leave Days and OT Hours are promoted — those are the numbers this work exists to make correct.

Replace the KPI `Builder` block with:

```dart
        Builder(builder: (context) {
          final p = LuxiumColors.of(context);
          final amber = Theme.of(context).brightness == Brightness.light
              ? const Color(0xFFF59E0B)
              : const Color(0xFFFBBF24);
          final tertiary = Theme.of(context).colorScheme.tertiary;
          final m = view.metrics;
          final asOfLabel =
              DateFormat('MMM d, yyyy').format(view.snapshot.asOf);
          return _ResponsiveRow(
            minColWidth: 220,
            children: [
              _KpiCard(
                icon: Icons.groups_outlined,
                iconBg: p.ctaTint,
                iconColor: p.cta,
                label: 'Active Employees',
                value: view.snapshot.activeEmployees.toString(),
                subtitle: 'as of $asOfLabel',
              ),
              _KpiCard(
                icon: Icons.access_time,
                iconBg: p.accentGreen.withValues(alpha: 0.14),
                iconColor: p.accentGreen,
                label: 'Attendance Rate',
                value: '${m.attendanceRatePct.toStringAsFixed(1)}%',
                subtitle:
                    '${m.presentDays} present · ${m.absentDays} absent',
              ),
              _KpiCard(
                icon: Icons.timer_outlined,
                iconBg: amber.withValues(alpha: 0.14),
                iconColor: amber,
                label: 'Late / UT',
                value: formatMinutes(m.lateUndertimeMinutes),
                subtitle:
                    '${m.avgLateMinutesPerWorkDay.toStringAsFixed(1)} min/work day',
              ),
              _KpiCard(
                icon: Icons.beach_access_outlined,
                iconBg: const Color(0xFF8B5CF6).withValues(alpha: 0.14),
                iconColor: const Color(0xFF8B5CF6),
                label: 'Leave Days',
                value: formatDays(m.leaveDays),
                subtitle: 'approved leave taken',
              ),
              _KpiCard(
                icon: Icons.trending_up,
                iconBg: tertiary.withValues(alpha: 0.14),
                iconColor: tertiary,
                label: 'OT Hours',
                value: '${m.overtimeHours.toStringAsFixed(1)} hrs',
                subtitle: 'net of late absorption',
              ),
              _KpiCard(
                icon: Icons.work_outline,
                iconBg: p.cta.withValues(alpha: 0.14),
                iconColor: p.cta,
                label: 'Open Applicants',
                value: view.openApplicants.toString(),
                subtitle: '${m.newApplicants} new this period',
              ),
            ],
          );
        }),
```

Add these two formatters at the bottom of `dashboard_screen.dart` (they are reused by the explorer in Task 8):

```dart
/// "6h 44m" / "44m" / "0m" — minutes are the natural unit for late/UT, but
/// a month's worth of them is unreadable without the hour rollup.
String formatMinutes(double minutes) {
  final total = minutes.round();
  if (total <= 0) return '0m';
  final h = total ~/ 60;
  final m = total % 60;
  if (h == 0) return '${m}m';
  return '${h}h ${m}m';
}

/// Leave days carry halves, so "7.5" — but drop the ".0" on whole days.
String formatDays(double days) {
  if (days == days.roundToDouble()) return days.toStringAsFixed(0);
  return days.toStringAsFixed(1);
}
```

- [ ] **Step 3: Stamp the snapshot cards and re-point the period cards**

The four distribution cards read from `view.snapshot`, and each title gains an "as of" stamp so it can never be misread as a period sum. `_SectionCard` gains an optional `subtitle`:

In `_SectionCard`, add `final String? subtitle;` to the fields and constructor, and render it under the title row:

```dart
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: TextStyle(fontSize: 11.5, color: p.subdued),
              ),
            ],
```

(place this immediately after the title `Row(...)`, before the existing `SizedBox(height: LuxiumSpacing.lg)`).

Then wire the cards:

```dart
        const SizedBox(height: 16),
        Builder(builder: (context) {
          final asOf =
              'as of ${DateFormat('MMM d, yyyy').format(view.snapshot.asOf)}';
          final s = view.snapshot;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ResponsiveRow(
                minColWidth: 360,
                children: [
                  _SectionCard(
                    title: 'Headcount by Department',
                    subtitle: asOf,
                    icon: Icons.bar_chart,
                    child: _DeptBars(counts: s.headcountByDepartment),
                  ),
                  _SectionCard(
                    title: 'Employment Type Distribution',
                    subtitle: asOf,
                    child: _DonutWithLegend(
                      counts: s.employmentTypeCounts,
                      centerLabel: 'Total',
                      palette: const [
                        Color(0xFF3B82F6),
                        Color(0xFF10B981),
                        Color(0xFFF59E0B),
                        Color(0xFFEF4444),
                        Color(0xFF8B5CF6),
                        Color(0xFF06B6D4),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _ResponsiveRow(
                minColWidth: 360,
                children: [
                  _SectionCard(
                    title: 'Employees by Hiring Entity',
                    subtitle: asOf,
                    child: _DonutWithLegend(
                      counts: s.hiringEntityCounts,
                      centerLabel: 'Total',
                      palette: const [
                        Color(0xFF7C3AED),
                        Color(0xFF14B8A6),
                        Color(0xFFEC4899),
                        Color(0xFFF59E0B),
                        Color(0xFF3B82F6),
                      ],
                    ),
                  ),
                  _SectionCard(
                    title: 'Tenure Distribution',
                    subtitle:
                        'Avg ${s.avgTenureMonths.toStringAsFixed(1)} months · $asOf',
                    child: _TenureBars(buckets: s.tenureBuckets),
                  ),
                ],
              ),
            ],
          );
        }),
```

Update the Attendance + Payroll row's titles to carry the period, and delete the `Employee Movement` `_SectionCard` entirely (its four tiles are superseded by the explorer's Hire/Sep columns):

```dart
        const SizedBox(height: 16),
        _ResponsiveRow(
          minColWidth: 420,
          children: [
            _SectionCard(
              title: 'Attendance Overview',
              subtitle: period.label,
              child: _AttendanceBlock(metrics: view.metrics),
            ),
            _SectionCard(
              title: 'Payroll Summary',
              subtitle: period.label,
              child: _PayrollBlock(metrics: view.metrics),
            ),
          ],
        ),
```

Delete the `_MovementBlock` and `_MovementTile` classes.

- [ ] **Step 4: Re-point `_PayrollBlock` at `MonthMetrics`**

Change its field to `final MonthMetrics metrics;`, and inside `build` read `metrics.payrollGross`, `metrics.avgGrossPerEmployee`, `metrics.sssTotal`, `metrics.philhealthTotal`, `metrics.pagibigTotal`, `metrics.withholdingTaxTotal`. Relabel the average:

```dart
        Text('Avg gross per employee: ${fmt(metrics.avgGrossPerEmployee)}',
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
```

Leave the four `_StatTile`s and their colours exactly as they are.

- [ ] **Step 5: Analyze**

Run: `flutter analyze`
Expected: only errors remaining should be inside `_AttendanceBlock` (still typed against the deleted `DashboardData`) — Task 8 replaces it. If `_AttendanceBlock` blocks the analyzer, temporarily change its field to `final MonthMetrics metrics;` and have it render `const SizedBox.shrink()`; Task 8 fills it in.

- [ ] **Step 6: Commit**

```bash
git add lib/features/dashboard/dashboard_screen.dart
git commit -m "feat(dashboard): month/year period control, reworked KPI row, as-of stamps

KPI row promotes Late/UT, Leave Days and OT Hours. Snapshot cards carry an
explicit 'as of' date so they cannot be misread as period sums. Employee
Movement tiles removed — superseded by the explorer's Hire/Sep columns."
```

---

### Task 8: Attendance Overview rework + Monthly Explorer

**Files:**
- Modify: `lib/features/dashboard/dashboard_screen.dart` (replace `_AttendanceBlock`; add `_MonthlyExplorer`)

**Interfaces:**
- Consumes: `MonthMetrics`, `DashboardView` (Tasks 5-6); `formatMinutes`, `formatDays` (Task 7); `ResponsiveTable` from `lib/widgets/responsive_table.dart`; `dashboardPeriodProvider` (Task 3).
- Removed: `_RingGauge`. Kept: `_MiniMetric`.

- [ ] **Step 1: Replace `_AttendanceBlock`**

The three rings go: "Leave Used" was `on-leave rows ÷ all rows`, which is not a metric anybody can act on, and "Attendance" vs "Present" rendered nearly the same ratio twice. A day-composition bar plus four tiles says strictly more in the same space.

```dart
class _AttendanceBlock extends StatelessWidget {
  final MonthMetrics metrics;
  const _AttendanceBlock({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final segments = <({String label, int value, Color color})>[
      (label: 'Present', value: m.presentDays, color: const Color(0xFF10B981)),
      (label: 'Absent', value: m.absentDays, color: const Color(0xFFEF4444)),
      (label: 'Leave', value: m.leaveDays.ceil(), color: const Color(0xFF8B5CF6)),
      (label: 'Rest', value: m.restDays, color: const Color(0xFF94A3B8)),
      (
        label: 'Holiday',
        value: m.regularHolidays + m.specialHolidays,
        color: const Color(0xFFF59E0B)
      ),
    ].where((s) => s.value > 0).toList();
    final total = segments.fold<int>(0, (s, e) => s + e.value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (total == 0)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text('No attendance in this period',
                  style: TextStyle(color: Colors.grey)),
            ),
          )
        else ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(LuxiumRadius.lg),
            child: SizedBox(
              height: 14,
              child: Row(
                children: [
                  for (final s in segments)
                    Expanded(
                      flex: s.value,
                      child: Tooltip(
                        message: '${s.label}: ${s.value} days',
                        child: ColoredBox(color: s.color),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: LuxiumSpacing.md),
          Wrap(
            spacing: LuxiumSpacing.lg,
            runSpacing: LuxiumSpacing.sm,
            children: [
              for (final s in segments)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          color: s.color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text('${s.label} ${s.value}',
                        style: const TextStyle(fontSize: 12)),
                  ],
                ),
            ],
          ),
        ],
        const SizedBox(height: LuxiumSpacing.lg),
        _ResponsiveRow(
          minColWidth: 130,
          spacing: 12,
          equalSize: false,
          children: [
            _MiniMetric(
                label: 'Late / UT',
                value: formatMinutes(m.lateUndertimeMinutes)),
            _MiniMetric(
                label: 'Avg late / work day',
                value:
                    '${m.avgLateMinutesPerWorkDay.toStringAsFixed(1)} min'),
            _MiniMetric(
                label: 'Overtime',
                value: '${m.overtimeHours.toStringAsFixed(1)} hrs'),
            _MiniMetric(
                label: 'Leave Days', value: formatDays(m.leaveDays)),
          ],
        ),
      ],
    );
  }
}
```

Delete the `_RingGauge` class.

- [ ] **Step 2: Add the Monthly Explorer**

Append to `dashboard_screen.dart`:

```dart
// ---------------------------------------------------------------------------
// Monthly Explorer — one row per month of the selected year, plus a year
// total. Doubles as the period selector: clicking a row re-slices the whole
// dashboard (no refetch — the year is already in memory).
//
// Only period-scoped metrics appear. Headcount / tenure / employment type are
// point-in-time snapshots that do not sum across months, so they are
// deliberately absent.
// ---------------------------------------------------------------------------
class _MonthlyExplorer extends ConsumerWidget {
  final DashboardView view;
  const _MonthlyExplorer({required this.view});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = LuxiumColors.of(context);
    final period = view.period;
    final currency =
        NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 0);
    final now = DateTime.now();

    Widget num_(String s, {bool strong = false, Color? color}) => Text(
          s,
          textAlign: TextAlign.right,
          style: TextStyle(
            fontFamily: 'GeistMono',
            fontSize: 12.5,
            fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
            color: color ?? p.foreground,
          ),
        );

    DataRow monthRow(MonthMetrics m) {
      final isFuture = m.year > now.year ||
          (m.year == now.year && m.month! > now.month);
      final selected = !period.isYear && period.month == m.month;
      final label = DateFormat('MMM').format(DateTime(m.year, m.month!, 1));
      final dim = isFuture ? p.subdued : null;

      return DataRow(
        selected: selected,
        onSelectChanged: isFuture
            ? null
            : (_) {
                ref.read(dashboardPeriodProvider.notifier).state =
                    period.copyWith(
                  mode: DashboardPeriodMode.month,
                  month: m.month,
                );
              },
        cells: [
          DataCell(Text(
            label,
            style: TextStyle(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: dim ?? p.foreground,
            ),
          )),
          DataCell(num_(isFuture ? '—' : '${m.workDays}', color: dim)),
          DataCell(num_(isFuture ? '—' : '${m.presentDays}', color: dim)),
          DataCell(num_(isFuture ? '—' : '${m.absentDays}', color: dim)),
          DataCell(num_(isFuture ? '—' : formatDays(m.leaveDays), color: dim)),
          DataCell(num_(
              isFuture ? '—' : formatMinutes(m.lateUndertimeMinutes),
              color: dim)),
          DataCell(num_(
              isFuture ? '—' : '${m.overtimeHours.toStringAsFixed(0)}h',
              color: dim)),
          DataCell(num_(isFuture ? '—' : '${m.newHires}', color: dim)),
          DataCell(num_(isFuture ? '—' : '${m.separations}', color: dim)),
          DataCell(num_(
              isFuture ? '—' : currency.format(m.payrollGross.toDouble()),
              color: dim)),
        ],
      );
    }

    final year = view.yearTotal;
    final yearSelected = period.isYear;
    final yearRow = DataRow(
      selected: yearSelected,
      onSelectChanged: (_) {
        ref.read(dashboardPeriodProvider.notifier).state =
            period.copyWith(mode: DashboardPeriodMode.year);
      },
      cells: [
        DataCell(Text('Year',
            style: TextStyle(
                fontWeight: FontWeight.w700, color: p.foreground))),
        DataCell(num_('${year.workDays}', strong: true)),
        DataCell(num_('${year.presentDays}', strong: true)),
        DataCell(num_('${year.absentDays}', strong: true)),
        DataCell(num_(formatDays(year.leaveDays), strong: true)),
        DataCell(
            num_(formatMinutes(year.lateUndertimeMinutes), strong: true)),
        DataCell(num_('${year.overtimeHours.toStringAsFixed(0)}h',
            strong: true)),
        DataCell(num_('${year.newHires}', strong: true)),
        DataCell(num_('${year.separations}', strong: true)),
        DataCell(num_(currency.format(year.payrollGross.toDouble()),
            strong: true)),
      ],
    );

    return ResponsiveTable(
      fullWidth: true,
      child: DataTable(
        columnSpacing: 20,
        headingRowHeight: 40,
        dataRowMinHeight: 40,
        dataRowMaxHeight: 44,
        showCheckboxColumn: false,
        columns: const [
          DataColumn(label: Text('Month')),
          DataColumn(label: Text('Work'), numeric: true),
          DataColumn(label: Text('Present'), numeric: true),
          DataColumn(label: Text('Absent'), numeric: true),
          DataColumn(label: Text('Leave'), numeric: true),
          DataColumn(label: Text('Late / UT'), numeric: true),
          DataColumn(label: Text('OT'), numeric: true),
          DataColumn(label: Text('Hires'), numeric: true),
          DataColumn(label: Text('Sep'), numeric: true),
          DataColumn(label: Text('Payroll'), numeric: true),
        ],
        rows: [
          for (final m in view.months) monthRow(m),
          yearRow,
        ],
      ),
    );
  }
}
```

Add the import at the top of the file:

```dart
import '../../widgets/responsive_table.dart';
```

- [ ] **Step 3: Mount the explorer where Employee Movement used to be**

In `_DashboardBody.build`, where the `Employee Movement` `_SectionCard` was:

```dart
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Monthly Explorer — ${view.period.year}',
          subtitle: 'Click a month to filter the dashboard',
          icon: Icons.table_chart_outlined,
          child: _MonthlyExplorer(view: view),
        ),
```

- [ ] **Step 4: Analyze**

Run: `flutter analyze`
Expected: **zero `error`-severity issues.** The feature's own files must contribute no new warnings/infos on top of the 189-issue baseline. This is the point at which the whole feature must compile — `dashboard_screen.dart` has no remaining references to the deleted `DashboardData` / `dashboardYearProvider`.

- [ ] **Step 5: Run the full test suite**

Run: `flutter test`
Expected: **655 pre-existing tests still pass** (0 failures), plus every test added in Tasks 1/3/4/5. A failure in `test/engine/` means the Task 2 pagination change altered payroll behaviour; stop and investigate rather than adjusting the expectation.

- [ ] **Step 6: Commit**

```bash
git add lib/features/dashboard/dashboard_screen.dart
git commit -m "feat(dashboard): day-composition attendance block + clickable Monthly Explorer

Rings replaced (the 'Leave Used' one measured on-leave rows over total rows,
which is not a real metric). Bottom section is now a month-by-month table of
period-scoped figures that doubles as the period selector."
```

---

### Task 9: Verify against real data

Static analysis and unit tests prove the math; they do not prove the dashboard is wired to the right columns. This task drives the real app.

**Files:** none (verification only)

- [ ] **Step 1: Launch the app**

Run: `flutter run -d linux --dart-define-from-file=env/prod.json`

(Note the file form — this project does NOT use individual `--dart-define=KEY=VAL` flags.)

- [ ] **Step 2: Confirm the default period**

Open the Dashboard. Expected: it lands on **Month mode, the current month**, and the subtitle reads `HR Analytics · July 2026`.

- [ ] **Step 3: Confirm the explorer filters**

Click a past month's row in the Monthly Explorer. Expected: every KPI, the Attendance Overview, and the Payroll Summary all change to that month; the "as of" stamps move to that month's last day; the clicked row highlights. **The change should be instant** — if there is a loading spinner, the year is being refetched, which means `dashboardYearDataProvider` is watching the whole period instead of `.select((p) => p.year)`.

Click the **Year** row. Expected: mode flips to Year, the month dropdown disappears, and the figures become the year totals.

- [ ] **Step 4: Tie out Late/UT and OT against a payslip — the whole point**

Pick a month with a RELEASED payroll run. Open that run's payslips and sum the `Late / UT` minutes and `OT` minutes across every payslip in it (page 2 of the payslip PDF shows both). Compare against the dashboard's `Late / UT` and `OT Hours` for the same month.

Expected: they match. Caveat when interpreting a mismatch — a payroll run's period (e.g. semi-monthly, 16th–31st) may not align to a calendar month, and the dashboard buckets by calendar month. Compare a month whose runs together cover exactly that calendar month, or compare against the sum of both semi-monthly runs for that month.

If they do not match, the bug is in the wiring, not the engine: check that `defaultShift` resolves (a null shift silently yields zero late minutes) and that `scorecardRepo.list(onlyActive: false)` is being used.

- [ ] **Step 5: Confirm the truncation is gone**

Pick a month where headcount × work days clearly exceeds 1000 attendance rows (roughly: more than ~38 staff on a 26-day month). Before this change the dashboard would have silently used only 1000 rows. Sanity-check that the month's `Work` count in the explorer is in the right ballpark (active staff × work days that month), not capped near 1000.

- [ ] **Step 6: Confirm movement is no longer zero**

Find a month in which someone was hired or separated (Employees list, or the employee's timeline). Expected: the explorer's `Hires` / `Sep` columns show them. Under the old code `Sep` was structurally always 0.

- [ ] **Step 7: Report findings**

Write up what tied out and what did not. **Do not claim the dashboard is accurate without the Step 4 comparison actually having been run** — that is the single check this entire plan exists to satisfy.

---

## Post-implementation note (raise with the user, do not act unilaterally)

The Task 2 pagination fix changes **what payroll sees** on any run whose attendance exceeded 1000 rows. Runs computed before the fix used a truncated slice. Recomputing such a run after this lands can legitimately produce different numbers than the payslips already RELEASED against it — correct, but it will look like a regression to anyone not expecting it.

Before merging, check whether any RELEASED run actually crossed that threshold:

```sql
select pr.id, pr.period_start, pr.period_end, pr.status, count(*) as attendance_rows
from payroll_runs pr
join employees e on e.company_id = pr.company_id
join attendance_day_records a
  on a.employee_id = e.id
 and a.attendance_date between pr.period_start and pr.period_end
where pr.status = 'RELEASED'
group by pr.id, pr.period_start, pr.period_end, pr.status
having count(*) > 1000
order by attendance_rows desc;
```

If that returns rows, those runs' released payslips were computed on partial attendance and need a decision (leave as-is for history vs. recompute + reissue). That is a business call, not a code change — surface it, do not resolve it in this plan.
