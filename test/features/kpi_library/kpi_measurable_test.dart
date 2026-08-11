import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/kpi_goal.dart';
import 'package:payroll_flutter/features/kpi_library/kpi_measurable.dart';

void main() {
  List<String> gapsFor({
    String? valueType = 'RATIO',
    String? unit = '%',
    String? numeratorLabel = 'Returns received',
    String? numeratorSource = 'BigSeller',
    String? denominatorLabel = 'Orders shipped',
    String? denominatorSource = 'BigSeller',
  }) => kpiDefinitionGaps(
    valueType: valueType,
    unit: unit,
    numeratorLabel: numeratorLabel,
    numeratorSource: numeratorSource,
    denominatorLabel: denominatorLabel,
    denominatorSource: denominatorSource,
  );

  test('a fully specified ratio has no gaps', () {
    expect(gapsFor(), isEmpty);
    expect(
      isKpiDefined(
        valueType: 'RATIO',
        unit: '%',
        numeratorLabel: 'Returns received',
        numeratorSource: 'BigSeller',
        denominatorLabel: 'Orders shipped',
        denominatorSource: 'BigSeller',
      ),
      isTrue,
    );
  });

  test('names every missing piece, not just the first', () {
    final gaps = gapsFor(numeratorSource: null, denominatorLabel: '  ');
    expect(gaps, containsAll(['source', 'denominator']));
    expect(gaps.length, 2);
  });

  test('a COUNT needs no denominator', () {
    expect(
      gapsFor(
        valueType: 'COUNT',
        unit: 'orders',
        denominatorLabel: null,
        denominatorSource: null,
      ),
      isEmpty,
    );
  });

  test('a RATIO without a denominator is not defined', () {
    final gaps = gapsFor(denominatorLabel: null, denominatorSource: null);
    expect(gaps, contains('denominator'));
    expect(gaps, contains('denominator source'));
  });

  test('the legacy library rows read as undefined', () {
    // "Documentation Accuracy" — a name and prose, nothing countable.
    final gaps = kpiDefinitionGaps(
      valueType: 'COUNT',
      unit: null,
      numeratorLabel: null,
      numeratorSource: null,
      denominatorLabel: null,
      denominatorSource: null,
    );
    expect(gaps, containsAll(['unit', 'what is counted', 'source']));
  });

  test('measurable for a role needs a defined KPI AND a goal', () {
    const goal = KpiGoal(direction: GoalDirection.lte, value: 3);
    expect(isMeasurableForRole(defined: true, goal: goal), isTrue);
    expect(isMeasurableForRole(defined: true, goal: null), isFalse);
    expect(isMeasurableForRole(defined: false, goal: goal), isFalse);
  });

  test('the vocabularies match the database check constraints', () {
    expect(kKpiValueTypes, [
      'COUNT',
      'RATIO',
      'CURRENCY',
      'PERCENT',
      'DURATION',
    ]);
    expect(kKpiCadences, ['WEEKLY', 'MONTHLY', 'QUARTERLY']);
    expect(kKpiProofTypes, ['REPORT_EXPORT', 'SCREENSHOT', 'SYSTEM_LINK']);
  });
}
