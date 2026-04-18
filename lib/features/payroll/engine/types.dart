import 'package:decimal/decimal.dart';

/// Pure engine types. Mirror payrollos/lib/payroll/types.ts.
/// All money-typed fields are Decimal. No Flutter, no I/O.

enum WageType { MONTHLY, DAILY, HOURLY }

enum PayFrequency { MONTHLY, SEMI_MONTHLY, BI_WEEKLY, WEEKLY }

enum DayType {
  WORKDAY,
  REST_DAY,
  REGULAR_HOLIDAY,
  SPECIAL_HOLIDAY,
  SPECIAL_WORKING,
}

enum PayslipLineCategory {
  BASIC_PAY,
  OVERTIME_REGULAR,
  OVERTIME_REST_DAY,
  OVERTIME_HOLIDAY,
  NIGHT_DIFFERENTIAL,
  HOLIDAY_PAY,
  REST_DAY_PAY,
  ALLOWANCE,
  REIMBURSEMENT,
  INCENTIVE,
  BONUS,
  ADJUSTMENT_ADD,
  LATE_DEDUCTION,
  UNDERTIME_DEDUCTION,
  LATE_UT_DEDUCTION,
  ABSENT_DEDUCTION,
  SSS_EE,
  SSS_ER,
  PHILHEALTH_EE,
  PHILHEALTH_ER,
  PAGIBIG_EE,
  PAGIBIG_ER,
  TAX_WITHHOLDING,
  /// Year-end annualization refund (BIR RR 11-2018). Emitted ONLY on the
  /// final payroll of the year when YTD withholding exceeds true annual tax.
  /// Positive amount — rendered on the earnings side so Net Pay goes up by
  /// the refund value.
  TAX_REFUND,
  CASH_ADVANCE_DEDUCTION,
  LOAN_DEDUCTION,
  ADJUSTMENT_DEDUCT,
  OTHER_DEDUCTION,
  PENALTY_DEDUCTION,
}

enum EmploymentType { REGULAR, PROBATIONARY, CONTRACTUAL, CONSULTANT, INTERN }

class PayProfileInput {
  final String employeeId;
  final WageType wageType;
  final Decimal baseRate;
  final PayFrequency payFrequency;
  final int standardWorkDaysPerMonth;
  final int standardHoursPerDay;

  final bool isBenefitsEligible;
  final bool isOtEligible;
  final bool isNdEligible;

  final Decimal riceSubsidy;
  final Decimal clothingAllowance;
  final Decimal laundryAllowance;
  final Decimal medicalAllowance;
  final Decimal transportationAllowance;
  final Decimal mealAllowance;
  final Decimal communicationAllowance;

  const PayProfileInput({
    required this.employeeId,
    required this.wageType,
    required this.baseRate,
    required this.payFrequency,
    required this.standardWorkDaysPerMonth,
    required this.standardHoursPerDay,
    required this.isBenefitsEligible,
    required this.isOtEligible,
    required this.isNdEligible,
    required this.riceSubsidy,
    required this.clothingAllowance,
    required this.laundryAllowance,
    required this.medicalAllowance,
    required this.transportationAllowance,
    required this.mealAllowance,
    required this.communicationAllowance,
  });
}

class AttendanceDayInput {
  final String id;
  final DateTime attendanceDate;
  final DayType dayType;
  final String? holidayName;

  // Minute counts are fractional so that seconds-level clock precision
  // survives the payroll computation (a 09:00:45 clock-in = 0.75 min late,
  // not "0 min"). All display code rounds to 3 decimals via
  // `.toStringAsFixed(3)`.
  final double workedMinutes;
  final double deductionMinutes;
  final double absentMinutes;

  final double otMinutes;
  final double otEarlyInMinutes;
  final double otLateOutMinutes;
  final double overtimeRestDayMinutes;
  final double overtimeHolidayMinutes;

  final bool earlyInApproved;
  final bool lateOutApproved;

  final double nightDiffMinutes;

  final Decimal? holidayMultiplier;
  final Decimal? restDayMultiplier;

  final bool isOnLeave;
  final bool leaveIsPaid;
  final Decimal? leaveHours;

  final Decimal? dailyRateOverride;

  const AttendanceDayInput({
    required this.id,
    required this.attendanceDate,
    required this.dayType,
    this.holidayName,
    required this.workedMinutes,
    required this.deductionMinutes,
    required this.absentMinutes,
    required this.otMinutes,
    required this.otEarlyInMinutes,
    required this.otLateOutMinutes,
    required this.overtimeRestDayMinutes,
    required this.overtimeHolidayMinutes,
    required this.earlyInApproved,
    required this.lateOutApproved,
    required this.nightDiffMinutes,
    this.holidayMultiplier,
    this.restDayMultiplier,
    required this.isOnLeave,
    required this.leaveIsPaid,
    this.leaveHours,
    this.dailyRateOverride,
  });
}

class ComputedPayslipLine {
  final PayslipLineCategory category;
  final String description;
  final Decimal? quantity;
  final Decimal? rate;
  final Decimal? multiplier;
  final Decimal amount;
  final int sortOrder;

  final String? attendanceDayRecordId;
  final String? manualAdjustmentId;
  final String? penaltyInstallmentId;
  final String? cashAdvanceId;
  final String? reimbursementId;

  final String? ruleCode;
  final String? ruleDescription;

  const ComputedPayslipLine({
    required this.category,
    required this.description,
    this.quantity,
    this.rate,
    this.multiplier,
    required this.amount,
    required this.sortOrder,
    this.attendanceDayRecordId,
    this.manualAdjustmentId,
    this.penaltyInstallmentId,
    this.cashAdvanceId,
    this.reimbursementId,
    this.ruleCode,
    this.ruleDescription,
  });

  Map<String, dynamic> toJson() => {
        'category': category.name,
        'description': description,
        if (quantity != null) 'quantity': quantity.toString(),
        if (rate != null) 'rate': rate.toString(),
        if (multiplier != null) 'multiplier': multiplier.toString(),
        'amount': amount.toString(),
        'sortOrder': sortOrder,
        if (attendanceDayRecordId != null) 'attendanceDayRecordId': attendanceDayRecordId,
        if (manualAdjustmentId != null) 'manualAdjustmentId': manualAdjustmentId,
        if (penaltyInstallmentId != null) 'penaltyInstallmentId': penaltyInstallmentId,
        if (cashAdvanceId != null) 'cashAdvanceId': cashAdvanceId,
        if (reimbursementId != null) 'reimbursementId': reimbursementId,
        if (ruleCode != null) 'ruleCode': ruleCode,
        if (ruleDescription != null) 'ruleDescription': ruleDescription,
      };
}

class ComputedPayslip {
  final String employeeId;
  final List<ComputedPayslipLine> lines;

  final Decimal grossPay;
  final Decimal totalEarnings;
  final Decimal totalDeductions;
  final Decimal netPay;

  final Decimal sssEe;
  final Decimal sssEr;
  final Decimal philhealthEe;
  final Decimal philhealthEr;
  final Decimal pagibigEe;
  final Decimal pagibigEr;
  final Decimal withholdingTax;

  final Decimal ytdGrossPay;
  final Decimal ytdTaxableIncome;
  final Decimal ytdTaxWithheld;

  final PayProfileInput payProfileSnapshot;

  const ComputedPayslip({
    required this.employeeId,
    required this.lines,
    required this.grossPay,
    required this.totalEarnings,
    required this.totalDeductions,
    required this.netPay,
    required this.sssEe,
    required this.sssEr,
    required this.philhealthEe,
    required this.philhealthEr,
    required this.pagibigEe,
    required this.pagibigEr,
    required this.withholdingTax,
    required this.ytdGrossPay,
    required this.ytdTaxableIncome,
    required this.ytdTaxWithheld,
    required this.payProfileSnapshot,
  });
}

class ManualAdjustment {
  final String? id;
  final String employeeId;
  final String type; // "EARNING" | "DEDUCTION"
  final PayslipLineCategory category;
  final String description;
  final Decimal amount;
  final String? remarks;

  const ManualAdjustment({
    this.id,
    required this.employeeId,
    required this.type,
    required this.category,
    required this.description,
    required this.amount,
    this.remarks,
  });
}

class SSSBracket {
  final Decimal minSalary;
  final Decimal? maxSalary; // null = Infinity
  final Decimal regularSsEe;
  final Decimal regularSsEr;
  final Decimal ecEr;
  final Decimal mpfEe;
  final Decimal mpfEr;

  const SSSBracket({
    required this.minSalary,
    required this.maxSalary,
    required this.regularSsEe,
    required this.regularSsEr,
    required this.ecEr,
    required this.mpfEe,
    required this.mpfEr,
  });
}

class SSSTableInput {
  final DateTime effectiveDate;
  final List<SSSBracket> brackets;
  const SSSTableInput({required this.effectiveDate, required this.brackets});
}

class PhilHealthTableInput {
  final DateTime effectiveDate;
  final Decimal premiumRate;
  final Decimal minBase;
  final Decimal maxBase;
  final Decimal eeShare;
  const PhilHealthTableInput({
    required this.effectiveDate,
    required this.premiumRate,
    required this.minBase,
    required this.maxBase,
    required this.eeShare,
  });
}

class PagIBIGTableInput {
  final DateTime effectiveDate;
  final Decimal eeRate;
  final Decimal erRate;
  final Decimal maxBase;
  const PagIBIGTableInput({
    required this.effectiveDate,
    required this.eeRate,
    required this.erRate,
    required this.maxBase,
  });
}

class TaxBracket {
  final Decimal minIncome;
  final Decimal? maxIncome; // null = Infinity
  final Decimal baseTax;
  final Decimal excessRate;
  const TaxBracket({
    required this.minIncome,
    required this.maxIncome,
    required this.baseTax,
    required this.excessRate,
  });
}

class TaxTableInput {
  final DateTime effectiveDate;
  final List<TaxBracket> brackets;
  const TaxTableInput({required this.effectiveDate, required this.brackets});
}

class RulesetInput {
  final String id;
  final int version;
  final SSSTableInput? sssTable;
  final PhilHealthTableInput? philhealthTable;
  final PagIBIGTableInput? pagibigTable;
  final TaxTableInput? taxTable;

  const RulesetInput({
    required this.id,
    required this.version,
    this.sssTable,
    this.philhealthTable,
    this.pagibigTable,
    this.taxTable,
  });
}

class EmployeeRegularizationInput {
  final String employeeId;
  final EmploymentType employmentType;
  final DateTime? regularizationDate;
  final DateTime hireDate;

  const EmployeeRegularizationInput({
    required this.employeeId,
    required this.employmentType,
    this.regularizationDate,
    required this.hireDate,
  });
}

class PayPeriodInput {
  final String id;
  final DateTime startDate;
  final DateTime endDate;
  final DateTime cutoffDate;
  final DateTime payDate;
  final int periodNumber;
  final PayFrequency payFrequency;

  const PayPeriodInput({
    required this.id,
    required this.startDate,
    required this.endDate,
    required this.cutoffDate,
    required this.payDate,
    required this.periodNumber,
    required this.payFrequency,
  });
}

class PreviousYtd {
  final Decimal grossPay;
  final Decimal taxableIncome;
  final Decimal taxWithheld;
  /// Number of prior RELEASED payslips for this employee in the same year.
  /// Drives the tax period number (`priorPeriodCount + 1`) so the projected-
  /// annual calculation divides cumulative taxable income by the correct
  /// number of completed periods — independent of the calendar start day,
  /// which is ambiguous when payrolls run on non-BIR-aligned schedules
  /// (e.g. 15-30 instead of 16-31).
  final int priorPeriodCount;
  const PreviousYtd({
    required this.grossPay,
    required this.taxableIncome,
    required this.taxWithheld,
    this.priorPeriodCount = 0,
  });
}

class ReimbursementInput {
  final String id;
  final Decimal amount;
  final String description;
  const ReimbursementInput({required this.id, required this.amount, required this.description});
}

class CashAdvanceDeduction {
  final String id;
  final Decimal amount;
  const CashAdvanceDeduction({required this.id, required this.amount});
}

class OrIncentive {
  final String id;
  final Decimal amount;
  final String description;
  const OrIncentive({required this.id, required this.amount, required this.description});
}

class EmployeeComputationInput {
  final PayProfileInput profile;
  final EmployeeRegularizationInput regularization;
  final List<AttendanceDayInput> attendance;
  final List<ManualAdjustment> manualAdjustments;
  final List<ReimbursementInput> reimbursements;
  final List<CashAdvanceDeduction> cashAdvanceDeductions;
  final List<OrIncentive> orIncentives;
  final PreviousYtd previousYtd;

  const EmployeeComputationInput({
    required this.profile,
    required this.regularization,
    required this.attendance,
    required this.manualAdjustments,
    required this.reimbursements,
    required this.cashAdvanceDeductions,
    required this.orIncentives,
    required this.previousYtd,
  });
}

class StatutoryOverride {
  final Decimal baseRate;
  final WageType wageType;
  const StatutoryOverride({required this.baseRate, required this.wageType});
}

class PenaltyDeduction {
  final String installmentId;
  final String penaltyId;
  final String description;
  final Decimal amount;
  const PenaltyDeduction({
    required this.installmentId,
    required this.penaltyId,
    required this.description,
    required this.amount,
  });
}

class CashAdvanceDeductionLine {
  final String cashAdvanceId;
  final String description;
  final Decimal amount;
  const CashAdvanceDeductionLine({
    required this.cashAdvanceId,
    required this.description,
    required this.amount,
  });
}

class EmployeePayrollInput {
  final PayProfileInput profile;
  final EmployeeRegularizationInput regularization;
  final List<AttendanceDayInput> attendance;
  final List<ManualAdjustment> manualAdjustments;
  final List<ReimbursementInput> reimbursements;
  final List<OrIncentive> orIncentives;
  final List<CashAdvanceDeductionLine> cashAdvanceDeductions;
  final PreviousYtd previousYtd;
  final StatutoryOverride? statutoryOverride;
  final bool taxOnFullEarnings;
  final List<PenaltyDeduction> penaltyDeductions;

  const EmployeePayrollInput({
    required this.profile,
    required this.regularization,
    required this.attendance,
    this.manualAdjustments = const [],
    this.reimbursements = const [],
    this.orIncentives = const [],
    this.cashAdvanceDeductions = const [],
    required this.previousYtd,
    this.statutoryOverride,
    this.taxOnFullEarnings = false,
    this.penaltyDeductions = const [],
  });
}

class PayrollComputationTotals {
  final Decimal grossPay;
  final Decimal totalEarnings;
  final Decimal totalDeductions;
  final Decimal netPay;
  final Decimal sssEeTotal;
  final Decimal sssErTotal;
  final Decimal philhealthEeTotal;
  final Decimal philhealthErTotal;
  final Decimal pagibigEeTotal;
  final Decimal pagibigErTotal;
  final Decimal withholdingTaxTotal;

  const PayrollComputationTotals({
    required this.grossPay,
    required this.totalEarnings,
    required this.totalDeductions,
    required this.netPay,
    required this.sssEeTotal,
    required this.sssErTotal,
    required this.philhealthEeTotal,
    required this.philhealthErTotal,
    required this.pagibigEeTotal,
    required this.pagibigErTotal,
    required this.withholdingTaxTotal,
  });
}

class PayrollComputationError {
  final String employeeId;
  final String error;
  const PayrollComputationError({required this.employeeId, required this.error});
}

class PayrollComputationResult {
  final List<ComputedPayslip> payslips;
  final PayrollComputationTotals totals;
  final int employeeCount;
  final List<PayrollComputationError> errors;

  const PayrollComputationResult({
    required this.payslips,
    required this.totals,
    required this.employeeCount,
    required this.errors,
  });
}

class PayrollComputationContext {
  final PayPeriodInput payPeriod;
  final RulesetInput ruleset;
  final List<EmployeeComputationInput> employees;

  const PayrollComputationContext({
    required this.payPeriod,
    required this.ruleset,
    required this.employees,
  });
}
