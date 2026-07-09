import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/payroll/engine/daily_rate.dart';

Decimal _d(String s) => Decimal.parse(s);

void main() {
  group('dailyRateFrom', () {
    test('MONTHLY divides by workDaysPerMonth', () {
      // 26000 / 26 = 1000 exactly — avoids scale ambiguity.
      expect(
        dailyRateFrom(
          baseSalary: _d('26000'),
          wageType: 'MONTHLY',
          workDaysPerMonth: 26,
          hoursPerDay: 8,
        ),
        _d('1000'),
      );
    });

    test('MONTHLY non-exact division keeps precision (scale 10)', () {
      final expected =
          (_d('30000') / Decimal.fromInt(26)).toDecimal(scaleOnInfinitePrecision: 10);
      expect(
        dailyRateFrom(
          baseSalary: _d('30000'),
          wageType: 'MONTHLY',
          workDaysPerMonth: 26,
          hoursPerDay: 8,
        ),
        expected,
      );
    });

    test('DAILY returns the base salary unchanged', () {
      expect(
        dailyRateFrom(
          baseSalary: _d('850'),
          wageType: 'DAILY',
          workDaysPerMonth: 26,
          hoursPerDay: 8,
        ),
        _d('850'),
      );
    });

    test('HOURLY multiplies by hoursPerDay', () {
      expect(
        dailyRateFrom(
          baseSalary: _d('100'),
          wageType: 'HOURLY',
          workDaysPerMonth: 26,
          hoursPerDay: 8,
        ),
        _d('800'),
      );
    });
  });
}
