import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/review_skill_rating.dart';

void main() {
  test('behavioral expectation snapshot does not require a level', () {
    final rating = ReviewSkillRating.fromRow({
      'id': 'rating-1',
      'review_id': 'review-1',
      'snapshot_order': 4,
      'skill_name': 'Accountability',
      'skill_description': 'Owns results and escalates early.',
      'skill_category': 'BEHAVIORAL',
      'manager_rating': null,
      'employee_comment': null,
      'manager_comment': null,
      'development_needed': false,
    });

    expect(rating.skillCategory, 'BEHAVIORAL');
    expect(rating.skillDescription, 'Owns results and escalates early.');
  });
}
