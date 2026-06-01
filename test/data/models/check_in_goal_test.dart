import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/check_in_goal.dart';

void main() {
  test('CheckInGoal constructs with required fields', () {
    final g = CheckInGoal(
      id: 'g1',
      checkInId: 'c1',
      goalType: 'PERFORMANCE',
      title: 'Ship feature X',
      progress: 0,
      status: 'IN_PROGRESS',
      carryForward: false,
      createdAt: DateTime.utc(2026, 4, 1),
      updatedAt: DateTime.utc(2026, 4, 1),
    );
    expect(g.id, 'g1');
    expect(g.goalType, 'PERFORMANCE');
    expect(g.progress, 0);
    expect(g.targetDate, isNull);
  });

  test('CheckInGoal.fromRow parses all columns', () {
    final r = <String, dynamic>{
      'id': 'g1',
      'check_in_id': 'c1',
      'goal_type': 'LEARNING',
      'title': 'Read X book',
      'description': 'Notes in Notion.',
      'target_date': '2026-06-30',
      'progress': 50,
      'status': 'IN_PROGRESS',
      'self_assessment': null,
      'manager_assessment': null,
      'rating': null,
      'carry_forward': false,
      'created_at': '2026-04-01T00:00:00Z',
      'updated_at': '2026-04-15T00:00:00Z',
    };
    final g = CheckInGoalFromRow.fromRow(r);
    expect(g.goalType, 'LEARNING');
    expect(g.progress, 50);
    expect(g.targetDate, DateTime.parse('2026-06-30'));
    expect(g.carryForward, isFalse);
  });
}
