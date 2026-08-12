import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/role/responsibilities_pane.dart';
import 'package:payroll_flutter/features/workforce_planning/wp_providers.dart';

import '../../../support/supabase_stub.dart';

WpTask _task({
  required String id,
  required String name,
  required String area,
  int areaSort = 0,
  int taskSort = 0,
}) => WpTask(
  id: id,
  companyId: 'co-1',
  name: name,
  roleScorecardId: 'card-1',
  responsibilityArea: area,
  areaSort: areaSort,
  taskSort: taskSort,
  timesSource: 'manual',
  minutesSource: 'manual',
  driverFactor: 1,
  isEssential: true,
  isExpectation: false,
  status: 'ACTIVE',
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initSupabaseStub();
  });

  Future<void> pump(WidgetTester tester, List<WpTask> tasks) async {
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wpTasksProvider.overrideWith((ref) async => tasks),
          wpAllTaskComputedProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ResponsibilitiesPane(cardId: 'card-1', companyId: 'co-1'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('groups by area in authored order, not alphabetically', (
    tester,
  ) async {
    // The card PDF and contract Annex A render in authored order; a pane that
    // sorted by name would show a different order than the document.
    await pump(tester, [
      _task(id: 't1', name: 'Zebra task', area: 'Setup', taskSort: 0),
      _task(id: 't2', name: 'Apple task', area: 'Setup', taskSort: 1),
      _task(id: 't3', name: 'Only one', area: 'Research', areaSort: 1),
    ]);

    final areas = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    expect(areas.indexOf('Setup'), lessThan(areas.indexOf('Research')));
    expect(areas.indexOf('Zebra task'), lessThan(areas.indexOf('Apple task')));
  });

  testWidgets('an uncosted responsibility reads as a dash, never as zero', (
    tester,
  ) async {
    // 0.0h would read as "this takes no time"; unknown and idle differ.
    await pump(tester, [_task(id: 't1', name: 'Uncosted work', area: 'Setup')]);
    expect(find.text('0.0'), findsNothing);
    expect(find.text('—'), findsWidgets);
  });

  testWidgets('shows only the card\'s own responsibilities', (tester) async {
    await pump(tester, [
      _task(id: 't1', name: 'Mine', area: 'Setup'),
      WpTask(
        id: 't9',
        companyId: 'co-1',
        name: 'Someone else\'s',
        roleScorecardId: 'card-2',
        responsibilityArea: 'Other',
        timesSource: 'manual',
        minutesSource: 'manual',
        driverFactor: 1,
        isEssential: true,
        isExpectation: false,
        status: 'ACTIVE',
      ),
    ]);
    expect(find.text('Mine'), findsOneWidget);
    expect(find.text('Someone else\'s'), findsNothing);
  });

  testWidgets('hides archived responsibilities', (tester) async {
    await pump(tester, [
      _task(id: 't1', name: 'Live work', area: 'Setup'),
      WpTask(
        id: 't2',
        companyId: 'co-1',
        name: 'Retired work',
        roleScorecardId: 'card-1',
        responsibilityArea: 'Setup',
        timesSource: 'manual',
        minutesSource: 'manual',
        driverFactor: 1,
        isEssential: true,
        isExpectation: false,
        status: 'ARCHIVED',
      ),
    ]);
    expect(find.text('Live work'), findsOneWidget);
    expect(find.text('Retired work'), findsNothing);
  });

  testWidgets(
    'the resync control pulls in a change made by another screen',
    (tester) async {
      // `_captured` only clears itself after this pane's OWN mutations (see
      // its doc comment), so watching `wpTasksProvider` alone is not enough —
      // another screen (e.g. the Tasks tab, or a different workbench tab
      // touching the same card) changing this card's tasks would otherwise
      // sit invisible behind the captured draft forever, even though the
      // pane's own hours/computed figures (not gated by `_captured`) already
      // moved on. Unlike `KpisPane`, this control never asks for
      // confirmation: every mutation here already persisted the instant its
      // dialog was confirmed, so there is nothing local this reload could
      // ever discard.
      var tasks = [_task(id: 't1', name: 'Task A', area: 'Setup')];
      tester.view.physicalSize = const Size(1400, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            wpTasksProvider.overrideWith((ref) async => tasks),
            wpAllTaskComputedProvider.overrideWith((ref) async => const []),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ResponsibilitiesPane(cardId: 'card-1', companyId: 'co-1'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Task A'), findsOneWidget);

      // Simulate another screen changing what's stored for this card.
      tasks = [_task(id: 't2', name: 'Task B', area: 'Setup')];

      await tester.tap(find.byKey(const ValueKey('resp-pane-resync')));
      await tester.pumpAndSettle();

      // No confirmation dialog for the reasons above — the reload just
      // happens.
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Task A'), findsNothing);
      expect(find.text('Task B'), findsOneWidget);
    },
  );
}
