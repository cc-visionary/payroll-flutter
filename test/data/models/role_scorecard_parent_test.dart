import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';

void main() {
  test('reads and writes the seat parent', () {
    final card = RoleScorecard.fromRow({
      'id': 'seat-1',
      'company_id': 'co-1',
      'job_title': 'Sourcing',
      'mission_statement': '',
      'wage_type': 'MONTHLY',
      'work_hours_per_day': 8,
      'work_days_per_week': 'Monday to Saturday',
      'is_active': true,
      'effective_date': '2026-01-01',
      'parent_id': 'seat-root',
    });
    expect(card.parentId, 'seat-root');
    expect(card.toUpsertPayload()['parent_id'], 'seat-root');
  });

  test('a root seat has no parent, and null round-trips', () {
    final card = RoleScorecard.fromRow({
      'id': 'seat-1',
      'company_id': 'co-1',
      'job_title': 'Visionary',
      'mission_statement': '',
      'wage_type': 'MONTHLY',
      'work_hours_per_day': 8,
      'work_days_per_week': 'Monday to Saturday',
      'is_active': true,
      'effective_date': '2026-01-01',
    });
    expect(card.parentId, isNull);
    expect(card.toUpsertPayload().containsKey('parent_id'), isTrue);
    expect(card.toUpsertPayload()['parent_id'], isNull);
  });
}
