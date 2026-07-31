import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/payroll/engine/compute_engine.dart';
import 'package:payroll_flutter/features/payroll/engine/statutory_tables.dart';
import 'package:payroll_flutter/features/payroll/engine/types.dart';

// Differential tax tests for DAILY/HOURLY paid leave (harness style mirrors
// test/engine/paid_leave_line_test.dart).
//
// `ComputedPayslip` does not expose the per-period taxable figure directly —
// only `ytdTaxableIncome` (= previousYtd.taxableIncome + currentPeriodTaxable,
// see compute_engine.dart ~line 605). Every case below builds employees with
// `previousYtd.taxableIncome == Decimal.zero` (the harness default), so
// `ytdTaxableIncome` IS this period's taxable income here. `withholdingTax`
// is asserted alongside as a second, independently-computed witness of the
// same underlying tax-base equality/inequality.

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

PayProfileInput _profile(WageType wt, Decimal rate) => PayProfileInput(
      employeeId: 'EMP-1',
      wageType: wt,
      baseRate: rate,
      payFrequency: PayFrequency.SEMI_MONTHLY,
      standardWorkDaysPerMonth: 26,
      standardHoursPerDay: 8,
      isBenefitsEligible: true,
      isOtEligible: false,
      isNdEligible: false,
      sssEligibilityOverride: false,
      philhealthEligibilityOverride: false,
      pagibigEligibilityOverride: false,
      riceSubsidy: Decimal.zero,
      clothingAllowance: Decimal.zero,
      laundryAllowance: Decimal.zero,
      medicalAllowance: Decimal.zero,
      transportationAllowance: Decimal.zero,
      mealAllowance: Decimal.zero,
      communicationAllowance: Decimal.zero,
    );

AttendanceDayInput _day({
  required String id,
  required DateTime date,
  double worked = 480,
  bool onLeave = false,
  bool leavePaid = false,
  Decimal? paidFraction,
  String? leaveTypeName,
}) =>
    AttendanceDayInput(
      id: id,
      attendanceDate: date,
      dayType: DayType.WORKDAY,
      workedMinutes: worked,
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
      isOnLeave: onLeave,
      leaveIsPaid: leavePaid,
      paidLeaveFraction: paidFraction ?? Decimal.zero,
      leaveTypeName: leaveTypeName,
    );

// `taxOnFullEarnings` defaults to false on EmployeePayrollInput -> BASIC PAY
// ONLY tax mode (see compute_engine.dart ~line 511). Left unset deliberately.
EmployeePayrollInput _employee(PayProfileInput p, List<AttendanceDayInput> att) =>
    EmployeePayrollInput(
      profile: p,
      regularization: EmployeeRegularizationInput(
        employeeId: p.employeeId,
        employmentType: EmploymentType.REGULAR,
        hireDate: DateTime.utc(2020, 1, 1),
        regularizationDate: DateTime.utc(2020, 7, 1),
      ),
      attendance: att,
      manualAdjustments: const [],
      reimbursements: const [],
      cashAdvanceDeductions: const [],
      previousYtd: PreviousYtd(
        grossPay: Decimal.zero,
        taxableIncome: Decimal.zero,
        taxWithheld: Decimal.zero,
      ),
    );

ComputedPayslip _run(PayProfileInput p, List<AttendanceDayInput> att) =>
    computeEmployeePayslip(_payPeriod(), _ruleset(), _employee(p, att));

void main() {
  group('DAILY: paid leave is taxed like worked pay', () {
    test('Case A (paid leave day) == Case B (same day worked)', () {
      final p = _profile(WageType.DAILY, _d('1000'));

      // Case A: one worked day + one FULL-DAY PAID leave day.
      final caseA = _run(p, [
        _day(id: 'w1', date: DateTime.utc(2026, 1, 5)),
        _day(
          id: 'l1',
          date: DateTime.utc(2026, 1, 6),
          worked: 0,
          onLeave: true,
          leavePaid: true,
          paidFraction: _d('1.0'),
          leaveTypeName: 'SIL',
        ),
      ]);

      // Case B: the same two days, both WORKED (no leave at all).
      final caseB = _run(p, [
        _day(id: 'w1', date: DateTime.utc(2026, 1, 5)),
        _day(id: 'w2', date: DateTime.utc(2026, 1, 6)),
      ]);

      expect(caseA.ytdTaxableIncome, caseB.ytdTaxableIncome);
      expect(caseA.withholdingTax, caseB.withholdingTax);
    });

    test('Case C (unpaid leave) taxes LESS than Case A (paid leave)', () {
      final p = _profile(WageType.DAILY, _d('1000'));

      final caseA = _run(p, [
        _day(id: 'w1', date: DateTime.utc(2026, 1, 5)),
        _day(
          id: 'l1',
          date: DateTime.utc(2026, 1, 6),
          worked: 0,
          onLeave: true,
          leavePaid: true,
          paidFraction: _d('1.0'),
          leaveTypeName: 'SIL',
        ),
      ]);

      // Case C: the same day is UNPAID leave instead (one fewer paid day).
      final caseC = _run(p, [
        _day(id: 'w1', date: DateTime.utc(2026, 1, 5)),
        _day(
          id: 'l1',
          date: DateTime.utc(2026, 1, 6),
          worked: 0,
          onLeave: true,
          leavePaid: false,
          paidFraction: Decimal.zero,
        ),
      ]);

      expect(caseC.ytdTaxableIncome, lessThan(caseA.ytdTaxableIncome));
    });
  });

  test(
      'MONTHLY: paid leave day does not change taxable vs. the same day '
      'worked (no double count)', () {
    final p = _profile(WageType.MONTHLY, _d('26000'));

    final caseAMonthly = _run(p, [
      _day(id: 'w1', date: DateTime.utc(2026, 1, 5)),
      _day(
        id: 'l1',
        date: DateTime.utc(2026, 1, 6),
        worked: 0,
        onLeave: true,
        leavePaid: true,
        paidFraction: _d('1.0'),
        leaveTypeName: 'SIL',
      ),
    ]);

    final caseBMonthly = _run(p, [
      _day(id: 'w1', date: DateTime.utc(2026, 1, 5)),
      _day(id: 'w2', date: DateTime.utc(2026, 1, 6)),
    ]);

    expect(caseAMonthly.ytdTaxableIncome, caseBMonthly.ytdTaxableIncome);
    expect(caseAMonthly.withholdingTax, caseBMonthly.withholdingTax);
  });
}
