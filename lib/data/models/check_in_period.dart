/// Plain-Dart model mirroring the `check_in_periods` table.
/// Periods are either company-wide (target_employee_id = null) for the
/// quarterly cycle, or employee-specific (target_employee_id set) for
/// probationary 1M/3M/5M milestones.
class CheckInPeriod {
  final String id;
  final String companyId;
  final String name;
  final String
  periodType; // enum: MONTHLY|QUARTERLY|ANNUAL|PROBATION_1M|PROBATION_3M|PROBATION_5M
  final DateTime startDate;
  final DateTime endDate;
  final DateTime dueDate;
  final bool isActive;
  final String? targetEmployeeId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CheckInPeriod({
    required this.id,
    required this.companyId,
    required this.name,
    required this.periodType,
    required this.startDate,
    required this.endDate,
    required this.dueDate,
    required this.isActive,
    this.targetEmployeeId,
    required this.createdAt,
    required this.updatedAt,
  });
}

extension CheckInPeriodFromRow on CheckInPeriod {
  static CheckInPeriod fromRow(Map<String, dynamic> r) {
    DateTime dt(Object v) => DateTime.parse(v as String);
    return CheckInPeriod(
      id: r['id'] as String,
      companyId: r['company_id'] as String,
      name: r['name'] as String,
      periodType: r['period_type'] as String,
      startDate: dt(r['start_date']),
      endDate: dt(r['end_date']),
      dueDate: dt(r['due_date']),
      isActive: r['is_active'] as bool,
      targetEmployeeId: r['target_employee_id'] as String?,
      createdAt: dt(r['created_at']),
      updatedAt: dt(r['updated_at']),
    );
  }
}
