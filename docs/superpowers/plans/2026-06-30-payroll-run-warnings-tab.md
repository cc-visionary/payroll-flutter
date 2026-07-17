# Payroll Run Warnings Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a **Warnings** tab to the payroll run detail screen that live-scans the period's attendance for actionable anomalies (missing clock-out/in, invalid worked time, unapproved overtime) and deep-links each to that day's attendance.

**Architecture:** A pure, unit-tested `detectWarnings` function consumes `AttendanceDay` records + a shift-template lookup and returns ephemeral `RunWarning`s. A Riverpod `runWarningsProvider` wires the run's company/period through the existing attendance + shift-template repositories into that function. A new `PayrollWarningsTab` renders the list; the detail screen gains the tab + an amber count badge. No database changes, no stored state.

**Tech Stack:** Flutter (Material 3), Riverpod (`FutureProvider.family`), GoRouter, Supabase Postgrest. Tests via `flutter_test`.

## Global Constraints

- **No database changes, no migrations, no stored state.** Warnings are recomputed live each load.
- **No manual warnings, no acknowledge/resolve, no inline edit.** The only action is deep-linking to attendance.
- **Single CTA color is Luxium purple** `#635BFF`/`#7F7DFC`; status chips use tinted background + darker text, **no colored borders** (per `PRODUCT.md` / CLAUDE.md). Warning chips: amber `#FEF3C7`/`#92400E`, error red `#FEE2E2`/`#991B1B`.
- **Unapproved-OT threshold = 30 minutes**, held in a named constant `kUnapprovedOtThresholdMinutes`.
- **Skip today + future days** in the scan; **both-null clock = normal absence, not flagged**; **overnight shifts and shiftless records skip only the OT check** (checks 1–3 still apply).
- Attendance table is `attendance_day_records`; employee embed is `employees!inner(employee_number, first_name, last_name)` (what `AttendanceDay.fromRow` expects).
- Run tests with `flutter test <path>`; analyze with `flutter analyze`. App run command: `flutter run -d linux --dart-define-from-file=env/prod.json`.

---

### Task 1: Pure detection model + `detectWarnings`

**Files:**
- Create: `lib/features/payroll/runs/detail/warnings.dart`
- Test: `test/features/payroll/run_warnings_test.dart`

**Interfaces:**
- Consumes: `AttendanceDay` (`lib/data/models/attendance_day.dart`), `ShiftTemplate` (`lib/data/models/shift_template.dart`), and the pure top-level `applyTime(DateTime, String)` + `isoDate(DateTime)` from `lib/features/attendance/attendance_row_vm.dart`.
- Produces:
  - `enum WarningType { missingClockOut, missingClockIn, invalidWorkedTime, unapprovedOvertime }`
  - `class RunWarning { final String employeeId; final String employeeLabel; final DateTime date; final WarningType type; final String message; const RunWarning({required ...}); }`
  - `const int kUnapprovedOtThresholdMinutes = 30;`
  - `List<RunWarning> detectWarnings({ required List<AttendanceDay> records, required Map<String, ShiftTemplate> shiftsById, required DateTime today, int unapprovedOtThresholdMinutes = kUnapprovedOtThresholdMinutes })`

- [ ] **Step 1: Write the failing test**

Create `test/features/payroll/run_warnings_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/attendance_day.dart';
import 'package:payroll_flutter/data/models/shift_template.dart';
import 'package:payroll_flutter/features/payroll/runs/detail/warnings.dart';

// All clock times are LOCAL DateTimes so toLocal() is identity under any tz.
DateTime _at(int h, int m) => DateTime(2026, 6, 15, h, m);
const _today = DateTime(2026, 6, 30); // every record day below is in the past

AttendanceDay _day({
  DateTime? tIn,
  DateTime? tOut,
  String? shiftId,
  bool lateOutApproved = false,
  bool earlyInApproved = false,
  int? approvedOtMinutes,
  DateTime? date,
}) =>
    AttendanceDay(
      id: 'A1',
      employeeId: 'E1',
      attendanceDate: date ?? DateTime(2026, 6, 15),
      dayType: 'WORKDAY',
      actualTimeIn: tIn,
      actualTimeOut: tOut,
      attendanceStatus: 'PRESENT',
      sourceType: 'LARK',
      earlyInApproved: earlyInApproved,
      lateOutApproved: lateOutApproved,
      lateInApproved: false,
      earlyOutApproved: false,
      approvedOtMinutes: approvedOtMinutes,
      isLocked: false,
      shiftTemplateId: shiftId,
      employeeNumber: 'EMP-001',
      employeeFirstName: 'Jane',
      employeeLastName: 'Doe',
    );

ShiftTemplate _shift({bool overnight = false}) => ShiftTemplate(
      id: 'S1',
      companyId: 'C1',
      code: 'DAY',
      name: 'Day Shift',
      startTime: '09:00:00',
      endTime: '18:00:00',
      isOvernight: overnight,
      breakType: 'AUTO_DEDUCT',
      breakMinutes: 60,
      graceMinutesLate: 0,
      graceMinutesEarlyOut: 0,
      scheduledWorkMinutes: 480,
      isActive: true,
    );

List<RunWarning> _run(List<AttendanceDay> records,
        {Map<String, ShiftTemplate>? shifts}) =>
    detectWarnings(
      records: records,
      shiftsById: shifts ?? {'S1': _shift()},
      today: _today,
    );

void main() {
  test('missing clock-out is flagged', () {
    final w = _run([_day(tIn: _at(9, 2), tOut: null, shiftId: 'S1')]);
    expect(w, hasLength(1));
    expect(w.single.type, WarningType.missingClockOut);
  });

  test('missing clock-in is flagged', () {
    final w = _run([_day(tIn: null, tOut: _at(18, 0), shiftId: 'S1')]);
    expect(w.single.type, WarningType.missingClockIn);
  });

  test('clock-out not after clock-in is flagged as invalid', () {
    final w = _run([_day(tIn: _at(18, 0), tOut: _at(9, 0), shiftId: 'S1')]);
    expect(w.single.type, WarningType.invalidWorkedTime);
  });

  test('a clean day inside the shift produces no warning', () {
    final w = _run([_day(tIn: _at(9, 0), tOut: _at(18, 0), shiftId: 'S1')]);
    expect(w, isEmpty);
  });

  test('both clock times null (absence) produces no warning', () {
    final w = _run([_day(tIn: null, tOut: null, shiftId: 'S1')]);
    expect(w, isEmpty);
  });

  test('45 min unapproved late-out is flagged as unapproved overtime', () {
    final w = _run([_day(tIn: _at(9, 0), tOut: _at(18, 45), shiftId: 'S1')]);
    expect(w.single.type, WarningType.unapprovedOvertime);
  });

  test('Lark-approved OT suppresses the overtime warning', () {
    final w = _run([
      _day(tIn: _at(9, 0), tOut: _at(18, 45), shiftId: 'S1', approvedOtMinutes: 60)
    ]);
    expect(w, isEmpty);
  });

  test('late-out approval flag suppresses the overtime warning', () {
    final w = _run([
      _day(tIn: _at(9, 0), tOut: _at(18, 45), shiftId: 'S1', lateOutApproved: true)
    ]);
    expect(w, isEmpty);
  });

  test('late-out under the 30-min threshold is not flagged', () {
    final w = _run([_day(tIn: _at(9, 0), tOut: _at(18, 20), shiftId: 'S1')]);
    expect(w, isEmpty);
  });

  test('40 min unapproved early-in is flagged as unapproved overtime', () {
    final w = _run([_day(tIn: _at(8, 20), tOut: _at(18, 0), shiftId: 'S1')]);
    expect(w.single.type, WarningType.unapprovedOvertime);
  });

  test('overnight shift skips the OT check but still flags missing clock-out', () {
    final shifts = {'S1': _shift(overnight: true)};
    final ot = _run([_day(tIn: _at(9, 0), tOut: _at(23, 0), shiftId: 'S1')],
        shifts: shifts);
    expect(ot, isEmpty); // OT skipped for overnight
    final missing = _run([_day(tIn: _at(9, 0), tOut: null, shiftId: 'S1')],
        shifts: shifts);
    expect(missing.single.type, WarningType.missingClockOut);
  });

  test('today/future records are skipped', () {
    final w = _run([
      _day(tIn: _at(9, 0), tOut: null, shiftId: 'S1', date: _today)
    ]);
    expect(w, isEmpty);
  });

  test('record without a shift skips OT but still flags missing clock-out', () {
    final clean = _run([_day(tIn: _at(9, 0), tOut: _at(22, 0), shiftId: null)]);
    expect(clean, isEmpty); // no shift window → no OT warning, times valid
    final missing = _run([_day(tIn: _at(9, 0), tOut: null, shiftId: null)]);
    expect(missing.single.type, WarningType.missingClockOut);
  });

  test('warnings are sorted by date then employee', () {
    final w = _run([
      _day(tIn: _at(9, 0), tOut: null, shiftId: 'S1', date: DateTime(2026, 6, 17)),
      _day(tIn: _at(9, 0), tOut: null, shiftId: 'S1', date: DateTime(2026, 6, 15)),
    ]);
    expect(w.first.date, DateTime(2026, 6, 15));
    expect(w.last.date, DateTime(2026, 6, 17));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/payroll/run_warnings_test.dart`
Expected: FAIL — `warnings.dart` / `detectWarnings` do not exist (compile error).

- [ ] **Step 3: Write minimal implementation**

Create `lib/features/payroll/runs/detail/warnings.dart`:

```dart
import '../../../../data/models/attendance_day.dart';
import '../../../../data/models/shift_template.dart';
import '../../../attendance/attendance_row_vm.dart' show applyTime;

/// Category of attendance anomaly surfaced on the run Warnings tab.
enum WarningType {
  missingClockOut,
  missingClockIn,
  invalidWorkedTime,
  unapprovedOvertime,
}

/// One attendance anomaly for one employee on one day. Ephemeral — built
/// live from attendance each load, never stored.
class RunWarning {
  final String employeeId;
  final String employeeLabel;
  final DateTime date;
  final WarningType type;
  final String message;
  const RunWarning({
    required this.employeeId,
    required this.employeeLabel,
    required this.date,
    required this.type,
    required this.message,
  });
}

/// Minutes past which an unapproved clock overage is worth flagging. Tunable.
const int kUnapprovedOtThresholdMinutes = 30;

/// Pure anomaly scan. [records] is the period's attendance, [shiftsById] maps
/// `shift_template_id` → template, and [today] is injected so future-day
/// skipping is deterministic in tests. Returns warnings sorted by date then
/// employee label.
List<RunWarning> detectWarnings({
  required List<AttendanceDay> records,
  required Map<String, ShiftTemplate> shiftsById,
  required DateTime today,
  int unapprovedOtThresholdMinutes = kUnapprovedOtThresholdMinutes,
}) {
  final todayDay = DateTime(today.year, today.month, today.day);
  final out = <RunWarning>[];

  for (final r in records) {
    final recDay = DateTime(
        r.attendanceDate.year, r.attendanceDate.month, r.attendanceDate.day);
    // Skip today + future: an employee still mid-shift hasn't clocked out yet.
    if (!recDay.isBefore(todayDay)) continue;

    final tIn = r.actualTimeIn;
    final tOut = r.actualTimeOut;

    // 1 / 2: exactly one side of the clock present.
    if (tIn != null && tOut == null) {
      out.add(RunWarning(
        employeeId: r.employeeId,
        employeeLabel: r.employeeLabel,
        date: recDay,
        type: WarningType.missingClockOut,
        message: 'Clocked in at ${_fmtTime(tIn)} but never clocked out.',
      ));
      continue;
    }
    if (tOut != null && tIn == null) {
      out.add(RunWarning(
        employeeId: r.employeeId,
        employeeLabel: r.employeeLabel,
        date: recDay,
        type: WarningType.missingClockIn,
        message: 'Clocked out at ${_fmtTime(tOut)} but never clocked in.',
      ));
      continue;
    }
    // Both null = normal absence — not flagged.
    if (tIn == null || tOut == null) continue;

    final localIn = tIn.toLocal();
    final localOut = tOut.toLocal();

    // 3: out not after in (zero/negative span) — a data error.
    if (!localOut.isAfter(localIn)) {
      out.add(RunWarning(
        employeeId: r.employeeId,
        employeeLabel: r.employeeLabel,
        date: recDay,
        type: WarningType.invalidWorkedTime,
        message: 'Clock-out is not after clock-in — check the times.',
      ));
      continue;
    }

    // 4: unapproved overtime — needs a resolvable, non-overnight shift.
    final shift =
        r.shiftTemplateId == null ? null : shiftsById[r.shiftTemplateId];
    if (shift == null || shift.isOvernight) continue;
    if ((r.approvedOtMinutes ?? 0) > 0) continue; // Lark-approved OT covers it.

    final shiftStart = applyTime(recDay, shift.startTime);
    final shiftEnd = applyTime(recDay, shift.endTime);
    final lateOutMin = localOut.difference(shiftEnd).inMinutes;
    final earlyInMin = shiftStart.difference(localIn).inMinutes;
    final flagLateOut =
        !r.lateOutApproved && lateOutMin > unapprovedOtThresholdMinutes;
    final flagEarlyIn =
        !r.earlyInApproved && earlyInMin > unapprovedOtThresholdMinutes;
    if (!flagLateOut && !flagEarlyIn) continue;

    final parts = <String>[
      if (flagLateOut) '$lateOutMin min past shift end',
      if (flagEarlyIn) '$earlyInMin min before shift start',
    ];
    out.add(RunWarning(
      employeeId: r.employeeId,
      employeeLabel: r.employeeLabel,
      date: recDay,
      type: WarningType.unapprovedOvertime,
      message: 'Worked ${parts.join(' and ')} with no OT approval.',
    ));
  }

  out.sort((a, b) {
    final c = a.date.compareTo(b.date);
    return c != 0 ? c : a.employeeLabel.compareTo(b.employeeLabel);
  });
  return out;
}

String _fmtTime(DateTime dt) {
  final l = dt.toLocal();
  final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
  final m = l.minute.toString().padLeft(2, '0');
  final ap = l.hour < 12 ? 'AM' : 'PM';
  return '$h:$m $ap';
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/payroll/run_warnings_test.dart`
Expected: PASS (all 14 tests green).

- [ ] **Step 5: Commit**

```bash
git add lib/features/payroll/runs/detail/warnings.dart test/features/payroll/run_warnings_test.dart
git commit -m "feat(payroll): pure attendance-warning detection for run warnings tab"
```

---

### Task 2: Data layer — company-scoped attendance + `runWarningsProvider`

**Files:**
- Modify: `lib/data/repositories/attendance_repository.dart` (`listByRange`, ~line 74-99)
- Modify: `lib/features/payroll/runs/detail/providers.dart`

**Interfaces:**
- Consumes: `detectWarnings` + `RunWarning` (Task 1); existing `attendanceRepositoryProvider`, `shiftTemplateListProvider`, `payrollRunDetailProvider`.
- Produces: `final runWarningsProvider = FutureProvider.family<List<RunWarning>, String>` keyed by `runId`; and `AttendanceRepository.listByRange({..., String? companyId})`.

- [ ] **Step 1: Add the `companyId` filter to `listByRange`**

In `lib/data/repositories/attendance_repository.dart`, change the `listByRange` signature and query. Current:

```dart
  Future<List<AttendanceDay>> listByRange({
    required DateTime start,
    required DateTime end,
    String? employeeId,
  }) async {
    final startIso = start.toIso8601String().substring(0, 10);
    final endIso = end.toIso8601String().substring(0, 10);
    var q = _client
        .from('attendance_day_records')
        .select('*, employees!inner(employee_number, first_name, last_name)')
        .gte('attendance_date', startIso)
        .lte('attendance_date', endIso);
    if (employeeId != null) q = q.eq('employee_id', employeeId);
```

Replace with (adds `companyId` param + embed filter):

```dart
  Future<List<AttendanceDay>> listByRange({
    required DateTime start,
    required DateTime end,
    String? employeeId,
    String? companyId,
  }) async {
    final startIso = start.toIso8601String().substring(0, 10);
    final endIso = end.toIso8601String().substring(0, 10);
    var q = _client
        .from('attendance_day_records')
        .select('*, employees!inner(employee_number, first_name, last_name)')
        .gte('attendance_date', startIso)
        .lte('attendance_date', endIso);
    if (employeeId != null) q = q.eq('employee_id', employeeId);
    // Restrict to one company by filtering the inner-joined employee. `!inner`
    // makes this an effective WHERE on the embedded resource.
    if (companyId != null) q = q.eq('employees.company_id', companyId);
```

(Leave the rest of the method — `.order(...)`, the `fromRow` loop — unchanged.)

- [ ] **Step 2: Add `runWarningsProvider` to the run detail providers**

In `lib/features/payroll/runs/detail/providers.dart`, add these imports below the existing ones:

```dart
import '../../../../data/repositories/attendance_repository.dart';
import '../../../../data/repositories/shift_template_repository.dart';
import 'warnings.dart';
```

Append at the end of the file:

```dart
/// Live, ephemeral attendance-anomaly scan for a run. Reads the run's company +
/// period, loads that period's attendance and the shift templates, and runs the
/// pure [detectWarnings]. Re-runs whenever [payrollRunDetailProvider] changes
/// (recompute / realtime) or when invalidated by the tab's Refresh button.
final runWarningsProvider =
    FutureProvider.family<List<RunWarning>, String>((ref, runId) async {
  final detail = await ref.watch(payrollRunDetailProvider(runId).future);
  if (detail == null) return const <RunWarning>[];
  final run = detail.run;
  final records = await ref.watch(attendanceRepositoryProvider).listByRange(
        start: run.periodStart,
        end: run.periodEnd,
        companyId: run.companyId,
      );
  final shifts = await ref.watch(shiftTemplateListProvider.future);
  final shiftsById = {for (final s in shifts) s.id: s};
  return detectWarnings(
    records: records,
    shiftsById: shiftsById,
    today: DateTime.now(),
  );
});
```

- [ ] **Step 3: Verify it compiles cleanly**

Run: `flutter analyze lib/data/repositories/attendance_repository.dart lib/features/payroll/runs/detail/providers.dart`
Expected: "No issues found!" (provider correctness is exercised by the widget test in Task 3 and the manual run in Task 4).

- [ ] **Step 4: Run the existing repository/provider tests to confirm no regressions**

Run: `flutter test test/features/payroll/`
Expected: PASS (Task 1 tests + existing `compute_service_select_test` still green).

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/attendance_repository.dart lib/features/payroll/runs/detail/providers.dart
git commit -m "feat(payroll): company-scoped attendance loader + runWarningsProvider"
```

---

### Task 3: `PayrollWarningsTab` widget

**Files:**
- Create: `lib/features/payroll/runs/detail/tabs/warnings_tab.dart`
- Test: `test/features/payroll/warnings_tab_test.dart`

**Interfaces:**
- Consumes: `runWarningsProvider` (Task 2), `RunWarning` / `WarningType` (Task 1), `isoDate` from `attendance_row_vm.dart`.
- Produces: `class PayrollWarningsTab extends ConsumerWidget { final String runId; const PayrollWarningsTab({super.key, required this.runId}); }`

- [ ] **Step 1: Write the failing widget test**

Create `test/features/payroll/warnings_tab_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/payroll/runs/detail/providers.dart';
import 'package:payroll_flutter/features/payroll/runs/detail/tabs/warnings_tab.dart';
import 'package:payroll_flutter/features/payroll/runs/detail/warnings.dart';

Widget _host(List<RunWarning> warnings) => ProviderScope(
      overrides: [
        runWarningsProvider('R1').overrideWith((ref) async => warnings),
      ],
      child: const MaterialApp(
        home: Scaffold(body: PayrollWarningsTab(runId: 'R1')),
      ),
    );

void main() {
  testWidgets('empty state shows the all-clear message', (tester) async {
    await tester.pumpWidget(_host(const []));
    await tester.pumpAndSettle();
    expect(find.text('No attendance warnings for this period.'), findsOneWidget);
  });

  testWidgets('populated state renders a warning row', (tester) async {
    await tester.pumpWidget(_host([
      RunWarning(
        employeeId: 'E1',
        employeeLabel: 'EMP-001 · Jane Doe',
        date: DateTime(2026, 6, 15),
        type: WarningType.missingClockOut,
        message: 'Clocked in at 9:02 AM but never clocked out.',
      ),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('EMP-001 · Jane Doe'), findsOneWidget);
    expect(find.textContaining('never clocked out'), findsOneWidget);
    expect(find.text('1 warning'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/payroll/warnings_tab_test.dart`
Expected: FAIL — `warnings_tab.dart` / `PayrollWarningsTab` do not exist.

- [ ] **Step 3: Write the widget**

Create `lib/features/payroll/runs/detail/tabs/warnings_tab.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../attendance/attendance_row_vm.dart' show isoDate;
import '../providers.dart';
import '../warnings.dart';

/// Read-only list of live attendance anomalies for a run. Ephemeral — recomputed
/// from attendance each load. Tapping a row deep-links to that day's attendance.
class PayrollWarningsTab extends ConsumerWidget {
  final String runId;
  const PayrollWarningsTab({super.key, required this.runId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(runWarningsProvider(runId));
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Error: $e', style: const TextStyle(color: Colors.red)),
      ),
      data: (warnings) {
        if (warnings.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_outline,
                      size: 40, color: Color(0xFF16A34A)),
                  const SizedBox(height: 12),
                  Text(
                    'No attendance warnings for this period.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            Row(
              children: [
                Text(
                  '${warnings.length} warning${warnings.length == 1 ? '' : 's'}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: () => ref.invalidate(runWarningsProvider(runId)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < warnings.length; i++) ...[
                    if (i > 0)
                      Divider(height: 1, color: Theme.of(context).dividerColor),
                    _WarningRow(warning: warnings[i]),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _WarningRow extends StatelessWidget {
  final RunWarning warning;
  const _WarningRow({required this.warning});

  @override
  Widget build(BuildContext context) {
    final (icon, bg, fg) = _style(warning.type);
    return InkWell(
      onTap: () => context
          .go('/attendance/${warning.employeeId}/${isoDate(warning.date)}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: fg),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    warning.employeeLabel,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_fmtDate(warning.date)} · ${warning.message}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: Color(0xFF9CA3AF)),
          ],
        ),
      ),
    );
  }

  static (IconData, Color, Color) _style(WarningType t) {
    switch (t) {
      case WarningType.invalidWorkedTime:
        return (
          Icons.error_outline,
          const Color(0xFFFEE2E2),
          const Color(0xFF991B1B)
        );
      case WarningType.missingClockOut:
      case WarningType.missingClockIn:
      case WarningType.unapprovedOvertime:
        return (
          Icons.warning_amber_rounded,
          const Color(0xFFFEF3C7),
          const Color(0xFF92400E)
        );
    }
  }

  static String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/payroll/warnings_tab_test.dart`
Expected: PASS (both widget tests green).

- [ ] **Step 5: Commit**

```bash
git add lib/features/payroll/runs/detail/tabs/warnings_tab.dart test/features/payroll/warnings_tab_test.dart
git commit -m "feat(payroll): warnings tab widget with deep-link rows"
```

---

### Task 4: Wire the Warnings tab into the run detail screen

**Files:**
- Modify: `lib/features/payroll/runs/detail/payroll_run_detail_screen.dart`

**Interfaces:**
- Consumes: `PayrollWarningsTab` (Task 3), `runWarningsProvider` (Task 2, already exported from `providers.dart` which is imported).
- Produces: a 4th (or 5th, with Approvals) tab labelled `Warnings` + amber count badge.

- [ ] **Step 1: Add the tab import**

In `payroll_run_detail_screen.dart`, with the other `tabs/` imports (after `import 'tabs/summary_tab.dart';`), add:

```dart
import 'tabs/warnings_tab.dart';
```

- [ ] **Step 2: Compute the warning count + bump the tab count**

Inside `build`'s `data: (detail) {` closure, just below `final showApprovals = ...;`, change the tab-count line and add the warning count. Current:

```dart
          final showApprovals =
              detail.run.status == 'REVIEW' || detail.run.status == 'RELEASED';
          final tabCount = showApprovals ? 4 : 3;
```

Replace with:

```dart
          final showApprovals =
              detail.run.status == 'REVIEW' || detail.run.status == 'RELEASED';
          final tabCount = showApprovals ? 5 : 4;
          final warnCount =
              ref.watch(runWarningsProvider(runId)).asData?.value.length ?? 0;
```

- [ ] **Step 3: Insert the Warnings tab in the TabBar**

In the `tabs:` list, insert the Warnings tab after Disbursement. Current:

```dart
                            tabs: [
                              const Tab(text: 'Summary'),
                              Tab(text: 'Payslips (${detail.payslipCount})'),
                              const Tab(text: 'Disbursement'),
                              if (showApprovals) const Tab(text: 'Approvals'),
                            ],
```

Replace with:

```dart
                            tabs: [
                              const Tab(text: 'Summary'),
                              Tab(text: 'Payslips (${detail.payslipCount})'),
                              const Tab(text: 'Disbursement'),
                              Tab(child: _WarningsTabLabel(count: warnCount)),
                              if (showApprovals) const Tab(text: 'Approvals'),
                            ],
```

- [ ] **Step 4: Insert the Warnings tab body in the TabBarView**

In the `TabBarView`'s `children:`, insert after the Disbursement tab. Current:

```dart
                  children: [
                    PayrollSummaryTab(detail: detail),
                    PayrollPayslipsTab(
                      runId: runId,
                      runStatus: detail.run.status,
                    ),
                    PayrollDisbursementTab(
                      runId: runId,
                      runStatus: detail.run.status,
                    ),
                    if (showApprovals) PayrollApprovalsTab(runId: runId),
                  ],
```

Replace with:

```dart
                  children: [
                    PayrollSummaryTab(detail: detail),
                    PayrollPayslipsTab(
                      runId: runId,
                      runStatus: detail.run.status,
                    ),
                    PayrollDisbursementTab(
                      runId: runId,
                      runStatus: detail.run.status,
                    ),
                    PayrollWarningsTab(runId: runId),
                    if (showApprovals) PayrollApprovalsTab(runId: runId),
                  ],
```

- [ ] **Step 5: Invalidate warnings on realtime + recompute**

In `_invalidateAll()`, add the warnings provider to the invalidation set. Current:

```dart
  void _invalidateAll() {
    if (!mounted) return;
    ref.invalidate(payrollRunDetailProvider(runId));
    ref.invalidate(payslipListForRunProvider(runId));
    ref.invalidate(payslipApprovalCountsProvider(runId));
    ref.invalidate(larkApprovalCountsProvider(runId));
  }
```

Replace with (append one line):

```dart
  void _invalidateAll() {
    if (!mounted) return;
    ref.invalidate(payrollRunDetailProvider(runId));
    ref.invalidate(payslipListForRunProvider(runId));
    ref.invalidate(payslipApprovalCountsProvider(runId));
    ref.invalidate(larkApprovalCountsProvider(runId));
    ref.invalidate(runWarningsProvider(runId));
  }
```

Then in `_ActionBar._compute`, just after `ref.invalidate(payrollRunsProvider);` (inside the success path), add:

```dart
      ref.invalidate(runWarningsProvider(runId));
```

- [ ] **Step 6: Add the `_WarningsTabLabel` widget**

At the end of `payroll_run_detail_screen.dart`, append:

```dart
/// Tab label that appends an amber count badge when the run has > 0 attendance
/// warnings. Renders just "Warnings" when the count is zero.
class _WarningsTabLabel extends StatelessWidget {
  final int count;
  const _WarningsTabLabel({required this.count});

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const Text('Warnings');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Warnings'),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF3C7),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF92400E),
            ),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 7: Analyze + run the full test suite**

Run: `flutter analyze lib/features/payroll/runs/detail/payroll_run_detail_screen.dart`
Expected: "No issues found!"

Run: `flutter test`
Expected: PASS (whole suite, including Task 1 + Task 3 tests).

- [ ] **Step 8: Manual verification in the app**

Run: `flutter run -d linux --dart-define-from-file=env/prod.json`
Verify, on a payroll run whose period contains a day with a clock-in but no clock-out:
1. The run detail screen shows a **Warnings** tab after Disbursement, with an amber badge showing the count.
2. The tab lists the anomaly row(s) with employee, date, and message.
3. Tapping a row navigates to that employee's attendance detail for that day.
4. A run with clean attendance shows the green "No attendance warnings for this period." empty state and no badge.

- [ ] **Step 9: Commit**

```bash
git add lib/features/payroll/runs/detail/payroll_run_detail_screen.dart
git commit -m "feat(payroll): add Warnings tab + count badge to run detail"
```

---

## Self-Review

**Spec coverage:**
- 4 detection rules (missing clock-out/in, invalid worked time, unapproved OT > 30 min) → Task 1 `detectWarnings` + tests.
- Skip today/future, both-null absence, overnight & shiftless skip OT only → Task 1 + tests (cases 11–13).
- Approved-OT suppression (Lark duration or side flag) → Task 1 + tests (cases 7, 8).
- Company + period scope from the run → Task 2 `listByRange(companyId:)` + provider.
- Reuse existing `shiftTemplateListProvider`, only new query is company-scoped attendance → Task 2.
- Ephemeral, no DB/stored state/manual/acknowledge → no migration tasks; provider recomputes; covered.
- Tab after Disbursement + amber badge + invalidate on recompute/realtime → Task 4.
- List rows with type-tinted icon, employee, date, message, deep-link to `/attendance/:id/:date`; empty state; refresh → Task 3.
- Unit tests for `detectWarnings` covering all spec cases → Task 1 (14 tests map to the spec's 13 cases + sort).

**Placeholder scan:** No TBD/TODO/"handle edge cases"/"similar to" — every code step shows full code.

**Type consistency:** `RunWarning`/`WarningType` fields and `detectWarnings` signature are identical across Tasks 1, 3, 4. `runWarningsProvider(runId)` keyed by `String` used consistently in Tasks 2–4. `listByRange(..., companyId:)` definition (Task 2) matches its call (Task 2 provider). `isoDate`/`applyTime` imported from `attendance_row_vm.dart` in both Task 1 and Task 3.
