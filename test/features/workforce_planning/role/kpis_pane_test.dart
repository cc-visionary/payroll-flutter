import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/kpi.dart';
import 'package:payroll_flutter/data/models/kpi_goal.dart';
import 'package:payroll_flutter/data/models/role_kpi.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';
import 'package:payroll_flutter/features/workforce_planning/role/kpis_pane.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../support/supabase_stub.dart';

/// Captures the links a save actually sends, instead of hitting the network —
/// these tests care about what `KpisPane` composes into `KpiLinkInput`, not
/// about `saveRoleScorecardKpis`'s own persistence logic (that is covered by
/// `role_scorecard_kpi_links_test.dart`).
class _CapturingRepository extends RoleScorecardRepository {
  _CapturingRepository() : super(Supabase.instance.client);

  List<KpiLinkInput>? captured;

  @override
  Future<void> saveRoleScorecardKpis(
    String roleScorecardId,
    String companyId,
    List<KpiLinkInput> links,
  ) async {
    captured = links;
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initSupabaseStub();
  });

  Future<void> pump(
    WidgetTester tester,
    List<RoleKpi> kpis, {
    _CapturingRepository? repo,
    List<Kpi> library = const [],
  }) async {
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roleKpisProvider('card-1').overrideWith((ref) async => kpis),
          kpiLibraryProvider.overrideWith((ref) async => library),
          if (repo != null)
            roleScorecardRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: KpisPane(cardId: 'card-1', companyId: 'co-1'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders a structured goal with its unit', (tester) async {
    await pump(tester, const [
      RoleKpi(
        kpiId: 'k1',
        name: 'Return Rate',
        goal: KpiGoal(direction: GoalDirection.lte, value: 3),
        unit: '%',
        cadence: 'WEEKLY',
      ),
    ]);
    expect(find.text('Return Rate'), findsOneWidget);
    expect(find.textContaining('≤ 3%'), findsWidgets);
  });

  testWidgets('flags a link with no goal as not measurable', (tester) async {
    await pump(tester, const [
      RoleKpi(kpiId: 'k1', name: 'Setup Accuracy', target: 'At least 98%'),
    ]);
    expect(find.textContaining('not measurable'), findsWidgets);
  });

  testWidgets('offers the legacy target as a suggestion, not a fact', (
    tester,
  ) async {
    // "At least 98%" is readable; the manager still confirms it, because a
    // bare "98%" is not and we must never guess a direction.
    await pump(tester, const [
      RoleKpi(kpiId: 'k1', name: 'Setup Accuracy', target: 'At least 98%'),
    ]);
    expect(find.textContaining('98'), findsWidgets);
    expect(find.textContaining('Suggested'), findsWidgets);
  });

  testWidgets(
    'tapping "Use suggestion" actually shows the value in the field, not '
    'just in the derived Goal text',
    (tester) async {
      // The Value/To fields are the row's own TextFormFields — a stable row
      // key across the mutation means TextFormField.initialValue is never
      // re-read, so writing a plain string onto the draft used to update the
      // computed "Goal:" line while leaving the editable field showing
      // nothing (empty), asking the manager to confirm a number they could
      // not see.
      await pump(tester, const [
        RoleKpi(kpiId: 'k1', name: 'Setup Accuracy', target: 'At least 98%'),
      ]);

      final valueFieldBefore = tester.widget<TextFormField>(
        find.byType(TextFormField).last,
      );
      expect(valueFieldBefore.controller?.text ?? '', isEmpty);

      await tester.tap(find.widgetWithText(TextButton, 'Use suggestion'));
      await tester.pumpAndSettle();

      final valueFieldAfter = tester.widget<TextFormField>(
        find.byType(TextFormField).last,
      );
      // parseLegacyTarget's KpiGoal.value is a double (98.0), and the
      // suggestion is written verbatim via `.toString()` — the field must
      // show exactly what was accepted, not a value the test guesses.
      expect(valueFieldAfter.controller?.text, '98.0');
    },
  );

  testWidgets('says nothing is measured yet when the role has no KPIs', (
    tester,
  ) async {
    await pump(tester, const []);
    expect(find.textContaining('No KPIs'), findsOneWidget);
  });

  testWidgets(
    'saving an existing link does not silently rewrite its cadence to '
    'Weekly',
    (tester) async {
      // Plan 1 deliberately removed saveRoleScorecardKpis's
      // `cadence ??= kpi.cadence` fallback because it did exactly this on
      // every card save. This pane is now the only caller, so its saved
      // KpiLinkInput must carry the link's real (non-Weekly) cadence.
      final repo = _CapturingRepository();
      await pump(tester, const [
        RoleKpi(
          kpiId: 'k1',
          name: 'Return Rate',
          goal: KpiGoal(direction: GoalDirection.lte, value: 3),
          unit: '%',
          cadence: 'MONTHLY',
        ),
      ], repo: repo);

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(repo.captured, isNotNull);
      expect(repo.captured!.single.cadence, 'MONTHLY');
    },
  );

  testWidgets(
    'adding an existing library KPI carries its cadence into the saved link',
    (tester) async {
      final repo = _CapturingRepository();
      await pump(
        tester,
        const [],
        repo: repo,
        library: const [
          Kpi(
            id: 'lib-1',
            companyId: 'co-1',
            name: 'On-Time Ship Rate',
            unit: '%',
            cadence: 'QUARTERLY',
            valueType: 'RATIO',
            numeratorLabel: 'On-time orders',
            numeratorSource: 'BigSeller',
            denominatorLabel: 'Orders',
            denominatorSource: 'BigSeller',
          ),
        ],
      );

      await tester.tap(find.widgetWithText(TextButton, 'Add KPI'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'On-Time Ship Rate',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('On-Time Ship Rate').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(repo.captured, isNotNull);
      expect(repo.captured!.single.kpiId, 'lib-1');
      expect(repo.captured!.single.cadence, 'QUARTERLY');
    },
  );

  testWidgets(
    "a brand-new KPI's cadence comes from the definition form the manager "
    'filled in, not a bare Weekly default hardcoded by the pane',
    (tester) async {
      // The migration's one-shot cadence backfill cannot reach a row created
      // after it ran, so a KPI defined here must carry whatever cadence the
      // manager actually picked in KpiDefinitionForm.
      final repo = _CapturingRepository();
      await pump(tester, const [], repo: repo);

      await tester.tap(find.widgetWithText(TextButton, 'Add KPI'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Brand New KPI');
      await tester.pumpAndSettle();

      // The KpiDefinitionForm should now be showing, defaulted to WEEKLY.
      // Change it away from that default so the assertion below can
      // distinguish "threaded from the form" from "always WEEKLY".
      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<String>, 'WEEKLY'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('MONTHLY').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(repo.captured, isNotNull);
      final link = repo.captured!.single;
      expect(link.kpiId, isNull, reason: 'brand-new — resolved server-side');
      expect(link.cadence, 'MONTHLY');
    },
  );

  testWidgets(
    'the resync control pulls in a change made by another screen',
    (tester) async {
      // `_captured` only clears itself after this pane's OWN save, so
      // watching `roleKpisProvider` alone is not enough — another screen
      // (e.g. the KPI Library dialog, or a different workbench tab) editing
      // the same card's KPIs would otherwise sit invisible behind the local
      // draft forever. This is the exact gap Task 4's ResponsibilitiesPane
      // was flagged for and never closed; this pane must not repeat it.
      var kpis = const [
        RoleKpi(
          kpiId: 'k1',
          name: 'Metric A',
          goal: KpiGoal(direction: GoalDirection.lte, value: 3),
          unit: '%',
          cadence: 'WEEKLY',
        ),
      ];
      tester.view.physicalSize = const Size(1400, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            roleKpisProvider('card-1').overrideWith((ref) async => kpis),
            kpiLibraryProvider.overrideWith((ref) async => const []),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: KpisPane(cardId: 'card-1', companyId: 'co-1'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Metric A'), findsOneWidget);

      // Simulate another screen changing what's stored for this card.
      kpis = const [
        RoleKpi(
          kpiId: 'k2',
          name: 'Metric B',
          goal: KpiGoal(direction: GoalDirection.gte, value: 10),
          unit: 'orders',
          cadence: 'MONTHLY',
        ),
      ];

      // Nothing was edited locally, so this must reload silently — no
      // confirmation dialog to click through for the common case.
      await tester.tap(find.byKey(const ValueKey('kpis-pane-resync')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Metric A'), findsNothing);
      expect(find.text('Metric B'), findsOneWidget);
    },
  );

  testWidgets(
    'resync asks before discarding an unsaved edit, and Cancel keeps it',
    (tester) async {
      await pump(tester, const [
        RoleKpi(
          kpiId: 'k1',
          name: 'Return Rate',
          goal: KpiGoal(direction: GoalDirection.lte, value: 3),
          unit: '%',
          cadence: 'WEEKLY',
        ),
      ]);

      // Make an unsaved edit: change the goal value away from its captured
      // baseline.
      await tester.enterText(find.byType(TextFormField).last, '5');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('kpis-pane-resync')));
      await tester.pumpAndSettle();

      expect(
        find.byType(AlertDialog),
        findsOneWidget,
        reason: 'a dirty draft must be confirmed before it is discarded',
      );

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      final valueField = tester.widget<TextFormField>(
        find.byType(TextFormField).last,
      );
      expect(
        valueField.controller?.text,
        '5',
        reason: 'cancelling the reload must leave the unsaved edit intact',
      );
    },
  );

  testWidgets(
    'confirming resync discards the unsaved edit and reloads',
    (tester) async {
      var kpis = const [
        RoleKpi(
          kpiId: 'k1',
          name: 'Return Rate',
          goal: KpiGoal(direction: GoalDirection.lte, value: 3),
          unit: '%',
          cadence: 'WEEKLY',
        ),
      ];
      tester.view.physicalSize = const Size(1400, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            roleKpisProvider('card-1').overrideWith((ref) async => kpis),
            kpiLibraryProvider.overrideWith((ref) async => const []),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: KpisPane(cardId: 'card-1', companyId: 'co-1'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).last, '5');
      await tester.pumpAndSettle();

      // Another screen also changed the server-side data in the meantime.
      kpis = const [
        RoleKpi(
          kpiId: 'k1',
          name: 'Return Rate',
          goal: KpiGoal(direction: GoalDirection.lte, value: 7),
          unit: '%',
          cadence: 'WEEKLY',
        ),
      ];

      await tester.tap(find.byKey(const ValueKey('kpis-pane-resync')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Discard and reload'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      final valueField = tester.widget<TextFormField>(
        find.byType(TextFormField).last,
      );
      expect(
        valueField.controller?.text,
        '7',
        reason: 'the unsaved "5" must be gone, replaced by the fresh server '
            'value',
      );
    },
  );

  testWidgets(
    'typing an existing KPI\'s exact name without tapping the suggestion '
    'still resolves to that KPI, not a new one defaulted to Weekly',
    (tester) async {
      // The side door: `_picked` was previously only set by `onSelected`, so
      // a manager who types the full correct name and presses Save without
      // clicking the Autocomplete row fell into the "create a new KPI"
      // branch — server-side upsertKpi then resolves the name back to this
      // SAME row, but the link's cadence had already been set to
      // KpiDefinitionForm's bare 'WEEKLY' default, silently overwriting the
      // real cadence's frequency text. Nothing on screen told the manager
      // typing was different from clicking.
      final repo = _CapturingRepository();
      await pump(
        tester,
        const [],
        repo: repo,
        library: const [
          Kpi(
            id: 'lib-1',
            companyId: 'co-1',
            name: 'On-Time Ship Rate',
            unit: '%',
            cadence: 'QUARTERLY',
            valueType: 'RATIO',
            numeratorLabel: 'On-time orders',
            numeratorSource: 'BigSeller',
            denominatorLabel: 'Orders',
            denominatorSource: 'BigSeller',
          ),
        ],
      );

      await tester.tap(find.widgetWithText(TextButton, 'Add KPI'));
      await tester.pumpAndSettle();
      // Type the exact existing name — deliberately NOT tapping the
      // Autocomplete suggestion row afterwards.
      await tester.enterText(
        find.byType(TextFormField).first,
        'On-Time Ship Rate',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(repo.captured, isNotNull);
      final link = repo.captured!.single;
      expect(
        link.kpiId,
        'lib-1',
        reason: 'must resolve to the existing library row, not create one',
      );
      expect(
        link.cadence,
        'QUARTERLY',
        reason: "must carry the KPI's real cadence, not the form's default",
      );
    },
  );
}
