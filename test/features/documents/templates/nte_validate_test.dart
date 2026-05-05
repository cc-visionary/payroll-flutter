import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/templates/nte_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/nte_validate.dart';

void main() {
  Delta nonEmpty() => Delta()..insert('Body text\n');

  NteInputs valid() => NteInputs(
        employeeId: 'e1',
        employeeFullName: 'Donald',
        employeeFirstName: 'Donald',
        employeeLastName: 'Xu',
        employeePosition: 'Engineer',
        employeeDepartment: 'Tech',
        companyId: 'c1',
        companyName: 'X',
        hrManagerName: 'Brixter',
        dateIssued: DateTime(2026, 5, 5),
        responseDeadline: DateTime(2026, 5, 10),
        subjectSubtopic: '',
        charges: [NteCharge(title: 'Charge 1', body: nonEmpty())],
        applicableViolations: ['Code of Conduct §3.1'],
      );

  test('valid inputs produce no errors', () {
    expect(validateNte(valid()), isEmpty);
  });

  test('empty charges flagged', () {
    final i = valid().copyWith(charges: []);
    expect(validateNte(i).any((e) => e.field == 'charges'), true);
  });

  test('empty charge title flagged', () {
    final i = valid().copyWith(charges: [
      NteCharge(title: '', body: nonEmpty()),
    ]);
    expect(
      validateNte(i).any((e) => e.field == 'charges[0].title'),
      true,
    );
  });

  test('empty charge body flagged', () {
    final i = valid().copyWith(charges: [
      NteCharge(title: 'X', body: Delta()..insert('\n')),
    ]);
    expect(validateNte(i).any((e) => e.field == 'charges[0].body'), true);
  });

  test('responseDeadline not after dateIssued flagged', () {
    final i = valid().copyWith(
      dateIssued: DateTime(2026, 5, 5),
      responseDeadline: DateTime(2026, 5, 5),
    );
    expect(
      validateNte(i).any((e) => e.field == 'responseDeadline'),
      true,
    );
  });

  test('empty violations flagged', () {
    final i = valid().copyWith(applicableViolations: []);
    expect(
      validateNte(i).any((e) => e.field == 'applicableViolations'),
      true,
    );
  });
}
