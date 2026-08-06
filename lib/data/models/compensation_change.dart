import 'package:decimal/decimal.dart';

/// Plain-Dart model mirroring the `compensation_changes` table
/// (supabase/migrations/20260708000001_compensation_changes.sql).
///
/// Effective-dated source of truth for an individual's pay/role. Payroll reads
/// the current effective row and falls back to `role_scorecards.base_salary`.
class CompensationChange {
  final String id;
  final String companyId;
  final String employeeId;
  final String
  changeType; // SALARY_INCREASE|SALARY_DECREASE|PROMOTION|LATERAL_TRANSFER|DEMOTION
  final String status; // SCHEDULED|APPLIED|CANCELLED
  final DateTime effectiveDate;
  final Decimal? prevBaseSalary;
  final Decimal? newBaseSalary;
  final String? prevWageType;
  final String? newWageType;
  final String? prevScorecardId;
  final String? newScorecardId;
  final String reason;
  final String? workflowId;
  final String? documentId;
  final String initiatedById;
  final DateTime? appliedAt;
  final DateTime createdAt;
  final DateTime? deletedAt;

  const CompensationChange({
    required this.id,
    required this.companyId,
    required this.employeeId,
    required this.changeType,
    required this.status,
    required this.effectiveDate,
    this.prevBaseSalary,
    this.newBaseSalary,
    this.prevWageType,
    this.newWageType,
    this.prevScorecardId,
    this.newScorecardId,
    this.reason = '',
    this.workflowId,
    this.documentId,
    required this.initiatedById,
    this.appliedAt,
    required this.createdAt,
    this.deletedAt,
  });

  /// True when this change moves the employee to a different role scorecard.
  bool get isRoleChange =>
      newScorecardId != null && newScorecardId != prevScorecardId;

  factory CompensationChange.fromRow(Map<String, dynamic> r) {
    Decimal? dec(Object? v) => v == null ? null : Decimal.parse(v.toString());
    DateTime? dt(Object? v) => v == null ? null : DateTime.parse(v as String);
    return CompensationChange(
      id: r['id'] as String,
      companyId: r['company_id'] as String,
      employeeId: r['employee_id'] as String,
      changeType: r['change_type'] as String,
      status: r['status'] as String,
      effectiveDate: DateTime.parse(r['effective_date'] as String),
      prevBaseSalary: dec(r['prev_base_salary']),
      newBaseSalary: dec(r['new_base_salary']),
      prevWageType: r['prev_wage_type'] as String?,
      newWageType: r['new_wage_type'] as String?,
      prevScorecardId: r['prev_scorecard_id'] as String?,
      newScorecardId: r['new_scorecard_id'] as String?,
      reason: r['reason'] as String? ?? '',
      workflowId: r['workflow_id'] as String?,
      documentId: r['document_id'] as String?,
      initiatedById: r['initiated_by_id'] as String,
      appliedAt: dt(r['applied_at']),
      createdAt: dt(r['created_at'])!,
      deletedAt: dt(r['deleted_at']),
    );
  }
}
