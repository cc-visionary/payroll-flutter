import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/self_review_submission.dart';

void main() {
  test('parses a versioned self-review submission', () {
    final submission = SelfReviewSubmission.fromRow({
      'id': 'submission-1',
      'review_id': 'review-1',
      'employee_id': 'employee-1',
      'version_number': 2,
      'form_version': 1,
      'external_submission_id': 'lark-123',
      'accomplishments': 'Improved packing accuracy',
      'attachments': [
        {'name': 'evidence.pdf'},
      ],
      'submitted_at': '2026-07-17T08:00:00Z',
      'is_active': true,
      'superseded_by_id': null,
    });

    expect(submission.versionNumber, 2);
    expect(submission.isActive, isTrue);
    expect(submission.attachments.single['name'], 'evidence.pdf');
    expect(submission.accomplishments, 'Improved packing accuracy');
  });
}
