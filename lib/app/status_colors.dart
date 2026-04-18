import 'package:flutter/material.dart';

/// Semantic status tokens for chips, badges, and status indicators.
/// Use these instead of hardcoding `Color(0xFF...)` literals — they
/// adapt to light/dark mode automatically.
///
/// Example:
///   final s = StatusPalette.of(context, StatusTone.success);
///   Chip(label: Text('Linked'), backgroundColor: s.background, labelStyle: TextStyle(color: s.foreground));
enum StatusTone {
  success,
  warning,
  danger,
  info,
  neutral,
  /// Holiday-specific: regular holiday (red-pink tint).
  holidayRegular,
  /// Holiday-specific: special non-working holiday (yellow tint).
  holidaySpecial,
  /// Holiday-specific: special working / extra day (cyan-purple tint).
  holidayWorking,
  /// Attendance: on-leave (distinct blue — not CTA purple, not info).
  attendanceOnLeave,
}

class StatusPalette {
  final Color background;
  final Color foreground;
  const StatusPalette(this.background, this.foreground);

  static StatusPalette of(BuildContext context, StatusTone tone) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return isLight ? _light[tone]! : _dark[tone]!;
  }

  static const _light = <StatusTone, StatusPalette>{
    StatusTone.success: StatusPalette(Color(0xFFDCFCE7), Color(0xFF166534)),
    StatusTone.warning: StatusPalette(Color(0xFFFEF3C7), Color(0xFF92400E)),
    StatusTone.danger:  StatusPalette(Color(0xFFFEE2E2), Color(0xFF991B1B)),
    StatusTone.info:    StatusPalette(Color(0xFFE8E9FF), Color(0xFF635BFF)),
    StatusTone.neutral: StatusPalette(Color(0xFFF5F5F5), Color(0xFF3C4F69)),
    StatusTone.holidayRegular: StatusPalette(Color(0xFFFEE2E2), Color(0xFF991B1B)),
    StatusTone.holidaySpecial: StatusPalette(Color(0xFFFEF3C7), Color(0xFF92400E)),
    StatusTone.holidayWorking: StatusPalette(Color(0xFFE8E9FF), Color(0xFF635BFF)),
    StatusTone.attendanceOnLeave: StatusPalette(Color(0xFFE6F0FB), Color(0xFF1F5AA8)),
  };

  static const _dark = <StatusTone, StatusPalette>{
    StatusTone.success: StatusPalette(Color(0x2600D66F), Color(0xFF00D66F)),
    StatusTone.warning: StatusPalette(Color(0x26FF6118), Color(0xFFFFB088)),
    StatusTone.danger:  StatusPalette(Color(0x2EDC2626), Color(0xFFFF8A8A)),
    StatusTone.info:    StatusPalette(Color(0x2E7F7DFC), Color(0xFFA8A6FF)),
    StatusTone.neutral: StatusPalette(Color(0xFF1A2C45), Color(0xFFC7D1DD)),
    StatusTone.holidayRegular: StatusPalette(Color(0x2EDC2626), Color(0xFFFF8A8A)),
    StatusTone.holidaySpecial: StatusPalette(Color(0x26FF6118), Color(0xFFFFB088)),
    StatusTone.holidayWorking: StatusPalette(Color(0x2E7F7DFC), Color(0xFFA8A6FF)),
    StatusTone.attendanceOnLeave: StatusPalette(Color(0xFF1C2638), Color(0xFF8FB4E0)),
  };
}

/// Canonical attendance statuses rendered in the shared Attendance tab and
/// daily attendance screen. Use [toneForAttendance] to resolve a tone when
/// the source data is a raw string, or call [palette] directly.
enum AttendanceStatus {
  present,
  absent,
  restDay,
  regularHoliday,
  specialHoliday,
  onLeave,
  noData;

  String get label => switch (this) {
        AttendanceStatus.present => 'Present',
        AttendanceStatus.absent => 'Absent',
        AttendanceStatus.restDay => 'Rest Day',
        AttendanceStatus.regularHoliday => 'Regular Holiday',
        AttendanceStatus.specialHoliday => 'Special Holiday',
        AttendanceStatus.onLeave => 'On Leave',
        AttendanceStatus.noData => 'No Data',
      };

  StatusTone get tone => switch (this) {
        AttendanceStatus.present => StatusTone.success,
        AttendanceStatus.absent => StatusTone.danger,
        AttendanceStatus.restDay => StatusTone.neutral,
        AttendanceStatus.regularHoliday => StatusTone.holidayRegular,
        AttendanceStatus.specialHoliday => StatusTone.holidaySpecial,
        AttendanceStatus.onLeave => StatusTone.attendanceOnLeave,
        AttendanceStatus.noData => StatusTone.neutral,
      };

  StatusPalette palette(BuildContext context) =>
      StatusPalette.of(context, tone);
}

/// Classify a row's status given its raw `status` + `dayType` strings plus
/// a worked flag. Central rule — mirrored by `_RowVM.status` in the
/// attendance widgets so labels and chip colors line up.
AttendanceStatus classifyAttendance({
  required String? status,
  required String? dayType,
  required bool worked,
}) {
  final s = (status ?? '').toUpperCase();
  final d = (dayType ?? '').toUpperCase();
  if (s.contains('LEAVE') || d.contains('LEAVE')) return AttendanceStatus.onLeave;
  if (d == 'REGULAR_HOLIDAY') return AttendanceStatus.regularHoliday;
  if (d.contains('SPECIAL')) return AttendanceStatus.specialHoliday;
  if (d == 'REST_DAY' && !worked) return AttendanceStatus.restDay;
  if (worked) return AttendanceStatus.present;
  if (s == 'ABSENT') return AttendanceStatus.absent;
  return AttendanceStatus.noData;
}

/// Map a common status string (APPROVED, PENDING, FAILED, ...) to a StatusTone.
/// Use this when rendering a chip whose label is the raw string from the API.
StatusTone toneForStatusString(String? status) {
  switch ((status ?? '').toUpperCase()) {
    case 'APPROVED':
    case 'COMPLETED':
    case 'ACTIVE':
    case 'PAID':
    case 'DEDUCTED':
    case 'RELEASED':
    case 'PRESENT':
      return StatusTone.success;
    case 'PENDING':
    case 'PENDING_APPROVAL':
    case 'PARTIAL':
    case 'IN_PROGRESS':
    case 'REVIEW':
    case 'DRAFT':
    case 'DRAFT_IN_REVIEW':
    case 'LATE':
      return StatusTone.warning;
    case 'REJECTED':
    case 'CANCELLED':
    case 'FAILED':
    case 'RECALLED':
    case 'SEPARATED':
    case 'ABSENT':
      return StatusTone.danger;
    default:
      return StatusTone.neutral;
  }
}

/// Convenience: build a brand-styled status chip with semantic tone.
class StatusChip extends StatelessWidget {
  final String label;
  final StatusTone tone;
  const StatusChip({super.key, required this.label, required this.tone});

  @override
  Widget build(BuildContext context) {
    final s = StatusPalette.of(context, tone);
    return Chip(
      label: Text(label, style: TextStyle(color: s.foreground, fontWeight: FontWeight.w600)),
      backgroundColor: s.background,
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
    );
  }
}
