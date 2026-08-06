import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/task_costing.dart';
import 'package:payroll_flutter/features/workforce_planning/tasks_paging.dart';

RoleScorecard _card(String id, String title) => RoleScorecard(
  id: id,
  companyId: 'c',
  jobTitle: title,
  missionStatement: '',
  responsibilities: const [],
  kpis: const [],
  wageType: 'MONTHLY',
  workHoursPerDay: 8,
  workDaysPerWeek: 'MON_FRI',
  isActive: true,
  effectiveDate: DateTime(2026, 1, 1),
);

WpTask _t(String id, {String? card, String? area, String? ext}) => WpTask(
  id: id,
  companyId: 'c',
  name: id,
  roleScorecardId: card,
  responsibilityArea: area,
  externalRef: ext,
);

void main() {
  group('pageOfTasks', () {
    final ten = [for (var i = 0; i < 10; i++) _t('t$i')];

    test('first page reports 1-4 of 10', () {
      final p = pageOfTasks(ten, 0, 4);
      expect(p.tasks.map((t) => t.id), ['t0', 't1', 't2', 't3']);
      expect(p.firstIndex, 1);
      expect(p.lastIndex, 4);
      expect(p.total, 10);
      expect(p.pageCount, 3);
      expect(p.hasPrev, isFalse);
      expect(p.hasNext, isTrue);
    });

    test('last page is short and reports its real bounds', () {
      final p = pageOfTasks(ten, 2, 4);
      expect(p.tasks.map((t) => t.id), ['t8', 't9']);
      expect(p.firstIndex, 9);
      expect(p.lastIndex, 10);
      expect(p.hasNext, isFalse);
    });

    test('an out-of-range page clamps instead of going blank', () {
      final p = pageOfTasks(ten, 99, 4);
      expect(p.page, 2, reason: 'deleting rows must not strand the user');
      expect(p.tasks, isNotEmpty);
    });

    test('a negative page clamps to the first', () {
      expect(pageOfTasks(ten, -5, 4).page, 0);
    });

    test('empty input is one empty page, not zero pages', () {
      final p = pageOfTasks(const [], 0, 25);
      expect(p.tasks, isEmpty);
      expect(p.pageCount, 1);
      expect(p.total, 0);
      expect(p.firstIndex, 0);
      expect(p.lastIndex, 0);
      expect(p.hasPrev, isFalse);
      expect(p.hasNext, isFalse);
    });

    test('an exact multiple does not add a trailing empty page', () {
      expect(pageOfTasks(ten, 0, 5).pageCount, 2);
    });

    test('page size larger than the list is a single page', () {
      final p = pageOfTasks(ten, 0, 500);
      expect(p.pageCount, 1);
      expect(p.tasks, hasLength(10));
    });

    test('a non-positive page size is rejected, not silently corrected', () {
      expect(() => pageOfTasks(ten, 0, 0), throwsArgumentError);
    });
  });

  group('scopes', () {
    final cards = [_card('rs1', 'Ops'), _card('rs2', 'HR')];
    final tasks = [
      _t('a1', card: 'rs1', area: 'A'),
      _t('a2', card: 'rs1', area: 'A'),
      _t('b1', card: 'rs2', area: 'B'),
      _t('leg', ext: 'T1'),
      _t('orphan'),
    ];

    test('lists All, each card, then the buckets with counts', () {
      final s = buildScopes(tasks, cards);
      expect(s.first.key, TaskScope.allKey);
      expect(s.first.count, 5);
      expect(
        s.map((x) => x.label),
        containsAll(['Ops', 'HR', 'From capacity model', 'Unattributed']),
      );
      expect(s.firstWhere((x) => x.label == 'Ops').count, 2);
    });

    test('empty buckets are omitted — an empty option is a dead end', () {
      final s = buildScopes([_t('a1', card: 'rs1', area: 'A')], cards);
      expect(s.map((x) => x.label), isNot(contains('From capacity model')));
      expect(s.map((x) => x.label), isNot(contains('Unattributed')));
      expect(
        s.map((x) => x.label),
        isNot(contains('HR')),
        reason: 'a card with no tasks has nothing to show',
      );
    });

    test('scoping to a card returns only its tasks', () {
      expect(tasksInScope(tasks, cards, 'rs1').map((t) => t.id), ['a1', 'a2']);
    });

    test('legacy and unattributed scopes are distinct', () {
      expect(tasksInScope(tasks, cards, TaskScope.legacyKey).map((t) => t.id), [
        'leg',
      ]);
      expect(
        tasksInScope(tasks, cards, TaskScope.unattributedKey).map((t) => t.id),
        ['orphan'],
      );
    });

    test('all-scope covers every task exactly once', () {
      final all = tasksInScope(tasks, cards, TaskScope.allKey);
      expect(all, hasLength(tasks.length));
      expect(all.map((t) => t.id).toSet(), tasks.map((t) => t.id).toSet());
    });

    test('paging over the all-scope never drops or duplicates a row', () {
      final all = tasksInScope(tasks, cards, TaskScope.allKey);
      final seen = <String>[];
      for (var p = 0; p < pageOfTasks(all, 0, 2).pageCount; p++) {
        seen.addAll(pageOfTasks(all, p, 2).tasks.map((t) => t.id));
      }
      expect(seen, hasLength(5));
      expect(seen.toSet(), hasLength(5));
    });
  });

  group('filtering', () {
    const drivers = <String, WpDriver>{};
    const rates = <String, WpRate>{};
    final tasks = [
      const WpTask(
        id: 'a',
        companyId: 'c',
        name: 'Pack and label orders',
        responsibilityArea: 'Fulfilment',
        ownerEmployeeId: 'e1',
        nodeId: 'n1',
        timesSource: 'manual',
        timesManual: 10,
        minutesSource: 'manual',
        minutesManual: 30,
      ),
      const WpTask(
        id: 'b',
        companyId: 'c',
        name: 'Train new staff',
        responsibilityArea: 'Development',
        isExpectation: true,
      ),
      const WpTask(
        id: 'c',
        companyId: 'c',
        name: 'Reconcile the bank',
        responsibilityArea: 'Finance',
        nodeId: 'n2',
      ),
    ];

    test('an empty filter returns everything untouched', () {
      expect(applyTaskFilter(tasks, const TaskFilter(), drivers, rates), tasks);
    });

    test('search matches the name', () {
      expect(
        applyTaskFilter(
          tasks,
          const TaskFilter(query: 'label'),
          drivers,
          rates,
        ).map((t) => t.id),
        ['a'],
      );
    });

    test('search also matches the responsibility area', () {
      expect(
        applyTaskFilter(
          tasks,
          const TaskFilter(query: 'finance'),
          drivers,
          rates,
        ).map((t) => t.id),
        ['c'],
        reason: 'area is how you find work you cannot name exactly',
      );
    });

    test('search is case-insensitive and trims', () {
      expect(
        applyTaskFilter(
          tasks,
          const TaskFilter(query: '  PACK '),
          drivers,
          rates,
        ).map((t) => t.id),
        ['a'],
      );
    });

    test('status filter separates costed, to-cost and expectation', () {
      List<String> ids(TaskCostState s) => applyTaskFilter(
        tasks,
        TaskFilter(state: s),
        drivers,
        rates,
      ).map((t) => t.id).toList();
      expect(ids(TaskCostState.costed), ['a']);
      expect(ids(TaskCostState.expectation), ['b']);
      expect(ids(TaskCostState.toCost), ['c']);
    });

    test('node and owner filters, including the unowned sentinel', () {
      expect(
        applyTaskFilter(
          tasks,
          const TaskFilter(nodeId: 'n2'),
          drivers,
          rates,
        ).map((t) => t.id),
        ['c'],
      );
      expect(
        applyTaskFilter(
          tasks,
          const TaskFilter(ownerId: 'e1'),
          drivers,
          rates,
        ).map((t) => t.id),
        ['a'],
      );
      expect(
        applyTaskFilter(
          tasks,
          const TaskFilter(ownerId: TaskFilter.unownedKey),
          drivers,
          rates,
        ).map((t) => t.id),
        ['b', 'c'],
      );
    });

    test('filters combine (AND, not OR)', () {
      expect(
        applyTaskFilter(
          tasks,
          const TaskFilter(query: 'the', state: TaskCostState.toCost),
          drivers,
          rates,
        ).map((t) => t.id),
        ['c'],
      );
    });
  });

  group('costingProgress', () {
    const drivers = <String, WpDriver>{};
    const rates = <String, WpRate>{};

    test('expectations count as RESOLVED so the queue can finish', () {
      final p = costingProgress(
        [
          const WpTask(
            id: 'a',
            companyId: 'c',
            name: 'costed',
            timesSource: 'manual',
            timesManual: 2,
            minutesSource: 'manual',
            minutesManual: 30,
          ),
          const WpTask(
            id: 'b',
            companyId: 'c',
            name: 'expectation',
            isExpectation: true,
          ),
          const WpTask(id: 'c', companyId: 'c', name: 'todo'),
        ],
        drivers,
        rates,
      );
      expect(p.costed, 1);
      expect(p.expectation, 1);
      expect(p.toCost, 1);
      expect(p.resolved, 2, reason: 'an expectation needs no estimate');
      expect(p.done, isFalse);
    });

    test(
      'done once nothing is left to cost, even with expectations present',
      () {
        final p = costingProgress(
          [
            const WpTask(
              id: 'a',
              companyId: 'c',
              name: 'e1',
              isExpectation: true,
            ),
            const WpTask(
              id: 'b',
              companyId: 'c',
              name: 'e2',
              isExpectation: true,
            ),
          ],
          drivers,
          rates,
        );
        expect(
          p.done,
          isTrue,
          reason: 'otherwise the banner is permanent wallpaper',
        );
        expect(p.fraction, 1.0);
      },
    );

    test('an empty inventory is complete, not divided by zero', () {
      final p = costingProgress(const [], drivers, rates);
      expect(p.fraction, 1.0);
      expect(p.done, isTrue);
    });
  });

  group('assignment tracking', () {
    Employee emp(
      String id,
      String? card, {
      String status = 'ACTIVE',
      DateTime? del,
    }) => Employee(
      id: id,
      companyId: 'c',
      employeeNumber: id,
      firstName: id,
      lastName: 'X',
      roleScorecardId: card,
      employmentType: 'FULL_TIME',
      employmentStatus: status,
      deletedAt: del,
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

    test('only ACTIVE, non-deleted holders make a card count as staffed', () {
      final held = cardsWithActiveHolders([
        emp('a', 'staffed'),
        emp('b', 'resigned-card', status: 'SEPARATED'),
        emp('c', 'archived-card', del: DateTime(2026, 1, 1)),
        emp('d', null),
      ]);
      expect(held, {'staffed'});
    });

    test('the three states are distinguished', () {
      const held = {'rs1'};
      expect(
        taskAssignment(
          const WpTask(
            id: '1',
            companyId: 'c',
            name: 'n',
            ownerEmployeeId: 'e1',
          ),
          held,
        ),
        TaskAssignment.explicit,
      );
      expect(
        taskAssignment(
          const WpTask(
            id: '2',
            companyId: 'c',
            name: 'n',
            roleScorecardId: 'rs1',
          ),
          held,
        ),
        TaskAssignment.derived,
      );
      expect(
        taskAssignment(const WpTask(id: '3', companyId: 'c', name: 'n'), held),
        TaskAssignment.unassigned,
      );
    });

    test('a card with no active holder is UNASSIGNED, not derived', () {
      expect(
        taskAssignment(
          const WpTask(
            id: '4',
            companyId: 'c',
            name: 'n',
            roleScorecardId: 'vacant',
          ),
          const {'rs1'},
        ),
        TaskAssignment.unassigned,
        reason: 'work on a vacant role reaches nobody — that is the gap to see',
      );
    });

    test('an explicit owner wins even on a staffed card', () {
      expect(
        taskAssignment(
          const WpTask(
            id: '5',
            companyId: 'c',
            name: 'n',
            roleScorecardId: 'rs1',
            ownerEmployeeId: 'e9',
          ),
          const {'rs1'},
        ),
        TaskAssignment.explicit,
      );
    });

    test('the tally counts each task exactly once', () {
      const held = {'rs1'};
      final t = tallyAssignments(const [
        WpTask(id: '1', companyId: 'c', name: 'n', ownerEmployeeId: 'e1'),
        WpTask(id: '2', companyId: 'c', name: 'n', roleScorecardId: 'rs1'),
        WpTask(id: '3', companyId: 'c', name: 'n', roleScorecardId: 'rs1'),
        WpTask(id: '4', companyId: 'c', name: 'n'),
      ], held);
      expect(t.explicit, 1);
      expect(t.derived, 2);
      expect(t.unassigned, 1);
    });

    test('filtering by assignment separates derived from truly unassigned', () {
      const held = {'rs1'};
      final tasks = const [
        WpTask(
          id: 'd1',
          companyId: 'c',
          name: 'derived',
          roleScorecardId: 'rs1',
        ),
        WpTask(id: 'u1', companyId: 'c', name: 'orphan'),
      ];
      expect(
        applyTaskFilter(
          tasks,
          const TaskFilter(assignment: TaskAssignment.unassigned),
          const {},
          const {},
          cardsWithHolders: held,
        ).map((t) => t.id),
        ['u1'],
        reason: 'the old "no explicit owner" filter returned BOTH of these',
      );
      expect(
        applyTaskFilter(
          tasks,
          const TaskFilter(assignment: TaskAssignment.derived),
          const {},
          const {},
          cardsWithHolders: held,
        ).map((t) => t.id),
        ['d1'],
      );
    });
  });
}
