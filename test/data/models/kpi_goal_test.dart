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

    test('a currency BETWEEN goal carries the unit on both bounds', () {
      expect(
        formatGoal(
          const KpiGoal(direction: GoalDirection.between, value: 5, valueMax: 10),
          '₱',
        ),
        '₱5 to ₱10',
      );
    });

    test('a word-unit BETWEEN goal carries the unit on the upper bound only', () {
      expect(
        formatGoal(
          const KpiGoal(direction: GoalDirection.between, value: 5, valueMax: 10),
          'days',
        ),
        '5 to 10 days',
      );
    });

    test('a unitless BETWEEN goal renders as plain numbers', () {
      expect(
        formatGoal(
          const KpiGoal(direction: GoalDirection.between, value: 5, valueMax: 10),
          null,
        ),
        '5 to 10',
      );
    });
  });

  group('parseLegacyTarget', () {
    test('reads the at-least family as GTE', () {
      for (final s in [
        'At least 98%',
        '≥ 98%',
        '>= 98',
        'minimum 98',
        'Min 98%',
        // Dotted abbreviation — Dart's regex backtracks off the literal ".".
        'Min. 98%',
      ]) {
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
        // Dotted abbreviation — Dart's regex backtracks off the literal ".".
        'Max. 3',
      ]) {
        final g = parseLegacyTarget(s);
        expect(g?.direction, GoalDirection.lte, reason: s);
        expect(g?.value, 3, reason: s);
      }
    });

    test('does not fire on words that merely contain under/below/within', () {
      // "Thunder" contains "under"; "Undercut" starts with it. Without word
      // boundaries either would misparse as an LTE goal.
      expect(parseLegacyTarget('Thunder 3'), isNull);
      expect(parseLegacyTarget('Undercut 3'), isNull);
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

    test('reads an explicitly-stated floor as GTE, never as LTE', () {
      // "no less than" contains "less than"; a substring match against the
      // at-most family would invert the goal.
      for (final s in ['No less than 98%', 'Not less than 98']) {
        final g = parseLegacyTarget(s);
        expect(g?.direction, GoalDirection.gte, reason: s);
        expect(g?.value, 98, reason: s);
      }
    });

    test('does not fire on words that merely contain min or max', () {
      expect(parseLegacyTarget('Minimal downtime: 5'), isNull);
      expect(parseLegacyTarget('Maximal uptime 5'), isNull);
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

    test('goalColumns round-trips a BETWEEN goal', () {
      final cols = goalColumns(
        const KpiGoal(
          direction: GoalDirection.between,
          value: 5,
          valueMax: 10,
        ),
        'days',
      );
      expect(cols['goal_direction'], 'BETWEEN');
      expect(cols['goal_value'], 5);
      expect(cols['goal_value_max'], 10);
      expect(cols['target'], '5 to 10 days');
    });
  });

  group('KpiGoal constructor', () {
    test('a BETWEEN goal without an upper bound is rejected, not rendered', () {
      expect(
        () => KpiGoal(
          direction: GoalDirection.between,
          value: 5,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('a BETWEEN goal whose upper bound is not above the lower bound is rejected', () {
      // valueMax <= value would render an inverted or empty range
      // ("10 to 5 days") and isOnTrack would evaluate an empty interval.
      expect(
        () => KpiGoal(
          direction: GoalDirection.between,
          value: 10,
          valueMax: 5,
        ),
        throwsA(isA<AssertionError>()),
      );
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
