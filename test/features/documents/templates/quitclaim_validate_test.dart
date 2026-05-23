import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/templates/quitclaim_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/quitclaim_validate.dart';

void main() {
  QuitclaimInputs valid() => QuitclaimInputs(
        employeeId: 'emp-1',
        employeeFullName: 'Donald Xu',
        employeeAddress: '123 Mabini St, Manila',
        civilStatus: 'single',
        companyId: 'co-1',
        companyName: 'LUXIUM TRADING CO.',
        finalPayAmount: Decimal.parse('47250.00'),
        dateTerminated: DateTime(2026, 4, 30),
        dateSigned: DateTime(2026, 5, 5),
        placeSigned: 'Manila City',
      );

  test('valid inputs produce no errors', () {
    expect(validateQuitclaim(valid()), isEmpty);
  });

  test('missing employee flagged', () {
    final i = valid().copyWith(employeeId: '');
    expect(validateQuitclaim(i).any((e) => e.field == 'employee'), true);
  });

  test('missing company flagged', () {
    final i = valid().copyWith(companyId: '');
    expect(validateQuitclaim(i).any((e) => e.field == 'company'), true);
  });

  test('missing employee address flagged', () {
    final i = valid().copyWith(employeeAddress: '   ');
    expect(
        validateQuitclaim(i).any((e) => e.field == 'employeeAddress'), true);
  });

  test('missing civil status flagged', () {
    final i = valid().copyWith(civilStatus: '');
    expect(validateQuitclaim(i).any((e) => e.field == 'civilStatus'), true);
  });

  test('missing place signed flagged', () {
    final i = valid().copyWith(placeSigned: '');
    expect(validateQuitclaim(i).any((e) => e.field == 'placeSigned'), true);
  });

  test('finalPayAmount must be > 0', () {
    final i = valid().copyWith(finalPayAmount: Decimal.zero);
    expect(
        validateQuitclaim(i).any((e) => e.field == 'finalPayAmount'), true);
  });

  test('dateSigned before dateTerminated flagged', () {
    final i = valid().copyWith(dateSigned: DateTime(2026, 4, 1));
    expect(validateQuitclaim(i).any((e) => e.field == 'dateSigned'), true);
  });
}
