import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';

void main() {
  test('fromRow maps hiring_entity_id; null when absent', () {
    final withEntity = RoleScorecard.fromRow({
      'id': 's1',
      'company_id': 'c1',
      'job_title': 'Dev',
      'mission_statement': 'm',
      'key_responsibilities': [],
      'kpis': [],
      'wage_type': 'MONTHLY',
      'work_hours_per_day': 8,
      'work_days_per_week': 'Monday to Saturday',
      'is_active': true,
      'effective_date': '2026-01-01',
      'hiring_entity_id': 'he1',
    });
    expect(withEntity.hiringEntityId, 'he1');

    final without = RoleScorecard.fromRow({
      'id': 's2',
      'company_id': 'c1',
      'job_title': 'Dev',
      'mission_statement': 'm',
      'key_responsibilities': [],
      'kpis': [],
      'wage_type': 'MONTHLY',
      'work_hours_per_day': 8,
      'work_days_per_week': 'Monday to Saturday',
      'is_active': true,
      'effective_date': '2026-01-01',
    });
    expect(without.hiringEntityId, isNull);
  });

  test('toUpsertPayload includes hiring_entity_id', () {
    final card = RoleScorecard.fromRow({
      'id': 's1',
      'company_id': 'c1',
      'job_title': 'Dev',
      'mission_statement': 'm',
      'key_responsibilities': [],
      'kpis': [],
      'wage_type': 'MONTHLY',
      'work_hours_per_day': 8,
      'work_days_per_week': 'Monday to Saturday',
      'is_active': true,
      'effective_date': '2026-01-01',
      'hiring_entity_id': 'he1',
    });
    expect(card.toUpsertPayload()['hiring_entity_id'], 'he1');
  });
}
