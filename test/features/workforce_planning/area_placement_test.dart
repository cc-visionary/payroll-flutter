import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/area_placement.dart';

RoleScorecard card(String id, List<String> areas) => RoleScorecard(
  id: id, companyId: 'c', jobTitle: id, missionStatement: '',
  responsibilities: [for (final a in areas) ResponsibilityArea(area: a, tasks: const ['x'])],
  kpis: const [], wageType: 'MONTHLY', workHoursPerDay: 8,
  workDaysPerWeek: 'MON_FRI', isActive: true, effectiveDate: DateTime(2026),
);

void main() {
  group('areaOptionsFor / defaultAreaFor', () {
    test('a card with areas: options in authored order, default is the first', () {
      final c = card('bh', ['Fulfilment', 'Customer care', ' Fulfilment ']);
      expect(areaOptionsFor(c), ['Fulfilment', 'Customer care']);
      expect(defaultAreaFor(c), 'Fulfilment');
    });

    test('a card with no areas (or no card) defaults to Responsibilities', () {
      expect(areaOptionsFor(card('om', const [])), isEmpty);
      expect(defaultAreaFor(card('om', const [])), kDefaultResponsibilityArea);
      expect(defaultAreaFor(null), 'Responsibilities');
    });
  });

  group('placeInArea', () {
    const existing = [
      WpTask(id: 'a1', companyId: 'c', name: 'A1', roleScorecardId: 'bh',
          responsibilityArea: 'Setup', areaSort: 0, taskSort: 0),
      WpTask(id: 'a2', companyId: 'c', name: 'A2', roleScorecardId: 'bh',
          responsibilityArea: 'Setup', areaSort: 0, taskSort: 1),
      WpTask(id: 'b1', companyId: 'c', name: 'B1', roleScorecardId: 'bh',
          responsibilityArea: 'Research', areaSort: 1, taskSort: 0),
    ];

    test('a new task lands at the end of its area', () {
      const fresh = WpTask(id: '', companyId: 'c', name: 'New', roleScorecardId: 'bh',
          responsibilityArea: 'Setup');
      final p = placeInArea(previous: null, next: fresh, allTasks: existing);
      expect((p.areaSort, p.taskSort), (0, 2));
    });

    test('a rename keeps its position', () {
      final renamed = WpTask(id: 'a1', companyId: 'c', name: 'A1 reworded',
          roleScorecardId: 'bh', responsibilityArea: 'Setup', areaSort: 0, taskSort: 0);
      final p = placeInArea(previous: existing.first, next: renamed, allTasks: existing);
      expect((p.areaSort, p.taskSort), (0, 0));
    });

    test('a change of area lands at the end of the new area', () {
      final moved = WpTask(id: 'a1', companyId: 'c', name: 'A1',
          roleScorecardId: 'bh', responsibilityArea: 'Research', areaSort: 0, taskSort: 0);
      final p = placeInArea(previous: existing.first, next: moved, allTasks: existing);
      expect((p.areaSort, p.taskSort), (1, 1));
    });

    test('a task with no role or area is left alone', () {
      const loose = WpTask(id: '', companyId: 'c', name: 'Loose', areaSort: 7, taskSort: 3);
      final p = placeInArea(previous: null, next: loose, allTasks: existing);
      expect((p.areaSort, p.taskSort), (7, 3));
    });
  });

  group('planRoleMoves (board drag/Apply)', () {
    const tasks = [
      WpTask(id: 't1', companyId: 'c', name: 'Pack', roleScorecardId: 'bh',
          responsibilityArea: 'Fulfilment', areaSort: 0, taskSort: 0),
      WpTask(id: 't2', companyId: 'c', name: 'Report', roleScorecardId: 'om',
          responsibilityArea: 'Reporting', areaSort: 0, taskSort: 0),
      WpTask(id: 't3', companyId: 'c', name: 'Audit', roleScorecardId: 'om',
          responsibilityArea: 'Reporting', areaSort: 0, taskSort: 1),
    ];

    test('the moved task takes the target card\'s first area, at its end', () {
      final plan = planRoleMoves(
        moves: {'t2': 'bh'},
        allTasks: tasks,
        rolesById: {'bh': card('bh', ['Fulfilment', 'Care'])},
      );
      expect(plan.single.taskId, 't2');
      expect(plan.single.roleId, 'bh');
      expect(plan.single.area, 'Fulfilment',
          reason: 'never the old role\'s "Reporting"');
      expect((plan.single.areaSort, plan.single.taskSort), (0, 1));
    });

    test('a target card with no areas gets "Responsibilities"', () {
      final plan = planRoleMoves(
        moves: {'t1': 'om'},
        allTasks: tasks,
        rolesById: {'om': card('om', const [])},
      );
      expect(plan.single.area, 'Responsibilities');
      expect(plan.single.areaSort, 1, reason: 'a new area goes after the last one');
      expect(plan.single.taskSort, 0);
    });

    test('two tasks moved into the same area take consecutive slots', () {
      final plan = planRoleMoves(
        moves: {'t2': 'bh', 't3': 'bh'},
        allTasks: tasks,
        rolesById: {'bh': card('bh', ['Fulfilment'])},
      );
      expect([for (final m in plan) m.taskSort], [1, 2]);
    });
  });

  test('end to end: a task placed by the new flow appears on the role card', () {
    // responsibilitiesFromTaskRows skips rows with no area — the reason every
    // new/moved task must carry one (ruling R11).
    const fresh = WpTask(id: 'n1', companyId: 'c', name: 'Count stock',
        roleScorecardId: 'bh');
    final c = card('bh', const []);
    final withArea = WpTask(
      id: fresh.id, companyId: fresh.companyId, name: fresh.name,
      roleScorecardId: fresh.roleScorecardId, responsibilityArea: defaultAreaFor(c),
    );
    final placed = placeInArea(previous: null, next: withArea, allTasks: const []);
    final rows = [
      {
        'id': placed.id, 'name': placed.name,
        'responsibility_area': placed.responsibilityArea,
        'area_sort': placed.areaSort, 'task_sort': placed.taskSort,
        'status': placed.status,
      },
    ];
    final areas = responsibilitiesFromTaskRows(rows);
    expect(areas.single.area, 'Responsibilities');
    expect(areas.single.tasks, ['Count stock']);
  });

  group('nextSortFor / needsResort (document ordering)', () {
    // area_sort/task_sort decide the order of the role-card PDF and the
    // employment-contract Annex A, so a wrong position rewords a document.
    final existing = [
      const WpTask(
        id: 'a1',
        companyId: 'c',
        name: 'A first',
        roleScorecardId: 'rs1',
        responsibilityArea: 'Setup',
        areaSort: 0,
        taskSort: 0,
      ),
      const WpTask(
        id: 'a2',
        companyId: 'c',
        name: 'A second',
        roleScorecardId: 'rs1',
        responsibilityArea: 'Setup',
        areaSort: 0,
        taskSort: 1,
      ),
      const WpTask(
        id: 'b1',
        companyId: 'c',
        name: 'B first',
        roleScorecardId: 'rs1',
        responsibilityArea: 'Research',
        areaSort: 1,
        taskSort: 0,
      ),
      const WpTask(
        id: 'x',
        companyId: 'c',
        name: 'other card',
        roleScorecardId: 'rs2',
        responsibilityArea: 'Setup',
        areaSort: 9,
        taskSort: 9,
      ),
    ];

    test(
      'joining an existing area appends, keeping the area heading in place',
      () {
        final p = nextSortFor(allTasks: existing, cardId: 'rs1', area: 'Setup');
        expect(
          p.areaSort,
          0,
          reason: 'moving a task must not reorder the headings',
        );
        expect(p.taskSort, 2, reason: 'last, which is what "add" means');
      },
    );

    test('a brand-new area goes after the last one', () {
      final p = nextSortFor(
        allTasks: existing,
        cardId: 'rs1',
        area: 'Training',
      );
      expect(p.areaSort, 2);
      expect(p.taskSort, 0);
    });

    test('the very first responsibility on a card starts at 0/0', () {
      final p = nextSortFor(
        allTasks: existing,
        cardId: 'brand-new',
        area: 'Any',
      );
      expect(p.areaSort, 0);
      expect(p.taskSort, 0);
    });

    test('area matching ignores case and padding', () {
      final p = nextSortFor(
        allTasks: existing,
        cardId: 'rs1',
        area: '  setup ',
      );
      expect(p.areaSort, 0);
      expect(p.taskSort, 2, reason: 'must not create a duplicate area heading');
    });

    test('another card\'s positions are ignored', () {
      final p = nextSortFor(
        allTasks: existing,
        cardId: 'rs1',
        area: 'Research',
      );
      expect(p.taskSort, 1, reason: 'rs2 has taskSort 9 but is irrelevant');
    });

    test('a new row always needs a position', () {
      expect(needsResort(null, existing.first), isTrue);
    });

    test(
      'a rename does NOT reposition — that would reword the contract annex',
      () {
        final renamed = WpTask(
          id: 'a2',
          companyId: 'c',
          name: 'A second, reworded',
          roleScorecardId: 'rs1',
          responsibilityArea: 'Setup',
          areaSort: 0,
          taskSort: 1,
        );
        expect(needsResort(existing[1], renamed), isFalse);
      },
    );

    test('moving to another area or card does need one', () {
      expect(
        needsResort(
          existing[1],
          const WpTask(
            id: 'a2',
            companyId: 'c',
            name: 'A second',
            roleScorecardId: 'rs1',
            responsibilityArea: 'Research',
          ),
        ),
        isTrue,
      );
      expect(
        needsResort(
          existing[1],
          const WpTask(
            id: 'a2',
            companyId: 'c',
            name: 'A second',
            roleScorecardId: 'rs2',
            responsibilityArea: 'Setup',
          ),
        ),
        isTrue,
      );
    });

    test('a case-only area change is not a move', () {
      expect(
        needsResort(
          existing[1],
          const WpTask(
            id: 'a2',
            companyId: 'c',
            name: 'A second',
            roleScorecardId: 'rs1',
            responsibilityArea: ' SETUP ',
          ),
        ),
        isFalse,
      );
    });
  });
}
