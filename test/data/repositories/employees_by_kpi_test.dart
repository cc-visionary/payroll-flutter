import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';

void main() {
  group('employeesByKpi', () {
    // Spec A Decision 4: the stored set IS the set. An employee with no
    // stored set is a gap to close, not somebody tracking their whole role —
    // otherwise the Balance tab's "N people have no KPI set" chip and the
    // people list one viewport below it contradict each other, and the
    // "N KPIs measuring nobody" chip credits KPIs to a person nobody curated.
    test('employee with NO stored set -> tracks nothing at all', () {
      const assignee = KpiAssignee(employeeId: 'e1', name: 'Alice');
      final result = employeesByKpi(
        employees: [(assignee: assignee, roleScorecardId: 'r1')],
        roleKpiIds: {
          'r1': {'a', 'b'},
        },
        employeeSubsets: const {},
      );
      expect(result.isEmpty, isTrue);
    });

    test('employee with an EMPTY stored set -> tracks nothing at all', () {
      const assignee = KpiAssignee(employeeId: 'e1', name: 'Alice');
      final result = employeesByKpi(
        employees: [(assignee: assignee, roleScorecardId: 'r1')],
        roleKpiIds: {
          'r1': {'a', 'b'},
        },
        employeeSubsets: const {'e1': <String>{}},
      );
      expect(result.isEmpty, isTrue);
    });

    test('employee whose stored set covers the whole role -> tracks both', () {
      const assignee = KpiAssignee(employeeId: 'e1', name: 'Alice');
      final result = employeesByKpi(
        employees: [(assignee: assignee, roleScorecardId: 'r1')],
        roleKpiIds: {
          'r1': {'a', 'b'},
        },
        employeeSubsets: {
          'e1': {'a', 'b'},
        },
      );
      expect(result['a']!.map((a) => a.name), ['Alice']);
      expect(result['b']!.map((a) => a.name), ['Alice']);
    });

    test('employee with on-role subset {a} -> tracks only a', () {
      const assignee = KpiAssignee(employeeId: 'e1', name: 'Alice');
      final result = employeesByKpi(
        employees: [(assignee: assignee, roleScorecardId: 'r1')],
        roleKpiIds: {
          'r1': {'a', 'b'},
        },
        employeeSubsets: {
          'e1': {'a'},
        },
      );
      expect(result['a']!.map((a) => a.name), ['Alice']);
      expect(result.containsKey('b'), isFalse);
    });

    // A stored set that no longer intersects the role (the person was moved
    // to another card) reads exactly like an absent one: a gap, not the whole
    // role. Same trigger condition as the Needs-attention chip's.
    test('employee with an off-role subset {z} -> tracks nothing at all', () {
      const assignee = KpiAssignee(employeeId: 'e1', name: 'Alice');
      final result = employeesByKpi(
        employees: [(assignee: assignee, roleScorecardId: 'r1')],
        roleKpiIds: {
          'r1': {'a', 'b'},
        },
        employeeSubsets: {
          'e1': {'z'},
        },
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
        employeeSubsets: const {},
      );
      expect(result.isEmpty, isTrue);
    });
  });
}
