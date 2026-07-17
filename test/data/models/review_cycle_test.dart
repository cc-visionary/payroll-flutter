import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/review_cycle.dart';

void main() {
  test('parses review-cycle dates, type, and workflow status', () {
    final cycle = ReviewCycle.fromRow({
      'id': 'cycle-1',
      'company_id': 'company-1',
      'name': '2026 Q3 Review',
      'review_type': 'QUARTERLY',
      'period_start': '2026-07-01',
      'period_end': '2026-09-30',
      'self_review_due_date': '2026-10-05',
      'manager_review_due_date': '2026-10-12',
      'finalization_due_date': '2026-10-17',
      'status': 'DRAFT',
      'lark_form_template_id': 'lark-form-1',
      'created_by': 'user-1',
      'created_at': '2026-07-17T01:00:00Z',
      'updated_at': '2026-07-17T01:00:00Z',
    });

    expect(cycle.reviewType, 'QUARTERLY');
    expect(cycle.periodStart, DateTime.parse('2026-07-01'));
    expect(cycle.finalizationDueDate, DateTime.parse('2026-10-17'));
    expect(cycle.status, 'DRAFT');
  });
}
