import 'package:decimal/decimal.dart';

import '../../data/models/hiring_entity.dart';
import '../../data/models/statutory_payable.dart';

/// Monthly Contributions Report — XLSX reference sheet for the external
/// accountant who remits SSS / PhilHealth / Pag-IBIG (and BIR withholding).
///
/// One sheet per brand (statutory entity), ONE ROW PER EMPLOYEE:
///
///   Month | Employee ID | Last Name | First Name | Monthly Salary |
///   SSS EE | SSS ER | PhilHealth EE | PhilHealth ER |
///   Pag-IBIG EE | Pag-IBIG ER | W/H Tax | Total EE | Total ER | Total
///
/// followed by a TOTALS row and a per-agency Remittance Status block
/// (Due / Paid / PAID-PARTIAL-UNPAID) sourced from the Mark-as-Paid ledger.
///
/// The Monthly Salary column is the DECLARED wage converted to a monthly
/// amount with the engine's statutory formula (see [declaredMonthlySalary]);
/// contribution cells are the month's actual deductions summed across all
/// RELEASED runs by `statutory_payable_breakdown_v`. Employee loans are
/// excluded — this report is for the benefits accountant only.
/// Spec: docs/superpowers/specs/2026-07-31-monthly-contributions-report-design.md

Decimal _div(Decimal a, Decimal b) =>
    (a / b).toDecimal(scaleOnInfinitePrecision: 10);

Decimal _round2(Decimal v) => Decimal.parse(v.toStringAsFixed(2));

/// Declared monthly salary — mirrors the statutory-override block in
/// `compute_engine.dart` (daily = DAILY as-is / HOURLY x hours / MONTHLY / 26,
/// then monthly = daily x 26). The override applies only when BOTH amount
/// and type are set and the amount is strictly positive — same partial-
/// override guard as ComputeService. Falls back to the scorecard rate,
/// converted identically, so employees without an override show their
/// actual rate (declared == actual for them).
Decimal declaredMonthlySalary({
  required Decimal? declaredWageOverride,
  required String? declaredWageType,
  required Decimal? scorecardBaseSalary,
  required String? scorecardWageType,
  int workHoursPerDay = 8,
}) {
  final overrideActive = declaredWageOverride != null &&
      declaredWageType != null &&
      declaredWageOverride > Decimal.zero;
  final rate =
      overrideActive ? declaredWageOverride : (scorecardBaseSalary ?? Decimal.zero);
  final type = overrideActive ? declaredWageType : scorecardWageType;

  Decimal daily;
  switch ((type ?? 'DAILY').toUpperCase()) {
    case 'MONTHLY':
      daily = _div(rate, Decimal.fromInt(26));
      break;
    case 'HOURLY':
      daily = rate * Decimal.fromInt(workHoursPerDay);
      break;
    case 'DAILY':
    default:
      daily = rate;
  }
  return _round2(daily * Decimal.fromInt(26));
}

/// Employee meta + derived salary for one report row.
class MonthlyContributionEmployee {
  final String employeeId;
  final String employeeNumber;
  final String firstName;
  final String lastName;
  final Decimal monthlySalary;
  const MonthlyContributionEmployee({
    required this.employeeId,
    required this.employeeNumber,
    required this.firstName,
    required this.lastName,
    required this.monthlySalary,
  });
}

/// One employee row — the month's summed deductions per agency. W/H tax is
/// EE-only (ER = 0 for BIR). Total EE deliberately includes W/H tax: the
/// column set matches the payslip's deduction block.
class MonthlyContributionRow {
  final MonthlyContributionEmployee employee;
  final Decimal sssEe;
  final Decimal sssEr;
  final Decimal philhealthEe;
  final Decimal philhealthEr;
  final Decimal pagibigEe;
  final Decimal pagibigEr;
  final Decimal withholdingTax;
  const MonthlyContributionRow({
    required this.employee,
    required this.sssEe,
    required this.sssEr,
    required this.philhealthEe,
    required this.philhealthEr,
    required this.pagibigEe,
    required this.pagibigEr,
    required this.withholdingTax,
  });

  Decimal get totalEe => sssEe + philhealthEe + pagibigEe + withholdingTax;
  Decimal get totalEr => sssEr + philhealthEr + pagibigEr;
  Decimal get total => totalEe + totalEr;
}

/// One line of the Remittance Status block. [status] is null when nothing
/// is due (renders as an em-dash).
class RemittanceStatusLine {
  final StatutoryAgency agency;
  final Decimal due;
  final Decimal paid;
  final DateTime? lastPaidOn;
  const RemittanceStatusLine({
    required this.agency,
    required this.due,
    required this.paid,
    this.lastPaidOn,
  });

  PayableStatus? get status =>
      due <= Decimal.zero ? null : classifyPayable(due, paid);
}

/// Assembled data for one brand sheet.
class MonthlyContributionsSheet {
  final HiringEntity brand;
  final List<MonthlyContributionRow> rows;
  final List<RemittanceStatusLine> statusLines;
  const MonthlyContributionsSheet({
    required this.brand,
    required this.rows,
    required this.statusLines,
  });

  Decimal _sum(Decimal Function(MonthlyContributionRow) f) =>
      rows.fold(Decimal.zero, (s, r) => s + f(r));

  Decimal get totalSssEe => _sum((r) => r.sssEe);
  Decimal get totalSssEr => _sum((r) => r.sssEr);
  Decimal get totalPhilhealthEe => _sum((r) => r.philhealthEe);
  Decimal get totalPhilhealthEr => _sum((r) => r.philhealthEr);
  Decimal get totalPagibigEe => _sum((r) => r.pagibigEe);
  Decimal get totalPagibigEr => _sum((r) => r.pagibigEr);
  Decimal get totalWithholdingTax => _sum((r) => r.withholdingTax);
  Decimal get totalEe => _sum((r) => r.totalEe);
  Decimal get totalEr => _sum((r) => r.totalEr);
  Decimal get total => _sum((r) => r.total);
}
