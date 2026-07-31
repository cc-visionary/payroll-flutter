import '../../../../data/models/attendance_day.dart';
import '../../../../data/models/shift_template.dart';
import '../../../attendance/attendance_row_vm.dart' show applyTime;
import '../../leave/paid_leave_matcher.dart';

/// Category of attendance anomaly surfaced on the run Warnings tab.
enum WarningType {
  missingClockOut,
  missingClockIn,
  invalidWorkedTime,
  unapprovedOvertime,
  leaveWithoutApprovedRequest,
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
  Map<String, List<ApprovedLeaveDay>> approvedLeavesByEmployee = const {},
}) {
  final todayDay = DateTime(today.year, today.month, today.day);
  final out = <RunWarning>[];

  for (final r in records) {
    final recDay = DateTime(
        r.attendanceDate.year, r.attendanceDate.month, r.attendanceDate.day);
    // Skip today + future: an employee still mid-shift hasn't clocked out yet.
    if (!recDay.isBefore(todayDay)) continue;

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
          employeeLabel: r.employeeLabel,
          date: recDay,
          type: WarningType.leaveWithoutApprovedRequest,
          message: 'On leave with no matching approved leave request — '
              'pay treatment cannot be determined.',
        ));
      }
    }

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
