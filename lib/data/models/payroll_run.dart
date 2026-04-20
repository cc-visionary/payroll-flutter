import 'package:decimal/decimal.dart';

/// PayrollRun is the canonical row for a payroll computation over a
/// user-picked date range. After migration 20260418000001 the period fields
/// live directly on this row — no pay_periods / payroll_calendars join.
class PayrollRun {
  final String id;
  final String companyId;
  final String status; // DRAFT, COMPUTING, REVIEW, RELEASED, CANCELLED
  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime payDate;
  final String? payFrequency; // WEEKLY | BI_WEEKLY | SEMI_MONTHLY | MONTHLY
  final Decimal totalGrossPay;
  final Decimal totalDeductions;
  final Decimal totalNetPay;
  final int employeeCount;
  final int payslipCount;
  final DateTime? approvedAt;
  final DateTime? releasedAt;
  final DateTime? updatedAt;
  final String? remarks;
  final DateTime createdAt;
  // Audit fields — populated when the query joins user_emails view.
  final String? createdById;
  final String? createdByEmail;
  final String? approvedById;
  final String? approvedByEmail;
  /// Flipped to `true` when HR hits "Distribute 13th Month" on this run.
  /// Lets reports filter 13th-month distributions separately from regular
  /// payroll runs.
  final bool isThirteenthMonthDistribution;

  const PayrollRun({
    required this.id,
    required this.companyId,
    required this.status,
    required this.periodStart,
    required this.periodEnd,
    required this.payDate,
    this.payFrequency,
    required this.totalGrossPay,
    required this.totalDeductions,
    required this.totalNetPay,
    required this.employeeCount,
    required this.payslipCount,
    this.approvedAt,
    this.releasedAt,
    this.updatedAt,
    this.remarks,
    required this.createdAt,
    this.createdById,
    this.createdByEmail,
    this.approvedById,
    this.approvedByEmail,
    this.isThirteenthMonthDistribution = false,
  });

  factory PayrollRun.fromRow(Map<String, dynamic> r) {
    final createdByEmbed = r['created_by'] as Map<String, dynamic>?;
    final approvedByEmbed = r['approved_by'] as Map<String, dynamic>?;
    DateTime? parseDateTime(Object? v) =>
        v == null ? null : DateTime.parse(v as String);
    // Defensive fallback: before migration 20260418000001 is applied,
    // period_start / period_end / pay_date may be absent. Fall back to
    // created_at so the UI can still render (as "—"-looking dates rather
    // than crashing the whole screen).
    final createdAt = DateTime.parse(r['created_at'] as String);
    DateTime parseDateOrFallback(Object? v) =>
        v == null ? createdAt : DateTime.parse(v as String);
    return PayrollRun(
      id: r['id'] as String,
      companyId: (r['company_id'] as String?) ?? '',
      status: r['status'] as String,
      periodStart: parseDateOrFallback(r['period_start']),
      periodEnd: parseDateOrFallback(r['period_end']),
      payDate: parseDateOrFallback(r['pay_date']),
      payFrequency: r['pay_frequency'] as String?,
      totalGrossPay: Decimal.parse((r['total_gross_pay'] ?? '0').toString()),
      totalDeductions: Decimal.parse((r['total_deductions'] ?? '0').toString()),
      totalNetPay: Decimal.parse((r['total_net_pay'] ?? '0').toString()),
      employeeCount: r['employee_count'] as int? ?? 0,
      payslipCount: r['payslip_count'] as int? ?? 0,
      approvedAt: parseDateTime(r['approved_at']),
      releasedAt: parseDateTime(r['released_at']),
      updatedAt: parseDateTime(r['updated_at']),
      remarks: r['remarks'] as String?,
      createdAt: createdAt,
      createdById: r['created_by_id'] as String?,
      createdByEmail: createdByEmbed?['email'] as String?,
      approvedById: r['approved_by_id'] as String?,
      approvedByEmail: approvedByEmbed?['email'] as String?,
      isThirteenthMonthDistribution:
          r['is_thirteenth_month_distribution'] as bool? ?? false,
    );
  }
}
