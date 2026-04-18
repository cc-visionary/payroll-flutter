import 'package:decimal/decimal.dart';

class PayslipLine {
  final String id;
  final String payslipId;
  final String category;
  final String description;
  final Decimal? quantity;
  final Decimal? rate;
  final Decimal? multiplier;
  final Decimal amount;
  final int sortOrder;

  const PayslipLine({
    required this.id,
    required this.payslipId,
    required this.category,
    required this.description,
    this.quantity,
    this.rate,
    this.multiplier,
    required this.amount,
    required this.sortOrder,
  });

  factory PayslipLine.fromRow(Map<String, dynamic> r) {
    Decimal? dec(Object? v) => v == null ? null : Decimal.parse(v.toString());
    return PayslipLine(
      id: r['id'] as String,
      payslipId: r['payslip_id'] as String,
      category: r['category'] as String,
      description: r['description'] as String,
      quantity: dec(r['quantity']),
      rate: dec(r['rate']),
      multiplier: dec(r['multiplier']),
      amount: Decimal.parse(r['amount'].toString()),
      sortOrder: r['sort_order'] as int? ?? 0,
    );
  }
}

class Payslip {
  final String id;
  final String payrollRunId;
  final String employeeId;
  final String? payslipNumber;
  final Decimal grossPay;
  final Decimal totalEarnings;
  final Decimal totalDeductions;
  final Decimal netPay;
  final Decimal sssEe;
  final Decimal philhealthEe;
  final Decimal pagibigEe;
  final Decimal withholdingTax;
  final Decimal ytdGrossPay;
  final Decimal ytdTaxableIncome;
  final Decimal ytdTaxWithheld;
  final String approvalStatus;
  final DateTime createdAt;
  final List<PayslipLine> lines;

  const Payslip({
    required this.id,
    required this.payrollRunId,
    required this.employeeId,
    this.payslipNumber,
    required this.grossPay,
    required this.totalEarnings,
    required this.totalDeductions,
    required this.netPay,
    required this.sssEe,
    required this.philhealthEe,
    required this.pagibigEe,
    required this.withholdingTax,
    required this.ytdGrossPay,
    required this.ytdTaxableIncome,
    required this.ytdTaxWithheld,
    required this.approvalStatus,
    required this.createdAt,
    this.lines = const [],
  });

  factory Payslip.fromRow(Map<String, dynamic> r, {List<PayslipLine> lines = const []}) {
    Decimal d(Object? v) => Decimal.parse((v ?? '0').toString());
    return Payslip(
      id: r['id'] as String,
      payrollRunId: r['payroll_run_id'] as String,
      employeeId: r['employee_id'] as String,
      payslipNumber: r['payslip_number'] as String?,
      grossPay: d(r['gross_pay']),
      totalEarnings: d(r['total_earnings']),
      totalDeductions: d(r['total_deductions']),
      netPay: d(r['net_pay']),
      sssEe: d(r['sss_ee']),
      philhealthEe: d(r['philhealth_ee']),
      pagibigEe: d(r['pagibig_ee']),
      withholdingTax: d(r['withholding_tax']),
      ytdGrossPay: d(r['ytd_gross_pay']),
      ytdTaxableIncome: d(r['ytd_taxable_income']),
      ytdTaxWithheld: d(r['ytd_tax_withheld']),
      approvalStatus: r['approval_status'] as String? ?? 'DRAFT_IN_REVIEW',
      createdAt: DateTime.parse(r['created_at'] as String),
      lines: lines,
    );
  }
}
