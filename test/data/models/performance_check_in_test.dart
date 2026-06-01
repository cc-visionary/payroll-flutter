import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/performance_check_in.dart';

void main() {
  test('PerformanceCheckIn constructs with required fields', () {
    final c = PerformanceCheckIn(
      id: 'c1',
      periodId: 'p1',
      employeeId: 'e1',
      status: 'DRAFT',
      createdAt: DateTime.utc(2026, 4, 1),
      updatedAt: DateTime.utc(2026, 4, 1),
    );
    expect(c.id, 'c1');
    expect(c.status, 'DRAFT');
    expect(c.reviewerId, isNull);
    expect(c.overallRating, isNull);
  });

  test('PerformanceCheckIn.fromRow parses all columns', () {
    final r = <String, dynamic>{
      'id': 'c1',
      'period_id': 'p1',
      'employee_id': 'e1',
      'reviewer_id': 'u2',
      'status': 'SUBMITTED',
      'overall_rating': 4,
      'overall_comments': 'Strong quarter.',
      'accomplishments': 'Shipped X.',
      'challenges': 'Y was hard.',
      'learnings': 'Z',
      'support_needed': null,
      'manager_feedback': null,
      'strengths': null,
      'areas_for_improvement': null,
      'submitted_at': '2026-04-15T08:00:00Z',
      'reviewed_at': null,
      'created_at': '2026-04-01T00:00:00Z',
      'updated_at': '2026-04-15T08:00:00Z',
    };
    final c = PerformanceCheckInFromRow.fromRow(r);
    expect(c.id, 'c1');
    expect(c.reviewerId, 'u2');
    expect(c.overallRating, 4);
    expect(c.accomplishments, 'Shipped X.');
    expect(c.submittedAt?.toUtc(), DateTime.utc(2026, 4, 15, 8));
    expect(c.reviewedAt, isNull);
  });
}
