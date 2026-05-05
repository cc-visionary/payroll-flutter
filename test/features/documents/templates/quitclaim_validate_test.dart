import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/templates/quitclaim_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/quitclaim_validate.dart';

void main() {
  QuitclaimInputs valid() => QuitclaimInputs(
        employeeId: 'emp-1',
        employeeFullName: 'Donald Xu',
        companyId: 'co-1',
        companyName: 'LUXIUM TRADING CO.',
        companyAddress: 'Manila',
        companySignatoryName: 'Clinton Xu',
        companySignatoryRole: 'CEO',
        dateTerminated: DateTime(2026, 4, 30),
        dateSigned: DateTime(2026, 5, 5),
        finalPayAmount: Decimal.parse('47250.00'),
      );

  test('valid inputs produce no errors', () {
    expect(validateQuitclaim(valid()), isEmpty);
  });

  test('missing employee flagged', () {
    final i = valid().copyWith(employeeId: '');
    expect(
      validateQuitclaim(i).any((e) => e.field == 'employee'),
      true,
    );
  });

  test('missing signatory flagged', () {
    final i = valid().copyWith(companySignatoryName: null);
    expect(
      validateQuitclaim(i).any((e) => e.field == 'signatoryName'),
      true,
    );
  });

  test('finalPayAmount must be > 0', () {
    final i = valid().copyWith(finalPayAmount: Decimal.zero);
    expect(
      validateQuitclaim(i).any((e) => e.field == 'finalPayAmount'),
      true,
    );
  });

  test('dateSigned before dateTerminated flagged', () {
    final i = valid().copyWith(dateSigned: DateTime(2026, 4, 1));
    expect(
      validateQuitclaim(i).any((e) => e.field == 'dateSigned'),
      true,
    );
  });
}
