// Payslip parity test suite.
//
// Loads every JSON fixture from test/engine/fixtures/ (produced by
// payrollos/scripts/export-parity-fixtures.ts) and asserts the Dart engine
// reproduces the payrollos outputs byte-for-byte.
//
// If the fixtures directory is empty (e.g. on a fresh checkout before the
// export script has run), the test is skipped instead of failing, so CI still
// runs green for developers who don't have access to the payrollos DB.

import 'dart:convert';
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/payroll/engine/compute_engine.dart';
import 'package:payroll_flutter/features/payroll/engine/statutory_tables.dart';
import 'package:payroll_flutter/features/payroll/engine/types.dart';

Decimal _d(Object? v) => v == null ? Decimal.zero : Decimal.parse(v.toString());
DateTime _date(String s) => DateTime.parse(s.length == 10 ? '${s}T00:00:00Z' : s);

WageType _wage(String s) => WageType.values.firstWhere((e) => e.name == s);
PayFrequency _freq(String s) => PayFrequency.values.firstWhere((e) => e.name == s);
DayType _dayType(String s) => DayType.values.firstWhere((e) => e.name == s);
EmploymentType _empType(String s) {
  return EmploymentType.values.firstWhere(
    (e) => e.name == s,
    orElse: () => EmploymentType.REGULAR,
  );
}

void main() {
  final dir = Directory('test/engine/fixtures');
  if (!dir.existsSync()) {
    test('parity fixtures: none — skipping (run export-parity-fixtures.ts in payrollos)', () {
      expect(true, isTrue);
    }, skip: 'No fixtures directory');
    return;
  }
  final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList();
  if (files.isEmpty) {
    test('parity fixtures: none — skipping (run export-parity-fixtures.ts in payrollos)', () {
      expect(true, isTrue);
    }, skip: 'No fixture JSON files');
    return;
  }

  for (final f in files) {
    final name = f.uri.pathSegments.last;
    test('parity: $name', () {
      final fixture = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final input = fixture['input'] as Map<String, dynamic>;
      final expected = fixture['expected'] as Map<String, dynamic>;

      final pp = input['payPeriod'] as Map<String, dynamic>;
      final payPeriod = PayPeriodInput(
        id: pp['id'],
        startDate: _date(pp['startDate']),
        endDate: _date(pp['endDate']),
        cutoffDate: _date(pp['cutoffDate']),
        payDate: _date(pp['payDate']),
        periodNumber: pp['periodNumber'],
        payFrequency: _freq(pp['payFrequency']),
      );

      final ruleset = RulesetInput(
        id: 'default-2026',
        version: 1,
        sssTable: SSS_TABLE,
        philhealthTable: PHILHEALTH_TABLE,
        pagibigTable: PAGIBIG_TABLE,
        taxTable: TAX_TABLE,
      );

      final emp = input['employee'] as Map<String, dynamic>;
      final prof = emp['profile'] as Map<String, dynamic>;
      final profile = PayProfileInput(
        employeeId: prof['employeeId'],
        wageType: _wage(prof['wageType']),
        baseRate: _d(prof['baseRate']),
        payFrequency: _freq(prof['payFrequency']),
        standardWorkDaysPerMonth: prof['standardWorkDaysPerMonth'],
        standardHoursPerDay: prof['standardHoursPerDay'],
        isBenefitsEligible: prof['isBenefitsEligible'],
        isOtEligible: prof['isOtEligible'],
        isNdEligible: prof['isNdEligible'],
        riceSubsidy: _d(prof['riceSubsidy']),
        clothingAllowance: _d(prof['clothingAllowance']),
        laundryAllowance: _d(prof['laundryAllowance']),
        medicalAllowance: _d(prof['medicalAllowance']),
        transportationAllowance: _d(prof['transportationAllowance']),
        mealAllowance: _d(prof['mealAllowance']),
        communicationAllowance: _d(prof['communicationAllowance']),
      );

      final reg = emp['regularization'] as Map<String, dynamic>;
      final regularization = EmployeeRegularizationInput(
        employeeId: reg['employeeId'],
        employmentType: _empType(reg['employmentType']),
        regularizationDate: reg['regularizationDate'] == null ? null : _date(reg['regularizationDate']),
        hireDate: _date(reg['hireDate']),
      );

      final attendance = (emp['attendance'] as List).cast<Map<String, dynamic>>().map((a) {
        return AttendanceDayInput(
          id: a['id'],
          attendanceDate: _date(a['attendanceDate']),
          dayType: _dayType(a['dayType']),
          workedMinutes: a['workedMinutes'] ?? 0,
          deductionMinutes: a['deductionMinutes'] ?? 0,
          absentMinutes: a['absentMinutes'] ?? 0,
          otMinutes: a['otMinutes'] ?? 0,
          otEarlyInMinutes: a['otEarlyInMinutes'] ?? 0,
          otLateOutMinutes: a['otLateOutMinutes'] ?? 0,
          overtimeRestDayMinutes: a['overtimeRestDayMinutes'] ?? 0,
          overtimeHolidayMinutes: a['overtimeHolidayMinutes'] ?? 0,
          earlyInApproved: a['earlyInApproved'] ?? false,
          lateOutApproved: a['lateOutApproved'] ?? false,
          nightDiffMinutes: a['nightDiffMinutes'] ?? 0,
          isOnLeave: a['isOnLeave'] ?? false,
          leaveIsPaid: a['leaveIsPaid'] ?? false,
          dailyRateOverride: a['dailyRateOverride'] == null ? null : _d(a['dailyRateOverride']),
        );
      }).toList();

      final prevYtd = emp['previousYtd'] as Map<String, dynamic>;
      final previousYtd = PreviousYtd(
        grossPay: _d(prevYtd['grossPay']),
        taxableIncome: _d(prevYtd['taxableIncome']),
        taxWithheld: _d(prevYtd['taxWithheld']),
      );

      final statOvr = emp['statutoryOverride'] as Map<String, dynamic>?;
      final input2 = EmployeePayrollInput(
        profile: profile,
        regularization: regularization,
        attendance: attendance,
        previousYtd: previousYtd,
        taxOnFullEarnings: emp['taxOnFullEarnings'] ?? false,
        statutoryOverride: statOvr == null
            ? null
            : StatutoryOverride(
                baseRate: _d(statOvr['baseRate']),
                wageType: _wage(statOvr['wageType']),
              ),
      );

      final result = computePayroll(payPeriod, ruleset, [input2]);
      expect(result.errors, isEmpty, reason: 'engine threw for $name');
      final got = result.payslips.first;

      // Money totals — exact match.
      _expectDec('grossPay', got.grossPay, _d(expected['grossPay']));
      _expectDec('totalEarnings', got.totalEarnings, _d(expected['totalEarnings']));
      _expectDec('totalDeductions', got.totalDeductions, _d(expected['totalDeductions']));
      _expectDec('netPay', got.netPay, _d(expected['netPay']));
      _expectDec('sssEe', got.sssEe, _d(expected['sssEe']));
      _expectDec('philhealthEe', got.philhealthEe, _d(expected['philhealthEe']));
      _expectDec('pagibigEe', got.pagibigEe, _d(expected['pagibigEe']));
      _expectDec('withholdingTax', got.withholdingTax, _d(expected['withholdingTax']));

      // Line-level match — order-sensitive by (category, sortOrder).
      final expectedLines = (expected['lines'] as List).cast<Map<String, dynamic>>();
      expect(got.lines.length, expectedLines.length,
          reason: 'line count differs for $name');
      for (var i = 0; i < expectedLines.length; i++) {
        final e = expectedLines[i];
        final g = got.lines[i];
        expect(g.category.name, e['category'], reason: 'line $i category $name');
        _expectDec('line $i amount', g.amount, _d(e['amount']));
      }
    });
  }
}

void _expectDec(String label, Decimal got, Decimal exp) {
  expect(got, exp, reason: '$label: got $got, expected $exp');
}
