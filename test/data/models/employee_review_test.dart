import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee_review.dart';

void main() {
  test('parses immutable Responsibility Card snapshot metadata', () {
    final review = EmployeeReview.fromRow({
      'id': 'review-1',
      'review_cycle_id': 'cycle-1',
      'employee_id': 'employee-1',
      'employee_name_snapshot': 'Maria Santos',
      'responsibility_card_id': 'card-1',
      'responsibility_card_version': 3,
      'direct_manager_id': 'manager-1',
      'review_type': 'QUARTERLY',
      'review_period_start': '2026-07-01',
      'review_period_end': '2026-09-30',
      'status': 'DRAFT',
      'responsibility_snapshot': [
        {
          'area': 'Customer service',
          'tasks': ['Respond to customers'],
        },
      ],
      'overall_rating': null,
      'overall_outcome': null,
      'finalized_by': null,
      'finalized_at': null,
      'created_at': '2026-07-17T01:00:00Z',
      'updated_at': '2026-07-17T01:00:00Z',
    });

    expect(review.employeeNameSnapshot, 'Maria Santos');
    expect(review.responsibilityCardVersion, 3);
    expect(review.responsibilitySnapshot.single['area'], 'Customer service');
    expect(review.overallRating, isNull);
  });
}
