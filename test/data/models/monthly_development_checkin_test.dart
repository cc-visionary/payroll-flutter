import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/monthly_development_checkin.dart';

void main() {
  test('parses a monthly check-in with goal updates', () {
    final checkin = MonthlyDevelopmentCheckin.fromRow({
      'id': 'checkin-1',
      'employee_id': 'employee-1',
      'manager_id': 'manager-1',
      'source_review_id': 'review-1',
      'checkin_date': '2026-08-17',
      'agreed_next_action': 'Complete the product assessment',
      'action_owner_id': 'employee-1',
      'action_due_date': '2026-08-31',
      'general_status': 'ON_TRACK',
      'completed_at': '2026-08-17T08:00:00Z',
      'monthly_checkin_goal_updates': [
        {
          'id': 'update-1',
          'goal_id': 'goal-1',
          'progress': 50,
          'goal_status': 'ON_TRACK',
          'progress_note': 'Assessment scheduled',
        },
      ],
    });

    expect(checkin.generalStatus, 'ON_TRACK');
    expect(checkin.goalUpdates.single.progress, 50);
    expect(checkin.agreedNextAction, 'Complete the product assessment');
  });
}
