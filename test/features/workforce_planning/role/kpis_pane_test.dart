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

      await tester.tap(find.byKey(const ValueKey('kpis-pane-resync')));
      await tester.pumpAndSettle();

      expect(find.text('Metric A'), findsNothing);
      expect(find.text('Metric B'), findsOneWidget);
    },
  );
}
