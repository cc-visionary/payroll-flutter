# Payroll Run — Warnings Tab

**Date:** 2026-06-30
**Branch:** `feat/payroll-run-warnings-tab`
**Status:** Approved design — ready for implementation plan

## Goal

Add a **Warnings** tab to the payroll run detail screen
(`payroll_run_detail_screen.dart`) that performs a live, ephemeral scan of the
run's attendance for the pay period and lists **actionable attendance
anomalies** — most commonly an employee who clocked in but never clocked out.
Each warning deep-links to that employee's attendance for the problematic day so
the user can go fix it before computing/releasing payroll.

## Non-goals (YAGNI)

These were explicitly excluded during brainstorming:

- **No database changes.** No `payroll_warnings` table, no migrations.
- **No stored state.** Warnings are recomputed live each time the tab loads;
  nothing is persisted.
- **No manual warnings / notes.** The tab only surfaces auto-detected anomalies.
- **No acknowledge / resolve / dismiss.** A warning clears only when the
  underlying attendance data is fixed.
- **No inline editing.** The single action is "jump to that day's attendance."

## Detection rules

The scan loads `attendance_day_records` for the run's **company** within the
run's pay period `[periodStart, periodEnd]`, joins the employee name, resolves
each record's shift template, and flags the following. **At most one warning per
record** (the buckets are mutually exclusive by construction).

| # | Type (`WarningType`) | Condition | Message example |
|---|----------------------|-----------|-----------------|
| 1 | `missingClockOut` | `actualTimeIn != null && actualTimeOut == null` | "Clocked in at 9:02 AM but never clocked out." |
| 2 | `missingClockIn` | `actualTimeOut != null && actualTimeIn == null` | "Clocked out at 6:00 PM but never clocked in." |
| 3 | `invalidWorkedTime` | both present & `actualTimeOut <= actualTimeIn` | "Clock-out is not after clock-in — check the times." |
| 4 | `unapprovedOvertime` | both present, **resolvable shift**, **not overnight**, an overage on either end **> 30 min** that is **not approved** | "Worked 47 min past shift end with no OT approval." |

### Rule details

- **Both clock times null** (a normal absence) is **not** flagged — that check
  was explicitly excluded.
- **Future / today's days are skipped** (`recordDate < today`, local). An
  employee still mid-shift today must not be flagged for "no clock-out yet."
- **Check 4 (`unapprovedOvertime`) specifics:**
  - Only evaluated when **both** clock times are present (so it never overlaps
    with checks 1/2) and the record has a resolvable `shift_template_id` (so we
    have a shift window). Records without a shift (rest days) are skipped for
    this check.
  - **Overnight shifts (`isOvernight == true`) are skipped** for this check —
    `applyTime(date, endTime)` puts the shift end on the same calendar day, so
    the overage math is unreliable for cross-midnight shifts. (Known
    limitation; documented, not solved here.) Checks 1–3 still apply to
    overnight records.
  - Overage is measured on **both ends**, each independently:
    - **Late-out overage** = `actualTimeOut − shiftEnd`. Flagged when
      `> 30 min` AND `lateOutApproved == false` AND `(approvedOtMinutes ?? 0) == 0`.
    - **Early-in overage** = `shiftStart − actualTimeIn`. Flagged when
      `> 30 min` AND `earlyInApproved == false` AND `(approvedOtMinutes ?? 0) == 0`.
  - A positive `approved_ot_minutes` (Lark-approved OT) suppresses the warning
    — that overtime is already accounted for.
  - The 30-minute threshold is a named constant (`_kUnapprovedOtThresholdMin`)
    so it is easy to tune.
- **Locked / released records** are still scanned and shown (informational); the
  deep-link still works (the attendance detail screen is read-only when locked).

## Scope

- **Company + period**, matching how the run sources its data — i.e. *all*
  attendance in the run's company for the period, not just employees who ended
  up on a payslip. This makes the tab a true pre-flight check that works even
  before compute.
- Synthetic unworked-holiday rows the compute engine fabricates in memory never
  exist in the DB, so the scan never sees them.

## Architecture

Four touch points, two new files. No existing flow is modified beyond adding a
tab.

### 1. NEW `lib/features/payroll/runs/detail/warnings.dart`

Pure model + detection logic (no Flutter, no Supabase — fully unit-testable):

```dart
enum WarningType { missingClockOut, missingClockIn, invalidWorkedTime, unapprovedOvertime }

class RunWarning {
  final String employeeId;
  final String employeeLabel;   // "EMP-001 · Jane Dela Cruz"
  final DateTime date;          // the attendance day
  final WarningType type;
  final String message;         // human-readable detail
}

/// Pure. Given the period's attendance records and a shift lookup,
/// return the list of anomalies (sorted by date, then employee label).
List<RunWarning> detectWarnings({
  required List<AttendanceDay> records,
  required Map<String, ShiftTemplate> shiftsById,
  required DateTime today,                 // injected for testability
  int unapprovedOtThresholdMinutes = 30,
});
```

### 2. EDIT `lib/data/repositories/payroll_repository.dart`

Add one method:

```dart
/// Raw attendance_day_records for [companyId] within [from]..[to],
/// joined with employees(employee_number, first_name, last_name) so
/// AttendanceDay.fromRow parses them. Used by the run Warnings tab.
Future<List<Map<String, dynamic>>> attendanceForPeriod({
  required String companyId,
  required DateTime from,
  required DateTime to,
});
```

(Table is `attendance_day_records`, consistent with `releaseRun` / `cancelRun`.)

### 3. EDIT `lib/features/payroll/runs/detail/providers.dart`

```dart
final runWarningsProvider =
    FutureProvider.family<List<RunWarning>, String>((ref, runId) async {
  final detail = await ref.watch(payrollRunDetailProvider(runId).future);
  if (detail == null) return const [];
  final run = detail.run;
  final repo = ref.watch(payrollRepositoryProvider);
  final rows = await repo.attendanceForPeriod(
    companyId: run.companyId, from: run.periodStart, to: run.periodEnd);
  final records = rows.map(AttendanceDay.fromRow).toList();
  final shifts = await ref.watch(shiftTemplateListProvider.future);
  final shiftsById = { for (final s in shifts) s.id: s };
  return detectWarnings(
    records: records, shiftsById: shiftsById, today: DateTime.now());
});
```

Reuses the existing `shiftTemplateListProvider`; the only new query is
`attendanceForPeriod`.

### 4. EDIT `lib/features/payroll/runs/detail/payroll_run_detail_screen.dart`

- Insert a **Warnings** tab after Disbursement, before the conditional
  Approvals tab. Tab order: `Summary · Payslips(n) · Disbursement · Warnings ·
  [Approvals]`.
- Base `tabCount` becomes 4 (was 3); `showApprovals` adds the 5th.
- The tab label shows an **amber count badge** when the warning count > 0
  (tinted chip: bg `#FEF3C7`, text `#92400E`, no border — per design system).
  The count comes from `ref.watch(runWarningsProvider(runId))`'s data length;
  while loading/zero, render the plain "Warnings" label with no badge.
- Add `ref.invalidate(runWarningsProvider(runId))` to `_invalidateAll()` and to
  the post-compute refresh list so the scan re-runs on recompute/realtime.

### 5. NEW `lib/features/payroll/runs/detail/tabs/warnings_tab.dart`

`PayrollWarningsTab(runId)` — watches `runWarningsProvider(runId)`:

- **loading** → centered `CircularProgressIndicator`.
- **error** → red error text (matches the screen's existing error style).
- **empty** → centered green check icon + "No attendance warnings for this
  period."
- **data (n > 0)** → a small header row with a **Refresh** `IconButton` (invalidates
  `runWarningsProvider(runId)` — covers attendance fixed on another screen),
  then a list of warning rows. Each row:
  - leading icon tinted by type (warning-amber for missing clock-out/in and
    unapproved OT; error-red for invalid worked time) using the app's
    status-chip tint convention (`lib/app/status_colors.dart`), no colored
    borders;
  - title = `employeeLabel`;
  - subtitle = formatted date + `message`;
  - trailing chevron;
  - `onTap` → `context.go('/attendance/${w.employeeId}/${isoDate(w.date)}')`
    (the existing per-employee, per-day attendance detail route).

  Rows are grouped/sorted by date then employee. Wrap the list per the project
  table convention only if it reads as tabular; a simple `ListView` of rows is
  acceptable here and matches the lighter tabs.

## Data flow

1. User opens a run → the Warnings tab label shows an amber badge with the count
   from `runWarningsProvider`.
2. The provider reads the run (company + period), loads
   `attendance_day_records` for the period and the shift templates, and runs the
   pure `detectWarnings`.
3. The tab renders the sorted warning list (or the empty state).
4. Tapping a row navigates to `/attendance/:employeeId/:date` for that day.
5. After the user fixes attendance there and returns, the **Refresh** button (or
   a recompute/realtime invalidation) re-runs the scan; fixed days drop off.

## Testing

Unit-test the pure `detectWarnings` in
`test/features/payroll/run_warnings_test.dart` (no Supabase, no widgets). Inject
a fixed `today` so future-day skipping is deterministic. Cases:

1. Clocked in, no clock-out → one `missingClockOut`.
2. Clocked out, no clock-in → one `missingClockIn`.
3. Both present, out before in → one `invalidWorkedTime`.
4. Both present, clean day within shift → **no** warning.
5. Both null (absence) → **no** warning.
6. Late-out 45 min past shift end, `lateOutApproved == false`,
   `approvedOtMinutes == 0` → one `unapprovedOvertime`.
7. Same as 6 but `approvedOtMinutes > 0` (Lark-approved) → **no** warning.
8. Same as 6 but `lateOutApproved == true` → **no** warning.
9. Late-out only 20 min (< 30 threshold) → **no** warning.
10. Early-in 40 min before shift start, `earlyInApproved == false` → one
    `unapprovedOvertime`.
11. Overnight shift with a large late-out overage → **no** `unapprovedOvertime`
    (skipped), but checks 1–3 still apply.
12. Record dated today/future with missing clock-out → **no** warning (skipped).
13. Record with no `shift_template_id` and a large clock-out time → **no**
    `unapprovedOvertime` (no shift window); checks 1–3 still apply.

## Edge cases summary

- Future/today days skipped.
- Both-null absences not flagged.
- Overnight shifts skip only the unapproved-OT check.
- Records without a shift skip only the unapproved-OT check.
- Approved OT (Lark duration or side flag) suppresses the OT warning.
- Locked/released records are still shown (informational); deep-link is
  read-only there.
- Synthetic holiday rows never reach the scan (DB-only source).
