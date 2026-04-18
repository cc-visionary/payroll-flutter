import 'package:decimal/decimal.dart';

class AttendanceDay {
  final String id;
  final String employeeId;
  final DateTime attendanceDate;
  final String dayType;
  final DateTime? actualTimeIn;
  final DateTime? actualTimeOut;
  final String attendanceStatus;
  final String sourceType;
  final int? workedMinutesComputed; // not stored — derived client-side if needed
  final bool earlyInApproved;
  final bool lateOutApproved;
  final bool lateInApproved;
  final bool earlyOutApproved;
  final int? approvedOtMinutes;
  final int? breakMinutesApplied;
  final Decimal? dailyRateOverride;
  final String? overrideReason;
  final String? overrideReasonCode;
  final String? overrideById;
  final DateTime? overrideAt;
  final bool isLocked;
  final String? holidayName;
  final String? shiftTemplateId;
  // Joined employee fields (populated when repo query includes !inner join)
  final String? employeeNumber;
  final String? employeeFirstName;
  final String? employeeLastName;

  String get employeeLabel {
    final name = [employeeFirstName, employeeLastName]
        .where((s) => s != null && s!.isNotEmpty)
        .join(' ');
    if (employeeNumber != null && name.isNotEmpty) return '$employeeNumber · $name';
    if (employeeNumber != null) return employeeNumber!;
    if (name.isNotEmpty) return name;
    return employeeId;
  }

  const AttendanceDay({
    required this.id,
    required this.employeeId,
    required this.attendanceDate,
    required this.dayType,
    this.actualTimeIn,
    this.actualTimeOut,
    required this.attendanceStatus,
    required this.sourceType,
    this.workedMinutesComputed,
    required this.earlyInApproved,
    required this.lateOutApproved,
    required this.lateInApproved,
    required this.earlyOutApproved,
    this.approvedOtMinutes,
    this.breakMinutesApplied,
    this.dailyRateOverride,
    this.overrideReason,
    this.overrideReasonCode,
    this.overrideById,
    this.overrideAt,
    required this.isLocked,
    this.holidayName,
    this.shiftTemplateId,
    this.employeeNumber,
    this.employeeFirstName,
    this.employeeLastName,
  });

  factory AttendanceDay.fromRow(Map<String, dynamic> r) => AttendanceDay(
        id: r['id'] as String,
        employeeId: r['employee_id'] as String,
        attendanceDate: DateTime.parse(r['attendance_date'] as String),
        dayType: r['day_type'] as String,
        actualTimeIn: r['actual_time_in'] == null
            ? null
            : DateTime.parse(r['actual_time_in'] as String),
        actualTimeOut: r['actual_time_out'] == null
            ? null
            : DateTime.parse(r['actual_time_out'] as String),
        attendanceStatus: r['attendance_status'] as String,
        sourceType: r['source_type'] as String,
        earlyInApproved: r['early_in_approved'] as bool? ?? false,
        lateOutApproved: r['late_out_approved'] as bool? ?? false,
        lateInApproved: r['late_in_approved'] as bool? ?? false,
        earlyOutApproved: r['early_out_approved'] as bool? ?? false,
        approvedOtMinutes: r['approved_ot_minutes'] as int?,
        breakMinutesApplied: r['break_minutes_applied'] as int?,
        dailyRateOverride: r['daily_rate_override'] == null
            ? null
            : Decimal.parse(r['daily_rate_override'].toString()),
        overrideReason: r['override_reason'] as String?,
        overrideReasonCode: r['override_reason_code'] as String?,
        overrideById: r['override_by_id'] as String?,
        overrideAt: r['override_at'] == null
            ? null
            : DateTime.parse(r['override_at'] as String),
        isLocked: r['is_locked'] as bool? ?? false,
        holidayName: r['holiday_name'] as String?,
        shiftTemplateId: r['shift_template_id'] as String?,
        employeeNumber: _emp(r)?['employee_number'] as String?,
        employeeFirstName: _emp(r)?['first_name'] as String?,
        employeeLastName: _emp(r)?['last_name'] as String?,
      );

  static Map<String, dynamic>? _emp(Map<String, dynamic> r) =>
      r['employees'] as Map<String, dynamic>?;
}
