// Shared attendance row view-model. One row = one calendar day for an
// employee; wraps the stored `AttendanceDay` record (if any) with the shift
// template, the holiday calendar event (if any), and the employee's scorecard
// `work_days_per_week` so display logic (shift text, status, worked / late /
// OT minutes) is computed in one place.
//
// Consumed by:
//   - lib/features/employees/profile/tabs/attendance_tab.dart (on-screen table)
//   - lib/features/payroll/payslips/payslip_pdf.dart (payslip page 2)
//
// The math here is ported from payrollos `lib/utils/timezone.ts:425-453`
// (deduction deficit model) and payrollos `components/attendance-row`
// (overtime + status promotion rules). Keep this file the single source of
// truth — if you touch a getter, the UI and the PDF update together.

import '../../data/models/attendance_day.dart';
import '../../data/models/calendar_event.dart';
import '../../data/models/shift_template.dart';

class AttendanceRowVm {
  final DateTime date;
  final AttendanceDay? record;
  final ShiftTemplate? shift;
  final CalendarEvent? holiday;
  final String? workDaysPerWeek;
  const AttendanceRowVm({
    required this.date,
    required this.record,
    required this.shift,
    required this.holiday,
    required this.workDaysPerWeek,
  });

  String get dayType {
    // The presence/absence of a per-record `shift_template_id` is the single
    // authoritative signal for "scheduled work day vs rest day":
    //
    //   - Shift assigned → scheduled work day (regardless of clock-in).
    //     If the employee was scheduled but didn't show up, that's an
    //     absence on a workday — NOT a rest day eligible for premium pay.
    //   - No shift assigned → rest day. If the employee clocked in
    //     anyway, the engine pays rest-day premium.
    //
    // Why not use the scorecard's weekly schedule? Because employees
    // routinely deviate (overtime weekend coverage, swapped rest days,
    // single-day shift changes), and the per-day shift assignment from
    // Lark is the actual roster Lark uses to compute pay. Lark sync sets
    // shift_template_id=null for rest days; admin can clear it manually
    // too. Either way, the column tells the truth about that specific day.
    //
    // Holidays always override — a worked holiday is REGULAR_HOLIDAY /
    // SPECIAL_HOLIDAY regardless of the shift assignment.
    if (holiday != null) return holiday!.dayType;
    final r = record;
    if (r != null) {
      if (r.shiftTemplateId != null) {
        // Has a shift: it's a workday (force WORKDAY even if the stored
        // day_type still says REST_DAY — could happen with old records
        // imported before this rule, or after a manual shift edit that
        // didn't update day_type). Holiday day_types stay (handled above
        // via the calendar_events check).
        final dt = r.dayType.toUpperCase();
        if (dt == 'REGULAR_HOLIDAY' ||
            dt == 'SPECIAL_HOLIDAY' ||
            dt == 'SPECIAL_WORKING') {
          return r.dayType;
        }
        return 'WORKDAY';
      }
      // No shift assigned — rest day, regardless of clock-in.
      return 'REST_DAY';
    }
    // No record at all — fall back to scorecard weekly schedule.
    if (isRestDay(date, workDaysPerWeek)) return 'REST_DAY';
    return 'WORKDAY';
  }

  String get status {
    final r = record;
    final worked = r?.actualTimeIn != null;
    // Rest-day promotion: even if the stored record says ABSENT, render as
    // REST_DAY when the employee didn't clock in and the date falls outside
    // their scheduled work days. Same promotion used in attendance_screen.
    if (!worked && isRestDay(date, workDaysPerWeek)) return 'REST_DAY';
    if (r != null) {
      if (!worked && r.dayType == 'REST_DAY') return 'REST_DAY';
      return r.attendanceStatus;
    }
    if (holiday != null) return 'HOLIDAY';
    return 'NO_DATA';
  }

  String? get holidayName => record?.holidayName ?? holiday?.name;

  /// Worked minutes with sub-minute precision (seconds/60). Late seconds
  /// matter for accurate late-deduction math, so we don't truncate.
  double? get workedMinutes {
    final r = record;
    if (r == null || r.actualTimeIn == null || r.actualTimeOut == null) {
      return null;
    }
    var tIn = r.actualTimeIn!.toLocal();
    var tOut = r.actualTimeOut!.toLocal();
    if (shift != null) {
      final shiftStart = applyTime(date, shift!.startTime);
      final shiftEnd = applyTime(date, shift!.endTime);
      if (!r.earlyInApproved && tIn.isBefore(shiftStart)) tIn = shiftStart;
      if (!r.lateOutApproved && tOut.isAfter(shiftEnd)) tOut = shiftEnd;
    }
    final mins = tOut.difference(tIn).inSeconds / 60.0;
    if (mins <= 0) return 0;
    final breakMin = r.breakMinutesApplied ?? shift?.breakMinutes ?? 60;
    final worked = mins - breakMin;
    return worked < 0 ? 0 : worked;
  }

  /// Compute scheduled-window work minutes vs what the shift expects. Used
  /// by both `deductionMinutes` (deficit) and `overtimeMinutes` (excess).
  /// Returns null when the row can't be evaluated (no record, no shift,
  /// holiday/rest day, or missing clock times) — callers treat that as 0.
  ({double schedWorked, double expectedWork})? _scheduledWork() {
    final r = record;
    if (r == null || shift == null) return null;
    final dt = dayType.toUpperCase();
    if (dt == 'REGULAR_HOLIDAY' ||
        dt == 'SPECIAL_HOLIDAY' ||
        dt.contains('REST')) {
      return null;
    }
    final tIn = r.actualTimeIn?.toLocal();
    final tOut = r.actualTimeOut?.toLocal();
    if (tIn == null || tOut == null) return null;

    final schedStart = applyTime(date, shift!.startTime);
    final schedEnd = applyTime(date, shift!.endTime);
    final shiftMins = schedEnd.difference(schedStart).inSeconds / 60.0;
    if (shiftMins <= 0) return null;
    final origBreak = shift!.breakMinutes.toDouble();
    final actualBreak = (r.breakMinutesApplied?.toDouble()) ?? origBreak;
    final expectedWorkMinutes = shiftMins - origBreak;

    final effectiveIn = r.lateInApproved
        ? schedStart
        : (tIn.isAfter(schedStart) ? tIn : schedStart);
    final effectiveOut = r.earlyOutApproved
        ? schedEnd
        : (tOut.isBefore(schedEnd) ? tOut : schedEnd);

    final schedGross =
        effectiveOut.difference(effectiveIn).inSeconds / 60.0;
    if (schedGross <= 0) {
      return (schedWorked: 0, expectedWork: expectedWorkMinutes);
    }
    final schedBreak = schedGross > 300 ? actualBreak : 0.0;
    final schedWorked = schedGross - schedBreak;
    return (schedWorked: schedWorked, expectedWork: expectedWorkMinutes);
  }

  /// Late/Undertime deduction — deficit model ported from payrollos
  /// (`lib/utils/timezone.ts:425-453`).
  double get deductionMinutes {
    final w = _scheduledWork();
    if (w == null) return 0;
    if (record?.actualTimeIn == null || record?.actualTimeOut == null) {
      return 0;
    }
    final deficit = w.expectedWork - w.schedWorked;
    return deficit < 0 ? 0 : deficit;
  }

  /// OT minutes. Priority order:
  ///
  /// 1. **Lark-approved duration** (`approved_ot_minutes > 0`) — the cap is
  ///    the approved amount, *not* the clock-out overage. If the employee
  ///    stayed 37 minutes late but the approval was only for 36 minutes,
  ///    we credit 36. The sync populates both `approved_ot_minutes` and
  ///    the side flags when OT comes from a Lark approval, so we detect
  ///    this case via the positive duration.
  ///
  /// 2. **Manually-approved flags** (`earlyInApproved` / `lateOutApproved`)
  ///    with no stored duration — admin toggled the flag in the edit
  ///    dialog, we trust the raw clock-time diff since no ceiling was
  ///    entered. Works even without Lark involvement.
  ///
  /// 3. **Implicit break OT** — when the applied break is shorter than the
  ///    shift's default, the employee worked through (part of) their
  ///    break; the excess over `expectedWork` inside the scheduled window
  ///    becomes OT. Only surfaces in scenario (2) — Lark approvals
  ///    already cover this case in their approved duration.
  ///
  /// Zero when the employee didn't clock in — protects against stale
  /// Lark-sync OT on unworked days.
  double get overtimeMinutes {
    final r = record;
    if (r == null) return 0;
    if (r.actualTimeIn == null) return 0;

    final approvedFromLark = (r.approvedOtMinutes ?? 0).toDouble();
    if (approvedFromLark > 0) {
      // Lark-capped OT — hard ceiling, ignores any over-time overage at
      // the clock.
      return approvedFromLark;
    }

    // No Lark approval — compute from admin-toggled flags + implicit
    // break-through OT.
    double derived = 0;
    if (shift != null) {
      final tIn = r.actualTimeIn?.toLocal();
      if (tIn != null && r.earlyInApproved) {
        final sched = applyTime(date, shift!.startTime);
        final diff = sched.difference(tIn).inSeconds / 60.0;
        if (diff > 0) derived += diff;
      }
      final tOut = r.actualTimeOut?.toLocal();
      if (tOut != null && r.lateOutApproved) {
        final sched = applyTime(date, shift!.endTime);
        final diff = tOut.difference(sched).inSeconds / 60.0;
        if (diff > 0) derived += diff;
      }
    }
    final w = _scheduledWork();
    if (w != null) {
      final excess = w.schedWorked - w.expectedWork;
      if (excess > 0) derived += excess;
    }
    return derived;
  }

  /// Net OT after late minutes are absorbed (per the company netting rule:
  /// late time first reduces OT before either is paid/deducted).
  double get netOvertimeMinutes {
    final ot = overtimeMinutes;
    final late = deductionMinutes;
    final net = ot - late;
    return net < 0 ? 0 : net;
  }

  /// Net late after OT minutes have been absorbed.
  double get netDeductionMinutes {
    final ot = overtimeMinutes;
    final late = deductionMinutes;
    final net = late - ot;
    return net < 0 ? 0 : net;
  }
}

/// Aggregated period totals derived from a set of [AttendanceRowVm]s. The
/// numbers displayed on the employee profile Attendance tab and on page 2 of
/// the payslip PDF both read from this class, so the "10 / 12 days" ratio
/// and `Late / UT` / `OT` totals stay perfectly in sync.
class AttendanceStats {
  /// Total scheduled work days in the period. A day counts when the
  /// employee either clocked in OR was scheduled (not rest day, not
  /// holiday). Holidays the employee *did* work are included.
  final int workDays;
  final int present;
  final int absent;
  final int restDays;
  final int regularHoliday;
  final int specialHoliday;
  final int onLeave;
  /// Net late/UT after OT absorption (company rule: late minutes are
  /// eaten by OT minutes first, only the remainder is deducted/paid).
  final double lateUndertimeMinutes;
  final double otMinutes;

  const AttendanceStats({
    required this.workDays,
    required this.present,
    required this.absent,
    required this.restDays,
    required this.regularHoliday,
    required this.specialHoliday,
    required this.onLeave,
    required this.lateUndertimeMinutes,
    required this.otMinutes,
  });

  /// Work Days = scheduled work days minus unworked holidays.
  ///   - Rest days (by weekday schedule or dayType) never count.
  ///   - Holidays not worked are excluded (counted as Regular/Special).
  ///   - Holidays worked DO count as Work Days (and still count as holiday).
  factory AttendanceStats.from(
    List<AttendanceRowVm> rows, {
    String? workDaysPerWeek,
  }) {
    int workDays = 0,
        present = 0,
        absent = 0,
        rest = 0,
        reg = 0,
        spec = 0,
        leave = 0;
    double lateMin = 0, ot = 0;
    for (final row in rows) {
      final dt = row.dayType.toUpperCase();
      final st = row.status.toUpperCase();
      final isLeave = st.contains('LEAVE');
      final isRestByDayType = dt.contains('REST');
      final isRestBySchedule = isRestDay(row.date, workDaysPerWeek);
      final isRest = isRestByDayType || isRestBySchedule;
      final isRegHoliday = dt == 'REGULAR_HOLIDAY' ||
          row.holiday?.dayType == 'REGULAR_HOLIDAY';
      final isSpecHoliday = (dt.contains('SPECIAL') && !isRegHoliday) ||
          (row.holiday != null &&
              row.holiday!.dayType.contains('SPECIAL') &&
              !isRegHoliday);
      final isAnyHoliday = isRegHoliday || isSpecHoliday;
      final worked = row.record?.actualTimeIn != null;

      final isWorkDay = worked || (!isRest && !isAnyHoliday);
      if (isWorkDay) {
        workDays++;
        if (!isLeave) {
          if (worked) {
            present++;
          } else if (st == 'ABSENT') {
            absent++;
          }
        }
      }

      if (isRest) rest++;
      if (isRegHoliday) {
        reg++;
      } else if (isSpecHoliday) {
        spec++;
      }
      if (isLeave) leave++;
      lateMin += row.netDeductionMinutes;
      ot += row.netOvertimeMinutes;
    }
    return AttendanceStats(
      workDays: workDays,
      present: present,
      absent: absent,
      restDays: rest,
      regularHoliday: reg,
      specialHoliday: spec,
      onLeave: leave,
      lateUndertimeMinutes: lateMin,
      otMinutes: ot,
    );
  }
}

/// Walk [start]..[end] (inclusive) and build one row per calendar day,
/// joining attendance records, the matching shift template, and holidays.
/// Rows after today are skipped (the UI only renders past/current days).
///
/// Pass [skipFutureDays] = false when you need to include future days anyway
/// (the payslip PDF does this — the pay period is authoritative).
List<AttendanceRowVm> buildAttendanceRows({
  required DateTime start,
  required DateTime end,
  required List<AttendanceDay> records,
  required Map<String, ShiftTemplate> shifts,
  required Map<String, CalendarEvent> holidays,
  ShiftTemplate? defaultShift,
  String? workDaysPerWeek,
  bool skipFutureDays = true,
}) {
  final byDate = <String, AttendanceDay>{
    for (final r in records) isoDate(r.attendanceDate): r,
  };
  final today = DateTime.now();
  final cutoff = DateTime(today.year, today.month, today.day);
  final rows = <AttendanceRowVm>[];
  for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
    if (skipFutureDays && d.isAfter(cutoff)) break;
    final iso = isoDate(d);
    final rec = byDate[iso];
    final shift = (rec?.shiftTemplateId != null
            ? shifts[rec!.shiftTemplateId]
            : null) ??
        defaultShift;
    final holiday = holidays[iso];
    rows.add(AttendanceRowVm(
      date: d,
      record: rec,
      shift: shift,
      holiday: holiday,
      workDaysPerWeek: workDaysPerWeek,
    ));
  }
  return rows;
}

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime applyTime(DateTime date, String hhmmss) {
  final parts = hhmmss.split(':');
  final h = int.tryParse(parts[0]) ?? 0;
  final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  return DateTime(date.year, date.month, date.day, h, m);
}

/// Parse free-form `work_days_per_week` (e.g. "Monday to Saturday",
/// "Mon, Tue, Wed, Thu, Fri") and decide if the given date falls OUTSIDE
/// that schedule (= rest day). Empty input defaults to Mon-Sat.
///
/// Internally caches the parsed bitmask per input string so the regex
/// doesn't re-run on every row of every rebuild — scorecards produce a
/// handful of distinct strings across the whole org.
bool isRestDay(DateTime date, String? workDaysPerWeek) =>
    !_workDayBitmask(workDaysPerWeek).contains(date.weekday);

const Map<String, int> _kDayNames = {
  'sunday': DateTime.sunday,
  'sun': DateTime.sunday,
  'monday': DateTime.monday,
  'mon': DateTime.monday,
  'tuesday': DateTime.tuesday,
  'tue': DateTime.tuesday,
  'tues': DateTime.tuesday,
  'wednesday': DateTime.wednesday,
  'wed': DateTime.wednesday,
  'thursday': DateTime.thursday,
  'thu': DateTime.thursday,
  'thur': DateTime.thursday,
  'thurs': DateTime.thursday,
  'friday': DateTime.friday,
  'fri': DateTime.friday,
  'saturday': DateTime.saturday,
  'sat': DateTime.saturday,
};

final _workDayCache = <String?, Set<int>>{};
final _kRangeRegex = RegExp(r'([a-z]+)\s*(?:to|-|–|—|until)\s*([a-z]+)');
final _kSplitRegex = RegExp(r'[,/;\s]+');

Set<int> _workDayBitmask(String? workDaysPerWeek) {
  // Cap cache growth — scorecards only produce a handful of distinct strings.
  if (_workDayCache.length > 64) _workDayCache.clear();
  final cached = _workDayCache[workDaysPerWeek];
  if (cached != null) return cached;

  Set<int> parse() {
    if (workDaysPerWeek == null || workDaysPerWeek.trim().isEmpty) {
      return const {
        DateTime.monday,
        DateTime.tuesday,
        DateTime.wednesday,
        DateTime.thursday,
        DateTime.friday,
        DateTime.saturday,
      };
    }
    final s = workDaysPerWeek.toLowerCase();
    final toMatch = _kRangeRegex.firstMatch(s);
    if (toMatch != null) {
      final a = _kDayNames[toMatch.group(1)!];
      final b = _kDayNames[toMatch.group(2)!];
      if (a != null && b != null) {
        final out = <int>{};
        if (a <= b) {
          for (var d = a; d <= b; d++) {
            out.add(d);
          }
        } else {
          // Wrap-around: e.g. "Saturday to Thursday".
          for (var d = a; d <= DateTime.sunday; d++) {
            out.add(d);
          }
          for (var d = DateTime.monday; d <= b; d++) {
            out.add(d);
          }
        }
        return out;
      }
    }
    final tokens = s.split(_kSplitRegex).where((t) => t.isNotEmpty);
    final working = tokens.map((t) => _kDayNames[t]).whereType<int>().toSet();
    if (working.isNotEmpty) return working;
    // Fallback: Mon-Sat.
    return const {
      DateTime.monday,
      DateTime.tuesday,
      DateTime.wednesday,
      DateTime.thursday,
      DateTime.friday,
      DateTime.saturday,
    };
  }

  final parsed = parse();
  _workDayCache[workDaysPerWeek] = parsed;
  return parsed;
}
