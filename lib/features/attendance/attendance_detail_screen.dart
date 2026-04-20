import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/breakpoints.dart';
import '../../data/models/attendance_day.dart';
import '../../data/models/employee.dart';
import '../../data/models/shift_template.dart';
import '../../data/repositories/attendance_repository.dart';
import '../../data/repositories/employee_repository.dart';
import '../../data/repositories/role_scorecard_repository.dart';
import '../../data/repositories/shift_template_repository.dart';
import 'attendance_screen.dart';

/// Per-person attendance detail for a single date.
/// Route: /attendance/:employeeId/:date (date is YYYY-MM-DD).
class AttendanceDetailScreen extends ConsumerWidget {
  final String employeeId;
  final DateTime date;
  const AttendanceDetailScreen({
    super.key,
    required this.employeeId,
    required this.date,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attendanceAsync = ref.watch(attendanceListProvider(
      AttendanceQuery(start: date, end: date, employeeId: employeeId),
    ));
    final employeeAsync =
        ref.watch(employeeByIdProvider(employeeId));
    final cardsAsync = ref.watch(roleScorecardListProvider);
    final roleTitleById = <String, String>{
      for (final c in cardsAsync.asData?.value ?? const []) c.id: c.jobTitle,
    };

    final employee = employeeAsync.asData?.value;
    final record = attendanceAsync.asData?.value.isNotEmpty == true
        ? attendanceAsync.asData!.value.first
        : null;
    final shiftsAsync = ref.watch(shiftTemplateListProvider);
    final shift = record?.shiftTemplateId == null
        ? null
        : shiftsAsync.asData?.value
            .where((s) => s.id == record!.shiftTemplateId)
            .cast<ShiftTemplate?>()
            .firstOrNull;

    final iso = date.toIso8601String().substring(0, 10);
    return Scaffold(
      appBar: AppBar(
        title: Text('Attendance · $iso'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/attendance');
            }
          },
        ),
      ),
      body: attendanceAsync.isLoading || employeeAsync.isLoading
          ? const Center(child: CircularProgressIndicator())
          : attendanceAsync.hasError
              ? Center(child: Text('Error: ${attendanceAsync.error}'))
              : _Body(
                  employee: employee,
                  record: record,
                  shift: shift,
                  date: date,
                  roleTitle: employee?.roleScorecardId != null
                      ? roleTitleById[employee!.roleScorecardId]
                      : null,
                ),
    );
  }
}

class _Body extends StatelessWidget {
  final Employee? employee;
  final AttendanceDay? record;
  final ShiftTemplate? shift;
  final DateTime date;
  final String? roleTitle;
  const _Body({
    required this.employee,
    required this.record,
    required this.shift,
    required this.date,
    required this.roleTitle,
  });

  @override
  Widget build(BuildContext context) {
    final name = employee?.fullName ??
        [record?.employeeFirstName, record?.employeeLastName]
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .join(' ');
    final empNo = employee?.employeeNumber ?? record?.employeeNumber ?? '—';
    final initials = _initials(name.isEmpty ? empNo : name);
    final status = _statusFor(record);
    final mobile = isMobile(context);

    final statusChip = Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(
            color: status.color, fontWeight: FontWeight.w700),
      ),
    );

    return ListView(
      padding: EdgeInsets.all(mobile ? 16 : 24),
      children: [
        // Header card
        Card(
          child: Padding(
            padding: EdgeInsets.all(mobile ? 16 : 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: mobile ? 24 : 32,
                  backgroundColor: status.color.withValues(alpha: 0.25),
                  child: Text(initials,
                      style: TextStyle(
                          color: status.color,
                          fontSize: mobile ? 14 : 18,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name.isEmpty ? empNo : name,
                          style: TextStyle(
                              fontSize: mobile ? 17 : 20,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        [empNo, roleTitle ?? employee?.jobTitle]
                            .whereType<String>()
                            .where((s) => s.isNotEmpty)
                            .join(' • '),
                        style: const TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _longDate(date),
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      if (mobile) ...[
                        const SizedBox(height: 8),
                        statusChip,
                      ],
                    ],
                  ),
                ),
                if (!mobile) statusChip,
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Clock card
        Card(
          child: Padding(
            padding: EdgeInsets.all(mobile ? 16 : 20),
            child: mobile
                ? Column(
                    children: [
                      _BigField(
                        label: 'CLOCK IN',
                        value: formatClock(record?.actualTimeIn),
                        color: status.color,
                      ),
                      const SizedBox(height: 16),
                      _BigField(
                        label: 'CLOCK OUT',
                        value: formatClock(record?.actualTimeOut),
                        color: status.color,
                      ),
                      const SizedBox(height: 16),
                      _BigField(
                        label: 'WORKED',
                        value: _workedDuration(record, shift),
                        color: status.color,
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: _BigField(
                          label: 'CLOCK IN',
                          value: formatClock(record?.actualTimeIn),
                          color: status.color,
                        ),
                      ),
                      const Icon(Icons.arrow_right_alt,
                          color: Colors.grey, size: 32),
                      Expanded(
                        child: _BigField(
                          label: 'CLOCK OUT',
                          value: formatClock(record?.actualTimeOut),
                          color: status.color,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _BigField(
                          label: 'WORKED',
                          value: _workedDuration(record, shift),
                          color: status.color,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 16),
        // Details card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Details',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                if (record == null)
                  const Text(
                    'No attendance record found for this date.',
                    style: TextStyle(color: Colors.grey),
                  )
                else ...[
                  _DetailRow('Day type', record!.dayType),
                  _DetailRow('Status', record!.attendanceStatus),
                  _DetailRow('Source', record!.sourceType),
                  if (record!.holidayName != null)
                    _DetailRow('Holiday', record!.holidayName!),
                  if (record!.approvedOtMinutes != null)
                    _DetailRow(
                        'Approved OT',
                        '${record!.approvedOtMinutes} min'),
                  _DetailRow(
                      'Early-in approved (OT)', record!.earlyInApproved ? 'Yes' : 'No'),
                  _DetailRow(
                      'Late-out approved (OT)', record!.lateOutApproved ? 'Yes' : 'No'),
                  _DetailRow('Locked', record!.isLocked ? 'Yes' : 'No'),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BigField extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _BigField({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                color: Colors.grey,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text(value,
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: isMobile(context) ? 120 : 160,
            child: Text(label,
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ),
          Expanded(
              child: Text(value,
                  style: const TextStyle(fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------
String _initials(String s) {
  final parts = s.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '—';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}

String _longDate(DateTime d) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December'
  ];
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday'
  ];
  return '${weekdays[(d.weekday - 1) % 7]}, ${months[(d.month - 1) % 12]} ${d.day}, ${d.year}';
}

/// Compute worked minutes, respecting shift bounds + OT approval flags:
/// - Clock-in earlier than shift start only counts when earlyInApproved.
/// - Clock-out later than shift end only counts when lateOutApproved.
/// - Deducts the record's applied break, or falls back to the shift's break,
///   then 60 minutes as a last resort.
String _workedDuration(AttendanceDay? r, ShiftTemplate? shift) {
  if (r == null || r.actualTimeIn == null || r.actualTimeOut == null) {
    return '—';
  }
  final tIn = r.actualTimeIn!.toLocal();
  final tOut = r.actualTimeOut!.toLocal();

  DateTime effectiveIn = tIn;
  DateTime effectiveOut = tOut;
  if (shift != null) {
    final shiftStart = _applyTime(tIn, shift.startTime);
    final shiftEnd = _applyTime(tIn, shift.endTime);
    if (!r.earlyInApproved && tIn.isBefore(shiftStart)) {
      effectiveIn = shiftStart;
    }
    if (!r.lateOutApproved && tOut.isAfter(shiftEnd)) {
      effectiveOut = shiftEnd;
    }
  }
  final rawMinutes = effectiveOut.difference(effectiveIn).inMinutes;
  if (rawMinutes <= 0) return '—';
  final breakMin = r.breakMinutesApplied ?? shift?.breakMinutes ?? 60;
  final worked = (rawMinutes - breakMin).clamp(0, rawMinutes);
  final h = worked ~/ 60;
  final m = worked % 60;
  return '${h}h ${m.toString().padLeft(2, '0')}m';
}

DateTime _applyTime(DateTime d, String hhmmss) {
  final parts = hhmmss.split(':');
  final h = int.tryParse(parts[0]) ?? 0;
  final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  return DateTime(d.year, d.month, d.day, h, m);
}

class _DetailStatus {
  final String label;
  final Color color;
  const _DetailStatus(this.label, this.color);
}

_DetailStatus _statusFor(AttendanceDay? r) {
  if (r == null) return const _DetailStatus('No Data', Color(0xFF9CA3AF));
  final s = r.attendanceStatus.toUpperCase();
  final d = r.dayType.toUpperCase();
  if (s.contains('LEAVE') || d.contains('LEAVE')) {
    return const _DetailStatus('On Leave', Color(0xFFA855F7));
  }
  if (r.actualTimeIn != null) {
    return const _DetailStatus('Present', Color(0xFF22C55E));
  }
  if (s == 'ABSENT') {
    return const _DetailStatus('Absent', Color(0xFFEF4444));
  }
  return const _DetailStatus('No Data', Color(0xFF9CA3AF));
}

