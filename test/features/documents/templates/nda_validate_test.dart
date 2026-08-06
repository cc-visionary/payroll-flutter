import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/templates/nda_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/nda_validate.dart';

void main() {
  NdaInputs valid() => NdaInputs(
    employeeId: 'e1',
    employeeFullName: 'Jamaica Vidal',
    employeePosition: 'HR Assistant',
    employeeHomeAddress: '8 Tendido St, Quezon City',
    companyId: 'c1',
    companyName: 'Luxium Trading Co.',
    companyAddress: '908 Alvarado St, Manila',
    effectiveDate: DateTime(2025, 6, 9),
    authorizedSignatoryName: 'Brixter Del Mundo',
    authorizedSignatoryRole: 'Authorized Signatory',
  );

  test('valid inputs produce no errors', () {
    expect(validateNda(valid()), isEmpty);
  });

  test('empty employeeId flagged', () {
    expect(
      validateNda(
        valid().copyWith(employeeId: ''),
      ).any((e) => e.field == 'employee'),
      true,
    );
  });

  test('empty companyId flagged', () {
    expect(
      validateNda(
        valid().copyWith(companyId: ''),
      ).any((e) => e.field == 'company'),
      true,
    );
  });

  test('empty employeeFullName flagged', () {
    expect(
      validateNda(
        valid().copyWith(employeeFullName: ''),
      ).any((e) => e.field == 'employeeFullName'),
      true,
    );
  });

  test('empty employeePosition flagged', () {
    expect(
      validateNda(
        valid().copyWith(employeePosition: ''),
      ).any((e) => e.field == 'employeePosition'),
      true,
    );
  });

  test('empty employeeHomeAddress flagged', () {
    expect(
      validateNda(
        valid().copyWith(employeeHomeAddress: ''),
      ).any((e) => e.field == 'employeeHomeAddress'),
      true,
    );
  });

  test('empty companyName flagged', () {
    expect(
      validateNda(
        valid().copyWith(companyName: ''),
      ).any((e) => e.field == 'companyName'),
      true,
    );
  });

  test('empty companyAddress flagged', () {
    expect(
      validateNda(
        valid().copyWith(companyAddress: ''),
      ).any((e) => e.field == 'companyAddress'),
      true,
    );
  });

  test('empty authorizedSignatoryName flagged', () {
    expect(
      validateNda(
        valid().copyWith(authorizedSignatoryName: ''),
      ).any((e) => e.field == 'authorizedSignatoryName'),
      true,
    );
  });

  test('null effectiveDate flagged', () {
    expect(
      validateNda(
        valid().copyWith(effectiveDate: null),
      ).any((e) => e.field == 'effectiveDate'),
      true,
    );
  });
}
