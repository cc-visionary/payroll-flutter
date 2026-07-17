import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/manager_review.dart';

void main() {
  test('parses strengths and development areas', () {
    final review = ManagerReview.fromRow({
      'id': 'manager-review-1',
      'review_id': 'review-1',
      'overall_feedback': 'Consistent performance',
      'strengths': [
        {'title': 'Accuracy', 'evidence': 'No packing errors'},
      ],
      'development_areas': [
        {'area': 'Product knowledge'},
      ],
      'recommended_outcome': 'CONTINUE_DEVELOPMENT',
      'submitted_at': '2026-07-17T08:00:00Z',
    });

    expect(review.strengths.single['title'], 'Accuracy');
    expect(review.developmentAreas.single['area'], 'Product knowledge');
    expect(review.submittedAt, isNotNull);
  });
}
