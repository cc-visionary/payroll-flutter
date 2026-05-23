import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/templates/liability_waiver_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/liability_waiver_validate.dart';

void main() {
  LiabilityWaiverInputs valid() => LiabilityWaiverInputs(
        employeeId: 'emp-1',
        employeeFullName: 'Donald Xu',
        employeeAddress: '123 Mabini St, Manila',
        companyId: 'co-1',
        companyName: 'LUXIUM TRADING CO.',
        dateOfEmployment: DateTime(2024, 1, 15),
        outingDate: DateTime(2026, 6, 20),
        outingLocation: 'Tagaytay City, Cavite',
        dateSigned: DateTime(2026, 5, 23),
        signingPlace: 'Manila City',
      );

  test('valid inputs produce no errors', () {
    expect(validateLiabilityWaiver(valid()), isEmpty);
  });

  test('missing employee flagged', () {
    final i = valid().copyWith(employeeId: '');
    expect(validateLiabilityWaiver(i).any((e) => e.field == 'employee'), true);
  });

  test('missing company flagged', () {
    final i = valid().copyWith(companyId: '');
    expect(validateLiabilityWaiver(i).any((e) => e.field == 'company'), true);
  });

  test('missing employee full name flagged', () {
    final i = valid().copyWith(employeeFullName: '   ');
    expect(
        validateLiabilityWaiver(i).any((e) => e.field == 'employeeFullName'),
        true);
  });

  test('missing employee address flagged', () {
    final i = valid().copyWith(employeeAddress: '   ');
    expect(
        validateLiabilityWaiver(i).any((e) => e.field == 'employeeAddress'),
        true);
  });

  test('missing company name flagged', () {
    final i = valid().copyWith(companyName: '');
    expect(validateLiabilityWaiver(i).any((e) => e.field == 'companyName'),
        true);
  });

  test('null date of employment flagged', () {
    final i = valid().copyWith(dateOfEmployment: null);
    expect(
        validateLiabilityWaiver(i).any((e) => e.field == 'dateOfEmployment'),
        true);
  });

  test('null outing date flagged', () {
    final i = valid().copyWith(outingDate: null);
    expect(validateLiabilityWaiver(i).any((e) => e.field == 'outingDate'),
        true);
  });

  test('missing outing location flagged', () {
    final i = valid().copyWith(outingLocation: '   ');
    expect(validateLiabilityWaiver(i).any((e) => e.field == 'outingLocation'),
        true);
  });

  test('missing signing place flagged', () {
    final i = valid().copyWith(signingPlace: '');
    expect(validateLiabilityWaiver(i).any((e) => e.field == 'signingPlace'),
        true);
  });
}
