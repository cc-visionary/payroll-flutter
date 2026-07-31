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

Iterable<ComputedPayslipLine> _paidLeave(ComputedPayslip ps) =>
    ps.lines.where((l) => l.category == PayslipLineCategory.PAID_LEAVE);

void main() {
  test('DAILY: full paid leave day emits a PAID_LEAVE earning at daily rate', () {
    final p = _profile(WageType.DAILY, _d('1000'));
    final ps = _run(p, [
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
    final lines = _paidLeave(ps).toList();
    expect(lines, hasLength(1));
    expect(lines.first.amount, _d('1000'));
    expect(lines.first.description, contains('SIL'));
  });

  test('DAILY: half-day paid leave pays half the daily rate', () {
    final p = _profile(WageType.DAILY, _d('1000'));
    final ps = _run(p, [
      _day(
        id: 'l1',
        date: DateTime.utc(2026, 1, 6),
        worked: 0,
        onLeave: true,
        leavePaid: true,
        paidFraction: _d('0.5'),
        leaveTypeName: 'SIL',
      ),
    ]);
    expect(_paidLeave(ps).single.amount, _d('500'));
  });

  test('DAILY: unpaid leave emits no PAID_LEAVE line', () {
    final p = _profile(WageType.DAILY, _d('1000'));
    final ps = _run(p, [
      _day(
        id: 'l1',
        date: DateTime.utc(2026, 1, 6),
        worked: 0,
        onLeave: true,
        leavePaid: false,
        paidFraction: Decimal.zero,
      ),
    ]);
    expect(_paidLeave(ps), isEmpty);
  });

  test('DAILY: ON_LEAVE day with worked minutes (mixed) emits no PAID_LEAVE line', () {
    final p = _profile(WageType.DAILY, _d('1000'));
    final ps = _run(p, [
      _day(
        id: 'm1',
        date: DateTime.utc(2026, 1, 6),
        worked: 240,
        onLeave: true,
        leavePaid: true,
        paidFraction: _d('0.5'),
        leaveTypeName: 'SIL',
      ),
    ]);
    expect(_paidLeave(ps), isEmpty);
  });

  test('MONTHLY: paid leave day emits a zero-amount PAID_LEAVE info line', () {
    final p = _profile(WageType.MONTHLY, _d('26000'));
    final ps = _run(p, [
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
    final lines = _paidLeave(ps).toList();
    expect(lines, hasLength(1));
    expect(lines.first.amount, Decimal.zero);
  });

  test('two paid leave days of the same type collapse into one line', () {
    final p = _profile(WageType.DAILY, _d('1000'));
    final ps = _run(p, [
      _day(id: 'l1', date: DateTime.utc(2026, 1, 6), worked: 0, onLeave: true, leavePaid: true, paidFraction: _d('1.0'), leaveTypeName: 'SIL'),
      _day(id: 'l2', date: DateTime.utc(2026, 1, 7), worked: 0, onLeave: true, leavePaid: true, paidFraction: _d('1.0'), leaveTypeName: 'SIL'),
    ]);
    final lines = _paidLeave(ps).toList();
    expect(lines, hasLength(1));
    expect(lines.first.amount, _d('2000'));
    expect(lines.first.quantity, _d('2'));
  });
}
