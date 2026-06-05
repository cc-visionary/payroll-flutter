import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/templates/final_pay_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/final_pay_validate.dart';

FinalPayInputs _base() => FinalPayInputs(
  employeeId: 'e1',
  employeeFullName: 'Alice',
  employeePosition: 'Accountant',
  companyId: 'c1',
  companyName: 'Luxium',
  hrManagerName: 'Brixter',
  lastNetPay: Decimal.parse('5000'),
  thirteenthMonth: Decimal.parse('2500'),
  unusedLeaveConversion: Decimal.parse('1000'),
  outstandingCashAdvance: Decimal.zero,
  computedAsOf: DateTime(2026, 6, 5),
  releaseDate: DateTime(2026, 6, 12),
);

void main() {
  test('passes for a complete input', () {
    expect(validateFinalPay(_base()), isEmpty);
  });

  test('requires employeeId', () {
    final i = _base().copyWith(employeeId: '');
    final errs = validateFinalPay(i);
    expect(errs.map((e) => e.field), contains('employee'));
  });

  test('requires companyId', () {
    final i = _base().copyWith(companyId: '');
    final errs = validateFinalPay(i);
    expect(errs.map((e) => e.field), contains('company'));
  });

  test('rejects negative lastNetPay', () {
    final i = _base().copyWith(lastNetPay: Decimal.parse('-1'));
    final errs = validateFinalPay(i);
    expect(errs.map((e) => e.field), contains('lastNetPay'));
  });

  test('rejects releaseDate before computedAsOf', () {
    final i = _base().copyWith(releaseDate: DateTime(2026, 6, 1));
    final errs = validateFinalPay(i);
    expect(errs.map((e) => e.field), contains('releaseDate'));
  });

  test('does NOT flag releaseDate > computedAsOf+30 (warn only)', () {
    final i = _base().copyWith(releaseDate: DateTime(2026, 9, 1));
    final errs = validateFinalPay(i);
    expect(errs.map((e) => e.field), isNot(contains('releaseDate')));
  });
}
