import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/templates/penalty_agreement_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/penalty_agreement_validate.dart';

PenaltyAgreementInputs _base() => PenaltyAgreementInputs(
  employeeId: 'e1',
  employeeFullName: 'Alice',
  employeePosition: 'Rider',
  companyId: 'c1',
  companyName: 'Luxium',
  hrManagerName: 'Brixter',
  penaltyId: 'p1',
  description: 'Lost a company scanner',
  totalAmount: Decimal.parse('3000'),
  effectiveDate: DateTime(2026, 8, 1),
  installments: [
    PenaltyInstallmentLine(number: 1, amount: Decimal.parse('1000')),
    PenaltyInstallmentLine(number: 2, amount: Decimal.parse('1000')),
    PenaltyInstallmentLine(number: 3, amount: Decimal.parse('1000')),
  ],
);

void main() {
  test('passes for a complete input', () {
    expect(validatePenaltyAgreement(_base()), isEmpty);
  });

  test('requires employeeId', () {
    final errs = validatePenaltyAgreement(_base().copyWith(employeeId: ''));
    expect(errs.map((e) => e.field), contains('employee'));
  });

  test('requires employeeFullName', () {
    final errs = validatePenaltyAgreement(
      _base().copyWith(employeeFullName: '   '),
    );
    expect(errs.map((e) => e.field), contains('employeeFullName'));
  });

  test('requires companyId', () {
    final errs = validatePenaltyAgreement(_base().copyWith(companyId: ''));
    expect(errs.map((e) => e.field), contains('company'));
  });

  test('requires a description', () {
    final errs = validatePenaltyAgreement(_base().copyWith(description: '  '));
    expect(errs.map((e) => e.field), contains('description'));
  });

  test('rejects a zero total', () {
    final errs = validatePenaltyAgreement(
      _base().copyWith(
        totalAmount: Decimal.zero,
        installments: [PenaltyInstallmentLine(number: 1, amount: Decimal.zero)],
      ),
    );
    expect(errs.map((e) => e.field), contains('totalAmount'));
  });

  test('rejects a negative total', () {
    final errs = validatePenaltyAgreement(
      _base().copyWith(totalAmount: Decimal.parse('-1')),
    );
    expect(errs.map((e) => e.field), contains('totalAmount'));
  });

  test('rejects an empty schedule', () {
    final errs = validatePenaltyAgreement(
      _base().copyWith(installments: const []),
    );
    expect(errs.map((e) => e.field), contains('installments'));
  });

  test('rejects a schedule that does not sum to the total', () {
    final errs = validatePenaltyAgreement(
      _base().copyWith(
        installments: [
          PenaltyInstallmentLine(number: 1, amount: Decimal.parse('1000')),
          PenaltyInstallmentLine(number: 2, amount: Decimal.parse('1000')),
        ],
      ),
    );
    expect(errs.map((e) => e.field), contains('installments'));
  });

  test('accepts a schedule whose last slot absorbs the rounding residual', () {
    final i = _base().copyWith(
      totalAmount: Decimal.parse('1000.00'),
      installments: [
        PenaltyInstallmentLine(number: 1, amount: Decimal.parse('333.33')),
        PenaltyInstallmentLine(number: 2, amount: Decimal.parse('333.33')),
        PenaltyInstallmentLine(number: 3, amount: Decimal.parse('333.34')),
      ],
    );
    expect(validatePenaltyAgreement(i), isEmpty);
  });

  test('compares Decimals exactly — a one-centavo gap is an error', () {
    final i = _base().copyWith(
      totalAmount: Decimal.parse('1000.00'),
      installments: [
        PenaltyInstallmentLine(number: 1, amount: Decimal.parse('333.33')),
        PenaltyInstallmentLine(number: 2, amount: Decimal.parse('333.33')),
        PenaltyInstallmentLine(number: 3, amount: Decimal.parse('333.33')),
      ],
    );
    expect(
      validatePenaltyAgreement(i).map((e) => e.field),
      contains('installments'),
    );
  });
}
