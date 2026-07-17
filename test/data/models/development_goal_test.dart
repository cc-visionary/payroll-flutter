import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/development_goal.dart';

void main() {
  test('parses a review development goal', () {
    final goal = DevelopmentGoal.fromRow({
      'id': 'goal-1',
      'employee_id': 'employee-1',
      'source_review_id': 'review-1',
      'goal_type': 'SKILL_DEVELOPMENT',
      'title': 'Improve product knowledge',
      'target': 'Pass the product assessment',
      'start_date': '2026-07-17',
      'due_date': '2026-10-17',
      'owner_id': 'employee-1',
      'manager_id': 'manager-1',
      'progress': 25,
      'status': 'ON_TRACK',
    });

    expect(goal.goalType, 'SKILL_DEVELOPMENT');
    expect(goal.progress, 25);
    expect(goal.dueDate, DateTime(2026, 10, 17));
  });
}
