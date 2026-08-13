import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/kpi_result.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/features/kpi_results/kpi_population.dart';

Employee _e(
  String id, {
  String? roleId,
  String? deptId,
  String status = 'ACTIVE',
  DateTime? deletedAt,
}) => Employee(
  id: id,
  companyId: 'c',
  employeeNumber: id,
  firstName: id,
  lastName: 'X',
  roleScorecardId: roleId,
  departmentId: deptId,
  employmentType: 'FULL_TIME',
  employmentStatus: status,
  deletedAt: deletedAt,
  hireDate: DateTime(2024, 1, 1),
  isRankAndFile: true,
  isOtEligible: false,
  isNdEligible: false,
  isHolidayPayEligible: false,
  sssEligibilityOverride: false,
  philhealthEligibilityOverride: false,
  pagibigEligibilityOverride: false,
  taxOnFullEarnings: false,
);

RoleScorecard _r(String id, {String? deptId}) => RoleScorecard(
  id: id,
  companyId: 'c',
  departmentId: deptId,
  jobTitle: 'Role $id',
  missionStatement: '',
  responsibilities: const [],
  kpis: const [],
  wageType: 'MONTHLY',
  workHoursPerDay: 8,
  workDaysPerWeek: 'MON_FRI',
  isActive: true,
  effectiveDate: DateTime(2026),
);

void main() {
  final roles = [_r('r-ops', deptId: 'd-ops'), _r('r-mkt', deptId: 'd-mkt')];

  test('company scope is every active holder', () {
    final ids = populationFor(
      scope: KpiScope.company,
      employees: [_e('a', roleId: 'r-ops'), _e('b', roleId: 'r-mkt')],
      roles: roles,
    );
    expect(ids, ['a', 'b']);
  });

  test('department scope resolves the department through the ROLE', () {
    final ids = populationFor(
      scope: KpiScope.department,
      departmentId: 'd-ops',
      employees: [_e('a', roleId: 'r-ops'), _e('b', roleId: 'r-mkt')],
      roles: roles,
    );
    expect(ids, ['a']);
  });

  test('a stale employees.department_id does not win over the role', () {
    // The employee row still says d-mkt from before the role moved.
    // The role is authoritative, so this person counts under d-ops.
    final ids = populationFor(
      scope: KpiScope.department,
      departmentId: 'd-ops',
      employees: [_e('a', roleId: 'r-ops', deptId: 'd-mkt')],
      roles: roles,
    );
    expect(ids, ['a']);
  });

  test('a person with no role falls out of department scope entirely', () {
    final ids = populationFor(
      scope: KpiScope.department,
      departmentId: 'd-ops',
      employees: [_e('a', roleId: 'r-ops'), _e('nobody', deptId: 'd-ops')],
      roles: roles,
    );
    expect(ids, ['a'], reason: 'the roleless person has no department');
  });

  test('a roleless person still counts at company scope', () {
    final ids = populationFor(
      scope: KpiScope.company,
      employees: [_e('nobody')],
      roles: roles,
    );
    expect(ids, ['nobody']);
  });

  test('a role pointing at no department contributes nobody', () {
    final ids = populationFor(
      scope: KpiScope.department,
      departmentId: 'd-ops',
      employees: [_e('a', roleId: 'r-orphan')],
      roles: [_r('r-orphan')],
    );
    expect(ids, isEmpty);
  });

  test('terminated and soft-deleted people are excluded at every scope', () {
    final emps = [
      _e('active', roleId: 'r-ops'),
      _e('gone', roleId: 'r-ops', status: 'TERMINATED'),
      _e('deleted', roleId: 'r-ops', deletedAt: DateTime(2026, 1, 1)),
    ];
    expect(populationFor(scope: KpiScope.company, employees: emps, roles: roles),
        ['active']);
    expect(
      populationFor(
        scope: KpiScope.department,
        departmentId: 'd-ops',
        employees: emps,
        roles: roles,
      ),
      ['active'],
    );
  });

  test('department scope with no department id is empty, not everyone', () {
    // Guards the worst failure mode: a misconfigured department KPI silently
    // reporting the whole company as its population.
    expect(
      populationFor(
        scope: KpiScope.department,
        employees: [_e('a', roleId: 'r-ops')],
        roles: roles,
      ),
      isEmpty,
    );
  });

  test('the result is sorted, so two identical calls agree', () {
    final ids = populationFor(
      scope: KpiScope.company,
      employees: [_e('z', roleId: 'r-ops'), _e('a', roleId: 'r-ops')],
      roles: roles,
    );
    expect(ids, ['a', 'z']);
  });
}
