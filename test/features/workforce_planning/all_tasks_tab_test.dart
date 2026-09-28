import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';
import 'package:payroll_flutter/data/repositories/workforce_planning_repository.dart';
import 'package:payroll_flutter/features/workforce_planning/tabs/all_tasks_tab.dart';
import 'package:payroll_flutter/features/workforce_planning/wp_providers.dart';

class _FakeRepo implements WorkforcePlanningRepository {
  final restored = <String>[];
  final deleted = <String>[];
  final saved = <WpTask>[];
  Set<String> failDelete = const {};

  @override
  Future<void> setTaskArchived(String taskId, bool archived) async {
    if (!archived) restored.add(taskId);
  }
  @override
  Future<void> deleteTask(String id) async {
    if (failDelete.contains(id)) throw Exception('fk');
    deleted.add(id);
  }
  @override
  Future<void> saveTask(WpTask task) async => saved.add(task);
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Employee emp(String id, {String? role, String status = 'ACTIVE'}) => Employee(
  id: id, companyId: 'c', employeeNumber: id, firstName: id, lastName: 'X',
  roleScorecardId: role, employmentType: 'FULL_TIME', employmentStatus: status,
  hireDate: DateTime(2024, 1, 1), isRankAndFile: true, isOtEligible: false,
  isNdEligible: false, isHolidayPayEligible: false,
  sssEligibilityOverride: false, philhealthEligibilityOverride: false,
  pagibigEligibilityOverride: false, taxOnFullEarnings: false,
);

RoleScorecard role(String id, String title) => RoleScorecard(
  id: id, companyId: 'c', jobTitle: title, missionStatement: '',
  responsibilities: const [ResponsibilityArea(area: 'Fulfilment', tasks: ['x'])],
  kpis: const [], wageType: 'MONTHLY', workHoursPerDay: 8,
  workDaysPerWeek: 'MON_FRI', isActive: true, effectiveDate: DateTime(2026),
);

void main() {
  const tasks = [
    WpTask(id: 'a', companyId: 'c', name: 'Pack Shopee orders', roleScorecardId: 'bh'),
    WpTask(id: 'b', companyId: 'c', name: 'Reply to chats'),
    WpTask(id: 'c', companyId: 'c', name: 'Legacy row', externalRef: 'X'),
    WpTask(id: 'd', companyId: 'c', name: 'Split thing', roleScorecardId: 'om', allocationReviewNote: 'was: x'),
    WpTask(id: 'e', companyId: 'c', name: 'Old', roleScorecardId: 'bh', status: 'ARCHIVED'),
    WpTask(id: 'f', companyId: 'c', name: 'Archived legacy', externalRef: 'Y', status: 'ARCHIVED'),
  ];

  test('default hides archived and legacy reference rows', () {
    expect(filterTasks(tasks).map((t) => t.id), ['a', 'b', 'd']);
  });
  test('search is case-insensitive on name', () {
    expect(filterTasks(tasks, query: 'shopee').map((t) => t.id), ['a']);
  });
  test('no role / flagged / by role', () {
    expect(filterTasks(tasks, filter: AllTasksFilter.noRole).map((t) => t.id), ['b']);
    expect(filterTasks(tasks, filter: AllTasksFilter.flagged).map((t) => t.id), ['d']);
    expect(filterTasks(tasks, filter: AllTasksFilter.role, roleId: 'bh').map((t) => t.id), ['a']);
  });
  test('F4: archived shows only ARCHIVED, non-legacy tasks', () {
    expect(filterTasks(tasks, filter: AllTasksFilter.archived).map((t) => t.id), ['e']);
    expect(filterTasks(tasks, filter: AllTasksFilter.archived, query: 'nothing'), isEmpty);
  });
  test('F6: old capacity-model rows = ACTIVE legacy reference rows only', () {
    expect(filterTasks(tasks, filter: AllTasksFilter.legacy).map((t) => t.id), ['c']);
  });

  Widget host(_FakeRepo repo, {List<WpTask> tasks = tasks}) => ProviderScope(
    overrides: [
      wpTasksProvider.overrideWith((ref) async => tasks),
      roleScorecardListProvider.overrideWith((ref) async => [role('bh', 'Brand Handler'), role('om', 'Ops Manager')]),
      wpActiveEmployeesProvider.overrideWith((ref) async => [
        emp('ana', role: 'bh'),
        emp('ben', role: 'bh'),
        emp('tom', role: 'bh', status: 'TERMINATED'),
      ]),
      wpAllTaskComputedProvider.overrideWith((ref) async => const []),
      wpConfigProvider.overrideWith((ref) async => null),
      wpNodesProvider.overrideWith((ref) async => const []),
      wpDriversProvider.overrideWith((ref) async => const []),
      wpRatesProvider.overrideWith((ref) async => const []),
      workforcePlanningRepositoryProvider.overrideWithValue(repo),
    ],
    child: const MaterialApp(home: Scaffold(body: AllTasksTab())),
  );

  void bigView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> pickFilter(WidgetTester tester, String label) async {
    await tester.tap(find.text('All tasks').first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('F3: editing a task shows the split across its role\'s ACTIVE holders', (tester) async {
    bigView(tester);
    await tester.pumpWidget(host(_FakeRepo()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pack Shopee orders'));
    await tester.pumpAndSettle();
    expect(find.textContaining('split across 2 people'), findsOneWidget,
        reason: 'Ana + Ben; the TERMINATED holder does not count');
    expect(find.textContaining('nobody holds this role yet'), findsNothing);
  });

  testWidgets('F4: the Archived filter lists archived tasks with a Restore action', (tester) async {
    bigView(tester);
    final repo = _FakeRepo();
    await tester.pumpWidget(host(repo));
    await tester.pumpAndSettle();
    await pickFilter(tester, 'Archived');
    expect(find.text('Old'), findsOneWidget);
    expect(find.text('Pack Shopee orders'), findsNothing);
    await tester.tap(find.byTooltip('Restore'));
    await tester.pumpAndSettle();
    expect(repo.restored, ['e']);
  });

  testWidgets('F6: old capacity-model rows can be deleted together, failures reported', (tester) async {
    bigView(tester);
    final repo = _FakeRepo()..failDelete = {'c2'};
    await tester.pumpWidget(host(repo, tasks: const [
      WpTask(id: 'c', companyId: 'c', name: 'Legacy row', externalRef: 'X'),
      WpTask(id: 'c2', companyId: 'c', name: 'Legacy two', externalRef: 'Z'),
      WpTask(id: 'a', companyId: 'c', name: 'Real work', roleScorecardId: 'bh'),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('Delete all of these'), findsNothing, reason: 'only on the legacy filter');
    await pickFilter(tester, 'Old capacity-model rows (2)');
    await tester.tap(find.text('Delete all of these'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Delete 2 old capacity-model rows?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete all'));
    await tester.pumpAndSettle();
    expect(repo.deleted, ['c']);
    expect(find.textContaining('1 of 2 could not be deleted'), findsOneWidget);
  });
}
