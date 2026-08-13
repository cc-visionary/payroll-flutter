import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';

void main() {
  group('employeesByKpi', () {
    // Pure inheritance: a person's KPIs are their role's KPIs, with no
    // per-employee subset to intersect against. An employee tracks every KPI
    // their role card links, full stop.
    test("employee on a role -> tracks every one of the role's KPIs", () {
      const assignee = KpiAssignee(employeeId: 'e1', name: 'Alice');
      final result = employeesByKpi(
        employees: [(assignee: assignee, roleScorecardId: 'r1')],
        roleKpiIds: {
          'r1': {'a', 'b'},
        },
      );
      expect(result['a']!.map((a) => a.name), ['Alice']);
      expect(result['b']!.map((a) => a.name), ['Alice']);
    });

    test('a role with no KPIs -> tracks nothing', () {
      const assignee = KpiAssignee(employeeId: 'e1', name: 'Alice');
      final result = employeesByKpi(
        employees: [(assignee: assignee, roleScorecardId: 'r1')],
        roleKpiIds: const {},
      );
      expect(result.isEmpty, isTrue);
    });

    test('employee with null roleScorecardId -> tracked on nothing', () {
      const assignee = KpiAssignee(employeeId: 'e1', name: 'Alice');
      final result = employeesByKpi(
        employees: [(assignee: assignee, roleScorecardId: null)],
        roleKpiIds: {
          'r1': {'a', 'b'},
        },
      );
      expect(result.isEmpty, isTrue);
    });

    test('two employees on the same role both track the same KPI', () {
      const alice = KpiAssignee(employeeId: 'e1', name: 'Alice');
      const bob = KpiAssignee(employeeId: 'e2', name: 'Bob');
      final result = employeesByKpi(
        employees: [
          (assignee: alice, roleScorecardId: 'r1'),
          (assignee: bob, roleScorecardId: 'r1'),
        ],
        roleKpiIds: {
          'r1': {'a'},
        },
      );
      expect(result['a']!.map((a) => a.name), containsAll(['Alice', 'Bob']));
      expect(result['a']!.length, 2);
    });

    test('employees on different roles do not cross-track', () {
      const alice = KpiAssignee(employeeId: 'e1', name: 'Alice');
      const bob = KpiAssignee(employeeId: 'e2', name: 'Bob');
      final result = employeesByKpi(
        employees: [
          (assignee: alice, roleScorecardId: 'r1'),
          (assignee: bob, roleScorecardId: 'r2'),
        ],
        roleKpiIds: {
          'r1': {'a'},
          'r2': {'b'},
        },
      );
      expect(result['a']!.map((a) => a.name), ['Alice']);
      expect(result['b']!.map((a) => a.name), ['Bob']);
    });
  });
}
