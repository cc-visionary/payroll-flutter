import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/payroll/engine/compute_engine.dart';
import 'package:payroll_flutter/features/payroll/engine/statutory_tables.dart';
import 'package:payroll_flutter/features/payroll/engine/types.dart';

Decimal _d(String s) => Decimal.parse(s);

PayPeriodInput _payPeriod() => PayPeriodInput(
      id: 'PP-1',
      startDate: DateTime.utc(2026, 1, 1),
      endDate: DateTime.utc(2026, 1, 15),
      cutoffDate: DateTime.utc(2026, 1, 15),
      payDate: DateTime.utc(2026, 1, 20),
      periodNumber: 1,
      payFrequency: PayFrequency.SEMI_MONTHLY,
    );

RulesetInput _ruleset() => RulesetInput(
      id: 'R-2026',
      version: 1,
      sssTable: SSS_TABLE,
      philhealthTable: PHILHEALTH_TABLE,
      pagibigTable: PAGIBIG_TABLE,
      taxTable: TAX_TABLE,
    );

PayProfileInput _probationaryProfile({
  bool sssOverride = false,
  bool philhealthOverride = false,
  bool pagibigOverride = false,
}) =>
    PayProfileInput(
      employeeId: 'EMP-OVR',
      wageType: WageType.MONTHLY,
      baseRate: _d('25000'),
      payFrequency: PayFrequency.SEMI_MONTHLY,
      standardWorkDaysPerMonth: 26,
      standardHoursPerDay: 8,
      isBenefitsEligible: true,
      isOtEligible: false,
      isNdEligible: false,
      sssEligibilityOverride: sssOverride,
      philhealthEligibilityOverride: philhealthOverride,
      pagibigEligibilityOverride: pagibigOverride,
      riceSubsidy: Decimal.zero,
      clothingAllowance: Decimal.zero,
      laundryAllowance: Decimal.zero,
      medicalAllowance: Decimal.zero,
      transportationAllowance: Decimal.zero,
      mealAllowance: Decimal.zero,
      communicationAllowance: Decimal.zero,
    );

List<AttendanceDayInput> _attendance() => [
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

EmployeePayrollInput _probationaryEmployee(PayProfileInput profile) =>
    EmployeePayrollInput(
      profile: profile,
      regularization: EmployeeRegularizationInput(
        employeeId: profile.employeeId,
        employmentType: EmploymentType.PROBATIONARY,
        hireDate: DateTime.utc(2026, 1, 1),
        // No regularizationDate set — still on probation during pay period.
      ),
      attendance: _attendance(),
      previousYtd: PreviousYtd(
        grossPay: Decimal.zero,
        taxableIncome: Decimal.zero,
        taxWithheld: Decimal.zero,
      ),
    );

void main() {
  group('engine: per-benefit eligibility overrides', () {
    test(
      'baseline (all overrides false) → probationary employee has no statutory deductions',
      () {
        final profile = _probationaryProfile();
        final result = computePayroll(
          _payPeriod(),
          _ruleset(),
          [_probationaryEmployee(profile)],
        );

        expect(result.errors, isEmpty);
        final ps = result.payslips.first;

        // No statutory lines — current behaviour unchanged.
        expect(
          ps.lines.where((l) => l.category == PayslipLineCategory.SSS_EE),
          isEmpty,
        );
        expect(
          ps.lines.where((l) => l.category == PayslipLineCategory.PHILHEALTH_EE),
          isEmpty,
        );
        expect(
          ps.lines.where((l) => l.category == PayslipLineCategory.PAGIBIG_EE),
          isEmpty,
        );
        expect(ps.sssEe, Decimal.zero);
        expect(ps.philhealthEe, Decimal.zero);
        expect(ps.pagibigEe, Decimal.zero);
        // Tax block is also gated on base eligibility — unchanged.
        expect(ps.withholdingTax, Decimal.zero);
      },
    );

    test(
      'SSS override only → SSS_EE line present; PhilHealth and Pag-IBIG absent',
      () {
        final profile = _probationaryProfile(sssOverride: true);
        final result = computePayroll(
          _payPeriod(),
          _ruleset(),
          [_probationaryEmployee(profile)],
        );

        expect(result.errors, isEmpty);
        final ps = result.payslips.first;

        // SSS_EE present.
        final sssLines = ps.lines
            .where((l) => l.category == PayslipLineCategory.SSS_EE)
            .toList();
        expect(sssLines.length, 1);
        expect(sssLines.first.amount > Decimal.zero, isTrue);
        expect(ps.sssEe > Decimal.zero, isTrue);
        expect(ps.sssEr > Decimal.zero, isTrue);

        // PhilHealth and Pag-IBIG NOT enrolled.
        expect(
          ps.lines.where((l) => l.category == PayslipLineCategory.PHILHEALTH_EE),
          isEmpty,
        );
        expect(
          ps.lines.where((l) => l.category == PayslipLineCategory.PAGIBIG_EE),
          isEmpty,
        );
        expect(ps.philhealthEe, Decimal.zero);
        expect(ps.pagibigEe, Decimal.zero);

        // Withholding-tax block stays gated on the BASE eligibility —
        // overrides are per statutory benefit only, never tax.
        expect(ps.withholdingTax, Decimal.zero);
      },
    );
  });
}
