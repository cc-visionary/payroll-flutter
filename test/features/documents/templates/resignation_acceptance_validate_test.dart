import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/templates/resignation_acceptance_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/resignation_acceptance_validate.dart';

ResignationAcceptanceInputs _b() => ResignationAcceptanceInputs(
  employeeId: 'e1',
  employeeFullName: 'B',
  companyId: 'c1',
  companyName: 'X',
  hrManagerName: 'HR',
  resignationDate: DateTime(2026, 6, 1),
  lastDayOfWork: DateTime(2026, 7, 1),
  issueDate: DateTime(2026, 6, 5),
);

void main() {
  test(
    'baseline valid',
    () => expect(validateResignationAcceptance(_b()), isEmpty),
  );
  test('lastDayOfWork < resignationDate rejected', () {
    final i = _b().copyWith(lastDayOfWork: DateTime(2026, 5, 1));
    expect(
      validateResignationAcceptance(i).map((e) => e.field),
      contains('lastDayOfWork'),
    );
  });
  test('turnoverInstructions required', () {
    final i = _b().copyWith(turnoverInstructions: '   ');
    expect(
      validateResignationAcceptance(i).map((e) => e.field),
      contains('turnoverInstructions'),
    );
  });
}
