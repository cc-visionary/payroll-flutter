import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

  /// The library KPI the pane asked to be created for an inline definition,
  /// as it would land in `kpis` — this is where the whole measurable
  /// definition either survives or is silently reduced to a bare COUNT.
  Kpi? createdLibraryKpi;
  bool? createdWithDefinition;

  @override
  Future<void> saveRoleScorecardKpis(
    String roleScorecardId,
    String companyId,
    List<KpiLinkInput> links,
  ) async {
    captured = links;
  }

  @override
  Future<Kpi> saveLibraryKpi({
    String? id,
    required String companyId,
    required String name,
    String? category,
    String? description,
    String? measurementUnit,
    String valueType = 'COUNT',
    String? numeratorLabel,
    String? numeratorSource,
    String? denominatorLabel,
    String? denominatorSource,
    String? unit,
    String cadence = 'WEEKLY',
    String? proofType,
    bool writeDefinition = false,
  }) async {
    createdWithDefinition = writeDefinition;
    return createdLibraryKpi = Kpi(
      id: id ?? 'lib-created',
      companyId: companyId,
      name: name,
      category: category,
      description: description,
      measurementUnit: measurementUnit,
      valueType: valueType,
      numeratorLabel: numeratorLabel,
      numeratorSource: numeratorSource,
      denominatorLabel: denominatorLabel,
      denominatorSource: denominatorSource,
      unit: unit,
      cadence: cadence,
      proofType: proofType,
    );
  }
}

/// The REAL [RoleScorecardRepository], pointed at a recording HTTP client, so
/// a pane-level test can assert on the row that actually lands in
/// `role_scorecard_kpis` rather than only on the [KpiLinkInput] the pane
/// composed.
///
/// Both halves are needed here, and neither alone would have caught the
/// regression this exists for: the pane faithfully forwarded a legacy link's
/// free-text target, `goalColumns` faithfully derived `target` from the goal,
/// and the data loss happened in the seam between them — a goal-less link
/// whose owner-caller supplied free text got a NULL target written over it.
class _WireRepository extends RoleScorecardRepository {
  _WireRepository(super.client);

  List<KpiLinkInput>? captured;

  @override
  Future<void> saveRoleScorecardKpis(
    String roleScorecardId,
    String companyId,
    List<KpiLinkInput> links,
  ) async {
    captured = links;
    await super.saveRoleScorecardKpis(roleScorecardId, companyId, links);
  }
}

/// A [_WireRepository], the `role_scorecard_kpis` rows its upserts sent, and
/// the `?columns=` list attached to each of those upsert POSTs.
///
/// The columns list matters as much as the rows: Postgrest sends the UNION of
/// every row's keys there, and PostgREST treats that union as the statement's
/// column set — so a key one row omitted is still written (as NULL) if
/// another row in the same batch carried it. `saveRoleScorecardKpis` splits
/// into homogeneous batches for exactly that reason.
({_WireRepository repo, List<Map> rows, List<String> upsertColumns})
wiredRepository() {
  final rows = <Map>[];
  final upsertColumns = <String>[];
  final mock = MockClient((request) async {
    if (request.method == 'POST' &&
        request.url.path.endsWith('/role_scorecard_kpis') &&
        request.body.isNotEmpty) {
      rows.addAll((jsonDecode(request.body) as List).cast<Map>());
      upsertColumns.add(request.url.queryParameters['columns'] ?? '');
    }
    return http.Response('[]', 200, request: request);
  });
  final client = SupabaseClient(
    'https://stub.supabase.co',
    'stub-anon-key',
    httpClient: mock,
    // Without this the GoTrue refresh timer outlives the widget test and
    // trips flutter_test's "Timer still pending" invariant.
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  return (
    repo: _WireRepository(client),
    rows: rows,
    upsertColumns: upsertColumns,
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initSupabaseStub();
  });

  Future<void> pump(
    WidgetTester tester,
    List<RoleKpi> kpis, {
    RoleScorecardRepository? repo,
    List<Kpi> library = const [],
    // Defaults to mirroring `library` — most tests don't care about the
    // active/all distinction. Pass a wider list explicitly to exercise
    // name-resolution against a deactivated KPI that must NOT appear in
    // the suggestion list (`library`) but must still resolve by exact name.
    List<Kpi>? allLibrary,
  }) async {
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roleKpisProvider('card-1').overrideWith((ref) async => kpis),
          kpiLibraryProvider.overrideWith((ref) async => library),
          kpiLibraryAllProvider.overrideWith(
            (ref) async => allLibrary ?? library,
          ),
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

  testWidgets(
    'says which half is missing, not always "set a goal"',
    (tester) async {
      // A goal IS set here; what is missing is the library definition. The
      // blanket "set a goal" sent the manager to re-do the one thing they
      // had already done, on the wrong screen.
      await pump(
        tester,
        const [
          RoleKpi(
            kpiId: 'k1',
            name: 'Return Rate',
            goal: KpiGoal(direction: GoalDirection.lte, value: 3),
            unit: '%',
            cadence: 'WEEKLY',
          ),
        ],
        library: const [
          Kpi(
            id: 'k1',
            companyId: 'co-1',
            name: 'Return Rate',
            unit: '%',
            // No numerator: the KPI says nothing about what is counted.
          ),
        ],
      );
      expect(find.textContaining('not measurable yet'), findsWidgets);
      expect(find.textContaining('what is counted'), findsWidgets);
      expect(find.textContaining('KPI Library'), findsWidgets);
      expect(find.textContaining('set a goal'), findsNothing);
    },
  );

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
      // The library row is created up front now (see the RATIO test below),
      // so the link references it by id instead of being resolved by name
      // server-side — but the cadence must still be the one the manager
      // picked, never the form's bare WEEKLY default.
      expect(link.kpiId, 'lib-created');
      expect(link.cadence, 'MONTHLY');
      expect(repo.createdLibraryKpi?.cadence, 'MONTHLY');
    },
  );

  testWidgets(
    'defining a RATIO inline creates the library row with its whole '
    'definition, not a bare COUNT with no numerator',
    (tester) async {
      // The inline-define path is half of what "Add KPI" offers. It captured
      // valueType/numerator/denominator/sources from KpiDefinitionForm and
      // then dropped every one of them, because KpiLinkInput had nowhere to
      // put them and saveRoleScorecardKpis constructed the new Kpi from
      // name/unit/cadence alone. The library row was inserted as
      // value_type = 'COUNT' with a null numerator, so the KPI read "not
      // measurable yet" forever and could never join anyone's tracked set.
      final repo = _CapturingRepository();
      await pump(tester, const [], repo: repo);

      await tester.tap(find.widgetWithText(TextButton, 'Add KPI'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Return Rate');
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<String>, 'COUNT'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('RATIO').last);
      await tester.pumpAndSettle();

      Future<void> fill(String label, String text) async {
        await tester.enterText(find.widgetWithText(TextFormField, label), text);
        await tester.pumpAndSettle();
      }

      await fill('What is counted', 'Returns');
      await fill('Source', 'BigSeller');
      await fill('Counted against', 'Orders');
      await fill('Denominator source', 'Temu');
      await fill('Unit', '%');

      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      final created = repo.createdLibraryKpi;
      expect(created, isNotNull, reason: 'the library row must be created');
      expect(
        repo.createdWithDefinition,
        isTrue,
        reason:
            'without writeDefinition the eight definition columns are not '
            'sent at all — saveLibraryKpi says so in its own doc comment',
      );
      expect(created!.name, 'Return Rate');
      expect(created.valueType, 'RATIO');
      expect(created.numeratorLabel, 'Returns');
      expect(created.numeratorSource, 'BigSeller');
      expect(created.denominatorLabel, 'Orders');
      expect(created.denominatorSource, 'Temu');
      expect(created.unit, '%');

      // And the row now on the pane links to that library id, so the goal it
      // gets is attached to the defined KPI rather than to a name.
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(repo.captured!.single.kpiId, 'lib-created');
    },
  );

  testWidgets(
    'this pane owns the goal columns — its saves carry writeGoal',
    (tester) async {
      // Without this the workbench could set a goal but never clear one: the
      // repository leaves the goal columns alone for a caller with no
      // opinion (see KpiLinkInput.writeGoal).
      final repo = _CapturingRepository();
      await pump(tester, const [
        RoleKpi(kpiId: 'k1', name: 'Return Rate', cadence: 'WEEKLY'),
      ], repo: repo);

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(repo.captured!.single.writeGoal, isTrue);
    },
  );

  testWidgets(
    'setting a goal on one KPI leaves a sibling legacy KPI\'s typed target '
    'intact',
    (tester) async {
      // The exact live action that destroyed data: a legacy card carries
      // KPIs with typed prose targets, HR opens the workbench and sets a
      // structured goal on ONE of them, then presses Save. This pane saves
      // the whole set in one call with writeGoal on every link, so the
      // untouched links rode along and had their `target` written to NULL.
      // That column is the ONLY copy of the prose, and it is what
      // role_card_pdf.dart and the employment contract's Annex A print —
      // silent, irreversible, and (because "Consistently high quality" is
      // unparseable) with no `Suggested:` prompt to warn the manager.
      final wired = wiredRepository();
      await pump(tester, const [
        RoleKpi(
          kpiId: 'k1',
          name: 'Return Rate',
          target: '≤ 3%',
          goal: KpiGoal(direction: GoalDirection.lte, value: 3),
          unit: '%',
          cadence: 'WEEKLY',
        ),
        RoleKpi(
          kpiId: 'k2',
          name: 'Setup Accuracy',
          target: 'Consistently high quality',
          frequency: 'Weekly',
          cadence: 'WEEKLY',
        ),
      ], repo: wired.repo);

      // Tighten the first KPI's goal from 3 to 2 — the Value field of the
      // first row (each row's other TextFormField, "To", only exists for a
      // BETWEEN goal).
      await tester.enterText(find.byType(TextFormField).first, '2');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      // Both links own their goal columns, so they share ONE homogeneous
      // upsert batch — see saveRoleScorecardKpis step 3 on why shapes cannot
      // mix. Now that a goal-less owned row carries a non-null `target`, that
      // batch's `?columns=` union has to be exactly what both rows already
      // sent: goalColumns emits all four keys whether or not there is a goal,
      // so adding the fallback text changes a VALUE, never the key set.
      expect(
        wired.upsertColumns,
        hasLength(1),
        reason: 'two owned rows are one shape and must not be split',
      );
      for (final key in [
        'target',
        'goal_direction',
        'goal_value',
        'goal_value_max',
      ]) {
        expect(
          wired.upsertColumns.single.contains(key),
          isTrue,
          reason:
              '$key is written by every row in an owned batch, so it belongs '
              'in the union — an owned row must never rely on omission',
        );
      }
      expect(wired.rows, hasLength(2));
      final edited = wired.rows.singleWhere((r) => r['kpi_id'] == 'k1');
      final untouched = wired.rows.singleWhere((r) => r['kpi_id'] == 'k2');

      expect(edited['target'], '≤ 2%', reason: 'the edit itself must land');
      expect(edited['goal_direction'], 'LTE');
      expect(edited['goal_value'], 2);

      expect(
        untouched['target'],
        'Consistently high quality',
        reason:
            'this KPI was never touched — its typed target is the only copy '
            'the role-card PDF and contract Annex A have',
      );
      expect(untouched['goal_direction'], isNull);
      expect(untouched['goal_value'], isNull);
    },
  );

  testWidgets(
    'clearing a goal the workbench authored clears the derived target too, '
    'rather than resurrecting the text it replaced',
    (tester) async {
      // The other side of the same coin, and the reason the pane — not the
      // repository — has to decide which links get free text. A link that
      // ARRIVED with a goal has a `target` that was derived FROM that goal
      // (`≤ 3%` here). Forwarding that derived text back on a save that
      // clears the goal would leave the card printing a bar nobody holds.
      final wired = wiredRepository();
      await pump(tester, const [
        RoleKpi(
          kpiId: 'k1',
          name: 'Return Rate',
          target: '≤ 3%',
          goal: KpiGoal(direction: GoalDirection.lte, value: 3),
          unit: '%',
          cadence: 'WEEKLY',
        ),
      ], repo: wired.repo);

      await tester.tap(find.byType(DropdownButtonFormField<GoalDirection?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('(none)').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(wired.rows, hasLength(1));
      final row = wired.rows.single;
      expect(row['goal_direction'], isNull);
      expect(
        row['target'],
        isNull,
        reason:
            'the derived text goes with the goal it was derived from — the '
            'pane must not send it back as if it were legacy prose',
      );
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

  testWidgets(
    'typing a deactivated KPI\'s exact name still resolves to it, not a '
    'new KPI with a default cadence',
    (tester) async {
      // kpiLibraryProvider (the Autocomplete's suggestion source) only ever
      // lists active KPIs, so a retired one is correctly absent from
      // suggestions — a manager should not be offered a retired measurable.
      // But upsertKpi resolves a typed name against EVERY row regardless of
      // is_active and silently reactivates a match (saveLibraryKpi's own doc
      // comment describes this as supported behaviour). Resolving the typed
      // name only against the active list, as `_matchByName` originally did,
      // reopens exactly the side door round 1 closed: the link would be
      // saved with KpiDefinitionForm's default cadence instead of this
      // KPI's real one.
      final repo = _CapturingRepository();
      const retired = Kpi(
        id: 'lib-retired',
        companyId: 'co-1',
        name: 'Legacy Return Rate',
        unit: '%',
        cadence: 'QUARTERLY',
        isActive: false,
        valueType: 'RATIO',
        numeratorLabel: 'Returns',
        numeratorSource: 'BigSeller',
        denominatorLabel: 'Orders',
        denominatorSource: 'BigSeller',
      );
      await pump(
        tester,
        const [],
        repo: repo,
        library: const [], // absent from suggestions — it is retired
        allLibrary: const [retired],
      );

      await tester.tap(find.widgetWithText(TextButton, 'Add KPI'));
      await tester.pumpAndSettle();
      // The Autocomplete offers nothing (retired KPIs aren't suggested), so
      // there is no row to click — type the full name and go straight to Add.
      await tester.enterText(
        find.byType(TextFormField).first,
        'Legacy Return Rate',
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
        'lib-retired',
        reason: 'must resolve to the existing (retired) row, not create one',
      );
      expect(
        link.cadence,
        'QUARTERLY',
        reason: "must carry the retired KPI's real cadence, not 'WEEKLY'",
      );
    },
  );
}
