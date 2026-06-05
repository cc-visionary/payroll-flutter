import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/templates/regularization_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/regularization_validate.dart';

RegularizationInputs _b() => RegularizationInputs(
  employeeId: 'e1',
  employeeFullName: 'A',
  companyId: 'c1',
  companyName: 'X',
  hrManagerName: 'HR',
  hireDate: DateTime(2026, 1, 5),
  regularizationDate: DateTime(2026, 6, 1),
  baseSalary: Decimal.parse('25000'),
  issueDate: DateTime(2026, 6, 5),
);

void main() {
  test('valid baseline', () => expect(validateRegularization(_b()), isEmpty));
  test('regularizationDate < hireDate rejected', () {
    final i = _b().copyWith(regularizationDate: DateTime(2025, 12, 1));
    expect(
      validateRegularization(i).map((e) => e.field),
      contains('regularizationDate'),
    );
  });
  test('baseSalary > 0 required', () {
    expect(
      validateRegularization(
        _b().copyWith(baseSalary: Decimal.zero),
      ).map((e) => e.field),
      contains('baseSalary'),
    );
  });
}
