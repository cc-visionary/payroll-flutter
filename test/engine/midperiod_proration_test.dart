import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/payroll/engine/compute_engine.dart';
import 'package:payroll_flutter/features/payroll/engine/statutory_tables.dart';
import 'package:payroll_flutter/features/payroll/engine/types.dart';

// Headline end-to-end scenario tests + invariant tests for mid-period
// payroll proration. Fixture helpers copied from
// test/engine/monthly_basic_pay_split_test.dart (engine tests are
// self-contained by convention).

Decimal _d(String s) => Decimal.parse(s);

/// 3-dp rounding helper for the comparison bounds in the headline test.
Decimal _round3ish(Decimal v) => Decimal.parse(v.toStringAsFixed(3));

/// 22 workdays in July 2026; `overrideBefore` is applied to days < `switchDay`.
EmployeePayrollInput _employee({
  required Decimal baseRate,
  Decimal? overrideBefore,
  int switchDay = 17,
}) {
  final profile = PayProfileInput(
    employeeId: 'EMP-001',
    wageType: WageType.MONTHLY,
    baseRate: baseRate,
    payFrequency: PayFrequency.MONTHLY,
    standardWorkDaysPerMonth: 26,
    standardHoursPerDay: 8,
    isBenefitsEligible: true,
    isOtEligible: false,
    isNdEligible: false,
    riceSubsidy: Decimal.zero,
    clothingAllowance: Decimal.zero,
    laundryAllowance: Decimal.zero,
    medicalAllowance: Decimal.zero,
    transportationAllowance: Decimal.zero,
    mealAllowance: Decimal.zero,
    communicationAllowance: Decimal.zero,
  );

  final attendance = <AttendanceDayInput>[];
  for (var day = 1; day <= 22; day++) {
    attendance.add(AttendanceDayInput(
      id: 'A$day',
      attendanceDate: DateTime.utc(2026, 7, day),
      dayType: DayType.WORKDAY,
      workedMinutes: 480,
      deductionMinutes: 0,
      absentMinutes: 0,
      otMinutes: 0,
      otEarlyInMinutes: 0,
      otLateOutMinutes: 0,
      overtimeRestDayMinutes: 0,
      overtimeHolidayMinutes: 0,
      earlyInApproved: false,
      lateOutApproved: false,
      nightDiffMinutes: 0,
      isOnLeave: false,
      leaveIsPaid: false,
      dailyRateOverride: (overrideBefore != null && day < switchDay) ? overrideBefore : null,
    ));
  }

  return EmployeePayrollInput(
    profile: profile,
    regularization: EmployeeRegularizationInput(
      employeeId: 'EMP-001',
      employmentType: EmploymentType.REGULAR,
      hireDate: DateTime.utc(2024, 1, 1),
    ),
    attendance: attendance,
    previousYtd: PreviousYtd(
      grossPay: Decimal.zero,
      taxableIncome: Decimal.zero,
      taxWithheld: Decimal.zero,
    ),
  );
}

PayPeriodInput get _july => PayPeriodInput(
      id: 'PP-7',
      startDate: DateTime.utc(2026, 7, 1),
      endDate: DateTime.utc(2026, 7, 31),
      cutoffDate: DateTime.utc(2026, 7, 31),
      payDate: DateTime.utc(2026, 8, 5),
      periodNumber: 7,
      payFrequency: PayFrequency.MONTHLY,
    );

RulesetInput get _ruleset => RulesetInput(
      id: 'r',
      version: 1,
      sssTable: SSS_TABLE,
      philhealthTable: PHILHEALTH_TABLE,
      pagibigTable: PAGIBIG_TABLE,
      taxTable: TAX_TABLE,
    );

/// Semi-monthly (Jul 16-31) fixture: 14 workdays (16..29). `overrideRate`
/// (when given) is applied to day 16 only; days 17+ use the standard rate.
EmployeePayrollInput _semiMonthlyEmployee({
  required Decimal baseRate,
  Decimal? overrideRate,
}) {
  final profile = PayProfileInput(
    employeeId: 'EMP-002',
    wageType: WageType.MONTHLY,
    baseRate: baseRate,
    payFrequency: PayFrequency.SEMI_MONTHLY,
    standardWorkDaysPerMonth: 26,
    standardHoursPerDay: 8,
    isBenefitsEligible: true,
    isOtEligible: false,
    isNdEligible: false,
    riceSubsidy: Decimal.zero,
    clothingAllowance: Decimal.zero,
    laundryAllowance: Decimal.zero,
    medicalAllowance: Decimal.zero,
    transportationAllowance: Decimal.zero,
    mealAllowance: Decimal.zero,
    communicationAllowance: Decimal.zero,
  );

  final attendance = <AttendanceDayInput>[];
  for (var day = 16; day <= 29; day++) {
    attendance.add(AttendanceDayInput(
      id: 'B$day',
      attendanceDate: DateTime.utc(2026, 7, day),
      dayType: DayType.WORKDAY,
      workedMinutes: 480,
      deductionMinutes: 0,
      absentMinutes: 0,
      otMinutes: 0,
      otEarlyInMinutes: 0,
      otLateOutMinutes: 0,
      overtimeRestDayMinutes: 0,
      overtimeHolidayMinutes: 0,
      earlyInApproved: false,
      lateOutApproved: false,
      nightDiffMinutes: 0,
      isOnLeave: false,
      leaveIsPaid: false,
      dailyRateOverride: (overrideRate != null && day == 16) ? overrideRate : null,
    ));
  }

  return EmployeePayrollInput(
    profile: profile,
    regularization: EmployeeRegularizationInput(
      employeeId: 'EMP-002',
      employmentType: EmploymentType.REGULAR,
      hireDate: DateTime.utc(2024, 1, 1),
    ),
    attendance: attendance,
    previousYtd: PreviousYtd(
      grossPay: Decimal.zero,
      taxableIncome: Decimal.zero,
      taxWithheld: Decimal.zero,
    ),
  );
}

PayPeriodInput get _julySecondHalf => PayPeriodInput(
      id: 'PP-7B',
      startDate: DateTime.utc(2026, 7, 16),
      endDate: DateTime.utc(2026, 7, 31),
      cutoffDate: DateTime.utc(2026, 7, 31),
      payDate: DateTime.utc(2026, 8, 5),
      periodNumber: 14,
      payFrequency: PayFrequency.SEMI_MONTHLY,
    );

void main() {
  test('HEADLINE: ₱30k -> ₱38k effective Jul 17 pro-rates a Jul 1-31 monthly run', () {
    final oldRate =
        (_d('30000') / Decimal.fromInt(26)).toDecimal(scaleOnInfinitePrecision: 10);
    final slip = computePayroll(
      _july,
      _ruleset,
      [_employee(baseRate: _d('38000'), overrideBefore: oldRate, switchDay: 17)],
    ).payslips.single;

    final basic = slip.lines
        .where((l) => l.category == PayslipLineCategory.BASIC_PAY)
        .toList();

    // Two lines: 16 days at the old rate, 6 at the new.
    expect(basic, hasLength(2));
    expect(basic[0].quantity, Decimal.fromInt(16));
    expect(basic[1].quantity, Decimal.fromInt(6));

    // Old rate strictly below the new rate.
    expect(basic[0].rate! < basic[1].rate!, isTrue);

    // Total is strictly between "all 22 days at the old rate" and "all 22
    // days at the new rate".
    final total = basic.fold<Decimal>(Decimal.zero, (a, l) => a + l.amount);
    final allOld = _round3ish(oldRate * Decimal.fromInt(22));
    final newRate =
        (_d('38000') / Decimal.fromInt(26)).toDecimal(scaleOnInfinitePrecision: 10);
    final allNew = _round3ish(newRate * Decimal.fromInt(22));
    expect(total > allOld, isTrue);
    expect(total < allNew, isTrue);
  });

  test('INVARIANT 2: no per-day overrides -> basic pay is exactly rate x workDays', () {
    // Do NOT compare two identical runs — that asserts nothing. Assert the
    // concrete pre-existing formula still holds for a single build with no
    // overrides at all.
    final slip = computePayroll(_july, _ruleset, [_employee(baseRate: _d('30000'))])
        .payslips
        .single;
    final basic = slip.lines
        .where((l) => l.category == PayslipLineCategory.BASIC_PAY)
        .toList();

    expect(basic, hasLength(1));
    expect(basic.single.description, 'Basic Pay (Monthly)');
    expect(basic.single.quantity, isNull);
    expect(basic.single.rate, isNull);

    // wage_calculator _round3's the standard daily rate: 30000/26 -> 1153.846.
    // The engine sums that rate over 22 workdays.
    final dailyRate = _d('1153.846');
    expect(basic.single.amount, dailyRate * Decimal.fromInt(22));
  });

  test('ENGINE honors a per-day override on every day', () {
    // NOTE: manual-vs-compensation PRECEDENCE lives in compute_service's `??=`
    // and is not unit-testable here (Supabase-row mapper; repo convention).
    // This test asserts only what the ENGINE guarantees: whatever
    // dailyRateOverride it is handed drives that day's rate.
    final manual = _d('999');
    final slip = computePayroll(
      _july,
      _ruleset,
      [_employee(baseRate: _d('30000'), overrideBefore: manual, switchDay: 23)],
    ).payslips.single;
    final basic = slip.lines
        .where((l) => l.category == PayslipLineCategory.BASIC_PAY)
        .toList();

    // All 22 days overridden to 999 -> one group at the overridden rate,
    // NOT the 1153.846 standard rate.
    expect(basic, hasLength(1));
    expect(basic.single.amount, manual * Decimal.fromInt(22));
  });

  test('SEMI-MONTHLY: Jul 16-31 period splits a single-day override from the rest', () {
    final oldRate =
        (_d('30000') / Decimal.fromInt(26)).toDecimal(scaleOnInfinitePrecision: 10);
    final slip = computePayroll(
      _julySecondHalf,
      _ruleset,
      [_semiMonthlyEmployee(baseRate: _d('38000'), overrideRate: oldRate)],
    ).payslips.single;

    final basic = slip.lines
        .where((l) => l.category == PayslipLineCategory.BASIC_PAY)
        .toList();

    // 14 workdays total (Jul 16-29): 1 at the old rate (day 16), 13 at the
    // standard/new rate (days 17-29).
    expect(basic, hasLength(2));
    expect(basic[0].quantity, Decimal.fromInt(1));
    expect(basic[0].description, 'Basic Pay (Semi-Monthly) — 1 day');
    expect(basic[1].quantity, Decimal.fromInt(13));
    expect(basic[1].description, 'Basic Pay (Semi-Monthly) — 13 days');
  });
}
