class ShiftTemplate {
  final String id;
  final String companyId;
  final String code;
  final String name;
  final String startTime; // HH:mm:ss
  final String endTime;
  final bool isOvernight;
  final String breakType;
  final int breakMinutes;
  final String? breakStartTime;
  final String? breakEndTime;
  final int graceMinutesLate;
  final int graceMinutesEarlyOut;
  final int scheduledWorkMinutes;
  final String? larkShiftId;
  final bool isActive;

  const ShiftTemplate({
    required this.id,
    required this.companyId,
    required this.code,
    required this.name,
    required this.startTime,
    required this.endTime,
    required this.isOvernight,
    required this.breakType,
    required this.breakMinutes,
    this.breakStartTime,
    this.breakEndTime,
    required this.graceMinutesLate,
    required this.graceMinutesEarlyOut,
    required this.scheduledWorkMinutes,
    this.larkShiftId,
    required this.isActive,
  });

  bool get isFromLark => larkShiftId != null;

  factory ShiftTemplate.fromRow(Map<String, dynamic> r) => ShiftTemplate(
        id: r['id'] as String,
        companyId: r['company_id'] as String,
        code: r['code'] as String,
        name: r['name'] as String,
        startTime: r['start_time'] as String,
        endTime: r['end_time'] as String,
        isOvernight: r['is_overnight'] as bool? ?? false,
        breakType: r['break_type'] as String? ?? 'AUTO_DEDUCT',
        breakMinutes: r['break_minutes'] as int? ?? 0,
        breakStartTime: r['break_start_time'] as String?,
        breakEndTime: r['break_end_time'] as String?,
        graceMinutesLate: r['grace_minutes_late'] as int? ?? 0,
        graceMinutesEarlyOut: r['grace_minutes_early_out'] as int? ?? 0,
        scheduledWorkMinutes: r['scheduled_work_minutes'] as int? ?? 480,
        larkShiftId: r['lark_shift_id'] as String?,
        isActive: r['is_active'] as bool? ?? true,
      );
}
