import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/workflow_instance.dart';

void main() {
  test('WorkflowInstance constructs with required fields', () {
    final w = WorkflowInstance(
      id: 'w1',
      companyId: 'c1',
      employeeId: 'e1',
      workflowType: 'SEPARATION',
      status: 'IN_PROGRESS',
      title: 'Separation — Maria Santos',
      context: const {},
      initiatedById: 'u1',
      createdAt: DateTime.utc(2026, 5, 31),
      updatedAt: DateTime.utc(2026, 5, 31),
    );
    expect(w.id, 'w1');
    expect(w.workflowType, 'SEPARATION');
    expect(w.status, 'IN_PROGRESS');
    expect(w.completedAt, isNull);
  });

  test('WorkflowInstance.fromRow parses all columns', () {
    final r = <String, dynamic>{
      'id': 'w1',
      'company_id': 'c1',
      'employee_id': 'e1',
      'workflow_type': 'HIRING',
      'status': 'DRAFT',
      'title': 'Hiring — Juan Cruz',
      'context': {'applicant_id': 'a1'},
      'result': null,
      'initiated_by_id': 'u1',
      'completed_at': null,
      'cancelled_at': null,
      'cancel_reason': null,
      'created_at': '2026-05-31T08:00:00Z',
      'updated_at': '2026-05-31T08:00:00Z',
    };
    final w = WorkflowInstanceFromRow.fromRow(r);
    expect(w.id, 'w1');
    expect(w.workflowType, 'HIRING');
    expect(w.status, 'DRAFT');
    expect(w.title, 'Hiring — Juan Cruz');
    expect(w.context['applicant_id'], 'a1');
    expect(w.completedAt, isNull);
    expect(w.cancelledAt, isNull);
  });
}
