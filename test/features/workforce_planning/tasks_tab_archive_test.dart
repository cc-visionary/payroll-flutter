import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';
import 'package:payroll_flutter/data/repositories/workforce_planning_repository.dart';
import 'package:payroll_flutter/features/workforce_planning/tabs/tasks_tab.dart';
import 'package:payroll_flutter/features/workforce_planning/wp_providers.dart';

class _FakeRepo implements WorkforcePlanningRepository {
  final List<(String, bool)> archiveCalls = [];
  @override
  Future<void> setTaskArchived(String taskId, bool archived) async {
    archiveCalls.add((taskId, archived));
  }

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

final _card = RoleScorecard(
  id: 'rs1',
  companyId: 'c',
  jobTitle: 'Ops',
  missionStatement: '',
  responsibilities: const [],
  kpis: const [],
  wageType: 'MONTHLY',
  workHoursPerDay: 8,
  workDaysPerWeek: 'MON_FRI',
  isActive: true,
  effectiveDate: DateTime(2026, 1, 1),
);

const _node = WpNode(id: 'n1', companyId: 'c', code: '6', name: '6. Fulfill');
const _active = WpTask(
  id: 't1',
  companyId: 'c',
  name: 'Pack orders',
  roleScorecardId: 'rs1',
  responsibilityArea: 'Fulfilment',
  criticality: 'CRITICAL',
  hoursPerMonth: 10,
);
const _archived = WpTask(
  id: 't2',
  companyId: 'c',
  name: 'Old blindbox packing',
  roleScorecardId: 'rs1',
  responsibilityArea: 'Fulfilment',
  status: 'ARCHIVED',
);

Widget _host(
  _FakeRepo repo, {
  List<WpTask> tasks = const [_active, _archived],
}) => ProviderScope(
  overrides: [
    wpTasksProvider.overrideWith((ref) async => tasks),
    wpNodesProvider.overrideWith((ref) async => const [_node]),
    wpDriversProvider.overrideWith((ref) async => const []),
    wpRatesProvider.overrideWith((ref) async => const []),
    wpActiveEmployeesProvider.overrideWith((ref) async => const []),
    roleScorecardListProvider.overrideWith((ref) async => [_card]),
    workforcePlanningRepositoryProvider.overrideWithValue(repo),
  ],
  child: const MaterialApp(home: Scaffold(body: TasksTab())),
);

void main() {
  testWidgets(
    'an active task shows its criticality chip; archived is hidden in a section',
    (tester) async {
      // The full-width table plus the Archived section below it exceed the
      // default 800x600 test surface — same fix as tasks_tab_costing_test.dart.
      tester.view.physicalSize = const Size(1750, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(_FakeRepo()));
      await tester.pumpAndSettle();

      // Active row + its chip visible; archived name is not in the main grid.
      expect(find.text('Pack orders'), findsOneWidget);
      expect(find.text('Critical'), findsOneWidget);
      expect(find.text('Old blindbox packing'), findsNothing);

      // It lives behind the Archived (1) expander.
      expect(find.text('Archived (1)'), findsOneWidget);
      await tester.tap(find.text('Archived (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Old blindbox packing'), findsOneWidget);
    },
  );

  testWidgets('the row Archive action calls setTaskArchived(true)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1750, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = _FakeRepo();
    await tester.pumpWidget(_host(repo, tasks: const [_active]));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Archive (no longer needed)'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Archive'));
    await tester.pumpAndSettle();

    expect(repo.archiveCalls, [('t1', true)]);
  });

  testWidgets('Restore calls setTaskArchived(false)', (tester) async {
    tester.view.physicalSize = const Size(1750, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = _FakeRepo();
    await tester.pumpWidget(_host(repo, tasks: const [_archived]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Archived (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Restore'));
    await tester.pumpAndSettle();

    expect(repo.archiveCalls, [('t2', false)]);
  });
}
