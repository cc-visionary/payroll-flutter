import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/capacity_math.dart';
import 'package:payroll_flutter/features/workforce_planning/role_load.dart';

Employee emp(String id, {String? role, String? reportsTo, String status = 'ACTIVE'}) => Employee(
  id: id, companyId: 'c', employeeNumber: id, firstName: id, lastName: 'X',
  roleScorecardId: role, reportsToId: reportsTo,
  employmentType: 'FULL_TIME', employmentStatus: status,
  hireDate: DateTime(2024, 1, 1), isRankAndFile: true, isOtEligible: false,
  isNdEligible: false, isHolidayPayEligible: false,
  sssEligibilityOverride: false, philhealthEligibilityOverride: false,
  pagibigEligibilityOverride: false, taxOnFullEarnings: false,
);

RoleScorecard role(String id, String title) => RoleScorecard(
  id: id, companyId: 'c', jobTitle: title, missionStatement: '',
  responsibilities: const [], kpis: const [], wageType: 'MONTHLY',
  workHoursPerDay: 8, workDaysPerWeek: 'MON_FRI', isActive: true,
  effectiveDate: DateTime(2026),
);

WpTask task(String id, {String? role, String? note, String? ext, String status = 'ACTIVE'}) =>
    WpTask(id: id, companyId: 'c', name: id, roleScorecardId: role,
        allocationReviewNote: note, externalRef: ext, status: status);

void main() {
  final bh = role('bh', 'Brand Handler');
  final om = role('om', 'Ops Manager');
  final kiosk = role('k', 'Kiosk Rep');

  List<RoleLoad> build({RoleMoves moves = const {}, Map<String, double>? caps}) => buildRoleLoads(
    roles: [bh, om, kiosk],
    employees: [
      emp('ana', role: 'bh', reportsTo: 'jer'),
      emp('ben', role: 'bh', reportsTo: 'jer'),
      emp('jer', role: 'om'),
      emp('gone', role: 'bh', status: 'SEPARATED'),
    ],
    tasks: [task('t1', role: 'bh'), task('t2', role: 'bh'), task('t3', role: 'om'), task('t4', role: 'k')],
    hoursByTaskId: {'t1': 200, 't2': 40, 't3': 100, 't4': 50},
    capacityByEmployee: caps ?? {'ana': 160, 'ben': 160, 'jer': 160},
    defaultCapacity: 160,
    moves: moves,
  );

  test('work, capacity, load, needs and short for a two-holder role', () {
    final r = build().firstWhere((x) => x.role.id == 'bh');
    expect(r.holders.map((h) => h.employee.id), ['ana', 'ben'], reason: 'SEPARATED excluded');
    expect(r.workHours, 240);
    expect(r.capacityHours, 320);
    expect(r.load, closeTo(0.75, 1e-9));
    expect(r.peopleNeeded, closeTo(1.5, 1e-9));
    expect(r.shortBy, 0);
    expect(r.status, LoadStatus.under);
  });

  test('capacity-weighted: a part-timer gets a smaller share, same load %', () {
    final r = build(caps: {'ana': 160, 'ben': 80, 'jer': 160}).firstWhere((x) => x.role.id == 'bh');
    expect(r.hoursFor('ana'), closeTo(160, 1e-9));
    expect(r.hoursFor('ben'), closeTo(80, 1e-9));
    expect(r.hoursFor('ana') / 160, closeTo(r.hoursFor('ben') / 80, 1e-9));
  });

  test('zero-holder role: no division by zero, needs counts, sorts first', () {
    final loads = build();
    expect(loads.first.role.id, 'k');
    final k = loads.first;
    expect(k.holders, isEmpty);
    expect(k.load, 0);
    expect(k.unstaffedWithWork, isTrue);
    expect(k.peopleNeeded, closeTo(50 / 160, 1e-9));
    expect(k.shortBy, closeTo(50 / 160, 1e-9));
    expect(k.hoursFor('ana'), 0);
  });

  test('a draft move shifts hours between roles', () {
    final before = build();
    final after = build(moves: {'t1': 'om'});
    double work(List<RoleLoad> l, String id) => l.firstWhere((x) => x.role.id == id).workHours;
    expect(work(before, 'om'), 100);
    expect(work(after, 'om'), 300);
    expect(work(after, 'bh'), 40);
    expect(after.firstWhere((x) => x.role.id == 'om').status, LoadStatus.over);
  });

  test('over-loaded roles sort before under-loaded ones', () {
    final ids = build(moves: {'t1': 'om'}).map((r) => r.role.id).toList();
    expect(ids, ['k', 'om', 'bh']);
  });

  test('checked by = distinct roles of the holders\' managers', () {
    final byId = {for (final r in [bh, om, kiosk]) r.id: r};
    final emps = [emp('ana', role: 'bh', reportsTo: 'jer'), emp('ben', role: 'bh', reportsTo: 'jer'), emp('jer', role: 'om')];
    expect(checkedByTitles(role: bh, employees: emps, rolesById: byId), ['Ops Manager']);
    expect(checkedByTitles(role: om, employees: emps, rolesById: byId), isEmpty, reason: 'reports to nobody');
  });

  test('checked by skips a manager with no role', () {
    final emps = [emp('ana', role: 'bh', reportsTo: 'boss'), emp('boss')];
    expect(checkedByTitles(role: bh, employees: emps, rolesById: {'bh': bh}), isEmpty);
  });

  test('no-role list excludes legacy reference rows and archived tasks', () {
    final tasks = [task('a'), task('b', ext: 'XLSX-1'), task('c', status: 'ARCHIVED'), task('d', role: 'bh')];
    expect(noRoleTasks(tasks).map((t) => t.id), ['a']);
    expect(noRoleTasks(tasks, moves: {'a': 'bh'}), isEmpty);
  });

  test('flagged list = active tasks carrying a review note', () {
    final tasks = [task('a', note: 'was: x'), task('b'), task('c', note: 'was: y', status: 'ARCHIVED')];
    expect(flaggedTasks(tasks).map((t) => t.id), ['a']);
  });

  test('taskHours projects growing work by the multiplier', () {
    const fixed = WpTaskComputed(taskId: 'a', companyId: 'c', hoursPerMonthBase: 10);
    const growing = WpTaskComputed(taskId: 'b', companyId: 'c', hoursPerMonthBase: 10, isGrowing: true);
    expect(taskHours(fixed, 2), 10);
    expect(taskHours(growing, 2), 20);
    expect(taskHours(null, 2), 0);
  });
}
