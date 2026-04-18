import 'package:decimal/decimal.dart';
import 'types.dart';

/// Statutory deduction calculators — SSS, PhilHealth, Pag-IBIG, Withholding Tax.
/// Ported from payrollos/lib/payroll/statutory-calculator.ts.

Decimal _round3(Decimal v) {
  final factor = Decimal.fromInt(1000);
  return ((v * factor).round(scale: 0) / factor).toDecimal(scaleOnInfinitePrecision: 3);
}

Decimal _div(Decimal a, Decimal b) => (a / b).toDecimal(scaleOnInfinitePrecision: 10);

Decimal _min(Decimal a, Decimal b) => a <= b ? a : b;
Decimal _max(Decimal a, Decimal b) => a >= b ? a : b;

bool _bracketContains(Decimal v, Decimal min, Decimal? max) {
  if (v < min) return false;
  if (max == null) return true;
  return v <= max;
}

// =============================================================================
// Regularization eligibility
// =============================================================================
bool isEligibleForStatutory(
  EmployeeRegularizationInput regularization,
  PayPeriodInput payPeriod,
  bool isBenefitsEligible,
) {
  if (!isBenefitsEligible) return false;
  if (regularization.employmentType == EmploymentType.REGULAR) return true;
  if (regularization.regularizationDate != null) {
    return !regularization.regularizationDate!.isAfter(payPeriod.endDate);
  }
  return false;
}

// =============================================================================
// SSS
// =============================================================================
class SssResult {
  final Decimal ee;
  final Decimal er;
  final Decimal total;
  const SssResult(this.ee, this.er, this.total);
}

SssResult calculateSSS(Decimal monthlySalary, SSSTableInput table) {
  SSSBracket? match;
  for (final b in table.brackets) {
    if (_bracketContains(monthlySalary, b.minSalary, b.maxSalary)) {
      match = b;
      break;
    }
  }
  match ??= table.brackets.last;
  final ee = match.regularSsEe + match.mpfEe;
  final er = match.regularSsEr + match.ecEr + match.mpfEr;
  return SssResult(ee, er, ee + er);
}

class StatutoryLinePair {
  final ComputedPayslipLine eeLine;
  final ComputedPayslipLine erLine;
  const StatutoryLinePair(this.eeLine, this.erLine);
}

StatutoryLinePair generateSSSLines(
  Decimal monthlySalary,
  SSSTableInput table,
  Decimal payPeriodsPerMonth,
) {
  final sss = calculateSSS(monthlySalary, table);
  final eePerPeriod = _round3(_div(sss.ee, payPeriodsPerMonth));
  final erPerPeriod = _round3(_div(sss.er, payPeriodsPerMonth));
  return StatutoryLinePair(
    ComputedPayslipLine(
      category: PayslipLineCategory.SSS_EE,
      description: 'SSS Employee Share',
      amount: eePerPeriod,
      sortOrder: 1100,
      ruleCode: 'SSS_EE',
      ruleDescription: 'SSS EE (Monthly: ${sss.ee})',
    ),
    ComputedPayslipLine(
      category: PayslipLineCategory.SSS_ER,
      description: 'SSS Employer Share',
      amount: erPerPeriod,
      sortOrder: 1101,
      ruleCode: 'SSS_ER',
      ruleDescription: 'SSS ER (Monthly: ${sss.er})',
    ),
  );
}

// =============================================================================
// PhilHealth
// =============================================================================
SssResult calculatePhilHealth(Decimal monthlySalary, PhilHealthTableInput table) {
  final base = _min(_max(monthlySalary, table.minBase), table.maxBase);
  final totalPremium = _round3(base * table.premiumRate);
  final ee = _round3(totalPremium * table.eeShare);
  final er = _round3(totalPremium * (Decimal.one - table.eeShare));
  return SssResult(ee, er, ee + er);
}

StatutoryLinePair generatePhilHealthLines(
  Decimal monthlySalary,
  PhilHealthTableInput table,
  Decimal payPeriodsPerMonth,
) {
  final r = calculatePhilHealth(monthlySalary, table);
  final eePerPeriod = _round3(_div(r.ee, payPeriodsPerMonth));
  final erPerPeriod = _round3(_div(r.er, payPeriodsPerMonth));
  return StatutoryLinePair(
    ComputedPayslipLine(
      category: PayslipLineCategory.PHILHEALTH_EE,
      description: 'PhilHealth Employee Share',
      amount: eePerPeriod,
      sortOrder: 1110,
      ruleCode: 'PHILHEALTH_EE',
      ruleDescription: 'PhilHealth EE (Monthly: ${r.ee})',
    ),
    ComputedPayslipLine(
      category: PayslipLineCategory.PHILHEALTH_ER,
      description: 'PhilHealth Employer Share',
      amount: erPerPeriod,
      sortOrder: 1111,
      ruleCode: 'PHILHEALTH_ER',
      ruleDescription: 'PhilHealth ER (Monthly: ${r.er})',
    ),
  );
}

// =============================================================================
// Pag-IBIG
// =============================================================================
SssResult calculatePagIBIG(Decimal monthlySalary, PagIBIGTableInput table) {
  final base = _min(monthlySalary, table.maxBase);
  final ee = _round3(base * table.eeRate);
  final er = _round3(base * table.erRate);
  return SssResult(ee, er, ee + er);
}

StatutoryLinePair generatePagIBIGLines(
  Decimal monthlySalary,
  PagIBIGTableInput table,
  Decimal payPeriodsPerMonth,
) {
  final r = calculatePagIBIG(monthlySalary, table);
  final eePerPeriod = _round3(_div(r.ee, payPeriodsPerMonth));
  final erPerPeriod = _round3(_div(r.er, payPeriodsPerMonth));
  return StatutoryLinePair(
    ComputedPayslipLine(
      category: PayslipLineCategory.PAGIBIG_EE,
      description: 'Pag-IBIG Employee Share',
      amount: eePerPeriod,
      sortOrder: 1120,
      ruleCode: 'PAGIBIG_EE',
      ruleDescription: 'Pag-IBIG EE (Monthly: ${r.ee})',
    ),
    ComputedPayslipLine(
      category: PayslipLineCategory.PAGIBIG_ER,
      description: 'Pag-IBIG Employer Share',
      amount: erPerPeriod,
      sortOrder: 1121,
      ruleCode: 'PAGIBIG_ER',
      ruleDescription: 'Pag-IBIG ER (Monthly: ${r.er})',
    ),
  );
}

// =============================================================================
// Withholding Tax (TRAIN Law graduated)
// =============================================================================
Decimal calculateAnnualTax(Decimal annualTaxableIncome, TaxTableInput table) {
  if (annualTaxableIncome <= Decimal.zero) return Decimal.zero;
  TaxBracket? match;
  for (final b in table.brackets) {
    if (_bracketContains(annualTaxableIncome, b.minIncome, b.maxIncome)) {
      match = b;
      break;
    }
  }
  match ??= table.brackets.last;
  final excess = annualTaxableIncome - match.minIncome;
  return _round3(match.baseTax + excess * match.excessRate);
}

Decimal calculateWithholdingTax(
  Decimal currentPeriodTaxable,
  Decimal ytdTaxable,
  Decimal ytdTaxWithheld,
  int periodNumber,
  int totalPeriods,
  TaxTableInput table,
) {
  final cumulativeTaxable = ytdTaxable + currentPeriodTaxable;
  final projectedAnnual = _div(cumulativeTaxable, Decimal.fromInt(periodNumber)) *
      Decimal.fromInt(totalPeriods);
  final projectedAnnualTax = calculateAnnualTax(projectedAnnual, table);
  final taxDueToDate =
      _div(projectedAnnualTax, Decimal.fromInt(totalPeriods)) * Decimal.fromInt(periodNumber);
  final currentWithholding = taxDueToDate - ytdTaxWithheld;
  return _max(Decimal.zero, _round3(currentWithholding));
}

ComputedPayslipLine? generateWithholdingTaxLine(
  Decimal currentPeriodTaxable,
  Decimal ytdTaxable,
  Decimal ytdTaxWithheld,
  int periodNumber,
  int totalPeriods,
  TaxTableInput table,
) {
  final tax = calculateWithholdingTax(
    currentPeriodTaxable,
    ytdTaxable,
    ytdTaxWithheld,
    periodNumber,
    totalPeriods,
    table,
  );
  if (tax <= Decimal.zero) return null;
  return ComputedPayslipLine(
    category: PayslipLineCategory.TAX_WITHHOLDING,
    description: 'Withholding Tax',
    amount: tax,
    sortOrder: 1200,
    ruleCode: 'WITHHOLDING_TAX',
    ruleDescription: 'Income Tax Withholding (TRAIN Law)',
  );
}
