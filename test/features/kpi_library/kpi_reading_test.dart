import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/kpi_goal.dart';
import 'package:payroll_flutter/features/kpi_library/kpi_reading.dart';

void main() {
  group('computeReadingValue', () {
    test('a percent ratio scales to 100 — 3 of 100 orders is 3%', () {
      expect(
        computeReadingValue(
          valueType: 'RATIO',
          unit: '%',
          numerator: 3,
          denominator: 100,
        ),
        3.0,
      );
    });

    test('a non-percent ratio is the plain quotient', () {
      expect(
        computeReadingValue(
          valueType: 'RATIO',
          unit: 'orders/day',
          numerator: 90,
          denominator: 30,
        ),
        3.0,
      );
    });

    test('a count is the numerator, denominator ignored', () {
      expect(
        computeReadingValue(
          valueType: 'COUNT',
          unit: 'orders',
          numerator: 42,
          denominator: 7,
        ),
        42.0,
      );
    });

    test('a zero denominator yields no reading rather than infinity', () {
      // A week with no orders shipped cannot have a return RATE. Reporting 0%
      // would read as a perfect week.
      expect(
        computeReadingValue(
          valueType: 'RATIO',
          unit: '%',
          numerator: 0,
          denominator: 0,
        ),
        isNull,
      );
    });

    test('a missing numerator or denominator yields no reading', () {
      expect(
        computeReadingValue(
          valueType: 'RATIO',
          unit: '%',
          numerator: null,
          denominator: 100,
        ),
        isNull,
      );
      expect(
        computeReadingValue(
          valueType: 'RATIO',
          unit: '%',
          numerator: 3,
          denominator: null,
        ),
        isNull,
      );
    });
  });

  group('isOnTrack', () {
    test('GTE is met at or above the bar', () {
      const g = KpiGoal(direction: GoalDirection.gte, value: 98);
      expect(isOnTrack(98, g), isTrue);
      expect(isOnTrack(99.5, g), isTrue);
      expect(isOnTrack(97.9, g), isFalse);
    });

    test('LTE is met at or below the bar', () {
      const g = KpiGoal(direction: GoalDirection.lte, value: 3);
      expect(isOnTrack(3, g), isTrue);
      expect(isOnTrack(0, g), isTrue);
      expect(isOnTrack(7.8, g), isFalse);
    });

    test('EQ tolerates floating-point dust', () {
      const g = KpiGoal(direction: GoalDirection.eq, value: 0.3);
      expect(isOnTrack(0.1 + 0.2, g), isTrue);
      expect(isOnTrack(0.31, g), isFalse);
    });

    test('BETWEEN is inclusive of both bounds', () {
      const g = KpiGoal(
        direction: GoalDirection.between,
        value: 5,
        valueMax: 10,
      );
      expect(isOnTrack(5, g), isTrue);
      expect(isOnTrack(10, g), isTrue);
      expect(isOnTrack(4.9, g), isFalse);
      expect(isOnTrack(10.1, g), isFalse);
    });

    test('no reading or no goal is unknown, not off-track', () {
      // An un-submitted week must never read as a miss.
      expect(isOnTrack(null, const KpiGoal(direction: GoalDirection.gte, value: 1)), isNull);
      expect(isOnTrack(5, null), isNull);
    });
  });
}
