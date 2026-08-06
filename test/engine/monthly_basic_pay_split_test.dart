import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/payroll/engine/compute_engine.dart';
import 'package:payroll_flutter/features/payroll/engine/statutory_tables.dart';
import 'package:payroll_flutter/features/payroll/engine/types.dart';

Decimal _d(String s) => Decimal.parse(s);

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
    attendance.add(
      AttendanceDayInput(
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
        dailyRateOverride: (overrideBefore != null && day < switchDay)
            ? overrideBefore
            : null,
      ),
    );
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

List<ComputedPayslipLine> _basicPayLines(EmployeePayrollInput emp) {
  final result = computePayroll(_july, _ruleset, [emp]);
  return result.payslips.single.lines
      .where((l) => l.category == PayslipLineCategory.BASIC_PAY)
      .toList();
}

void main() {
  test('single rate -> one line, no quantity/rate (invariant 4)', () {
    final lines = _basicPayLines(_employee(baseRate: _d('30000')));
    expect(lines, hasLength(1));
    expect(lines.single.description, 'Basic Pay (Monthly)');
    expect(lines.single.quantity, isNull);
    expect(lines.single.rate, isNull);
  });

  test(
    'two rates -> two lines, old rate first, summing to the per-day total',
    () {
      // Standard = 38000/26; days 1..16 overridden to 30000/26.
      final oldRate = (_d('30000') / Decimal.fromInt(26)).toDecimal(
        scaleOnInfinitePrecision: 10,
      );
      final lines = _basicPayLines(
        _employee(
          baseRate: _d('38000'),
          overrideBefore: oldRate,
          switchDay: 17,
        ),
      );

      expect(lines, hasLength(2));
      // First-occurrence order: the overridden (old) rate is day 1.
      expect(lines[0].quantity, Decimal.fromInt(16));
      expect(lines[1].quantity, Decimal.fromInt(6));
      expect(lines[0].description, 'Basic Pay (Monthly) — 16 days');
      expect(lines[1].description, 'Basic Pay (Monthly) — 6 days');
      // Old rate strictly below the new rate.
      expect(lines[0].rate! < lines[1].rate!, isTrue);

      final total = lines.fold<Decimal>(Decimal.zero, (a, l) => a + l.amount);
      final expected =
          lines[0].rate! * Decimal.fromInt(16) +
          lines[1].rate! * Decimal.fromInt(6);
      expect(total, expected);
    },
  );
}
