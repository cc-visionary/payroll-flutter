import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/capacity_math.dart';
import 'package:payroll_flutter/features/workforce_planning/rebalance.dart';

Employee _e(String id, {String? card, String status = 'ACTIVE', DateTime? deleted}) =>
    Employee(
      id: id, companyId: 'c', employeeNumber: id, firstName: id, lastName: 'X',
      roleScorecardId: card, employmentType: 'FULL_TIME', employmentStatus: status,
      deletedAt: deleted, hireDate: DateTime(2024, 1, 1), isRankAndFile: true,
      isOtEligible: false, isNdEligible: false, isHolidayPayEligible: false,
      sssEligibilityOverride: false, philhealthEligibilityOverride: false,
      pagibigEligibilityOverride: false, taxOnFullEarnings: false,
    );

WpTask _t(String id, {String? owner, String? card}) => WpTask(
    id: id, companyId: 'c', name: id, ownerEmployeeId: owner, roleScorecardId: card);

WpTaskComputed _c(String id, double h, {bool growing = false}) => WpTaskComputed(
    taskId: id, companyId: 'c', hoursPerMonthBase: h, isGrowing: growing);

void main() {
  group('attribution mirrors wp_person_load', () {
    test('an explicit owner takes the whole task', () {
      final h = hoursByEmployee(
        tasks: [_t('t1', owner: 'a')],
        computedByTaskId: {'t1': _c('t1', 40)},
        employees: [_e('a'), _e('b')],
        multiplier: 1,
      );
      expect(h['a'], 40);
      expect(h['b'], isNull);
    });

    test('an unowned card task splits across ACTIVE holders', () {
      final h = hoursByEmployee(
        tasks: [_t('t1', card: 'rs1')],
        computedByTaskId: {'t1': _c('t1', 40)},
        employees: [_e('a', card: 'rs1'), _e('b', card: 'rs1')],
        multiplier: 1,
      );
      expect(h['a'], 20);
      expect(h['b'], 20);
    });

    test('separated and soft-deleted holders do not dilute the split', () {
      final h = hoursByEmployee(
        tasks: [_t('t1', card: 'rs1')],
        computedByTaskId: {'t1': _c('t1', 40)},
        employees: [
          _e('a', card: 'rs1'),
          _e('gone', card: 'rs1', status: 'SEPARATED'),
          _e('archived', card: 'rs1', deleted: DateTime(2026, 1, 1)),
        ],
        multiplier: 1,
      );
      expect(h['a'], 40, reason: 'one real holder carries all of it');
    });

    test('a task with neither owner nor card reaches nobody', () {
      final tasks = [_t('t1')];
      final computed = {'t1': _c('t1', 40)};
      expect(hoursByEmployee(
          tasks: tasks, computedByTaskId: computed,
          employees: [_e('a')], multiplier: 1), isEmpty);
      expect(unattributedHours(
          tasks: tasks, computedByTaskId: computed,
          employees: [_e('a')], multiplier: 1), 40);
    });

    test('a vacant role card is unattributed, not spread over everyone', () {
      final tasks = [_t('t1', card: 'empty')];
      final computed = {'t1': _c('t1', 40)};
      expect(hoursByEmployee(
          tasks: tasks, computedByTaskId: computed,
          employees: [_e('a', card: 'other')], multiplier: 1), isEmpty);
      expect(unattributedHours(
          tasks: tasks, computedByTaskId: computed,
          employees: [_e('a', card: 'other')], multiplier: 1), 40);
    });

    test('growing tasks scale, fixed ones do not', () {
      final h = hoursByEmployee(
        tasks: [_t('g', owner: 'a'), _t('f', owner: 'a')],
        computedByTaskId: {'g': _c('g', 10, growing: true), 'f': _c('f', 10)},
        employees: [_e('a')],
        multiplier: 2,
      );
      expect(h['a'], 30);
    });
  });

  group('draft moves', () {
    final employees = [_e('over', card: 'rs1'), _e('spare')];
    final tasks = [_t('t1', owner: 'over'), _t('t2', owner: 'over')];
    final computed = {'t1': _c('t1', 100), 't2': _c('t2', 40)};

    test('moving shifts hours from one to the other without changing the total', () {
      final before = hoursByEmployee(
          tasks: tasks, computedByTaskId: computed,
          employees: employees, multiplier: 1);
      final after = hoursByEmployee(
          tasks: tasks, computedByTaskId: computed, employees: employees,
          multiplier: 1, moves: {'t2': 'spare'});
      expect(before['over'], 140);
      expect(after['over'], 100);
      expect(after['spare'], 40);
      expect(after.values.reduce((a, b) => a + b),
          before.values.reduce((a, b) => a + b),
          reason: 'rebalancing must not create or destroy work');
    });

    test('moving a SHARED responsibility pins all of it to one person', () {
      final emps = [_e('a', card: 'rs1'), _e('b', card: 'rs1')];
      final shared = [_t('t1', card: 'rs1')];
      final comp = {'t1': _c('t1', 40)};
      final before = hoursByEmployee(
          tasks: shared, computedByTaskId: comp, employees: emps, multiplier: 1);
      expect(before['a'], 20);
      expect(before['b'], 20);

      final after = hoursByEmployee(
          tasks: shared, computedByTaskId: comp, employees: emps,
          multiplier: 1, moves: {'t1': 'a'});
      expect(after['a'], 40);
      expect(after['b'], isNull,
          reason: 'an explicit owner removes it from every other holder');
    });

    test('projections report current and planned side by side', () {
      final p = buildProjections(
        employees: employees, tasks: tasks, computedByTaskId: computed,
        capacityByEmployee: const {'over': 100, 'spare': 100},
        multiplier: 1, defaultCapacity: 160, moves: {'t2': 'spare'},
      );
      final over = p.firstWhere((x) => x.employeeId == 'over');
      final spare = p.firstWhere((x) => x.employeeId == 'spare');
      expect(over.currentHours, 140);
      expect(over.plannedHours, 100);
      expect(over.currentStatus, LoadStatus.over);
      expect(over.plannedStatus, LoadStatus.ok);
      expect(over.changed, isTrue);
      expect(spare.plannedHours, 40);
      expect(spare.headroom, 60);
    });

    test('ranked by planned load so whoever needs relief is on top', () {
      final p = buildProjections(
        employees: employees, tasks: tasks, computedByTaskId: computed,
        capacityByEmployee: const {'over': 100, 'spare': 100},
        multiplier: 1, defaultCapacity: 160,
      );
      expect(p.first.employeeId, 'over');
    });

    test('a person with no capacity record falls back to the default', () {
      final p = buildProjections(
        employees: [_e('a')], tasks: const [], computedByTaskId: const {},
        capacityByEmployee: const {}, multiplier: 1, defaultCapacity: 160,
      );
      expect(p.single.capacityHours, 160);
    });
  });

  group('plannedTasksFor', () {
    test('lists owned and derived tasks, heaviest first, with the share', () {
      final emps = [_e('a', card: 'rs1'), _e('b', card: 'rs1')];
      final tasks = [_t('own', owner: 'a'), _t('shared', card: 'rs1')];
      final comp = {'own': _c('own', 10), 'shared': _c('shared', 40)};
      final list = plannedTasksFor(
          employeeId: 'a', employees: emps, tasks: tasks,
          computedByTaskId: comp, multiplier: 1);
      expect(list.map((p) => p.task.id), ['shared', 'own']);
      expect(list.first.hours, 20, reason: 'half of a two-holder task');
      expect(list.first.derived, isTrue);
      expect(list.first.shared, isTrue);
      expect(list.last.derived, isFalse);
    });

    test('a moved task appears on the destination and leaves the source', () {
      final emps = [_e('a'), _e('b')];
      final tasks = [_t('t1', owner: 'a')];
      final comp = {'t1': _c('t1', 10)};
      final moves = {'t1': 'b'};
      expect(plannedTasksFor(employeeId: 'a', employees: emps, tasks: tasks,
          computedByTaskId: comp, multiplier: 1, moves: moves), isEmpty);
      final dest = plannedTasksFor(employeeId: 'b', employees: emps, tasks: tasks,
          computedByTaskId: comp, multiplier: 1, moves: moves);
      expect(dest.single.task.id, 't1');
      expect(dest.single.moved, isTrue);
    });
  });

  group('guards', () {
    final emps = [_e('a'), _e('b')];

    test('an uncosted task is refused with an explanation', () {
      final err = moveError(
        task: _t('t1', owner: 'a'), toEmployeeId: 'b',
        employees: emps, computedByTaskId: {'t1': _c('t1', 0)},
      );
      expect(err, contains('not costed'));
    });

    test('dropping on the current owner is a no-op, not an error', () {
      expect(
        moveError(task: _t('t1', owner: 'a'), toEmployeeId: 'a',
            employees: emps, computedByTaskId: {'t1': _c('t1', 5)}),
        isNull,
      );
    });

    test('an unknown target is refused', () {
      expect(
        moveError(task: _t('t1', owner: 'a'), toEmployeeId: 'ghost',
            employees: emps, computedByTaskId: {'t1': _c('t1', 5)}),
        contains('no longer active'),
      );
    });

    test('dragging back to the original owner clears the draft', () {
      final tasks = [_t('t1', owner: 'a')];
      expect(prunedMoves({'t1': 'a'}, tasks), isEmpty,
          reason: 'that is not an unsaved change');
      expect(prunedMoves({'t1': 'b'}, tasks), {'t1': 'b'});
    });

    test('a draft for a task that no longer exists is dropped', () {
      expect(prunedMoves({'gone': 'a'}, [_t('t1')]), isEmpty);
    });
  });
}
