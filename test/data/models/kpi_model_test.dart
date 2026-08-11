import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/kpi.dart';
import 'package:payroll_flutter/data/models/role_kpi.dart';
import 'package:payroll_flutter/data/models/kpi_goal.dart';

void main() {
  test('Kpi.fromRow reads the measurable definition', () {
    final k = Kpi.fromRow({
      'id': 'k1',
      'company_id': 'c1',
      'name': 'Return Rate',
      'value_type': 'RATIO',
      'numerator_label': 'Returns received',
      'numerator_source': 'BigSeller',
      'denominator_label': 'Orders shipped',
      'denominator_source': 'BigSeller',
      'unit': '%',
      'cadence': 'WEEKLY',
      'proof_type': 'REPORT_EXPORT',
    });
    expect(k.valueType, 'RATIO');
    expect(k.numeratorLabel, 'Returns received');
    expect(k.denominatorSource, 'BigSeller');
    expect(k.unit, '%');
    expect(k.cadence, 'WEEKLY');
    expect(k.proofType, 'REPORT_EXPORT');
  });

  test('Kpi.fromRow defaults a legacy row rather than throwing', () {
    // Rows written before 20260811000001 have no definition at all.
    final k = Kpi.fromRow({
      'id': 'k1',
      'company_id': 'c1',
      'name': 'Documentation Accuracy',
    });
    expect(k.valueType, 'COUNT');
    expect(k.cadence, 'WEEKLY');
    expect(k.unit, isNull);
    expect(k.numeratorLabel, isNull);
  });

  test('Kpi.toInsert round-trips every definition column', () {
    const k = Kpi(
      id: '',
      companyId: 'c1',
      name: 'Return Rate',
      valueType: 'RATIO',
      numeratorLabel: 'Returns received',
      numeratorSource: 'BigSeller',
      denominatorLabel: 'Orders shipped',
      denominatorSource: 'BigSeller',
      unit: '%',
      cadence: 'WEEKLY',
      proofType: 'REPORT_EXPORT',
    );
    final row = k.toInsert('c1');
    expect(row['value_type'], 'RATIO');
    expect(row['numerator_label'], 'Returns received');
    expect(row['denominator_source'], 'BigSeller');
    expect(row['unit'], '%');
    expect(row['cadence'], 'WEEKLY');
    expect(row['proof_type'], 'REPORT_EXPORT');
  });

  test('Kpi.toInsert blanks empty strings to null', () {
    const k = Kpi(
      id: '',
      companyId: 'c1',
      name: 'X',
      numeratorLabel: '   ',
      unit: '',
    );
    final row = k.toInsert('c1');
    expect(row['numerator_label'], isNull);
    expect(row['unit'], isNull);
  });

  test('RoleKpi.fromRow lifts the goal and the KPI definition', () {
    final rk = RoleKpi.fromRow({
      'kpi_id': 'k1',
      'target': '≤ 3%',
      'frequency': 'Weekly',
      'goal_direction': 'LTE',
      'goal_value': 3,
      'kpis': {'name': 'Return Rate', 'unit': '%', 'cadence': 'WEEKLY'},
    });
    expect(rk.name, 'Return Rate');
    expect(rk.goal?.direction, GoalDirection.lte);
    expect(rk.goal?.value, 3);
    expect(rk.unit, '%');
    expect(rk.cadence, 'WEEKLY');
  });

  test('RoleKpi.fromRow leaves the goal null on a legacy link', () {
    final rk = RoleKpi.fromRow({
      'kpi_id': 'k1',
      'target': 'At least 98%',
      'kpis': {'name': 'Setup Accuracy'},
    });
    expect(rk.goal, isNull);
    expect(rk.target, 'At least 98%');
  });
}
