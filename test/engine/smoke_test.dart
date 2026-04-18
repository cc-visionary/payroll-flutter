import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/payroll/engine/compute_engine.dart';
import 'package:payroll_flutter/features/payroll/engine/statutory_tables.dart';
import 'package:payroll_flutter/features/payroll/engine/types.dart';

Decimal _d(String s) => Decimal.parse(s);

void main() {
  test('engine: regular monthly employee, no OT, no ND, full month worked', () {
    // ₱30,000/month monthly employee, semi-monthly, 12 work days in the period
    final profile = PayProfileInput(
      employeeId: 'EMP-001',
      wageType: WageType.MONTHLY,
      baseRate: _d('30000'),
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

    final payPeriod = PayPeriodInput(
      id: 'PP-1',
      startDate: DateTime.utc(2026, 1, 1),
      endDate: DateTime.utc(2026, 1, 15),
      cutoffDate: DateTime.utc(2026, 1, 15),
      payDate: DateTime.utc(2026, 1, 20),
      periodNumber: 1,
      payFrequency: PayFrequency.SEMI_MONTHLY,
    );

    final ruleset = RulesetInput(
      id: 'R-2026',
      version: 1,
      sssTable: SSS_TABLE,
      philhealthTable: PHILHEALTH_TABLE,
      pagibigTable: PAGIBIG_TABLE,
      taxTable: TAX_TABLE,
    );

    final attendance = <AttendanceDayInput>[];
    for (var day = 1; day <= 15; day++) {
      final date = DateTime.utc(2026, 1, day);
      final weekday = date.weekday; // 1..7
      final isWeekend = weekday == 6 || weekday == 7;
      attendance.add(AttendanceDayInput(
        id: 'ATT-$day',
        attendanceDate: date,
        dayType: isWeekend ? DayType.REST_DAY : DayType.WORKDAY,
        workedMinutes: isWeekend ? 0 : 480,
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
      ));
    }

    final employee = EmployeePayrollInput(
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

    final result = computePayroll(payPeriod, ruleset, [employee]);

    expect(result.errors, isEmpty);
    expect(result.payslips.length, 1);
    final ps = result.payslips.first;

    // Basic pay: 11 workdays × 1153.846 (30000/26 rounded to 3dp) = 12,692.306
    final basic = ps.lines.firstWhere((l) => l.category == PayslipLineCategory.BASIC_PAY);
    expect(basic.amount, _d('12692.306'));

    // SSS, PhilHealth, Pag-IBIG should be present
    expect(
      ps.lines.where((l) => l.category == PayslipLineCategory.SSS_EE).length,
      1,
    );
    expect(
      ps.lines.where((l) => l.category == PayslipLineCategory.PHILHEALTH_EE).length,
      1,
    );
    expect(
      ps.lines.where((l) => l.category == PayslipLineCategory.PAGIBIG_EE).length,
      1,
    );

    // Net pay > 0
    expect(ps.netPay > Decimal.zero, isTrue);
  });

  test('engine: probationary employee → no statutory deductions', () {
    final profile = PayProfileInput(
      employeeId: 'EMP-002',
      wageType: WageType.MONTHLY,
      baseRate: _d('25000'),
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

    final payPeriod = PayPeriodInput(
      id: 'PP-1',
      startDate: DateTime.utc(2026, 1, 1),
      endDate: DateTime.utc(2026, 1, 15),
      cutoffDate: DateTime.utc(2026, 1, 15),
      payDate: DateTime.utc(2026, 1, 20),
      periodNumber: 1,
      payFrequency: PayFrequency.SEMI_MONTHLY,
    );

    final ruleset = RulesetInput(
      id: 'R-2026',
      version: 1,
      sssTable: SSS_TABLE,
      philhealthTable: PHILHEALTH_TABLE,
      pagibigTable: PAGIBIG_TABLE,
      taxTable: TAX_TABLE,
    );

    final attendance = <AttendanceDayInput>[
      AttendanceDayInput(
        id: 'ATT-1',
        attendanceDate: DateTime.utc(2026, 1, 5),
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
      ),
    ];

    final employee = EmployeePayrollInput(
      profile: profile,
      regularization: EmployeeRegularizationInput(
        employeeId: 'EMP-002',
        employmentType: EmploymentType.PROBATIONARY,
        hireDate: DateTime.utc(2026, 1, 1),
        // no regularizationDate
      ),
      attendance: attendance,
      previousYtd: PreviousYtd(
        grossPay: Decimal.zero,
        taxableIncome: Decimal.zero,
        taxWithheld: Decimal.zero,
      ),
    );

    final result = computePayroll(payPeriod, ruleset, [employee]);
    expect(result.errors, isEmpty);
    final ps = result.payslips.first;

    // No statutory deductions for probationary
    expect(ps.sssEe, Decimal.zero);
    expect(ps.philhealthEe, Decimal.zero);
    expect(ps.pagibigEe, Decimal.zero);
    expect(ps.withholdingTax, Decimal.zero);
  });
}
