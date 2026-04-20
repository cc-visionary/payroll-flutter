import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/repositories/payroll_repository.dart';

void main() {
  group('thirteenthMonthPayout', () {
    test('divides basis by 12 with banker rounding to 2dp', () {
      // Annual basic = ₱154,830 → payout = 12,902.50 exactly.
      expect(
        PayrollRepository.thirteenthMonthPayout(Decimal.parse('154830')),
        Decimal.parse('12902.50'),
      );
    });

    test('rounds half-up on 2nd decimal', () {
      // 1 / 12 = 0.0833333... → 0.08
      expect(
        PayrollRepository.thirteenthMonthPayout(Decimal.parse('1')),
        Decimal.parse('0.08'),
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
