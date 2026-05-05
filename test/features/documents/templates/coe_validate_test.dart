import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/templates/coe_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/coe_validate.dart';

void main() {
  CoeInputs valid() => CoeInputs(
        employeeId: 'e1',
        employeeFullName: 'D',
        companyId: 'c1',
        companyName: 'X',
        hrManagerName: 'HR',
        position: 'Engineer',
        dateStart: DateTime(2024, 1, 1),
        dateEnd: DateTime(2026, 4, 30),
      );

  test('valid inputs produce no errors', () {
    expect(validateCoe(valid()), isEmpty);
  });

  test('dateEnd before dateStart flagged', () {
    final i = valid().copyWith(dateEnd: DateTime(2023, 1, 1));
    expect(validateCoe(i).any((e) => e.field == 'dateEnd'), true);
  });

  test('missing position flagged', () {
    final i = valid().copyWith(position: '');
    expect(validateCoe(i).any((e) => e.field == 'position'), true);
  });
}
