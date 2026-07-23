import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';

void main() {
  test('fromRow reads a card PRIMARY assignment', () {
    final a = WpTaskAssignment.fromRow({
      'id': 'a1', 'company_id': 'c', 'task_id': 't1',
      'role_scorecard_id': 'rs1', 'employee_id': null,
      'assignment_role': 'PRIMARY', 'allocation_pct': 100,
    });
    expect(a.roleScorecardId, 'rs1');
    expect(a.employeeId, isNull);
    expect(a.assignmentRole, 'PRIMARY');
    expect(a.allocationPct, 100);
  });

  test('fromRow reads a person CONTRIBUTOR with a fractional pct', () {
    final a = WpTaskAssignment.fromRow({
      'id': 'a2', 'company_id': 'c', 'task_id': 't1',
      'role_scorecard_id': null, 'employee_id': 'e1',
      'assignment_role': 'CONTRIBUTOR', 'allocation_pct': 42.5,
    });
    expect(a.employeeId, 'e1');
    expect(a.assignmentRole, 'CONTRIBUTOR');
    expect(a.allocationPct, 42.5);
  });

  test('toUpsert writes the target + role + pct', () {
    const a = WpTaskAssignment(id: '', companyId: 'c', taskId: 't1',
        roleScorecardId: 'rs1', assignmentRole: 'PRIMARY', allocationPct: 60);
    final m = a.toUpsert('c');
    expect(m['task_id'], 't1');
    expect(m['role_scorecard_id'], 'rs1');
    expect(m['employee_id'], isNull);
    expect(m['assignment_role'], 'PRIMARY');
    expect(m['allocation_pct'], 60);
  });
}
