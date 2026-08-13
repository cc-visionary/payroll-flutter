import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/role_outcome.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';
import 'package:payroll_flutter/features/workforce_planning/role/outcomes_pane.dart';
import 'package:payroll_flutter/features/workforce_planning/wp_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

RoleOutcome _outcome({
  required String id,
  required String area,
  required String text,
  int sortOrder = 0,
}) => RoleOutcome(
  id: id,
  companyId: 'co-1',
  roleScorecardId: 'card-1',
  responsibilityArea: area,
  text: text,
  sortOrder: sortOrder,
);

/// Captures what a save actually sends and drops, instead of hitting the
/// network — mirrors `kpis_pane_test.dart`'s `_CapturingRepository`.
class _CapturingRepository extends RoleScorecardRepository {
  _CapturingRepository() : super(Supabase.instance.client);

  List<RoleOutcome>? savedOutcomes;
  List<String> deletedIds = [];

  @override
  Future<void> saveOutcomes(String roleId, List<RoleOutcome> outcomes) async {
    savedOutcomes = outcomes;
  }

  @override
  Future<void> deleteOutcome(String id) async {
    deletedIds.add(id);
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initSupabaseStub();
  });

  Future<void> pump(
    WidgetTester tester, {
    List<WpTask> tasks = const [],
    List<RoleOutcome> outcomes = const [],
    _CapturingRepository? repo,
  }) async {
    tester.view.physicalSize = const Size(1400, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wpTasksProvider.overrideWith((ref) async => tasks),
          roleOutcomesProvider('card-1').overrideWith((ref) async => outcomes),
          if (repo != null)
            roleScorecardRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OutcomesPane(cardId: 'card-1', companyId: 'co-1'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('each accountability area renders as a heading, in authored order', (
    tester,
  ) async {
    await pump(
      tester,
      tasks: [
        _task(id: 't1', name: 'Pack orders', area: 'Fulfillment', areaSort: 0),
        _task(id: 't2', name: 'Investigate', area: 'Research', areaSort: 1),
      ],
    );

    final fulfillmentY = tester.getTopLeft(find.text('Fulfillment')).dy;
    final researchY = tester.getTopLeft(find.text('Research')).dy;
    expect(fulfillmentY, lessThan(researchY));
  });

  testWidgets('an area with no outcomes shows the empty-state line, not blank space', (
    tester,
  ) async {
    await pump(
      tester,
      tasks: [_task(id: 't1', name: 'Pack orders', area: 'Fulfillment')],
    );

    expect(
      find.text('No outcomes written for this area yet.'),
      findsOneWidget,
    );
  });

  testWidgets("an outcome's text renders under its own area and not another", (
    tester,
  ) async {
    await pump(
      tester,
      tasks: [
        _task(id: 't1', name: 'Pack orders', area: 'Fulfillment', areaSort: 0),
        _task(id: 't2', name: 'Investigate', area: 'Research', areaSort: 1),
      ],
      outcomes: [
        _outcome(
          id: 'o1',
          area: 'Fulfillment',
          text: 'Customers receive the correct product',
        ),
        _outcome(id: 'o2', area: 'Research', text: 'Findings are actionable'),
      ],
    );

    final fulfillmentY = tester.getTopLeft(find.text('Fulfillment')).dy;
    final fulfillmentOutcomeY = tester
        .getTopLeft(find.text('Customers receive the correct product'))
        .dy;
    final researchY = tester.getTopLeft(find.text('Research')).dy;
    final researchOutcomeY = tester
        .getTopLeft(find.text('Findings are actionable'))
        .dy;

    expect(fulfillmentY, lessThan(fulfillmentOutcomeY));
    expect(fulfillmentOutcomeY, lessThan(researchY));
    expect(researchY, lessThan(researchOutcomeY));
  });

  testWidgets('adding an outcome to one area and saving calls saveOutcomes with that area\'s name', (
    tester,
  ) async {
    final repo = _CapturingRepository();
    await pump(
      tester,
      tasks: [_task(id: 't1', name: 'Pack orders', area: 'Fulfillment')],
      repo: repo,
    );

    await tester.tap(find.widgetWithText(TextButton, 'Add outcome'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextFormField).last,
      'Orders ship complete and undamaged',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repo.savedOutcomes, isNotNull);
    expect(repo.savedOutcomes, hasLength(1));
    expect(repo.savedOutcomes!.single.responsibilityArea, 'Fulfillment');
    expect(
      repo.savedOutcomes!.single.text,
      'Orders ship complete and undamaged',
    );
  });

  testWidgets('removing the middle outcome of three drops that one, not the last', (
    tester,
  ) async {
    // The card editor shipped this bug for months (fixed in 6ae6c9b): unkeyed
    // fields are matched positionally, so the surviving rows kept the text of
    // the rows before them and the LAST row appeared to vanish.
    await pump(
      tester,
      tasks: [_task(id: 't1', name: 'Pack orders', area: 'Fulfillment')],
      outcomes: [
        _outcome(id: 'o1', area: 'Fulfillment', text: 'First outcome'),
        _outcome(id: 'o2', area: 'Fulfillment', text: 'Second outcome'),
        _outcome(id: 'o3', area: 'Fulfillment', text: 'Third outcome'),
      ],
    );

    expect(find.byType(TextFormField), findsNWidgets(3));
    await tester.tap(
      find.widgetWithIcon(IconButton, Icons.delete_outline).at(1),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('First outcome'), findsOneWidget);
    expect(find.text('Second outcome'), findsNothing);
    expect(find.text('Third outcome'), findsOneWidget);
  });

  testWidgets(
    'an outcome whose area no longer exists on the role appears under an '
    'orphaned heading, not silently dropped',
    (tester) async {
      await pump(
        tester,
        tasks: [_task(id: 't1', name: 'Pack orders', area: 'Fulfillment')],
        outcomes: [
          _outcome(
            id: 'o1',
            area: 'Old Area Name',
            text: 'A stranded outcome',
          ),
        ],
      );

      expect(find.text('A stranded outcome'), findsOneWidget);
      expect(find.textContaining('Old Area Name'), findsOneWidget);
      // Not grouped under a current area it does not belong to.
      expect(
        find.text('No outcomes written for this area yet.'),
        findsOneWidget,
      );
    },
  );
}
