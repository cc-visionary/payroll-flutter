import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:payroll_flutter/data/models/kpi.dart';
import 'package:payroll_flutter/data/models/role_kpi.dart';
import 'package:payroll_flutter/data/models/role_outcome.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';
import 'package:payroll_flutter/features/workforce_planning/role/kpis_pane.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../support/supabase_stub.dart';

/// Covers Task 5: a role's KPI names the outcome it proves
/// (`role_scorecard_kpis.outcome_id`). Two seams, two techniques:
///
/// * The PANE — does picking an outcome in `KpisPane`'s selector actually
///   land on the `KpiLinkInput` it sends? Covered with a capturing fake
///   repository, mirroring `kpis_pane_test.dart`'s `_CapturingRepository`.
/// * The REPOSITORY — does `saveRoleScorecardKpis` actually persist that
///   value, and does a link with no outcome leave a SIBLING link's stored
///   outcome alone in the same call? Covered against the REAL repository
///   wired to a recording `MockClient`, because this is exactly the class of
///   bug `saveRoleScorecardKpis`'s doc comment warns about: PostgREST sends
///   the union of every row's keys as `?columns=`, and silently NULLs any key
///   a row omitted. A fake repository can't reproduce that; only the real
///   upsert body can.
/// The one `DropdownButtonFormField<String?>` in `KpisPane`'s row — the
/// outcome picker. Not found by key: the row's key is derived from
/// `identityHashCode(draft)` (see `_KpisPaneState._buildRow`), which a test
/// cannot predict. `find.byType` alone does not reliably match a generic
/// widget's concrete instantiation, so this matches by `is` instead.
Finder _outcomePickerFinder() =>
    find.byWidgetPredicate((w) => w is DropdownButtonFormField<String?>);

RoleOutcome _outcome({required String id, required String area, required String text}) =>
    RoleOutcome(
      id: id,
      companyId: 'co-1',
      roleScorecardId: 'card-1',
      responsibilityArea: area,
      text: text,
    );

class _CapturingRepository extends RoleScorecardRepository {
  _CapturingRepository() : super(Supabase.instance.client);

  List<KpiLinkInput>? saved;

  @override
  Future<void> saveRoleScorecardKpis(
    String roleScorecardId,
    String companyId,
    List<KpiLinkInput> links,
  ) async {
    saved = links;
  }
}

/// A real [RoleScorecardRepository] pointed at a recording HTTP client — see
/// `kpis_pane_test.dart`'s `wiredRepository()`, duplicated here (it is
/// private to that file) because this test needs the same technique: the
/// question is what actually reached `role_scorecard_kpis`, not what the pane
/// composed.
({RoleScorecardRepository repo, List<Map> rows, List<String> upsertColumns})
_wiredRepository() {
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
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  return (
    repo: RoleScorecardRepository(client),
    rows: rows,
    upsertColumns: upsertColumns,
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initSupabaseStub();
  });

  group('KpisPane outcome picker', () {
    Future<void> pump(
      WidgetTester tester, {
      required RoleScorecardRepository repo,
      List<RoleKpi> kpis = const [],
      List<RoleOutcome> outcomes = const [],
    }) async {
      tester.view.physicalSize = const Size(1400, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            roleKpisProvider('card-1').overrideWith((ref) async => kpis),
            roleOutcomesProvider(
              'card-1',
            ).overrideWith((ref) async => outcomes),
            kpiLibraryProvider.overrideWith((ref) async => const []),
            kpiLibraryAllProvider.overrideWith((ref) async => const []),
            roleScorecardRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
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

    testWidgets('picking an outcome saves its id on the link', (
      tester,
    ) async {
      final repo = _CapturingRepository();
      await pump(
        tester,
        repo: repo,
        kpis: const [
          RoleKpi(
            kpiId: 'k1',
            name: 'Return Rate',
            unit: '%',
            cadence: 'WEEKLY',
          ),
        ],
        outcomes: [
          _outcome(
            id: 'o1',
            area: 'Fulfillment',
            text: 'Customers receive the correct product',
          ),
        ],
      );

      // The row's own widget key is derived from `identityHashCode(draft)`
      // (see `_KpisPaneState._buildRow`), which is not predictable from the
      // test — a type-based predicate finds the one outcome picker in the
      // tree without needing to guess it.
      await tester.tap(_outcomePickerFinder());
      await tester.pumpAndSettle();
      // Menu-item text is indented ("  Customers receive…") to read as
      // grouped under its area header, so an exact `find.text` match would
      // miss it.
      await tester
          .tap(find.textContaining('Customers receive the correct product').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(repo.saved, isNotNull);
      // Assert the VALUE, not just that the key exists — a buggy write can
      // emit `outcomeId` unconditionally as null and still pass a
      // presence-only check.
      expect(repo.saved!.single.outcomeId, 'o1');
    });

    testWidgets(
      'a link that already carries an outcome offers "— none —" to clear it',
      (tester) async {
        final repo = _CapturingRepository();
        await pump(
          tester,
          repo: repo,
          kpis: const [
            RoleKpi(
              kpiId: 'k1',
              name: 'Return Rate',
              unit: '%',
              cadence: 'WEEKLY',
              outcomeId: 'o1',
            ),
          ],
          outcomes: [
            _outcome(
              id: 'o1',
              area: 'Fulfillment',
              text: 'Customers receive the correct product',
            ),
          ],
        );

        await tester.tap(_outcomePickerFinder());
        await tester.pumpAndSettle();
        await tester.tap(find.text('— none —').last);
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();

        expect(repo.saved, isNotNull);
        expect(repo.saved!.single.outcomeId, isNull);
      },
    );
  });

  group('saveRoleScorecardKpis persists outcome_id', () {
    test('writes the outcome_id value, not just the key', () async {
      final w = _wiredRepository();
      const link = KpiLinkInput(
        kpiId: 'k1',
        name: 'Return Rate',
        target: '',
        frequency: '',
        outcomeId: 'o1',
        writeGoal: true,
      );
      await w.repo.saveRoleScorecardKpis('card-1', 'co-1', [link]);

      expect(w.rows, hasLength(1));
      expect(w.rows.single['outcome_id'], 'o1');
    });

    test(
      'a link with no outcome does not disturb a sibling link\'s stored '
      'outcome in the same call',
      () async {
        final w = _wiredRepository();
        const withOutcome = KpiLinkInput(
          kpiId: 'k1',
          name: 'Return Rate',
          target: '',
          frequency: '',
          outcomeId: 'o1',
          writeGoal: true,
        );
        const withoutOutcome = KpiLinkInput(
          kpiId: 'k2',
          name: 'Setup Accuracy',
          target: '',
          frequency: '',
          writeGoal: true,
        );

        await w.repo.saveRoleScorecardKpis('card-1', 'co-1', [
          withOutcome,
          withoutOutcome,
        ]);

        final rowsByKpi = {for (final r in w.rows) r['kpi_id']: r};
        expect(rowsByKpi['k1']!['outcome_id'], 'o1');
        expect(rowsByKpi['k2']!['outcome_id'], isNull);
      },
    );
  });
}
