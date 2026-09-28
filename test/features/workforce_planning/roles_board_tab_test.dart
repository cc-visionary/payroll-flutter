import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';
import 'package:payroll_flutter/data/repositories/workforce_planning_repository.dart';
import 'package:payroll_flutter/features/workforce_planning/tabs/roles_board_tab.dart';
import 'package:payroll_flutter/features/workforce_planning/wp_providers.dart';

class _FakeRepo implements WorkforcePlanningRepository {
  final applied = <Map<String, String>>[];
  final cleared = <String>[];

  /// Ids [moveTasksToRoles] should report as failed on its next call, mirroring
  /// the real repo's per-row failure reporting. Consumed (reset to empty) once used.
  List<String> failNext = const [];

  /// When true, [moveTasksToRoles] throws instead of returning — simulates a
  /// network/unexpected error rather than a per-row failure. Consumed once used.
  bool throwNext = false;

  @override
  Future<List<String>> moveTasksToRoles(Map<String, String> moves) async {
    if (throwNext) {
      throwNext = false;
      throw Exception('network error');
    }
    applied.add({...moves});
    final failed = failNext;
    failNext = const [];
    return failed;
  }
  @override
  Future<void> clearReviewNote(String taskId) async => cleared.add(taskId);
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Employee emp(String id, String first, {String? role, String? reportsTo}) => Employee(
  id: id, companyId: 'c', employeeNumber: id, firstName: first, lastName: 'X',
  roleScorecardId: role, reportsToId: reportsTo,
  employmentType: 'FULL_TIME', employmentStatus: 'ACTIVE',
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

Widget _host(_FakeRepo repo, {List<WpTask>? tasks}) => ProviderScope(
  overrides: [
    wpActiveEmployeesProvider.overrideWith((ref) async => [
      emp('ana', 'Ana', role: 'bh', reportsTo: 'jer'),
      emp('ben', 'Ben', role: 'bh', reportsTo: 'jer'),
      emp('jer', 'Jeremy', role: 'om'),
    ]),
    roleScorecardListProvider.overrideWith((ref) async => [role('bh', 'Brand Handler'), role('om', 'Ops Manager')]),
    wpTasksProvider.overrideWith((ref) async => tasks ?? const [
      WpTask(id: 't1', companyId: 'c', name: 'Pack orders', roleScorecardId: 'bh'),
      WpTask(id: 't2', companyId: 'c', name: 'Weekly report', roleScorecardId: 'om'),
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
}
