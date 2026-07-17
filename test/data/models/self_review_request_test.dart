import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/self_review_request.dart';

void main() {
  test('parses Lark delivery metadata without exposing submission token', () {
    final request = SelfReviewRequest.fromRow({
      'id': 'request-1',
      'review_id': 'review-1',
      'review_cycle_id': 'cycle-1',
      'employee_id': 'employee-1',
      'form_version': 1,
      'status': 'SENT',
      'form_link': 'https://example.test/form',
      'lark_message_id': 'message-1',
      'sent_at': '2026-07-17T01:00:00Z',
      'attempt_count': 1,
      'error_message': null,
    });

    expect(request.status, 'SENT');
    expect(request.larkMessageId, 'message-1');
    expect(request.sentAt, DateTime.parse('2026-07-17T01:00:00Z'));
    expect(request.attemptCount, 1);
  });
}
