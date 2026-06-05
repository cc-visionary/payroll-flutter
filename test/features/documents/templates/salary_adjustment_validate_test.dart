import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/templates/salary_adjustment_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/salary_adjustment_validate.dart';

SalaryAdjustmentInputs _base() => SalaryAdjustmentInputs(
  employeeId: 'e1',
  employeeFullName: 'Bob',
  companyId: 'c1',
  companyName: 'X',
  hrManagerName: 'HR',
  oldSalary: Decimal.parse('20000'),
  newSalary: Decimal.parse('25000'),
  effectiveDate: DateTime(2026, 7, 1),
  issueDate: DateTime(2026, 6, 5),
  reason: 'Annual merit increase',
);

void main() {
  test('passes for adjustment with all fields', () {
    expect(validateSalaryAdjustment(_base()), isEmpty);
  });

  test('requires reason', () {
    final i = _base().copyWith(reason: '');
    expect(validateSalaryAdjustment(i).map((e) => e.field), contains('reason'));
  });

  test('promotion requires newRoleScorecardId', () {
    final i = _base().copyWith(type: SalaryAdjustmentType.promotion);
    expect(
      validateSalaryAdjustment(i).map((e) => e.field),
      contains('newRoleScorecardId'),
    );
  });

  test('promotion rejects same old=new scorecard', () {
    final i = _base().copyWith(
      type: SalaryAdjustmentType.promotion,
      oldRoleScorecardId: 'r1',
      newRoleScorecardId: 'r1',
    );
    expect(
      validateSalaryAdjustment(i).map((e) => e.field),
      contains('newRoleScorecardId'),
    );
  });

  test('rejects oldSalary == newSalary', () {
    final i = _base().copyWith(newSalary: Decimal.parse('20000'));
    expect(
      validateSalaryAdjustment(i).map((e) => e.field),
      contains('newSalary'),
    );
  });
}
