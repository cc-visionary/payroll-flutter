import 'package:decimal/decimal.dart';
import 'types.dart';
import 'wage_calculator.dart';

/// Payslip line generators — ported from payrollos/lib/payroll/payslip-generator.ts.

class _SortOrder {
  static const int BASIC_PAY = 100;
  static const int REGULAR_HOLIDAY_PAY = 110;
  static const int SPECIAL_HOLIDAY_PAY = 120;
  static const int REST_DAY_PAY = 130;
  static const int OVERTIME_REGULAR = 200;
  static const int OVERTIME_REST_DAY = 210;
  static const int OVERTIME_HOLIDAY = 220;
  static const int NIGHT_DIFFERENTIAL = 300;
  static const int ALLOWANCE = 400;
  static const int REIMBURSEMENT = 500;
  static const int INCENTIVE = 600;
  static const int BONUS = 700;
  static const int ADJUSTMENT_ADD = 800;
  static const int LATE_DEDUCTION = 1000;
  static const int UNDERTIME_DEDUCTION = 1010;
  static const int LATE_UT_DEDUCTION = 1015;
  static const int ABSENT_DEDUCTION = 1020;
  static const int SSS_EE = 1100;
  static const int PHILHEALTH_EE = 1110;
  static const int PAGIBIG_EE = 1120;
  static const int TAX_WITHHOLDING = 1200;
  static const int CASH_ADVANCE_DEDUCTION = 1300;
  static const int LOAN_DEDUCTION = 1310;
  static const int PENALTY_DEDUCTION = 1350;
  static const int ADJUSTMENT_DEDUCT = 1400;
  static const int OTHER_DEDUCTION = 1500;
}

Decimal _round3(Decimal v) {
  final factor = Decimal.fromInt(1000);
  return ((v * factor).round(scale: 0) / factor).toDecimal(scaleOnInfinitePrecision: 3);
}

Decimal _fromInt(int i) => Decimal.fromInt(i);
Decimal _fromDouble(double v) => Decimal.parse(v.toString());
Decimal _div(Decimal a, Decimal b) => (a / b).toDecimal(scaleOnInfinitePrecision: 10);

String _toFixed3(num v) => v.toStringAsFixed(3);
String _toFixed3d(Decimal v) {
  final f = Decimal.fromInt(1000);
  final rounded = ((v * f).round(scale: 0) / f).toDecimal(scaleOnInfinitePrecision: 3);
  final parts = rounded.toString().split('.');
  if (parts.length == 1) return '${parts[0]}.000';
  final frac = parts[1].padRight(3, '0').substring(0, 3);
  return '${parts[0]}.$frac';
}

// =============================================================================
// Basic Pay
// =============================================================================
ComputedPayslipLine generateBasicPayLine(
  PayProfileInput profile,
  DerivedRates rates,
  int workDays,
  PayFrequency payFrequency,
) {
  final amount = calculateBasicPay(profile, rates, workDays, payFrequency);

  String description;
  Decimal? quantity;
  Decimal? rate;

  if (profile.wageType == WageType.MONTHLY) {
    description = payFrequency == PayFrequency.SEMI_MONTHLY
        ? 'Basic Pay (Semi-Monthly)'
        : 'Basic Pay (Monthly)';
  } else {
    description = 'Basic Pay ($workDays days)';
    quantity = _fromInt(workDays);
    rate = rates.dailyRate;
  }

  return ComputedPayslipLine(
    category: PayslipLineCategory.BASIC_PAY,
    description: description,
    quantity: quantity,
    rate: rate,
    amount: amount,
    sortOrder: _SortOrder.BASIC_PAY,
    ruleCode: 'BASIC_PAY',
  );
}

// =============================================================================
// Deductions
// =============================================================================
ComputedPayslipLine? generateLateDeductionLine(int totalLateMinutes, DerivedRates rates) {
  if (totalLateMinutes <= 0) return null;
  final amount = calculateLateDeduction(totalLateMinutes, rates);
  final hours = _round3(_div(_fromInt(totalLateMinutes), _fromInt(60)));
  return ComputedPayslipLine(
    category: PayslipLineCategory.LATE_DEDUCTION,
    description: 'Late Deduction ($hours hrs)',
    quantity: hours,
    rate: rates.hourlyRate,
    amount: amount,
    sortOrder: _SortOrder.LATE_DEDUCTION,
    ruleCode: 'LATE_DEDUCT',
  );
}

ComputedPayslipLine? generateUndertimeDeductionLine(int totalUndertimeMinutes, DerivedRates rates) {
  if (totalUndertimeMinutes <= 0) return null;
  final amount = calculateUndertimeDeduction(totalUndertimeMinutes, rates);
  final hours = _round3(_div(_fromInt(totalUndertimeMinutes), _fromInt(60)));
  return ComputedPayslipLine(
    category: PayslipLineCategory.UNDERTIME_DEDUCTION,
    description: 'Undertime Deduction ($hours hrs)',
    quantity: hours,
    rate: rates.hourlyRate,
    amount: amount,
    sortOrder: _SortOrder.UNDERTIME_DEDUCTION,
    ruleCode: 'UNDERTIME_DEDUCT',
  );
}

ComputedPayslipLine? generateLateUtDeductionLine(
  int totalLateMinutes,
  int totalUndertimeMinutes,
  DerivedRates rates,
) {
  final totalMinutes = totalLateMinutes + totalUndertimeMinutes;
  if (totalMinutes <= 0) return null;
  final amount = _round3(rates.minuteRate * _fromInt(totalMinutes));
  return ComputedPayslipLine(
    category: PayslipLineCategory.LATE_UT_DEDUCTION,
    description: 'Late/Undertime Deduction (${_toFixed3(totalMinutes)} mins)',
    quantity: _fromInt(totalMinutes),
    rate: rates.minuteRate,
    amount: amount,
    sortOrder: _SortOrder.LATE_UT_DEDUCTION,
    ruleCode: 'LATE_UT_DEDUCT',
  );
}

ComputedPayslipLine? generateAbsentDeductionLine(
  int totalAbsentMinutes,
  DerivedRates rates,
  int standardMinutesPerDay,
) {
  if (totalAbsentMinutes <= 0) return null;
  final amount = calculateAbsentDeduction(totalAbsentMinutes, rates, standardMinutesPerDay);
  final days = _round3(_div(_fromInt(totalAbsentMinutes), _fromInt(standardMinutesPerDay)));
  return ComputedPayslipLine(
    category: PayslipLineCategory.ABSENT_DEDUCTION,
    description: 'Absent Deduction (${_toFixed3d(days)} days)',
    quantity: days,
    rate: rates.dailyRate,
    amount: amount,
    sortOrder: _SortOrder.ABSENT_DEDUCTION,
    ruleCode: 'ABSENT_DEDUCT',
  );
}

// =============================================================================
// Overtime
// =============================================================================
ComputedPayslipLine? generateRegularOvertimeLine(
  int totalOtMinutes,
  DerivedRates rates,
  List<String> attendanceRecordIds,
) {
  if (totalOtMinutes <= 0) return null;
  final amount = calculateOvertimePay(totalOtMinutes, rates, PhMultipliers.OT_REGULAR);
  return ComputedPayslipLine(
    category: PayslipLineCategory.OVERTIME_REGULAR,
    description: 'Regular Overtime (${_toFixed3(totalOtMinutes)} mins @ 125%)',
    quantity: _fromInt(totalOtMinutes),
    rate: rates.minuteRate,
    multiplier: PhMultipliers.OT_REGULAR,
    amount: amount,
    sortOrder: _SortOrder.OVERTIME_REGULAR,
    ruleCode: 'OT_REGULAR',
    ruleDescription: 'Regular Day Overtime (125%)',
  );
}

ComputedPayslipLine? generateRestDayOvertimeLine(int totalOtMinutes, DerivedRates rates) {
  if (totalOtMinutes <= 0) return null;
  final amount = calculateOvertimePay(totalOtMinutes, rates, PhMultipliers.REST_DAY_OT);
  return ComputedPayslipLine(
    category: PayslipLineCategory.OVERTIME_REST_DAY,
    description: 'Rest Day Overtime (${_toFixed3(totalOtMinutes)} mins @ 169%)',
    quantity: _fromInt(totalOtMinutes),
    rate: rates.minuteRate,
    multiplier: PhMultipliers.REST_DAY_OT,
    amount: amount,
    sortOrder: _SortOrder.OVERTIME_REST_DAY,
    ruleCode: 'OT_REST_DAY',
    ruleDescription: 'Rest Day Overtime (169%)',
  );
}

ComputedPayslipLine? generateHolidayOvertimeLine(
  int totalOtMinutes,
  DerivedRates rates,
  String holidayType, // "REGULAR" | "SPECIAL"
) {
  if (totalOtMinutes <= 0) return null;
  final multiplier = holidayType == 'REGULAR'
      ? PhMultipliers.REGULAR_HOLIDAY_OT
      : PhMultipliers.SPECIAL_HOLIDAY_OT;
  final amount = calculateOvertimePay(totalOtMinutes, rates, multiplier);
  final pct = (multiplier * Decimal.fromInt(100)).round(scale: 0).toBigInt().toInt();
  final label = holidayType == 'REGULAR' ? 'Regular' : 'Special';
  return ComputedPayslipLine(
    category: PayslipLineCategory.OVERTIME_HOLIDAY,
    description: '$label Holiday OT (${_toFixed3(totalOtMinutes)} mins @ $pct%)',
    quantity: _fromInt(totalOtMinutes),
    rate: rates.minuteRate,
    multiplier: multiplier,
    amount: amount,
    sortOrder: _SortOrder.OVERTIME_HOLIDAY,
    ruleCode: 'OT_${holidayType}_HOLIDAY',
    ruleDescription: '$label Holiday Overtime ($pct%)',
  );
}

// =============================================================================
// Night Differential
// =============================================================================
ComputedPayslipLine? generateNightDiffLine(int totalNdMinutes, DerivedRates rates) {
  if (totalNdMinutes <= 0) return null;
  final amount = calculateNightDiffPay(totalNdMinutes, rates, PhMultipliers.NIGHT_DIFF);
  return ComputedPayslipLine(
    category: PayslipLineCategory.NIGHT_DIFFERENTIAL,
    description: 'Night Differential (${_toFixed3(totalNdMinutes)} mins @ 10%)',
    quantity: _fromInt(totalNdMinutes),
    rate: rates.minuteRate,
    multiplier: PhMultipliers.NIGHT_DIFF,
    amount: amount,
    sortOrder: _SortOrder.NIGHT_DIFFERENTIAL,
    ruleCode: 'NIGHT_DIFF',
    ruleDescription: 'Night Differential (10%)',
  );
}

// =============================================================================
// Holiday & Rest Day premiums
// =============================================================================
List<ComputedPayslipLine> generateHolidayPremiumLines(
  List<AttendanceDayInput> attendance,
  DerivedRates rates,
  int standardMinutesPerDay, {
  int standardHoursPerDay = 8,
}) {
  final lines = <ComputedPayslipLine>[];
  double _min(double a, double b) => a < b ? a : b;
  final stdMinPerDay = standardMinutesPerDay.toDouble();

  final regularHolidays =
      attendance.where((a) => a.dayType == DayType.REGULAR_HOLIDAY && a.workedMinutes > 0).toList();
  final specialHolidays =
      attendance.where((a) => a.dayType == DayType.SPECIAL_HOLIDAY && a.workedMinutes > 0).toList();
  final unworkedRegularHolidays =
      attendance.where((a) => a.dayType == DayType.REGULAR_HOLIDAY && a.workedMinutes == 0).toList();

  // Regular holiday worked — 200% of regular rate
  if (regularHolidays.isNotEmpty) {
    double totalRegularMinutes = 0;
    Decimal totalAmount = Decimal.zero;
    for (final a in regularHolidays) {
      final dayRates = getDayRates(rates, standardHoursPerDay, a.dailyRateOverride);
      final cappedMinutes = _min(a.workedMinutes, stdMinPerDay);
      totalRegularMinutes += cappedMinutes;
      totalAmount += dayRates.hourlyRate *
          _div(_fromDouble(cappedMinutes), _fromInt(60)) *
          PhMultipliers.REGULAR_HOLIDAY;
    }
    totalAmount = _round3(totalAmount);
    if (totalAmount > Decimal.zero) {
      lines.add(ComputedPayslipLine(
        category: PayslipLineCategory.HOLIDAY_PAY,
        description: 'Regular Holiday Pay (${_toFixed3(totalRegularMinutes)} mins @ 200%)',
        quantity: _fromDouble(totalRegularMinutes),
        rate: rates.minuteRate,
        multiplier: PhMultipliers.REGULAR_HOLIDAY,
        amount: totalAmount,
        sortOrder: _SortOrder.REGULAR_HOLIDAY_PAY,
        ruleCode: 'REGULAR_HOLIDAY_WORKED',
        ruleDescription: 'Regular Holiday Pay (200% of regular rate)',
      ));
    }
  }

  // Special holiday worked — 130% of regular rate
  if (specialHolidays.isNotEmpty) {
    double totalRegularMinutes = 0;
    Decimal totalAmount = Decimal.zero;
    for (final a in specialHolidays) {
      final dayRates = getDayRates(rates, standardHoursPerDay, a.dailyRateOverride);
      final cappedMinutes = _min(a.workedMinutes, stdMinPerDay);
      totalRegularMinutes += cappedMinutes;
      totalAmount += dayRates.hourlyRate *
          _div(_fromDouble(cappedMinutes), _fromInt(60)) *
          PhMultipliers.SPECIAL_HOLIDAY;
    }
    totalAmount = _round3(totalAmount);
    if (totalAmount > Decimal.zero) {
      lines.add(ComputedPayslipLine(
        category: PayslipLineCategory.HOLIDAY_PAY,
        description: 'Special Holiday Pay (${_toFixed3(totalRegularMinutes)} mins @ 130%)',
        quantity: _fromDouble(totalRegularMinutes),
        rate: rates.minuteRate,
        multiplier: PhMultipliers.SPECIAL_HOLIDAY,
        amount: totalAmount,
        sortOrder: _SortOrder.SPECIAL_HOLIDAY_PAY,
        ruleCode: 'SPECIAL_HOLIDAY_WORKED',
        ruleDescription: 'Special Holiday Pay (130% of regular rate)',
      ));
    }
  }

  // Partially worked regular holidays — base pay for unworked portion
  {
    double totalUnworkedMinutes = 0;
    Decimal totalUnworkedAmount = Decimal.zero;
    for (final a in regularHolidays) {
      final cappedMinutes = _min(a.workedMinutes, stdMinPerDay);
      final unworkedMinutes = stdMinPerDay - cappedMinutes;
      if (unworkedMinutes > 0) {
        final dayRates = getDayRates(rates, standardHoursPerDay, a.dailyRateOverride);
        totalUnworkedMinutes += unworkedMinutes;
        totalUnworkedAmount +=
            dayRates.hourlyRate * _div(_fromDouble(unworkedMinutes), _fromInt(60));
      }
    }
    totalUnworkedAmount = _round3(totalUnworkedAmount);
    if (totalUnworkedAmount > Decimal.zero) {
      lines.add(ComputedPayslipLine(
        category: PayslipLineCategory.HOLIDAY_PAY,
        description:
            'Regular Holiday Base Pay - Unworked Hours (${_toFixed3(totalUnworkedMinutes)} mins @ 100%)',
        quantity: _fromDouble(totalUnworkedMinutes),
        rate: rates.minuteRate,
        multiplier: Decimal.parse('1.0'),
        amount: totalUnworkedAmount,
        sortOrder: _SortOrder.REGULAR_HOLIDAY_PAY + 1,
        ruleCode: 'REGULAR_HOLIDAY_PARTIAL_BASE',
        ruleDescription: 'Regular Holiday base pay for unworked portion (paid even if not worked)',
      ));
    }
  }

  // Fully unworked regular holidays
  if (unworkedRegularHolidays.isNotEmpty) {
    final count = unworkedRegularHolidays.length;
    Decimal totalAmount = Decimal.zero;
    for (final a in unworkedRegularHolidays) {
      final dayRates = getDayRates(rates, standardHoursPerDay, a.dailyRateOverride);
      totalAmount += dayRates.dailyRate;
    }
    lines.add(ComputedPayslipLine(
      category: PayslipLineCategory.HOLIDAY_PAY,
      description: 'Regular Holiday Pay - Unworked ($count day${count > 1 ? 's' : ''})',
      quantity: _fromInt(count),
      rate: rates.dailyRate,
      amount: totalAmount,
      sortOrder: _SortOrder.REGULAR_HOLIDAY_PAY + 2,
      ruleCode: 'REGULAR_HOLIDAY_UNWORKED',
      ruleDescription: 'Regular Holiday Pay (paid even if not worked)',
    ));
  }

  return lines;
}

ComputedPayslipLine? generateRestDayPremiumLine(
  List<AttendanceDayInput> attendance,
  DerivedRates rates, {
  int standardHoursPerDay = 8,
}) {
  final restDayRecords =
      attendance.where((a) => a.dayType == DayType.REST_DAY && a.workedMinutes > 0).toList();
  if (restDayRecords.isEmpty) return null;

  double totalMinutes = 0;
  Decimal totalAmount = Decimal.zero;
  for (final a in restDayRecords) {
    final dayRates = getDayRates(rates, standardHoursPerDay, a.dailyRateOverride);
    totalMinutes += a.workedMinutes;
    totalAmount += dayRates.hourlyRate *
        _div(_fromDouble(a.workedMinutes), _fromInt(60)) *
        PhMultipliers.REST_DAY;
  }
  totalAmount = _round3(totalAmount);
  if (totalAmount <= Decimal.zero) return null;

  return ComputedPayslipLine(
    category: PayslipLineCategory.REST_DAY_PAY,
    description: 'Rest Day Pay (${_toFixed3(totalMinutes)} mins @ 130%)',
    quantity: _fromDouble(totalMinutes),
    rate: rates.minuteRate,
    multiplier: PhMultipliers.REST_DAY,
    amount: totalAmount,
    sortOrder: _SortOrder.REST_DAY_PAY,
    ruleCode: 'REST_DAY_PAY',
    ruleDescription: 'Rest Day Pay (130% of regular rate)',
  );
}

// =============================================================================
// Allowances
// =============================================================================
List<ComputedPayslipLine> generateAllowanceLines(
  PayProfileInput profile,
  Decimal periodsPerMonth,
) {
  final lines = <ComputedPayslipLine>[];
  int sortOffset = 0;

  void add(String name, Decimal monthlyAmount) {
    if (monthlyAmount <= Decimal.zero) return;
    final amount = _round3(_div(monthlyAmount, periodsPerMonth));
    lines.add(ComputedPayslipLine(
      category: PayslipLineCategory.ALLOWANCE,
      description: name,
      amount: amount,
      sortOrder: _SortOrder.ALLOWANCE + sortOffset++,
      ruleCode: 'ALLOWANCE_${name.toUpperCase().replaceAll(' ', '_')}',
    ));
  }

  add('Rice Subsidy', profile.riceSubsidy);
  add('Clothing Allowance', profile.clothingAllowance);
  add('Laundry Allowance', profile.laundryAllowance);
  add('Medical Allowance', profile.medicalAllowance);
  add('Transportation Allowance', profile.transportationAllowance);
  add('Meal Allowance', profile.mealAllowance);
  add('Communication Allowance', profile.communicationAllowance);

  return lines;
}

// =============================================================================
// Manual Adjustments
// =============================================================================
List<ComputedPayslipLine> generateManualAdjustmentLines(List<ManualAdjustment> adjustments) {
  return List.generate(adjustments.length, (index) {
    final adj = adjustments[index];
    final isEarning = adj.type == 'EARNING';
    return ComputedPayslipLine(
      category: isEarning ? PayslipLineCategory.ADJUSTMENT_ADD : PayslipLineCategory.ADJUSTMENT_DEDUCT,
      description: adj.description,
      amount: adj.amount,
      sortOrder: (isEarning ? _SortOrder.ADJUSTMENT_ADD : _SortOrder.ADJUSTMENT_DEDUCT) + index,
      manualAdjustmentId: adj.id,
      ruleCode: 'MANUAL_ADJUSTMENT',
    );
  });
}
