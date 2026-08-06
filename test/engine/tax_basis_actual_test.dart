import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/payroll/engine/compute_engine.dart';
import 'package:payroll_flutter/features/payroll/engine/statutory_tables.dart';
import 'package:payroll_flutter/features/payroll/engine/types.dart';

Decimal _d(String s) => Decimal.parse(s);

/// 22 workdays in July 2026; `overrideBefore` is applied to days < `switchDay`.
/// `statutoryOverride` forwards the BIR-declared wage knob (Invariant 1).
EmployeePayrollInput _employee({
  required Decimal baseRate,
  Decimal? overrideBefore,
  int switchDay = 17,
  StatutoryOverride? statutoryOverride,
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
    statutoryOverride: statutoryOverride,
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

ComputedPayslip _run(EmployeePayrollInput emp) =>
    computePayroll(_july, _ruleset, [emp]).payslips.single;

void main() {
  // Days 1..16 carry the OLD (lower) scorecard rate 30000/26; days 17..22 use
  // the standard 38000/26 rate. `flat` shares one rate across all 22 days.
  final oldRate = (_d('30000') / Decimal.fromInt(26)).toDecimal(
    scaleOnInfinitePrecision: 10,
  );

  test(
    'Test A — no override: pro-rated tax uses ACTUAL pay, below the flat run',
    () {
      final prorated = _run(
        _employee(
          baseRate: _d('38000'),
          overrideBefore: oldRate,
          switchDay: 17,
        ),
      );
      final flat = _run(_employee(baseRate: _d('38000')));

      // Non-vacuous: both runs must actually withhold tax at this salary.
      expect(
        prorated.withholdingTax > Decimal.zero,
        isTrue,
        reason: 'pro-rated withholding must be positive (raise salary if not)',
      );
      expect(
        flat.withholdingTax > Decimal.zero,
        isTrue,
        reason: 'flat withholding must be positive (raise salary if not)',
      );

      // The pro-rated run pays less basic pay (early days at the old rate), so
      // its tax basis — and therefore its withholding — is strictly lower.
      // Pre-fix both runs taxed rates.dailyRate * workDays (identical) and this
      // was an equality, so `<` failed (RED).
      expect(
        prorated.withholdingTax < flat.withholdingTax,
        isTrue,
        reason:
            'pro-rated actual pay is lower, so its withholding must be lower',
      );
    },
  );

  test('Test B — statutoryOverride: tax + statutory ignore per-day rates '
      '(hard invariant)', () {
    final override = StatutoryOverride(
      baseRate: _d('20000'),
      wageType: WageType.MONTHLY,
    );

    final prorated = _run(
      _employee(
        baseRate: _d('38000'),
        overrideBefore: oldRate,
        switchDay: 17,
        statutoryOverride: override,
      ),
    );
    final flat = _run(
      _employee(baseRate: _d('38000'), statutoryOverride: override),
    );

    expect(
      prorated.withholdingTax,
      flat.withholdingTax,
      reason:
          'declared-wage override fixes the tax basis; per-day rates '
          'must not move withholding',
    );
    expect(prorated.sssEe, flat.sssEe, reason: 'SSS must ignore per-day rates');
    expect(
      prorated.philhealthEe,
      flat.philhealthEe,
      reason: 'PhilHealth must ignore per-day rates',
    );
    expect(
      prorated.pagibigEe,
      flat.pagibigEe,
      reason: 'Pag-IBIG must ignore per-day rates',
    );
  });

  test(
    'Test C — no override: statutory contributions ignore per-day rates',
    () {
      final prorated = _run(
        _employee(
          baseRate: _d('38000'),
          overrideBefore: oldRate,
          switchDay: 17,
        ),
      );
      final flat = _run(_employee(baseRate: _d('38000')));

      // Contributions derive from the period-level MSC (rates.msc), never the
      // per-day basic pay, so mid-period rate splits must not move them.
      expect(
        prorated.sssEe,
        flat.sssEe,
        reason: 'SSS must ignore per-day rates',
      );
      expect(
        prorated.philhealthEe,
        flat.philhealthEe,
        reason: 'PhilHealth must ignore per-day rates',
      );
      expect(
        prorated.pagibigEe,
        flat.pagibigEe,
        reason: 'Pag-IBIG must ignore per-day rates',
      );
    },
  );
}
