import 'package:decimal/decimal.dart';
import 'types.dart';
import 'wage_calculator.dart';
import 'statutory_calculator.dart';
import 'statutory_tables.dart';
import 'payslip_generator.dart';

/// Main payroll computation orchestrator.
/// Ported verbatim from payrollos/lib/payroll/compute-engine.ts.

Decimal _round3(Decimal v) {
  final factor = Decimal.fromInt(1000);
  return ((v * factor).round(scale: 0) / factor).toDecimal(scaleOnInfinitePrecision: 3);
}

Decimal _fromInt(int i) => Decimal.fromInt(i);
Decimal _fromDouble(double v) => Decimal.parse(v.toString());
Decimal _div(Decimal a, Decimal b) => (a / b).toDecimal(scaleOnInfinitePrecision: 10);
Decimal _max(Decimal a, Decimal b) => a >= b ? a : b;
Decimal _min(Decimal a, Decimal b) => a <= b ? a : b;

String _toFixed3(int v) => v.toStringAsFixed(3);
String _toFixed3d(Decimal v) {
  final f = Decimal.fromInt(1000);
  final rounded = ((v * f).round(scale: 0) / f).toDecimal(scaleOnInfinitePrecision: 3);
  final parts = rounded.toString().split('.');
  if (parts.length == 1) return '${parts[0]}.000';
  final frac = parts[1].padRight(3, '0').substring(0, 3);
  return '${parts[0]}.$frac';
}

// =============================================================================
// Public entry points
// =============================================================================

PayrollComputationResult computePayroll(
  PayPeriodInput payPeriod,
  RulesetInput ruleset,
  List<EmployeePayrollInput> employees,
) {
  final payslips = <ComputedPayslip>[];
  final errors = <PayrollComputationError>[];

  for (final employee in employees) {
    try {
      final ps = computeEmployeePayslip(payPeriod, ruleset, employee);
      payslips.add(ps);
    } catch (e) {
      errors.add(PayrollComputationError(
        employeeId: employee.profile.employeeId,
        error: e.toString(),
      ));
    }
  }

  Decimal sumField(Decimal Function(ComputedPayslip) f) =>
      payslips.fold(Decimal.zero, (acc, p) => acc + f(p));

  final totals = PayrollComputationTotals(
    grossPay: sumField((p) => p.grossPay),
    totalEarnings: sumField((p) => p.totalEarnings),
    totalDeductions: sumField((p) => p.totalDeductions),
    netPay: sumField((p) => p.netPay),
    sssEeTotal: sumField((p) => p.sssEe),
    sssErTotal: sumField((p) => p.sssEr),
    philhealthEeTotal: sumField((p) => p.philhealthEe),
    philhealthErTotal: sumField((p) => p.philhealthEr),
    pagibigEeTotal: sumField((p) => p.pagibigEe),
    pagibigErTotal: sumField((p) => p.pagibigEr),
    withholdingTaxTotal: sumField((p) => p.withholdingTax),
  );

  return PayrollComputationResult(
    payslips: payslips,
    totals: totals,
    employeeCount: payslips.length,
    errors: errors,
  );
}

ComputedPayslip computeEmployeePayslip(
  PayPeriodInput payPeriod,
  RulesetInput ruleset,
  EmployeePayrollInput employee,
) {
  final profile = employee.profile;
  final regularization = employee.regularization;
  final attendance = employee.attendance;
  final lines = <ComputedPayslipLine>[];

  // 1. Derived rates
  final rates = calculateDerivedRates(profile);
  final standardMinutesPerDay = profile.standardHoursPerDay * 60;
  final periodsPerMonth = _getPeriodsPerMonth(payPeriod.payFrequency);

  final hpd = profile.standardHoursPerDay;

  // 2. Work-day attendance
  final workDayAttendance = attendance.where((a) {
    if (a.isOnLeave && a.leaveIsPaid && profile.wageType == WageType.MONTHLY) return true;
    if (a.workedMinutes > 0 &&
        a.dayType != DayType.REGULAR_HOLIDAY &&
        a.dayType != DayType.SPECIAL_HOLIDAY &&
        a.dayType != DayType.REST_DAY) {
      return true;
    }
    return false;
  }).toList();
  final workDays = workDayAttendance.length;

  // 3. Basic pay lines
  if (profile.wageType == WageType.MONTHLY) {
    Decimal basicPayTotal = Decimal.zero;
    for (final day in workDayAttendance) {
      final dayRates = getDayRates(rates, hpd, day.dailyRateOverride);
      basicPayTotal += dayRates.dailyRate;
    }
    basicPayTotal = _round3(basicPayTotal);
    lines.add(ComputedPayslipLine(
      category: PayslipLineCategory.BASIC_PAY,
      description: payPeriod.payFrequency == PayFrequency.SEMI_MONTHLY
          ? 'Basic Pay (Semi-Monthly)'
          : 'Basic Pay (Monthly)',
      amount: basicPayTotal,
      sortOrder: 100,
      ruleCode: 'BASIC_PAY',
    ));
  } else {
    // Group by effective daily rate
    final rateGroups = <String, _RateGroup>{};
    for (final day in workDayAttendance) {
      final dayRates = getDayRates(rates, hpd, day.dailyRateOverride);
      final key = dayRates.dailyRate.toString();
      final g = rateGroups[key] ?? _RateGroup(dayRates.dailyRate, 0);
      rateGroups[key] = _RateGroup(dayRates.dailyRate, g.count + 1);
    }
    for (final g in rateGroups.values) {
      final qty = g.count.toDouble();
      lines.add(ComputedPayslipLine(
        category: PayslipLineCategory.BASIC_PAY,
        description:
            'Basic Pay (${qty.toStringAsFixed(3)} day${g.count != 1 ? 's' : ''})',
        quantity: _fromDouble(qty),
        rate: g.rate,
        amount: _round3(g.rate * _fromDouble(qty)),
        sortOrder: 100,
        ruleCode: 'BASIC_PAY',
      ));
    }
  }

  // 4. Deductions (late/UT only)
  //
  // Absent days are NOT deducted as a separate line. Step 2 / 3 above already
  // exclude them from `workDayAttendance`, so Basic Pay = daysPresent × rate
  // naturally reflects the reduction. Producing an ABSENT_DEDUCTION line on
  // top would double-charge the employee for every missed day.
  // Late/UT vs OT netting rule (per user 2026-04):
  //   If an employee is late but also worked OT the same day, the OT minutes
  //   first absorb the late minutes before either is counted. Effectively:
  //     effectiveOt   = max(0, otMinutes - lateMinutes)
  //     effectiveLate = max(0, lateMinutes - otMinutes)
  //   This prevents double-charging an employee who made up the late time
  //   by working overtime. We compute the net values per-day and use them
  //   downstream for both the LATE_UT_DEDUCTION line and the OT lines.
  final nettedLatePerDay = <String, double>{};
  final nettedOtPerDay = <String, double>{};
  for (final day in attendance) {
    if (day.dayType != DayType.WORKDAY) continue;
    final lateRaw = day.deductionMinutes;
    final otRaw = day.otMinutes;
    if (lateRaw <= 0 && otRaw <= 0) continue;
    final netLate = (lateRaw - otRaw).clamp(0.0, double.infinity);
    final netOt = (otRaw - lateRaw).clamp(0.0, double.infinity);
    nettedLatePerDay[day.id] = netLate;
    nettedOtPerDay[day.id] = netOt;
  }

  double totalDeductionMinutes = 0;
  Decimal lateUtDeductionAmount = Decimal.zero;

  for (final day in attendance) {
    if (day.dayType != DayType.WORKDAY) continue;
    final dayRates = getDayRates(rates, hpd, day.dailyRateOverride);
    final netLate = nettedLatePerDay[day.id] ?? day.deductionMinutes;
    if (netLate > 0) {
      totalDeductionMinutes += netLate;
      lateUtDeductionAmount += dayRates.minuteRate * _fromDouble(netLate);
    }
  }

  if (totalDeductionMinutes > 0) {
    lateUtDeductionAmount = _round3(lateUtDeductionAmount);
    lines.add(ComputedPayslipLine(
      category: PayslipLineCategory.LATE_UT_DEDUCTION,
      description:
          'Late/Undertime Deduction (${totalDeductionMinutes.toStringAsFixed(3)} mins)',
      quantity: _fromDouble(totalDeductionMinutes),
      rate: rates.minuteRate,
      amount: lateUtDeductionAmount,
      sortOrder: 1015,
      ruleCode: 'LATE_UT_DEDUCT',
    ));
  }

  // 5. Overtime — uses the netted OT minutes (late time absorbed first).
  if (profile.isOtEligible) {
    lines.addAll(_generateOvertimeLines(
      attendance,
      rates,
      standardMinutesPerDay,
      hpd,
      nettedOtPerDay: nettedOtPerDay,
    ));
  }

  // 6. Night differential
  if (profile.isNdEligible) {
    double totalNdMinutes = 0;
    Decimal totalNdAmount = Decimal.zero;
    for (final day in attendance) {
      if (day.nightDiffMinutes > 0) {
        final dayRates = getDayRates(rates, hpd, day.dailyRateOverride);
        totalNdMinutes += day.nightDiffMinutes;
        totalNdAmount += dayRates.hourlyRate *
            _div(_fromDouble(day.nightDiffMinutes), _fromInt(60)) *
            PhMultipliers.NIGHT_DIFF;
      }
    }
    if (totalNdMinutes > 0) {
      totalNdAmount = _round3(totalNdAmount);
      lines.add(ComputedPayslipLine(
        category: PayslipLineCategory.NIGHT_DIFFERENTIAL,
        description:
            'Night Differential (${totalNdMinutes.toStringAsFixed(3)} mins @ 10%)',
        quantity: _fromDouble(totalNdMinutes),
        rate: rates.minuteRate,
        multiplier: PhMultipliers.NIGHT_DIFF,
        amount: totalNdAmount,
        sortOrder: 300,
        ruleCode: 'NIGHT_DIFF',
        ruleDescription: 'Night Differential (10%)',
      ));
    }
  }

  // 7. Holiday and rest day premiums
  lines.addAll(generateHolidayPremiumLines(attendance, rates, standardMinutesPerDay,
      standardHoursPerDay: hpd));
  final restDayLine = generateRestDayPremiumLine(attendance, rates, standardHoursPerDay: hpd);
  if (restDayLine != null) lines.add(restDayLine);

  // 8. Allowances
  lines.addAll(generateAllowanceLines(profile, periodsPerMonth));

  // 9. Manual adjustments
  lines.addAll(generateManualAdjustmentLines(employee.manualAdjustments));

  // 10. Penalty deductions
  for (final p in employee.penaltyDeductions) {
    lines.add(ComputedPayslipLine(
      category: PayslipLineCategory.PENALTY_DEDUCTION,
      description: p.description,
      amount: p.amount,
      sortOrder: 1350,
      penaltyInstallmentId: p.installmentId,
      ruleCode: 'PENALTY_DEDUCTION',
      ruleDescription: 'Penalty installment deduction',
    ));
  }

  // 11. Cash advance deductions
  for (final ca in employee.cashAdvanceDeductions) {
    lines.add(ComputedPayslipLine(
      category: PayslipLineCategory.CASH_ADVANCE_DEDUCTION,
      description: ca.description,
      amount: ca.amount,
      sortOrder: 1300,
      cashAdvanceId: ca.cashAdvanceId,
      ruleCode: 'CASH_ADVANCE',
      ruleDescription: 'Cash advance deduction from Lark approval',
    ));
  }

  // 12. Reimbursements
  for (final r in employee.reimbursements) {
    lines.add(ComputedPayslipLine(
      category: PayslipLineCategory.REIMBURSEMENT,
      description: r.description,
      amount: r.amount,
      sortOrder: 500,
      reimbursementId: r.id,
      ruleCode: 'REIMBURSEMENT',
      ruleDescription: 'Reimbursement from Lark approval',
    ));
  }

  // 13. Statutory deductions
  Decimal sssEe = Decimal.zero;
  Decimal sssEr = Decimal.zero;
  Decimal philhealthEe = Decimal.zero;
  Decimal philhealthEr = Decimal.zero;
  Decimal pagibigEe = Decimal.zero;
  Decimal pagibigEr = Decimal.zero;
  Decimal currentPeriodTaxable = Decimal.zero;

  final isStatutoryEligible = isEligibleForStatutory(
    regularization,
    payPeriod,
    profile.isBenefitsEligible,
  );

  if (isStatutoryEligible) {
    final sssTable = ruleset.sssTable ?? SSS_TABLE;
    final philhealthTable = ruleset.philhealthTable ?? PHILHEALTH_TABLE;
    final pagibigTable = ruleset.pagibigTable ?? PAGIBIG_TABLE;

    Decimal monthlyGross = rates.msc;
    if (employee.statutoryOverride != null) {
      final o = employee.statutoryOverride!;
      final workDaysPerMonth = profile.standardWorkDaysPerMonth;
      final hoursPerDay = profile.standardHoursPerDay;
      Decimal statutoryDailyRate;
      switch (o.wageType) {
        case WageType.DAILY:
          statutoryDailyRate = o.baseRate;
          break;
        case WageType.HOURLY:
          statutoryDailyRate = o.baseRate * _fromInt(hoursPerDay);
          break;
        case WageType.MONTHLY:
          statutoryDailyRate = _div(o.baseRate, _fromInt(workDaysPerMonth));
          break;
      }
      monthlyGross = statutoryDailyRate * _fromInt(26);
    }

    final sssLines = generateSSSLines(monthlyGross, sssTable, periodsPerMonth);
    lines.add(sssLines.eeLine);
    sssEe = sssLines.eeLine.amount;
    sssEr = sssLines.erLine.amount;

    final philhealthLines = generatePhilHealthLines(monthlyGross, philhealthTable, periodsPerMonth);
    lines.add(philhealthLines.eeLine);
    philhealthEe = philhealthLines.eeLine.amount;
    philhealthEr = philhealthLines.erLine.amount;

    final pagibigLines = generatePagIBIGLines(monthlyGross, pagibigTable, periodsPerMonth);
    lines.add(pagibigLines.eeLine);
    pagibigEe = pagibigLines.eeLine.amount;
    pagibigEr = pagibigLines.erLine.amount;
  }

  // 14. Withholding tax
  Decimal withholdingTax = Decimal.zero;

  if (isStatutoryEligible) {
    final taxTable = ruleset.taxTable ?? TAX_TABLE;

    // Compute the basic-pay portion of the tax base. The declared wage
    // override (when set) ALWAYS replaces the scorecard rate for tax —
    // override is the BIR-declared salary, not a per-period actual.
    Decimal taxBasicPay;
    Decimal taxLateUtDeduction;
    {
      final workDaysPerMonth = profile.standardWorkDaysPerMonth;
      final hoursPerDay = profile.standardHoursPerDay;
      Decimal taxDailyRate;
      Decimal taxMinuteRate;
      if (employee.statutoryOverride != null) {
        final o = employee.statutoryOverride!;
        switch (o.wageType) {
          case WageType.DAILY:
            taxDailyRate = o.baseRate;
            break;
          case WageType.HOURLY:
            taxDailyRate = o.baseRate * _fromInt(hoursPerDay);
            break;
          case WageType.MONTHLY:
            taxDailyRate = _div(o.baseRate, _fromInt(workDaysPerMonth));
            break;
        }
        taxMinuteRate = _div(taxDailyRate, _fromInt(hoursPerDay * 60));
      } else {
        taxDailyRate = rates.dailyRate;
        taxMinuteRate = rates.minuteRate;
      }
      taxBasicPay = _round3(taxDailyRate * _fromInt(workDays));
      taxLateUtDeduction =
          _round3(taxMinuteRate * _fromDouble(totalDeductionMinutes));
    }

    if (employee.taxOnFullEarnings) {
      // GROSS PAY mode: tax base = (override or scorecard) basic pay
      // - late/UT + OT + holiday + ND - statutory.
      // Commissions, bonuses, adjustments, allowances, and reimbursements
      // are excluded by policy.
      final extras = lines
          .where((l) => _grossPayExtraTaxableCategories.contains(l.category))
          .fold(Decimal.zero, (acc, l) => acc + l.amount);
      final taxBase = taxBasicPay - taxLateUtDeduction + extras;
      currentPeriodTaxable = _max(
        Decimal.zero,
        taxBase - sssEe - philhealthEe - pagibigEe,
      );
    } else {
      // BASIC PAY ONLY mode: tax base = basic pay - late/UT - statutory.
      // Excludes OT, holiday, ND, commissions, adjustments — by design.
      final taxBase = taxBasicPay - taxLateUtDeduction;
      currentPeriodTaxable = _max(
        Decimal.zero,
        taxBase - sssEe - philhealthEe - pagibigEe,
      );
    }

    final totalPeriodsPerYear =
        (periodsPerMonth * Decimal.fromInt(12)).toBigInt().toInt();

    // Period number for the withholding-tax projection. Counting the actual
    // released payslips for this employee this year is the only reliable
    // signal — calendar-day heuristics break when pay periods don't match
    // BIR's 1-15 / 16-end split (e.g. a company running 15-30 would see
    // both halves map to "period 1", doubling the projected annual and
    // inflating tax).
    final taxPeriodNumber = employee.previousYtd.priorPeriodCount + 1;

    // BIR RR 11-2018 §2.79(B)(1): the last payroll of the year is an
    // ANNUALISATION — employer re-computes against actual cumulative
    // taxable income (no more projection) and trues up over/under
    // withholding as a refund or catch-up. We trigger this when the pay
    // period ends in December AND the current period completes the
    // expected cycle for the year. Off-cycle December bonus runs that
    // push the count beyond the schedule fall through to normal
    // cumulative math.
    final isYearEndAnnualization = payPeriod.endDate.month == 12 &&
        taxPeriodNumber == totalPeriodsPerYear;

    if (isYearEndAnnualization) {
      final actualAnnualTaxable =
          employee.previousYtd.taxableIncome + currentPeriodTaxable;
      final annualTaxOwed = calculateAnnualTax(actualAnnualTaxable, taxTable);
      final alreadyWithheld = employee.previousYtd.taxWithheld;
      final diff = _round3(annualTaxOwed - alreadyWithheld);

      if (diff > Decimal.zero) {
        // Under-withheld YTD → take the shortfall this period.
        lines.add(ComputedPayslipLine(
          category: PayslipLineCategory.TAX_WITHHOLDING,
          description: 'Withholding Tax (Year-End Adjustment)',
          amount: diff,
          sortOrder: 1200,
          ruleCode: 'WITHHOLDING_TAX_ANNUALIZATION',
          ruleDescription:
              'Year-end annualisation (BIR RR 11-2018) — shortfall from projected vs actual annual tax',
        ));
        withholdingTax = diff;
      } else if (diff < Decimal.zero) {
        // Over-withheld YTD → refund on the earnings side.
        final refundAmount = _round3(-diff);
        lines.add(ComputedPayslipLine(
          category: PayslipLineCategory.TAX_REFUND,
          description: 'Tax Refund (Year-End Annualization)',
          amount: refundAmount,
          sortOrder: 350,
          ruleCode: 'TAX_REFUND_ANNUALIZATION',
          ruleDescription:
              'Year-end annualisation (BIR RR 11-2018) — refund of projected over-withholding',
        ));
        // Net withholding for this period is negative — cumulative YTD
        // tax withheld accumulator on the payslip subtracts the refund.
        withholdingTax = diff;
      }
      // diff == 0 → perfect projection, no line emitted.
    } else {
      final taxLine = generateWithholdingTaxLine(
        currentPeriodTaxable,
        employee.previousYtd.taxableIncome,
        employee.previousYtd.taxWithheld,
        taxPeriodNumber,
        totalPeriodsPerYear,
        taxTable,
      );

      if (taxLine != null) {
        lines.add(taxLine);
        withholdingTax = taxLine.amount;
      }
    }
  }

  // Sort lines by sortOrder
  lines.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  final totalEarnings = _sumEarnings(lines);
  final totalDeductions = _sumDeductions(lines);
  final grossPay = totalEarnings;
  final netPay = _round3(totalEarnings - totalDeductions);

  final ytdGrossPay = employee.previousYtd.grossPay + grossPay;
  final ytdTaxableIncome = employee.previousYtd.taxableIncome + currentPeriodTaxable;
  final ytdTaxWithheld = employee.previousYtd.taxWithheld + withholdingTax;

  return ComputedPayslip(
    employeeId: profile.employeeId,
    lines: lines,
    grossPay: grossPay,
    totalEarnings: totalEarnings,
    totalDeductions: totalDeductions,
    netPay: netPay,
    sssEe: sssEe,
    sssEr: sssEr,
    philhealthEe: philhealthEe,
    philhealthEr: philhealthEr,
    pagibigEe: pagibigEe,
    pagibigEr: pagibigEr,
    withholdingTax: withholdingTax,
    ytdGrossPay: ytdGrossPay,
    ytdTaxableIncome: ytdTaxableIncome,
    ytdTaxWithheld: ytdTaxWithheld,
    payProfileSnapshot: profile,
  );
}

// =============================================================================
// Helpers
// =============================================================================

class _RateGroup {
  final Decimal rate;
  final int count;
  const _RateGroup(this.rate, this.count);
}

List<ComputedPayslipLine> _generateOvertimeLines(
  List<AttendanceDayInput> attendance,
  DerivedRates rates,
  int standardMinutesPerDay,
  int standardHoursPerDay, {
  Map<String, double>? nettedOtPerDay,
}) {
  final lines = <ComputedPayslipLine>[];

  double regularOtMinutes = 0;
  Decimal regularOtAmount = Decimal.zero;
  double restDayOtMinutes = 0;
  Decimal restDayOtAmount = Decimal.zero;
  double regularHolidayOtMinutes = 0;
  Decimal regularHolidayOtAmount = Decimal.zero;
  double specialHolidayOtMinutes = 0;
  Decimal specialHolidayOtAmount = Decimal.zero;

  for (final a in attendance) {
    if (a.workedMinutes <= 0) continue;
    final dayRates = getDayRates(rates, standardHoursPerDay, a.dailyRateOverride);

    if (a.dayType == DayType.WORKDAY) {
      // Use the late-vs-OT-netted minutes when provided (workday OT only —
      // late time happens on workdays). Falls back to the raw approved OT
      // when no netting map is supplied (e.g., pure-engine tests).
      final ot = nettedOtPerDay?[a.id] ?? a.otMinutes;
      if (ot > 0) {
        regularOtMinutes += ot;
        regularOtAmount += dayRates.hourlyRate *
            _div(_fromDouble(ot), _fromInt(60)) *
            PhMultipliers.OT_REGULAR;
      }
    } else if (a.dayType == DayType.REST_DAY) {
      // Rest-day OT must be explicitly approved (manual flags or Lark's
      // approved_ot_minutes routed by compute_service). Clocking past
      // 8 hours on a rest day does NOT automatically pay OT — admin must
      // approve it via the edit dialog's Early-In / Late-Out toggles.
      // Mirrors AttendanceRowVm.overtimeMinutes (UI) so the timeline and
      // payslip agree.
      final ot = a.overtimeRestDayMinutes;
      if (ot > 0) {
        restDayOtMinutes += ot;
        restDayOtAmount += dayRates.hourlyRate *
            _div(_fromDouble(ot), _fromInt(60)) *
            PhMultipliers.REST_DAY_OT;
      }
    } else if (a.dayType == DayType.REGULAR_HOLIDAY) {
      // Regular-holiday OT requires explicit approval (same policy as
      // rest-day and regular workday OT). No auto-derivation from
      // workedMinutes > 8h — admin must toggle Early-In / Late-Out, or
      // the OT must be pre-approved in Lark.
      double ot = a.overtimeHolidayMinutes;
      if (ot <= 0) ot = a.otMinutes;
      if (ot > 0) {
        regularHolidayOtMinutes += ot;
        regularHolidayOtAmount += dayRates.hourlyRate *
            _div(_fromDouble(ot), _fromInt(60)) *
            PhMultipliers.REGULAR_HOLIDAY_OT;
      }
    } else if (a.dayType == DayType.SPECIAL_HOLIDAY) {
      // Same approval policy as regular holiday.
      double ot = a.overtimeHolidayMinutes;
      if (ot <= 0) ot = a.otMinutes;
      if (ot > 0) {
        specialHolidayOtMinutes += ot;
        specialHolidayOtAmount += dayRates.hourlyRate *
            _div(_fromDouble(ot), _fromInt(60)) *
            PhMultipliers.SPECIAL_HOLIDAY_OT;
      }
    }
  }

  if (regularOtMinutes > 0) {
    lines.add(ComputedPayslipLine(
      category: PayslipLineCategory.OVERTIME_REGULAR,
      description:
          'Regular Overtime (${regularOtMinutes.toStringAsFixed(3)} mins @ 125%)',
      quantity: _fromDouble(regularOtMinutes),
      rate: rates.minuteRate,
      multiplier: PhMultipliers.OT_REGULAR,
      amount: _round3(regularOtAmount),
      sortOrder: 200,
      ruleCode: 'OT_REGULAR',
      ruleDescription: 'Regular Day Overtime (125%)',
    ));
  }
  if (restDayOtMinutes > 0) {
    lines.add(ComputedPayslipLine(
      category: PayslipLineCategory.OVERTIME_REST_DAY,
      description:
          'Rest Day Overtime (${restDayOtMinutes.toStringAsFixed(3)} mins @ 169%)',
      quantity: _fromDouble(restDayOtMinutes),
      rate: rates.minuteRate,
      multiplier: PhMultipliers.REST_DAY_OT,
      amount: _round3(restDayOtAmount),
      sortOrder: 210,
      ruleCode: 'OT_REST_DAY',
      ruleDescription: 'Rest Day Overtime (169%)',
    ));
  }
  if (regularHolidayOtMinutes > 0) {
    lines.add(ComputedPayslipLine(
      category: PayslipLineCategory.OVERTIME_HOLIDAY,
      description:
          'Regular Holiday OT (${regularHolidayOtMinutes.toStringAsFixed(3)} mins @ 260%)',
      quantity: _fromDouble(regularHolidayOtMinutes),
      rate: rates.minuteRate,
      multiplier: PhMultipliers.REGULAR_HOLIDAY_OT,
      amount: _round3(regularHolidayOtAmount),
      sortOrder: 220,
      ruleCode: 'OT_REGULAR_HOLIDAY',
      ruleDescription: 'Regular Holiday Overtime (260%)',
    ));
  }
  if (specialHolidayOtMinutes > 0) {
    lines.add(ComputedPayslipLine(
      category: PayslipLineCategory.OVERTIME_HOLIDAY,
      description:
          'Special Holiday OT (${specialHolidayOtMinutes.toStringAsFixed(3)} mins @ 169%)',
      quantity: _fromDouble(specialHolidayOtMinutes),
      rate: rates.minuteRate,
      multiplier: PhMultipliers.SPECIAL_HOLIDAY_OT,
      amount: _round3(specialHolidayOtAmount),
      sortOrder: 220,
      ruleCode: 'OT_SPECIAL_HOLIDAY',
      ruleDescription: 'Special Holiday Overtime (169%)',
    ));
  }

  return lines;
}

const _earningCategories = <PayslipLineCategory>{
  PayslipLineCategory.BASIC_PAY,
  PayslipLineCategory.OVERTIME_REGULAR,
  PayslipLineCategory.OVERTIME_REST_DAY,
  PayslipLineCategory.OVERTIME_HOLIDAY,
  PayslipLineCategory.NIGHT_DIFFERENTIAL,
  PayslipLineCategory.HOLIDAY_PAY,
  PayslipLineCategory.REST_DAY_PAY,
  PayslipLineCategory.ALLOWANCE,
  PayslipLineCategory.REIMBURSEMENT,
  PayslipLineCategory.INCENTIVE,
  PayslipLineCategory.BONUS,
  PayslipLineCategory.ADJUSTMENT_ADD,
  PayslipLineCategory.TAX_REFUND,
};

/// Categories added on top of (override-derived) basic pay when computing the
/// GROSS_PAY-mode withholding-tax base. Excludes BASIC_PAY itself — that
/// portion is recomputed from the override rate × workDays so the BIR-declared
/// wage is the basis, not the actual payslip basic-pay line.
/// Excludes commissions (INCENTIVE), bonuses, adjustments, allowances, and
/// reimbursements by policy.
const _grossPayExtraTaxableCategories = <PayslipLineCategory>{
  PayslipLineCategory.OVERTIME_REGULAR,
  PayslipLineCategory.OVERTIME_REST_DAY,
  PayslipLineCategory.OVERTIME_HOLIDAY,
  PayslipLineCategory.NIGHT_DIFFERENTIAL,
  PayslipLineCategory.HOLIDAY_PAY,
  PayslipLineCategory.REST_DAY_PAY,
};

const _deductionCategories = <PayslipLineCategory>{
  PayslipLineCategory.LATE_DEDUCTION,
  PayslipLineCategory.UNDERTIME_DEDUCTION,
  PayslipLineCategory.LATE_UT_DEDUCTION,
  PayslipLineCategory.ABSENT_DEDUCTION,
  PayslipLineCategory.SSS_EE,
  PayslipLineCategory.PHILHEALTH_EE,
  PayslipLineCategory.PAGIBIG_EE,
  PayslipLineCategory.TAX_WITHHOLDING,
  PayslipLineCategory.CASH_ADVANCE_DEDUCTION,
  PayslipLineCategory.LOAN_DEDUCTION,
  PayslipLineCategory.PENALTY_DEDUCTION,
  PayslipLineCategory.ADJUSTMENT_DEDUCT,
  PayslipLineCategory.OTHER_DEDUCTION,
};

Decimal _sumEarnings(List<ComputedPayslipLine> lines) => lines
    .where((l) => _earningCategories.contains(l.category))
    .fold(Decimal.zero, (acc, l) => acc + l.amount);

Decimal _sumDeductions(List<ComputedPayslipLine> lines) => lines
    .where((l) => _deductionCategories.contains(l.category))
    .fold(Decimal.zero, (acc, l) => acc + l.amount);

Decimal _getPeriodsPerMonth(PayFrequency payFrequency) {
  switch (payFrequency) {
    case PayFrequency.MONTHLY:
      return Decimal.one;
    case PayFrequency.SEMI_MONTHLY:
      return Decimal.fromInt(2);
    case PayFrequency.BI_WEEKLY:
      return Decimal.parse('2.17');
    case PayFrequency.WEEKLY:
      return Decimal.parse('4.33');
  }
}


extension _DecimalToDouble on Decimal {
  double toDouble() => double.parse(toString());
}
