import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/kpi_goal.dart';

void main() {
  group('formatGoal', () {
    test('renders each direction with its unit', () {
      expect(
        formatGoal(const KpiGoal(direction: GoalDirection.gte, value: 98), '%'),
        '≥ 98%',
      );
      expect(
        formatGoal(const KpiGoal(direction: GoalDirection.lte, value: 3), '%'),
        '≤ 3%',
      );
      expect(
        formatGoal(const KpiGoal(direction: GoalDirection.eq, value: 0), null),
        '= 0',
      );
      expect(
        formatGoal(
          const KpiGoal(
            direction: GoalDirection.between,
            value: 5,
            valueMax: 10,
          ),
          'days',
        ),
        '5 to 10 days',
      );
    });

    test('drops a trailing .0 so goals read like people write them', () {
      expect(
        formatGoal(const KpiGoal(direction: GoalDirection.lte, value: 3.0), '%'),
        '≤ 3%',
      );
      expect(
        formatGoal(const KpiGoal(direction: GoalDirection.lte, value: 3.5), '%'),
        '≤ 3.5%',
      );
    });

    test('separates a word unit from the number, but not a symbol', () {
      expect(
        formatGoal(const KpiGoal(direction: GoalDirection.lte, value: 14), 'days'),
        '≤ 14 days',
      );
      expect(
        formatGoal(const KpiGoal(direction: GoalDirection.gte, value: 20), '₱'),
        '≥ ₱20',
      );
    });
  });

  group('parseLegacyTarget', () {
    test('reads the at-least family as GTE', () {
      for (final s in ['At least 98%', '≥ 98%', '>= 98', 'minimum 98', 'Min 98%']) {
        final g = parseLegacyTarget(s);
        expect(g?.direction, GoalDirection.gte, reason: s);
        expect(g?.value, 98, reason: s);
      }
    });

    test('reads the at-most family as LTE', () {
      for (final s in [
        'At most 3%',
        '≤ 3%',
        '<= 3',
        'maximum 3',
        'No more than 3%',
        'Under 3',
        'Within 3 days',
      ]) {
        final g = parseLegacyTarget(s);
        expect(g?.direction, GoalDirection.lte, reason: s);
        expect(g?.value, 3, reason: s);
      }
    });

    test('reads zero-defect wording as LTE 0', () {
      expect(parseLegacyTarget('Zero')?.direction, GoalDirection.lte);
      expect(parseLegacyTarget('Zero')?.value, 0);
      expect(parseLegacyTarget('No preventable errors')?.value, 0);
    });

    test('refuses a bare number — direction is not knowable', () {
      // "98%" could be a floor or a ceiling. Guessing would silently invert a
      // goal, so the upgrade UI asks instead of assuming.
      expect(parseLegacyTarget('98%'), isNull);
      expect(parseLegacyTarget('100'), isNull);
    });

    test('returns null for prose with no number', () {
      expect(parseLegacyTarget('Consistently high quality'), isNull);
      expect(parseLegacyTarget(''), isNull);
      expect(parseLegacyTarget(null), isNull);
    });
  });

  group('goalColumns', () {
    test('writes the legacy target text from the structured goal', () {
      final cols = goalColumns(
        const KpiGoal(direction: GoalDirection.lte, value: 3),
        '%',
      );
      expect(cols['goal_direction'], 'LTE');
      expect(cols['goal_value'], 3);
      expect(cols['goal_value_max'], isNull);
      expect(cols['target'], '≤ 3%');
    });

    test('nulls every goal column when there is no goal', () {
      final cols = goalColumns(null, '%');
      expect(cols['goal_direction'], isNull);
      expect(cols['goal_value'], isNull);
      expect(cols['goal_value_max'], isNull);
      expect(cols['target'], isNull);
    });
  });

  group('KpiGoal.fromRow', () {
    test('returns null when the row carries no direction', () {
      expect(KpiGoal.fromRow({'goal_direction': null, 'goal_value': 3}), isNull);
    });

    test('reads numerics that Postgres returned as int or String', () {
      final a = KpiGoal.fromRow({'goal_direction': 'GTE', 'goal_value': 98});
      expect(a?.value, 98);
      final b = KpiGoal.fromRow({'goal_direction': 'LTE', 'goal_value': '3.5'});
      expect(b?.value, 3.5);
    });
  });

  group('frequencyLabelFromCadence', () {
    test('maps the cadence vocabulary to the legacy display text', () {
      expect(frequencyLabelFromCadence('WEEKLY'), 'Weekly');
      expect(frequencyLabelFromCadence('MONTHLY'), 'Monthly');
      expect(frequencyLabelFromCadence('QUARTERLY'), 'Quarterly');
      expect(frequencyLabelFromCadence(null), isNull);
    });
  });
}
