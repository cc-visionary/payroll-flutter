import 'package:decimal/decimal.dart';

/// Plain-Dart model mirroring the `role_rate_changes` table
/// (supabase/migrations/20260928000001_role_rate_changes.sql).
///
/// One effective-dated change to a role's default base rate. Only employees
/// with no `compensation_changes` record of their own are paid from it.
class RoleRateChange {
  final String id;
  final String companyId;
  final String roleScorecardId;
  final DateTime effectiveDate;
  final Decimal? prevBaseSalary;
  final Decimal newBaseSalary;
  final String reason;
  final String? initiatedById;
  final DateTime createdAt;

  const RoleRateChange({
    required this.id,
    required this.companyId,
    required this.roleScorecardId,
    required this.effectiveDate,
    this.prevBaseSalary,
    required this.newBaseSalary,
    this.reason = '',
    this.initiatedById,
    required this.createdAt,
  });

  factory RoleRateChange.fromRow(Map<String, dynamic> r) => RoleRateChange(
    id: r['id'] as String,
    companyId: r['company_id'] as String,
    roleScorecardId: r['role_scorecard_id'] as String,
    effectiveDate: DateTime.parse(r['effective_date'] as String),
    prevBaseSalary: r['prev_base_salary'] == null
        ? null
        : Decimal.parse(r['prev_base_salary'].toString()),
    newBaseSalary: Decimal.parse(r['new_base_salary'].toString()),
    reason: (r['reason'] as String?) ?? '',
    initiatedById: r['initiated_by_id'] as String?,
    createdAt: DateTime.parse(r['created_at'] as String),
  );
}
