import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/rebalance.dart';

Employee _e(String id, {String? card}) => Employee(
      id: id, companyId: 'c', employeeNumber: id, firstName: id, lastName: 'x',
      employmentType: 'REGULAR', employmentStatus: 'ACTIVE', hireDate: DateTime(2026),
      isRankAndFile: true, isOtEligible: false, isNdEligible: false,
      isHolidayPayEligible: false, taxOnFullEarnings: false, roleScorecardId: card);

const _task = WpTask(id: 't', companyId: 'c', name: 't');

WpTaskAssignment _pa(String emp, double pct, {String role = 'PRIMARY'}) => WpTaskAssignment(
    id: 'a', companyId: 'c', taskId: 't', employeeId: emp, assignmentRole: role, allocationPct: pct);
WpTaskAssignment _ca(String card, double pct, {String role = 'PRIMARY'}) => WpTaskAssignment(
    id: 'a', companyId: 'c', taskId: 't', roleScorecardId: card, assignmentRole: role, allocationPct: pct);

List<Employee> Function(String) _holders(List<Employee> emps) =>
    (cardId) => [for (final e in emps) if (e.roleScorecardId == cardId) e];

void main() {
  test('move override gives 100% to the moved person', () {
    final r = attributeTask(hours: 40, task: _task, assignments: const [],
        holdersOf: _holders(const []), moveOverride: 'x');
    expect(r.shares, [(employeeId: 'x', hours: 40.0, derived: false, holderCount: 1)]);
    expect(r.unattributed, 0);
  });

  test('two person assignments split by pct; Σ100 leaves nothing unattributed', () {
    final r = attributeTask(hours: 100, task: _task,
        assignments: [_pa('a', 60), _pa('b', 40, role: 'CONTRIBUTOR')],
        holdersOf: _holders(const []));
    expect(r.shares.firstWhere((s) => s.employeeId == 'a').hours, 60);
    expect(r.shares.firstWhere((s) => s.employeeId == 'b').hours, 40);
    expect(r.unattributed, 0);
  });

  test('card assignment splits its pct across active holders (derived)', () {
    final r = attributeTask(hours: 100, task: _task, assignments: [_ca('rs1', 60)],
        holdersOf: _holders([_e('h1', card: 'rs1'), _e('h2', card: 'rs1')]));
    // 60% = 60h across 2 holders = 30 each; 40% unallocated -> unattributed
    expect(r.shares.every((s) => s.hours == 30 && s.derived && s.holderCount == 2), isTrue);
    expect(r.unattributed, 40);
  });

  test('vacant card share is unattributed, not lost', () {
    final r = attributeTask(hours: 100, task: _task, assignments: [_ca('empty', 100)],
        holdersOf: _holders(const []));
    expect(r.shares, isEmpty);
    expect(r.unattributed, 100);
  });

  test('fallback: no assignments + owner -> owner full', () {
    const owned = WpTask(id: 't', companyId: 'c', name: 't', ownerEmployeeId: 'o');
    final r = attributeTask(hours: 40, task: owned, assignments: const [], holdersOf: _holders(const []));
    expect(r.shares, [(employeeId: 'o', hours: 40.0, derived: false, holderCount: 1)]);
    expect(r.unattributed, 0);
  });

  test('fallback: no assignments + card -> split across holders', () {
    const carded = WpTask(id: 't', companyId: 'c', name: 't', roleScorecardId: 'rs1');
    final r = attributeTask(hours: 40, task: carded, assignments: const [],
        holdersOf: _holders([_e('h1', card: 'rs1'), _e('h2', card: 'rs1')]));
    expect(r.shares.length, 2);
    expect(r.shares.every((s) => s.hours == 20 && s.derived), isTrue);
  });

  test('fallback: no assignments, no owner, no card -> all unattributed', () {
    final r = attributeTask(hours: 40, task: _task, assignments: const [], holdersOf: _holders(const []));
    expect(r.shares, isEmpty);
    expect(r.unattributed, 40);
  });

  test('an uncosted (0h) task with a person assignment still identifies the carrier', () {
    final r = attributeTask(hours: 0, task: _task, assignments: [_pa('a', 100)],
        holdersOf: _holders(const []));
    expect(r.shares, [(employeeId: 'a', hours: 0.0, derived: false, holderCount: 1)]);
    expect(r.unattributed, 0);
  });

  test('an uncosted (0h) task with the owner fallback still identifies the owner', () {
    const owned = WpTask(id: 't', companyId: 'c', name: 't', ownerEmployeeId: 'o');
    final r = attributeTask(hours: 0, task: owned, assignments: const [], holdersOf: _holders(const []));
    expect(r.shares, [(employeeId: 'o', hours: 0.0, derived: false, holderCount: 1)]);
    expect(r.unattributed, 0);
  });
}
