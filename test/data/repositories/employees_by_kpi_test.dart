import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';

void main() {
  group('employeesByKpi', () {
    test('employee with role KPI set {a,b} and no subset -> tracks both', () {
      const assignee = KpiAssignee(employeeId: 'e1', name: 'Alice');
      final result = employeesByKpi(
        employees: [(assignee: assignee, roleScorecardId: 'r1')],
        roleKpiIds: {
          'r1': {'a', 'b'},
        },
        employeeSubsets: const {},
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

    test(
      'employee with off-role subset {z} -> falls back to full role set {a,b}',
      () {
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
        expect(result['a']!.map((a) => a.name), ['Alice']);
        expect(result['b']!.map((a) => a.name), ['Alice']);
      },
    );

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
