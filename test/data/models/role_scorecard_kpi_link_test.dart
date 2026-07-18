import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';

Map<String, dynamic> baseRow(Object? embeddedKpis) => {
  'id': 'card-1',
  'company_id': 'co-1',
  'job_title': 'Brand Associate',
  'department_id': null,
  'mission_statement': 'Own the storefront.',
  'key_responsibilities': [],
  'kpis': [], // legacy column, ignored when embed present
  'required_skills': [],
  'behavioral_expectations': [],
  'version': 1,
  'salary_range_min': null,
  'salary_range_max': null,
  'base_salary': null,
  'wage_type': 'MONTHLY',
  'work_hours_per_day': 8,
  'work_days_per_week': 'MON_FRI',
  'is_active': true,
  'effective_date': '2026-01-01',
  'hiring_entity_id': null,
  'role_scorecard_kpis': embeddedKpis,
};

void main() {
  test('kpis come from the embedded link, ordered by sort_order', () {
    final card = RoleScorecard.fromRow(baseRow([
      {'target': '3%', 'frequency': 'Monthly', 'sort_order': 1,
       'kpis': {'name': 'Retention', 'measurement_unit': '%'}},
      {'target': '10/day', 'frequency': 'Weekly', 'sort_order': 0,
       'kpis': {'name': 'Throughput', 'measurement_unit': 'orders'}},
    ]));
    expect(card.kpis.map((k) => k.name), ['Throughput', 'Retention']);
    expect(card.kpis.first.measurement, 'orders');
    expect(card.kpis.first.target, '10/day');
    expect(card.kpis[1].frequency, 'Monthly');
  });

  test('falls back to legacy kpis JSON when no embed present', () {
    final row = baseRow(null)..['kpis'] = [
      {'name': 'Legacy', 'measurement': 'x', 'target': '1', 'frequency': 'Monthly'},
    ];
    final card = RoleScorecard.fromRow(row);
    expect(card.kpis.single.name, 'Legacy');
  });

  test('toUpsertPayload no longer includes kpis', () {
    final card = RoleScorecard.fromRow(baseRow(const []));
    expect(card.toUpsertPayload().containsKey('kpis'), isFalse);
  });
}
