import 'package:decimal/decimal.dart';

/// Canonical list of statutory agencies the screen aggregates over. The
/// underlying enum on the database side is `statutory_agency`. Order here
/// is the order rows render in the table and exported workbook.
enum StatutoryAgency {
  sssContribution('SSS_CONTRIBUTION', 'SSS Contribution', 'SSS'),
  philhealthContribution(
      'PHILHEALTH_CONTRIBUTION', 'PhilHealth Contribution', 'PhilHealth'),
  pagibigContribution('PAGIBIG_CONTRIBUTION', 'Pag-IBIG Contribution', 'Pag-IBIG'),
  birWithholding('BIR_WITHHOLDING', 'BIR 1601-C Withholding', 'BIR'),
  employeeLoan('EMPLOYEE_LOAN', 'Employee Loan Remittances', 'Loans');

  final String dbValue;
  final String fullLabel;
  final String shortLabel;
  const StatutoryAgency(this.dbValue, this.fullLabel, this.shortLabel);

  static StatutoryAgency? fromDb(String? raw) {
    if (raw == null) return null;
    for (final a in StatutoryAgency.values) {
      if (a.dbValue == raw) return a;
    }
    return null;
  }
}

/// One row from `statutory_payables_due_v`: per (brand × month × agency)
/// total owed, plus the EE / ER split and the count of contributing
/// payslips and employees. Drives the main payables table.
class StatutoryPayable {
  final String hiringEntityId;
  final int periodYear;
  final int periodMonth;
  final StatutoryAgency agency;
  final Decimal amountDue;
  final Decimal eeShare;
  final Decimal erShare;
  final int payslipCount;
  final int employeeCount;

  const StatutoryPayable({
    required this.hiringEntityId,
    required this.periodYear,
    required this.periodMonth,
    required this.agency,
    required this.amountDue,
    required this.eeShare,
    required this.erShare,
    required this.payslipCount,
    required this.employeeCount,
  });

  factory StatutoryPayable.fromRow(Map<String, dynamic> r) {
    Decimal d(Object? v) => Decimal.parse((v ?? '0').toString());
    final agency = StatutoryAgency.fromDb(r['agency'] as String?);
    if (agency == null) {
      throw StateError('Unknown statutory_agency value: ${r['agency']}');
    }
    return StatutoryPayable(
      hiringEntityId: r['hiring_entity_id'] as String,
      periodYear: (r['period_year'] as num).toInt(),
      periodMonth: (r['period_month'] as num).toInt(),
      agency: agency,
      amountDue: d(r['amount_due']),
      eeShare: d(r['ee_share']),
      erShare: d(r['er_share']),
      payslipCount: (r['payslip_count'] as num).toInt(),
      employeeCount: (r['employee_count'] as num).toInt(),
    );
  }
}

/// Aggregate of non-voided payments toward a single (brand × month × agency)
/// payable. The repository fetches this from `statutory_payments_paid_v`
/// and joins client-side with [StatutoryPayable].
class StatutoryPaymentSummary {
  final String hiringEntityId;
  final int periodYear;
  final int periodMonth;
  final StatutoryAgency agency;
  final Decimal amountPaid;
  final int paymentCount;
  final DateTime? lastPaidOn;

  const StatutoryPaymentSummary({
    required this.hiringEntityId,
    required this.periodYear,
    required this.periodMonth,
    required this.agency,
    required this.amountPaid,
    required this.paymentCount,
    this.lastPaidOn,
  });

  factory StatutoryPaymentSummary.fromRow(Map<String, dynamic> r) {
    Decimal d(Object? v) => Decimal.parse((v ?? '0').toString());
    final agency = StatutoryAgency.fromDb(r['agency'] as String?);
    if (agency == null) {
      throw StateError('Unknown statutory_agency value: ${r['agency']}');
    }
    return StatutoryPaymentSummary(
      hiringEntityId: r['hiring_entity_id'] as String,
      periodYear: (r['period_year'] as num).toInt(),
      periodMonth: (r['period_month'] as num).toInt(),
      agency: agency,
      amountPaid: d(r['amount_paid']),
      paymentCount: (r['payment_count'] as num).toInt(),
      lastPaidOn: r['last_paid_on'] == null
          ? null
          : DateTime.parse(r['last_paid_on'] as String),
    );
  }
}

/// One employee row in the per-(brand × month × agency) breakdown drawer +
/// XLSX export. Pulled from `statutory_payable_breakdown_v` and joined
/// client-side with `employees` for name / number / MI.
class StatutoryPayableBreakdownRow {
  final String hiringEntityId;
  final int periodYear;
  final int periodMonth;
  final StatutoryAgency agency;
  final String employeeId;
  final Decimal eeShare;
  final Decimal erShare;
  final Decimal totalAmount;

  const StatutoryPayableBreakdownRow({
    required this.hiringEntityId,
    required this.periodYear,
    required this.periodMonth,
    required this.agency,
    required this.employeeId,
    required this.eeShare,
    required this.erShare,
    required this.totalAmount,
  });

  factory StatutoryPayableBreakdownRow.fromRow(Map<String, dynamic> r) {
    Decimal d(Object? v) => Decimal.parse((v ?? '0').toString());
    final agency = StatutoryAgency.fromDb(r['agency'] as String?);
    if (agency == null) {
      throw StateError('Unknown statutory_agency value: ${r['agency']}');
    }
    return StatutoryPayableBreakdownRow(
      hiringEntityId: r['hiring_entity_id'] as String,
      periodYear: (r['period_year'] as num).toInt(),
      periodMonth: (r['period_month'] as num).toInt(),
      agency: agency,
      employeeId: r['employee_id'] as String,
      eeShare: d(r['ee_share']),
      erShare: d(r['er_share']),
      totalAmount: d(r['total_amount']),
    );
  }
}

/// Status chip state for a payable: `Unpaid` (zero paid), `Partial` (some
/// paid but less than due), `Paid` (paid == due, with PHP rounding
/// tolerance), `Overpaid` (paid > due). The single source of truth used by
/// both the on-screen chip and the XLSX summary cell.
enum PayableStatus {
  unpaid,
  partial,
  paid,
  overpaid;

  String get label => switch (this) {
        PayableStatus.unpaid => 'Unpaid',
        PayableStatus.partial => 'Partial',
        PayableStatus.paid => 'Paid',
        PayableStatus.overpaid => 'Overpaid',
      };
}

/// Decide a payable's status from the (due, paid) pair. The 0.01 PHP
/// rounding epsilon swallows centavo-level differences from agency
/// portals; the screen still surfaces the variance numerically so HR
/// notices anything beyond rounding.
PayableStatus classifyPayable(Decimal due, Decimal paid) {
  final epsilon = Decimal.parse('0.01');
  if (paid <= Decimal.zero) return PayableStatus.unpaid;
  final diff = paid - due;
  final absDiff = diff < Decimal.zero ? -diff : diff;
  if (absDiff < epsilon) return PayableStatus.paid;
  if (paid < due) return PayableStatus.partial;
  return PayableStatus.overpaid;
}
