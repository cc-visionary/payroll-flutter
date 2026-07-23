import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';
import 'package:payroll_flutter/data/repositories/workforce_planning_repository.dart';
import 'package:payroll_flutter/features/workforce_planning/tabs/tasks_tab.dart';
import 'package:payroll_flutter/features/workforce_planning/wp_providers.dart';

/// Records what the grid actually sends, so the tests can assert the patch —
/// the thing that decides whether hours land correctly in the database.
class _FakeRepo implements WorkforcePlanningRepository {
  final List<Map<String, Map<String, dynamic>>> calls = [];
  List<String> failWith = const [];

  @override
  Future<List<String>> updateTaskCosts(Map<String, Map<String, dynamic>> byId) async {
    calls.add(byId);
    return failWith;
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

const _driver = WpDriver(
    id: 'd1', companyId: 'c', name: 'Shopee orders', value: 120, grows: true);
const _rate =
    WpRate(id: 'r1', companyId: 'c', name: 'Pick/pack', minutesEach: 8);
const _node = WpNode(id: 'n1', companyId: 'c', code: '6', name: '6. Fulfill');

// A real promoted responsibility, not a short label — the length is what used
// to blow out the table's natural width.
const _task = WpTask(
    id: 't1', companyId: 'c',
    name: 'Lead the flashing, installation, configuration, testing, and final '
        'preparation of Linux, Android, and supported gaming devices.',
    roleScorecardId: 'rs1', responsibilityArea: 'Fulfilment');

Widget _host(_FakeRepo repo) => ProviderScope(
      overrides: [
        wpTasksProvider.overrideWith((ref) async => const [_task]),
        wpNodesProvider.overrideWith((ref) async => const [_node]),
        wpDriversProvider.overrideWith((ref) async => const [_driver]),
        wpRatesProvider.overrideWith((ref) async => const [_rate]),
        wpActiveEmployeesProvider.overrideWith((ref) async => const []),
        roleScorecardListProvider.overrideWith((ref) async => [_card]),
        workforcePlanningRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(home: Scaffold(body: TasksTab())),
    );

Future<void> _enterCostMode(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text('Cost tasks'));
  await tester.pumpAndSettle();
}

void main() {
  // The header now reports costing PROGRESS rather than a raw uncosted count:
  // expectations count as resolved, so the number can actually reach zero
  // instead of being a permanent banner.
  testWidgets('costing progress is surfaced before entering cost mode', (tester) async {
    await tester.pumpWidget(_host(_FakeRepo()));
    await tester.pumpAndSettle();
    expect(find.textContaining('0 of 1 resolved'), findsOneWidget);
    expect(find.textContaining('1 still to cost'), findsOneWidget);
  });

  testWidgets('typing manual times + minutes computes hours live and saves the patch',
      (tester) async {
    final repo = _FakeRepo();
    await tester.pumpWidget(_host(repo));
    await _enterCostMode(tester);

    // Save is disabled until something is actually edited.
    expect(find.text('Not costed'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('times-t1-manual')), '20');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('mins-t1-manual')), '45');
    await tester.pumpAndSettle();

    // 20 * 45 / 60 = 15.0
    expect(find.text('15.0'), findsOneWidget);
    expect(find.text('Save 1'), findsOneWidget);

    await tester.tap(find.text('Save 1'));
    await tester.pumpAndSettle();

    expect(repo.calls, hasLength(1));
    final patch = repo.calls.single['t1']!;
    expect(patch['times_source'], 'manual');
    expect(patch['times_manual'], 20);
    expect(patch['minutes_manual'], 45);
    expect(patch['driver_id'], isNull);
    expect(patch['rate_id'], isNull);
  });

  testWidgets('picking a growing driver marks the row as scaling', (tester) async {
    final repo = _FakeRepo();
    await tester.pumpWidget(_host(repo));
    await _enterCostMode(tester);

    await tester.tap(find.text('Manual').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shopee orders ↗').last);
    await tester.pumpAndSettle();
    // Minutes still unset -> not costed yet, so no hours and no Scales chip.
    expect(find.text('Scales'), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('mins-t1-manual')), '10');
    await tester.pumpAndSettle();

    // 120 * 1 * 10 / 60 = 20.0, and it scales because the driver grows.
    expect(find.text('20.0'), findsOneWidget);
    expect(find.text('Scales'), findsOneWidget);

    await tester.tap(find.text('Save 1'));
    await tester.pumpAndSettle();
    final patch = repo.calls.single['t1']!;
    expect(patch['times_source'], 'driver');
    expect(patch['driver_id'], 'd1');
    expect(patch['times_manual'], isNull,
        reason: 'a driver-sourced row must not keep a stale manual count');
  });

  testWidgets('editing back to the original value drops the change', (tester) async {
    await tester.pumpWidget(_host(_FakeRepo()));
    await _enterCostMode(tester);

    await tester.enterText(find.byKey(const ValueKey('times-t1-manual')), '20');
    await tester.pumpAndSettle();
    expect(find.text('Save 1'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('times-t1-manual')), '');
    await tester.pumpAndSettle();
    expect(find.text('Save 1'), findsNothing,
        reason: 'back to the starting value is not a change');
    expect(find.textContaining('Costing — edit the cells'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed,
      isNull,
      reason: 'save must be disabled when there is nothing to save',
    );
  });

  testWidgets('a failed row stays dirty so it can be retried', (tester) async {
    final repo = _FakeRepo()..failWith = ['t1'];
    await tester.pumpWidget(_host(repo));
    await _enterCostMode(tester);

    await tester.enterText(find.byKey(const ValueKey('times-t1-manual')), '20');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save 1'));
    await tester.pumpAndSettle();

    expect(find.textContaining('1 failed'), findsOneWidget);
    expect(find.text('Save 1'), findsOneWidget,
        reason: 'the failed row must remain unsaved and retryable');
  });

  // Regression: the tables used to inherit ResponsiveTable's 1100px cap, so on
  // a wide window they stopped a third of the way across and the Owner column
  // was clipped mid-word. Long responsibility sentences also set the table's
  // natural width, pushing the right-hand columns out of reach.
  testWidgets('tables fill a wide window instead of capping at 1100', (tester) async {
    tester.view.physicalSize = const Size(1750, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(_FakeRepo()));
    await tester.pumpAndSettle();

    final table = tester.getRect(find.byType(DataTable).first);
    expect(table.width, greaterThan(1400),
        reason: 'table must span the pane, not stop at the old 1100 cap');

    // Every column header is inside the viewport — nothing clipped off-screen.
    for (final h in ['Task', 'Node', 'Hours/mo', 'Owner', 'Cadence']) {
      expect(tester.getRect(find.text(h)).right, lessThan(1750),
          reason: '$h header must be visible without scrolling');
    }
  });

  testWidgets('a long responsibility name is clamped, not allowed to set table width',
      (tester) async {
    tester.view.physicalSize = const Size(1750, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(_FakeRepo()));
    await tester.pumpAndSettle();

    final nameCell = tester.widget<Text>(find.text(_task.name));
    expect(nameCell.maxLines, 2);
    expect(nameCell.overflow, TextOverflow.ellipsis);
  });

  testWidgets('cancelling with pending edits asks before discarding', (tester) async {
    await tester.pumpWidget(_host(_FakeRepo()));
    await _enterCostMode(tester);

    await tester.enterText(find.byKey(const ValueKey('times-t1-manual')), '20');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Save 1'), findsOneWidget);
  });

  testWidgets('typing a direct Hours figure computes and saves it', (tester) async {
    final repo = _FakeRepo();
    await tester.pumpWidget(_host(repo));
    await _enterCostMode(tester);

    await tester.enterText(find.byKey(const ValueKey('hours-t1')), '30');
    await tester.pumpAndSettle();

    expect(find.text('30.0'), findsOneWidget); // live hours
    await tester.tap(find.text('Save 1'));
    await tester.pumpAndSettle();

    final patch = repo.calls.single['t1']!;
    expect(patch['hours_per_month'], 30);
    expect(patch['driver_id'], isNull);
    expect(patch['times_manual'], isNull);
  });
}
