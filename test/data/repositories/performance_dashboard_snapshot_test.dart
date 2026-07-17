import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/development_goal.dart';
import 'package:payroll_flutter/data/models/employee_review.dart';
import 'package:payroll_flutter/data/models/review_cycle.dart';
import 'package:payroll_flutter/data/repositories/review_cycle_repository.dart';

void main() {
  test('summarizes review workload and goal risk', () {
    EmployeeReview review(String id, String status) => EmployeeReview.fromRow({
      'id': id,
      'review_cycle_id': 'cycle-1',
      'employee_id': 'employee-$id',
      'employee_name_snapshot': 'Employee $id',
      'responsibility_card_id': 'card-1',
      'responsibility_card_version': 1,
      'direct_manager_id': 'manager-1',
      'review_type': 'QUARTERLY',
      'review_period_start': '2026-07-01',
      'review_period_end': '2026-09-30',
      'status': status,
      'responsibility_snapshot': [],
      'created_at': '2026-07-01T00:00:00Z',
      'updated_at': '2026-07-01T00:00:00Z',
    });

    DevelopmentGoal goal(String id, String status) => DevelopmentGoal.fromRow({
      'id': id,
      'employee_id': 'employee-1',
      'source_review_id': 'review-1',
      'goal_type': 'PERFORMANCE',
      'title': 'Goal $id',
      'target': 'Target',
      'start_date': '2026-07-01',
      'due_date': '2026-09-30',
      'owner_id': 'employee-1',
      'manager_id': 'manager-1',
      'progress': 25,
      'status': status,
    });

    final snapshot = PerformanceDashboardSnapshot(
      reviews: [
        review('1', 'AWAITING_SELF_REVIEW'),
        review('2', 'MANAGER_REVIEW_IN_PROGRESS'),
        review('3', 'READY_FOR_DISCUSSION'),
        review('4', 'OVERDUE'),
      ],
      cycles: const [],
      goals: [goal('1', 'ON_TRACK'), goal('2', 'AT_RISK')],
      employeesWithoutManager: 1,
      employeesWithoutResponsibilityCard: 2,
    );

    expect(snapshot.awaitingSelfReview, 1);
    expect(snapshot.pendingManagerReview, 2);
    expect(snapshot.readyForDiscussion, 1);
    expect(snapshot.overdueReviews, 1);
    expect(snapshot.activeGoals, 2);
    expect(snapshot.goalsAtRisk, 1);
  });

  group('overdueReviewsAsOf', () {
    ReviewCycle cycle({
      required String selfDue,
      required String managerDue,
    }) => ReviewCycle.fromRow({
      'id': 'cycle-1',
      'company_id': 'company-1',
      'name': 'Q3 2026',
      'review_type': 'QUARTERLY',
      'period_start': '2026-07-01',
      'period_end': '2026-09-30',
      'self_review_due_date': selfDue,
      'manager_review_due_date': managerDue,
      'status': 'ACTIVE',
      'lark_form_template_id': 'tmpl',
      'created_by': 'user-1',
      'created_at': '2026-07-01T00:00:00Z',
      'updated_at': '2026-07-01T00:00:00Z',
    });

    EmployeeReview review(String id, String status) => EmployeeReview.fromRow({
      'id': id,
      'review_cycle_id': 'cycle-1',
      'employee_id': 'employee-$id',
      'employee_name_snapshot': 'Employee $id',
      'responsibility_card_id': 'card-1',
      'responsibility_card_version': 1,
      'direct_manager_id': 'manager-1',
      'review_type': 'QUARTERLY',
      'review_period_start': '2026-07-01',
      'review_period_end': '2026-09-30',
      'status': status,
      'responsibility_snapshot': [],
      'created_at': '2026-07-01T00:00:00Z',
      'updated_at': '2026-07-01T00:00:00Z',
    });

    PerformanceDashboardSnapshot snapshotOf(List<EmployeeReview> reviews) =>
        PerformanceDashboardSnapshot(
          reviews: reviews,
          cycles: [cycle(selfDue: '2026-08-10', managerDue: '2026-08-20')],
          goals: const [],
          employeesWithoutManager: 0,
          employeesWithoutResponsibilityCard: 0,
        );

    test('a self-review past its due date counts as overdue', () {
      final snapshot = snapshotOf([review('1', 'AWAITING_SELF_REVIEW')]);
      expect(snapshot.overdueReviewsAsOf(DateTime(2026, 8, 11)), 1);
    });

    test('the same review before its due date does not', () {
      final snapshot = snapshotOf([review('1', 'AWAITING_SELF_REVIEW')]);
      expect(snapshot.overdueReviewsAsOf(DateTime(2026, 8, 9)), 0);
    });

    test('a manager review is measured against the manager due date', () {
      final snapshot = snapshotOf([review('1', 'MANAGER_REVIEW_IN_PROGRESS')]);
      // past the self-review date but not yet the manager one
      expect(snapshot.overdueReviewsAsOf(DateTime(2026, 8, 15)), 0);
      expect(snapshot.overdueReviewsAsOf(DateTime(2026, 8, 21)), 1);
    });

    test('finalized and ready-for-discussion reviews are never overdue', () {
      final snapshot = snapshotOf([
        review('1', 'FINALIZED'),
        review('2', 'READY_FOR_DISCUSSION'),
        review('3', 'DISCUSSION_COMPLETED'),
      ]);
      expect(snapshot.overdueReviewsAsOf(DateTime(2026, 12, 31)), 0);
    });

    test('a stored OVERDUE status is still honoured', () {
      final snapshot = snapshotOf([review('1', 'OVERDUE')]);
      expect(snapshot.overdueReviewsAsOf(DateTime(2026, 7, 2)), 1);
    });

    test('a review whose cycle is missing is not counted', () {
      final snapshot = PerformanceDashboardSnapshot(
        reviews: [review('1', 'AWAITING_SELF_REVIEW')],
        cycles: const [],
        goals: const [],
        employeesWithoutManager: 0,
        employeesWithoutResponsibilityCard: 0,
      );
      expect(snapshot.overdueReviewsAsOf(DateTime(2026, 12, 31)), 0);
    });
  });
}
