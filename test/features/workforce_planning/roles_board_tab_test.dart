import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';
import 'package:payroll_flutter/data/repositories/workforce_planning_repository.dart';
import 'package:payroll_flutter/features/auth/profile_provider.dart';
import 'package:payroll_flutter/features/workforce_planning/tabs/roles_board_tab.dart';
import 'package:payroll_flutter/features/workforce_planning/wp_providers.dart';

class _FakeRepo implements WorkforcePlanningRepository {
  final applied = <Map<String, String>>[];
  final appliedMoves = <TaskRoleMove>[];
  final cleared = <String>[];
  final saved = <WpTask>[];
  bool throwOnSave = false;
  bool throwOnClear = false;

  /// When set, [clearReviewNote] waits on it — lets a test see the pending state.
  Completer<void>? clearGate;

  /// Ids [moveTasksToRoles] should report as failed on its next call, mirroring
  /// the real repo's per-row failure reporting. Consumed (reset to empty) once used.
  List<String> failNext = const [];

  /// When true, [moveTasksToRoles] throws instead of returning — simulates a
  /// network/unexpected error rather than a per-row failure. Consumed once used.
  bool throwNext = false;

  @override
  Future<List<String>> moveTasksToRoles(List<TaskRoleMove> moves) async {
    if (throwNext) {
      throwNext = false;
      throw Exception('network error');
    }
    applied.add({for (final m in moves) m.taskId: m.roleId});
    appliedMoves.addAll(moves);
    final failed = failNext;
    failNext = const [];
    return failed;
  }
  @override
  Future<void> clearReviewNote(String taskId) async {
    await clearGate?.future;
    if (throwOnClear) throw Exception('offline');
    cleared.add(taskId);
  }
  @override
  Future<void> saveTask(WpTask task) async {
    if (throwOnSave) throw Exception('offline');
    saved.add(task);
  }
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Employee emp(String id, String first, {String? role, String? reportsTo, String status = 'ACTIVE', DateTime? deletedAt}) => Employee(
  id: id, companyId: 'c', employeeNumber: id, firstName: first, lastName: 'X',
  roleScorecardId: role, reportsToId: reportsTo, deletedAt: deletedAt,
  employmentType: 'FULL_TIME', employmentStatus: status,
  hireDate: DateTime(2024, 1, 1), isRankAndFile: true, isOtEligible: false,
  isNdEligible: false, isHolidayPayEligible: false,
  sssEligibilityOverride: false, philhealthEligibilityOverride: false,
  pagibigEligibilityOverride: false, taxOnFullEarnings: false,
);

RoleScorecard role(String id, String title, {List<String> areas = const [], String companyId = 'c'}) => RoleScorecard(
  id: id, companyId: companyId, jobTitle: title, missionStatement: '',
  responsibilities: [for (final a in areas) ResponsibilityArea(area: a, tasks: const ['x'])], kpis: const [], wageType: 'MONTHLY',
  workHoursPerDay: 8, workDaysPerWeek: 'MON_FRI', isActive: true,
  effectiveDate: DateTime(2026),
);

Widget _host(_FakeRepo repo, {List<WpTask>? tasks, List<Employee>? employees, List<RoleScorecard>? roles}) => ProviderScope(
  overrides: [
    userProfileProvider.overrideWith((ref) async => null),
    wpActiveEmployeesProvider.overrideWith((ref) async => employees ?? [
      emp('ana', 'Ana', role: 'bh', reportsTo: 'jer'),
      emp('ben', 'Ben', role: 'bh', reportsTo: 'jer'),
      emp('jer', 'Jeremy', role: 'om'),
    ]),
    roleScorecardListProvider.overrideWith((ref) async => roles ?? [
      role('bh', 'Brand Handler', areas: ['Fulfilment']),
      role('om', 'Ops Manager', areas: ['Reporting']),
    ]),
    wpTasksProvider.overrideWith((ref) async => tasks ?? const [
      WpTask(id: 't1', companyId: 'c', name: 'Pack orders', roleScorecardId: 'bh',
          responsibilityArea: 'Fulfilment', cadence: 'DAILY', timesManual: 26, minutesManual: 60),
      WpTask(id: 't2', companyId: 'c', name: 'Weekly report', roleScorecardId: 'om',
          responsibilityArea: 'Reporting'),
    ]),
    wpAllTaskComputedProvider.overrideWith((ref) async => const [
      WpTaskComputed(taskId: 't1', companyId: 'c', hoursPerMonthBase: 160),
      WpTaskComputed(taskId: 't2', companyId: 'c', hoursPerMonthBase: 176),
    ]),
    wpPersonLoadsProvider.overrideWith((ref) async => [
      for (final id in ['ana', 'ben', 'jer']) WpPersonLoad(employeeId: id, companyId: 'c', capacityHours: 160),
    ]),
    wpConfigProvider.overrideWith((ref) async => null),
    wpDriversProvider.overrideWith((ref) async => const []),
    wpNodesProvider.overrideWith((ref) async => const []),
    wpRatesProvider.overrideWith((ref) async => const []),
    workforcePlanningRepositoryProvider.overrideWithValue(repo),
  ],
  child: const MaterialApp(home: Scaffold(body: RolesBoardTab())),
);

Future<void> drag(WidgetTester tester, Finder from, Finder to) async {
  final g = await tester.startGesture(tester.getCenter(from));
  await tester.pump(const Duration(milliseconds: 100));
  await g.moveTo(tester.getCenter(to));
  await tester.pump();
  await g.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('over-loaded role first, with needs/short and checked-by', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(_FakeRepo()));
    await tester.pumpAndSettle();

    final om = tester.getTopLeft(find.byKey(const ValueKey('role-card-om')));
    final bh = tester.getTopLeft(find.byKey(const ValueKey('role-card-bh')));
    expect(om.dy < bh.dy, isTrue, reason: 'Ops Manager 110% sorts above Brand Handler 50%');
    expect(find.textContaining('Needs 1.1 people'), findsOneWidget);
    expect(find.textContaining('short 0.1'), findsOneWidget);
    expect(find.textContaining('checked by Ops Manager'), findsOneWidget);
    // R5: role creation moved here from the retired Roles tab.
    expect(find.widgetWithText(FilledButton, 'New role'), findsOneWidget);
  });

  testWidgets('drag a task to another role -> draft with before/after, Apply writes it', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final repo = _FakeRepo();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await drag(tester, find.byKey(const ValueKey('task-t2')), find.byKey(const ValueKey('role-card-bh')));
    expect(find.text('1 unsaved move'), findsOneWidget);
    expect(find.textContaining('50% → 105%'), findsOneWidget, reason: 'Brand Handler 160h → 336h of 320h');

    await tester.tap(find.text('Apply 1'));
    await tester.pumpAndSettle();
    expect(repo.applied, [{'t2': 'bh'}]);
  });

  testWidgets('Review Focus 3: dropping on its own role records nothing; dragging back removes the draft', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(_FakeRepo()));
    await tester.pumpAndSettle();

    await drag(tester, find.byKey(const ValueKey('task-t1')), find.byKey(const ValueKey('role-card-bh')));
    expect(find.textContaining('unsaved'), findsNothing);

    await drag(tester, find.byKey(const ValueKey('task-t1')), find.byKey(const ValueKey('role-card-om')));
    expect(find.text('1 unsaved move'), findsOneWidget);
    await drag(tester, find.byKey(const ValueKey('task-t1')), find.byKey(const ValueKey('role-card-bh')));
    expect(find.textContaining('unsaved'), findsNothing);
  });

  testWidgets('Reset discards drafts without writing', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final repo = _FakeRepo();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();
    await drag(tester, find.byKey(const ValueKey('task-t2')), find.byKey(const ValueKey('role-card-bh')));
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(find.textContaining('unsaved'), findsNothing);
    expect(repo.applied, isEmpty);
  });

  testWidgets('Apply throws: all drafts are kept, snackbar shown, Apply/Reset re-enabled', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final repo = _FakeRepo()..throwNext = true;
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await drag(tester, find.byKey(const ValueKey('task-t2')), find.byKey(const ValueKey('role-card-bh')));
    expect(find.text('1 unsaved move'), findsOneWidget);

    await tester.tap(find.text('Apply 1'));
    await tester.pumpAndSettle();

    // The draft is kept — nothing was confirmed saved.
    expect(find.text('1 unsaved move'), findsOneWidget);
    expect(find.textContaining('Could not apply moves'), findsOneWidget);
    expect(repo.applied, isEmpty);

    // Apply/Reset are enabled again (not stuck disabled behind `_applying`):
    // tapping Reset actually clears the draft.
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(find.textContaining('unsaved'), findsNothing);
  });

  testWidgets('Apply: a move the repo reports as failed stays a draft, the other is applied', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final repo = _FakeRepo()..failNext = ['t1'];
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await drag(tester, find.byKey(const ValueKey('task-t1')), find.byKey(const ValueKey('role-card-om')));
    await drag(tester, find.byKey(const ValueKey('task-t2')), find.byKey(const ValueKey('role-card-bh')));
    expect(find.text('2 unsaved moves'), findsOneWidget);

    await tester.tap(find.text('Apply 2'));
    await tester.pumpAndSettle();

    expect(repo.applied, [{'t1': 'om', 't2': 'bh'}]);
    // t2's move succeeded and is gone; t1's failed and stays a draft.
    expect(find.text('1 unsaved move'), findsOneWidget);
    expect(find.textContaining('could not be saved'), findsOneWidget);
  });

  void bigView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Finder inCard(String roleId, String text) => find.descendant(
    of: find.byKey(ValueKey('role-card-$roleId')),
    matching: find.text(text),
  );

  testWidgets('F1: Apply writes the target role\'s first area, at the end of it', (tester) async {
    bigView(tester);
    final repo = _FakeRepo();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await drag(tester, find.byKey(const ValueKey('task-t2')), find.byKey(const ValueKey('role-card-bh')));
    await tester.tap(find.text('Apply 1'));
    await tester.pumpAndSettle();

    final m = repo.appliedMoves.single;
    expect(m.roleId, 'bh');
    expect(m.area, 'Fulfilment', reason: 'never the old role\'s "Reporting"');
    expect((m.areaSort, m.taskSort), (0, 1), reason: 'after Pack orders');
  });

  testWidgets('F1: a new task added on a role card gets that role\'s first area, placed last', (tester) async {
    bigView(tester);
    final repo = _FakeRepo();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(inCard('bh', 'Add task'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Count stock');
    await tester.enterText(find.widgetWithText(TextFormField, 'Minutes each time'), '10');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final t = repo.saved.single;
    expect(t.roleScorecardId, 'bh');
    expect(t.responsibilityArea, 'Fulfilment');
    expect((t.areaSort, t.taskSort), (0, 1));
    expect(t.companyId, 'c');
  });

  testWidgets('F2: a failed task save shows a message instead of failing silently', (tester) async {
    bigView(tester);
    final repo = _FakeRepo()..throwOnSave = true;
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(inCard('bh', 'Add task'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Count stock');
    await tester.enterText(find.widgetWithText(TextFormField, 'Minutes each time'), '10');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not save task'), findsOneWidget);
  });

  const flagged = [
    WpTask(id: 't1', companyId: 'c', name: 'Pack orders', roleScorecardId: 'bh',
        responsibilityArea: 'Fulfilment', allocationReviewNote: 'was split 50/50'),
  ];

  testWidgets('F2: "Looks right" is disabled while its call is pending', (tester) async {
    bigView(tester);
    final repo = _FakeRepo()..clearGate = Completer<void>();
    await tester.pumpWidget(_host(repo, tasks: flagged));
    await tester.pumpAndSettle();

    Finder button() => find.widgetWithText(TextButton, 'Looks right');
    await tester.tap(button());
    await tester.pump();
    expect(tester.widget<TextButton>(button()).onPressed, isNull);

    repo.clearGate!.complete();
    await tester.pumpAndSettle();
    expect(repo.cleared, ['t1']);
  });

  testWidgets('F2: a failed "Looks right" shows a message and re-enables the button', (tester) async {
    bigView(tester);
    final repo = _FakeRepo()..throwOnClear = true;
    await tester.pumpWidget(_host(repo, tasks: flagged));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Looks right'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not clear the check'), findsOneWidget);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Looks right')).onPressed, isNotNull);
  });

  testWidgets('F2: with no company id, "Add task" is disabled rather than writing an empty one', (tester) async {
    bigView(tester);
    await tester.pumpWidget(_host(
      _FakeRepo(),
      employees: const [],
      roles: [role('bh', 'Brand Handler', companyId: '')],
      tasks: const [],
    ));
    await tester.pumpAndSettle();
    final add = find.ancestor(of: inCard('bh', 'Add task'), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));
    expect(tester.widget<ButtonStyleButton>(add.first).onPressed, isNull);
  });

  testWidgets('F7: the Add holder picker lists only active, not-deleted people', (tester) async {
    bigView(tester);
    await tester.pumpWidget(_host(_FakeRepo(), employees: [
      emp('jer', 'Jeremy', role: 'om'),
      emp('amy', 'Amy'),
      emp('tom', 'Tom', status: 'TERMINATED'),
      emp('del', 'Dell', deletedAt: DateTime(2026)),
    ]));
    await tester.pumpAndSettle();

    await tester.tap(inCard('bh', 'Add holder'));
    await tester.pumpAndSettle();
    expect(find.text('Amy X'), findsOneWidget);
    expect(find.text('Jeremy X'), findsOneWidget);
    expect(find.text('Tom X'), findsNothing);
    expect(find.text('Dell X'), findsNothing);
  });
}
