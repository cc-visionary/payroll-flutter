import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/data/repositories/workforce_planning_repository.dart';
import 'package:payroll_flutter/features/workforce_planning/tabs/balance_tab.dart';
import 'package:payroll_flutter/features/workforce_planning/wp_providers.dart';

/// Captures reassignments so a test can prove Apply wrote exactly the drafts.
class _FakeRepo implements WorkforcePlanningRepository {
  final List<(String, String?)> reassigned = [];

  @override
  Future<void> reassignTaskOwner(String taskId, String? ownerEmployeeId) async {
    reassigned.add((taskId, ownerEmployeeId));
  }

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Employee _emp(String id, String first, String last, {String? title, String? card}) =>
    Employee(
      id: id, companyId: 'c', employeeNumber: id, firstName: first, lastName: last,
      jobTitle: title, roleScorecardId: card, employmentType: 'FULL_TIME',
      employmentStatus: 'ACTIVE', hireDate: DateTime(2024, 1, 1),
      isRankAndFile: true, isOtEligible: false, isNdEligible: false,
      isHolidayPayEligible: false, sssEligibilityOverride: false,
      philhealthEligibilityOverride: false, pagibigEligibilityOverride: false,
      taxOnFullEarnings: false,
    );

WpPersonLoad _cap(String id, double hours) => WpPersonLoad(
    employeeId: id, companyId: 'c', capacityHours: hours, growthMultiplier: 1);

Widget _host({
  required List<Employee> employees,
  required List<WpTask> tasks,
  required List<WpTaskComputed> computed,
  Map<String, int> kpis = const {},
  _FakeRepo? repo,
}) =>
    ProviderScope(
      overrides: [
        wpActiveEmployeesProvider.overrideWith((ref) async => employees),
        wpTasksProvider.overrideWith((ref) async => tasks),
        wpAllTaskComputedProvider.overrideWith((ref) async => computed),
        wpPersonLoadsProvider
            .overrideWith((ref) async => [for (final e in employees) _cap(e.id, 160)]),
        wpKpiCountByEmployeeProvider.overrideWith((ref) async => kpis),
        wpConfigProvider.overrideWith((ref) async => null),
        if (repo != null) workforcePlanningRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(home: Scaffold(body: BalanceTab())),
    );

/// Marvin 210h of 160h = 131% (over); Brixter has nothing.
List<Employee> get _people => [
      _emp('e1', 'Marvin', 'Ong', title: 'Sys'),
      _emp('e2', 'Brixter', 'Del Mundo', title: 'HR'),
    ];
List<WpTask> get _tasks => const [
      WpTask(id: 't1', companyId: 'c', name: 'Flashing devices', ownerEmployeeId: 'e1'),
      WpTask(id: 't2', companyId: 'c', name: 'Device QC', ownerEmployeeId: 'e1'),
    ];
List<WpTaskComputed> get _computed => const [
      WpTaskComputed(taskId: 't1', companyId: 'c', hoursPerMonthBase: 160),
      WpTaskComputed(taskId: 't2', companyId: 'c', hoursPerMonthBase: 50),
    ];

Future<void> _drag(WidgetTester tester, String taskName, String personName) async {
  final from = tester.getCenter(find.text(taskName));
  final to = tester.getCenter(find.text(personName));
  final g = await tester.startGesture(from);
  await tester.pump(const Duration(milliseconds: 100));
  await g.moveTo(to);
  await tester.pump();
  await g.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('ranks people by load and flags the one over capacity', (tester) async {
    await tester.pumpWidget(
        _host(employees: _people, tasks: _tasks, computed: _computed, kpis: {'e1': 4}));
    await tester.pumpAndSettle();

    // Twice for the selected person: once in the list, once as the panel title.
    expect(find.text('Marvin Ong'), findsNWidgets(2));
    expect(find.text('Brixter Del Mundo'), findsOneWidget);
    expect(find.text('131%'), findsOneWidget, reason: '210h of 160h');
    // Also twice: the list chip and the panel chip for the selected person.
    expect(find.text('Over'), findsNWidgets(2));
    expect(find.textContaining('1 over capacity'), findsOneWidget);
    // KPI count survived the rewrite from the old table layout.
    expect(find.textContaining('4 KPIs'), findsOneWidget);
  });

  testWidgets('the busiest person is selected first and their work is listed',
      (tester) async {
    await tester.pumpWidget(_host(employees: _people, tasks: _tasks, computed: _computed));
    await tester.pumpAndSettle();
    expect(find.text('Flashing devices'), findsOneWidget);
    expect(find.text('Device QC'), findsOneWidget);
    expect(find.textContaining('2 weighted responsibilities'), findsOneWidget);
  });

  testWidgets('dragging a task onto a person drafts a move without saving it',
      (tester) async {
    final repo = _FakeRepo();
    await tester.pumpWidget(
        _host(employees: _people, tasks: _tasks, computed: _computed, repo: repo));
    await tester.pumpAndSettle();
    expect(find.textContaining('unsaved'), findsNothing);

    await _drag(tester, 'Device QC', 'Brixter Del Mundo');

    expect(find.textContaining('1 unsaved move'), findsOneWidget);
    expect(find.text('Apply 1'), findsOneWidget);
    expect(repo.reassigned, isEmpty, reason: 'a draft must not touch the database');
    // 210 -> 160 = 100%, and the old figure is shown struck through.
    expect(find.text('was 131%'), findsOneWidget);
  });

  testWidgets('Reset discards the drafts', (tester) async {
    await tester.pumpWidget(_host(employees: _people, tasks: _tasks, computed: _computed));
    await tester.pumpAndSettle();
    await _drag(tester, 'Device QC', 'Brixter Del Mundo');
    expect(find.textContaining('1 unsaved move'), findsOneWidget);

    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(find.textContaining('unsaved'), findsNothing);
    expect(find.text('131%'), findsOneWidget, reason: 'back to the original split');
  });

  testWidgets('Apply writes exactly the drafted moves', (tester) async {
    final repo = _FakeRepo();
    await tester.pumpWidget(
        _host(employees: _people, tasks: _tasks, computed: _computed, repo: repo));
    await tester.pumpAndSettle();
    await _drag(tester, 'Device QC', 'Brixter Del Mundo');

    await tester.tap(find.text('Apply 1'));
    await tester.pumpAndSettle();

    expect(repo.reassigned, [('t2', 'e2')]);
    expect(find.textContaining('Applied 1 move'), findsOneWidget);
  });

  testWidgets('an uncosted task cannot be moved and says why', (tester) async {
    await tester.pumpWidget(_host(
      employees: _people,
      tasks: const [
        WpTask(id: 't1', companyId: 'c', name: 'Uncosted work', ownerEmployeeId: 'e1'),
      ],
      computed: const [
        WpTaskComputed(taskId: 't1', companyId: 'c', hoursPerMonthBase: 0),
      ],
    ));
    await tester.pumpAndSettle();
    // Every load is 0 here, so ranking falls back to name and Brixter sorts
    // first — pick Marvin explicitly rather than depending on that.
    await tester.tap(find.text('Marvin Ong'));
    await tester.pumpAndSettle();
    expect(find.text('1 still to cost'), findsOneWidget);
    // No Draggable wraps it, so there is nothing to pick up.
    expect(
      find.ancestor(of: find.text('Uncosted work'), matching: find.byType(Draggable<String>)),
      findsNothing,
    );
  });

  testWidgets('a shared responsibility warns that moving it hands over the whole task',
      (tester) async {
    await tester.pumpWidget(_host(
      employees: [
        _emp('e1', 'Arriane', 'P', card: 'rs1'),
        _emp('e2', 'Ron', 'G', card: 'rs1'),
      ],
      tasks: const [
        WpTask(id: 't1', companyId: 'c', name: 'Kiosk demo', roleScorecardId: 'rs1'),
      ],
      computed: const [
        WpTaskComputed(taskId: 't1', companyId: 'c', hoursPerMonthBase: 40),
      ],
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Shared by 2'), findsOneWidget);
    expect(find.text('20.0h'), findsOneWidget, reason: 'each holder carries half');
  });

  testWidgets('unattributed work is surfaced, not silently dropped', (tester) async {
    await tester.pumpWidget(_host(
      employees: _people,
      tasks: const [WpTask(id: 't1', companyId: 'c', name: 'Orphan work')],
      computed: const [
        WpTaskComputed(taskId: 't1', companyId: 'c', hoursPerMonthBase: 12),
      ],
    ));
    await tester.pumpAndSettle();
    // Wording is now "unassigned" with an FTE readout, and it counts only
    // GENUINE orphans — legacy reference rows are reported separately.
    expect(find.textContaining('12.0h unassigned'), findsOneWidget);
  });

  // Regression: _drop selects the destination, which unmounts the card being
  // dragged; a disposed Draggable never fires onDragEnd, so a hover preview
  // cleared only there stayed set and kept rendering a move Reset could not
  // undo.
  testWidgets('the drag preview does not survive the drop', (tester) async {
    await tester.pumpWidget(_host(employees: _people, tasks: _tasks, computed: _computed));
    await tester.pumpAndSettle();
    await _drag(tester, 'Device QC', 'Brixter Del Mundo');
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();

    expect(find.text('131%'), findsOneWidget, reason: 'back to the original split');
    expect(find.textContaining('was '), findsNothing,
        reason: 'no phantom before/after left over');
  });

  testWidgets('the unassigned pool is a row in the rail you can open',
      (tester) async {
    await tester.pumpWidget(_host(
      employees: _people,
      tasks: const [
        WpTask(id: 't1', companyId: 'c', name: 'Orphan work'),
        WpTask(id: 't2', companyId: 'c', name: 'Owned work', ownerEmployeeId: 'e1'),
      ],
      computed: const [
        WpTaskComputed(taskId: 't1', companyId: 'c', hoursPerMonthBase: 12),
        WpTaskComputed(taskId: 't2', companyId: 'c', hoursPerMonthBase: 40),
      ],
    ));
    await tester.pumpAndSettle();
    expect(find.text('Unassigned'), findsOneWidget);
    expect(find.textContaining('1 task reaching nobody'), findsOneWidget);

    await tester.tap(find.text('Unassigned'));
    await tester.pumpAndSettle();
    expect(find.text('Orphan work'), findsOneWidget);
    expect(find.textContaining('Drag onto a person'), findsOneWidget);
  });

  testWidgets('legacy reference rows are not reported as unassigned debt',
      (tester) async {
    await tester.pumpWidget(_host(
      employees: _people,
      tasks: const [
        // No owner, no card, but an external_ref: the capacity-model copy whose
        // hours already live on a role-card responsibility.
        WpTask(id: 'L1', companyId: 'c', name: 'Legacy row', externalRef: 'T1'),
      ],
      computed: const [
        WpTaskComputed(taskId: 'L1', companyId: 'c', hoursPerMonthBase: 800),
      ],
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('800.0h unassigned'), findsNothing,
        reason: 'that work is already counted on the responsibilities');
    expect(find.textContaining('reference (not counted)'), findsOneWidget);
    expect(find.text('Unassigned'), findsNothing, reason: 'nothing to hand out');
  });

  testWidgets('a person with uncosted work is flagged as understated',
      (tester) async {
    await tester.pumpWidget(_host(
      employees: _people,
      tasks: const [
        WpTask(id: 't1', companyId: 'c', name: 'Costed', ownerEmployeeId: 'e1'),
        WpTask(id: 't2', companyId: 'c', name: 'No hours', ownerEmployeeId: 'e1'),
        WpTask(id: 't3', companyId: 'c', name: 'Just an expectation',
            ownerEmployeeId: 'e1', isExpectation: true),
      ],
      computed: const [
        WpTaskComputed(taskId: 't1', companyId: 'c', hoursPerMonthBase: 40),
      ],
    ));
    await tester.pumpAndSettle();
    // 3 tasks, 1 costed, 1 expectation -> 1 of 2 costable is missing.
    expect(find.textContaining('1 of 2 uncosted — understated'), findsOneWidget,
        reason: 'expectations must not be counted as missing estimates');
  });

  // Behavioural standards and required skills are role-scorecard concerns:
  // they apply across the whole role rather than being units of work, so they
  // carry no hours and have no place in a workload view. They used to trail the
  // list looking like broken rows, then like a backlog.
  testWidgets('behavioural expectations are excluded from the workload panel',
      (tester) async {
    await tester.pumpWidget(_host(
      employees: _people,
      tasks: const [
        WpTask(id: 't1', companyId: 'c', name: 'Real costed work', ownerEmployeeId: 'e1'),
        WpTask(id: 't2', companyId: 'c', name: 'Ensure procedures are followed',
            ownerEmployeeId: 'e1', isExpectation: true),
      ],
      computed: const [
        WpTaskComputed(taskId: 't1', companyId: 'c', hoursPerMonthBase: 40),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Ensure procedures are followed'), findsNothing,
        reason: 'a behavioural standard is not workload');
    expect(find.text('Real costed work'), findsOneWidget);
    expect(find.textContaining('1 weighted responsibility'), findsOneWidget,
        reason: 'the count is weighted work only');
    expect(find.textContaining('still to cost'), findsNothing,
        reason: 'an expectation is not an outstanding estimate');
  });

  testWidgets('a genuinely uncosted task is still reported as outstanding',
      (tester) async {
    await tester.pumpWidget(_host(
      employees: _people,
      tasks: const [
        WpTask(id: 't1', companyId: 'c', name: 'Needs an estimate', ownerEmployeeId: 'e1'),
      ],
      computed: const [],
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marvin Ong'));
    await tester.pumpAndSettle();
    expect(find.text('1 still to cost'), findsOneWidget);
    expect(find.text('needs costing'), findsOneWidget);
  });

}
