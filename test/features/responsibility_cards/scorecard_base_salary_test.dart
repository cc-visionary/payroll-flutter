import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/responsibility_cards/scorecard_base_salary.dart';

Decimal _d(String s) => Decimal.parse(s);

void main() {
  group('resolveScorecardBaseSalaryOnSave', () {
    test('EDIT: base salary is immutable — the typed value is ignored', () {
      // The whole point: editing must never reprice employees on this role.
      final result = resolveScorecardBaseSalaryOnSave(
        isEdit: true,
        existingBaseSalary: _d('1184.61'),
        typedText: '9999',
      );
      expect(result, _d('1184.61'));
    });

    test('EDIT: a null existing value stays null', () {
      final result = resolveScorecardBaseSalaryOnSave(
        isEdit: true,
        existingBaseSalary: null,
        typedText: '5000',
      );
      expect(result, isNull);
    });

    test('CREATE: the typed value is used', () {
      final result = resolveScorecardBaseSalaryOnSave(
        isEdit: false,
        existingBaseSalary: null,
        typedText: '1300',
      );
      expect(result, _d('1300'));
    });

    test('CREATE: empty text -> null', () {
      final result = resolveScorecardBaseSalaryOnSave(
        isEdit: false,
        existingBaseSalary: null,
        typedText: '   ',
      );
      expect(result, isNull);
    });

    test('CREATE: an unparseable value (e.g. a thousands comma) -> null', () {
      final result = resolveScorecardBaseSalaryOnSave(
        isEdit: false,
        existingBaseSalary: null,
        typedText: '1,300',
      );
      expect(result, isNull);
    });
  });
}
