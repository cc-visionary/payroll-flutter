import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/repositories/payroll_repository.dart';

void main() {
  group('thirteenthMonthPayout (provision model)', () {
    // Under the provision model, `accrued_thirteenth_month_basis` already
    // holds the 13th-month earned (per-release `(basic - late) / 12`
    // summed over releases), so the payout equals the accrued basis.

    test('payout equals the accrued basis', () {
      // A full year's provisions summed to exactly one month's basic.
      expect(
        PayrollRepository.thirteenthMonthPayout(Decimal.parse('12902.50')),
        Decimal.parse('12902.50'),
      );
    });

    test('mid-year basis pays out whatever has accrued', () {
      // Only a few provisions so far — payout is proportionally small.
      expect(
        PayrollRepository.thirteenthMonthPayout(Decimal.parse('807.69')),
        Decimal.parse('807.69'),
      );
    });

    test('zero basis is zero payout', () {
      expect(
        PayrollRepository.thirteenthMonthPayout(Decimal.zero),
        Decimal.zero,
      );
    });

    test('negative basis clamps to zero', () {
      expect(
        PayrollRepository.thirteenthMonthPayout(Decimal.parse('-100')),
        Decimal.zero,
      );
    });
  });
}
