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
  // Iterate by calendar day, not duration. Duration(days: 1) can skip or repeat
  // a calendar day across DST transitions. DateTime(year, month, day+1) is
  // timezone-safe and normalises month/year overflow.
  for (
    var d = start;
    !d.isAfter(end);
    d = DateTime(d.year, d.month, d.day + 1)
  ) {
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
