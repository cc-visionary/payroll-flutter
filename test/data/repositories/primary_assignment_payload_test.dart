import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/repositories/workforce_planning_repository.dart';

void main() {
  test('owner wins: a person PRIMARY @100', () {
    final p = primaryAssignmentPayload(
        companyId: 'c', taskId: 't', ownerEmployeeId: 'e', roleScorecardId: 'rs');
    expect(p!['employee_id'], 'e');
    expect(p['role_scorecard_id'], isNull);
    expect(p['assignment_role'], 'PRIMARY');
    expect(p['allocation_pct'], 100);
  });
  test('no owner, has card: a card PRIMARY @100', () {
    final p = primaryAssignmentPayload(companyId: 'c', taskId: 't', roleScorecardId: 'rs');
    expect(p!['role_scorecard_id'], 'rs');
    expect(p['employee_id'], isNull);
    expect(p['allocation_pct'], 100);
  });
  test('neither owner nor card: null (unassigned)', () {
    expect(primaryAssignmentPayload(companyId: 'c', taskId: 't'), isNull);
  });
}
