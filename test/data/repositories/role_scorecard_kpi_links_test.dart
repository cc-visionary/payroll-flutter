import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:payroll_flutter/data/models/kpi.dart';
import 'package:payroll_flutter/data/models/kpi_goal.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Covers the composition inside [RoleScorecardRepository.saveRoleScorecardKpis]
/// that unit tests on [Kpi]/[KpiGoal] alone cannot reach: the spread of
/// [goalColumns] into the upsert row, [KpiLinkInput.cadence] threading through
/// the `resolved` records, and its interaction with dedupe/`sort_order`. That
/// composition is what writes the `target`/`frequency` text rendered into
/// role-card PDFs and signed employment contracts — a regression here would
/// not be caught by `goalColumns`'s own tests, which never touch the
/// repository.
///
/// A recording [MockClient] stands in for Postgrest's HTTP transport: no
/// `Supabase.initialize` and no live server, just an in-memory record of every
/// request the repository issued.
class _RecordedRequest {
  final String method;
  final Uri url;
  final Object? body;
  _RecordedRequest(this.method, this.url, this.body);
  String get path => url.path;

  /// The `?columns=` list Postgrest attaches to every BULK insert/upsert (the
  /// union of every row's keys — see `PostgrestQueryBuilder`'s
  /// `_setColumnsSearchParam` in postgrest 2.6.0). PostgREST treats that list
  /// as the statement's full column set: a row that omitted one of them is
  /// inserted with NULL, and `resolution=merge-duplicates` expands to
  /// `on conflict do update set <every listed column> = excluded.<column>`.
  /// So "the key is absent from my row map" only means "the column is left
  /// alone" when the column is absent from THIS list too.
  String get columnsParam => url.queryParameters['columns'] ?? '';
}

void main() {
  test(
    'saveRoleScorecardKpis derives target/frequency from the goal, not stale free text',
    () async {
      final recorded = <_RecordedRequest>[];
      final mock = MockClient((request) async {
        Object? body;
        if (request.body.isNotEmpty) {
          try {
            body = jsonDecode(request.body);
          } catch (_) {
            body = request.body;
          }
        }
        recorded.add(_RecordedRequest(request.method, request.url, body));
        return http.Response('[]', 200, request: request);
      });

      final client = SupabaseClient(
        'https://stub.supabase.co',
        'stub-anon-key',
        httpClient: mock,
        // Prevent the GoTrue auto-refresh periodic timer, which otherwise
        // leaks past the test and trips flutter_test's
        // "Timer still pending" invariant.
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final repo = RoleScorecardRepository(client);

      const goalLink = KpiLinkInput(
        kpiId: 'kpi-1',
        name: 'Return Rate',
        // Deliberately stale free text: the goal below must win over both.
        target: 'At least 98%',
        frequency: 'Monthly',
        goal: KpiGoal(direction: GoalDirection.lte, value: 3),
        unit: '%',
        cadence: 'WEEKLY',
      );
      const freeTextLink = KpiLinkInput(
        kpiId: 'kpi-2',
        name: 'Setup Accuracy',
        target: 'Consistently high quality',
        frequency: 'Quarterly',
        // No goal, no cadence — a legacy link that never got upgraded.
      );

      await repo.saveRoleScorecardKpis('card-1', 'co-1', [
        goalLink,
        freeTextLink,
      ]);

      final upsertRequests = recorded
          .where(
            (r) => r.method == 'POST' && r.path.endsWith('/role_scorecard_kpis'),
          )
          .toList();
      // One POST per row SHAPE, not per save: a goal-carrying row and a
      // goal-less one cannot share a batch (see _RecordedRequest.columnsParam
      // and saveRoleScorecardKpis's step 3), so collect the rows across
      // however many batches went out.
      final rows = upsertRequests
          .expand((r) => (r.body as List).cast<Map>())
          .toList();
      expect(rows, hasLength(2));

      final goalRow = rows.singleWhere((r) => r['kpi_id'] == 'kpi-1');
      expect(goalRow['target'], '≤ 3%');
      expect(goalRow['goal_direction'], 'LTE');
      expect(goalRow['goal_value'], 3);
      expect(goalRow['goal_value_max'], isNull);
      expect(goalRow['frequency'], 'Weekly');
      expect(goalRow['sort_order'], 0);

      final freeTextRow = rows.singleWhere((r) => r['kpi_id'] == 'kpi-2');
      expect(freeTextRow['target'], 'Consistently high quality');
      expect(freeTextRow['frequency'], 'Quarterly');
      expect(freeTextRow['goal_direction'], isNull);
      expect(freeTextRow['goal_value'], isNull);
      expect(freeTextRow['goal_value_max'], isNull);
      expect(freeTextRow['sort_order'], 1);
    },
  );

  test(
    'a name-matched existing KPI (kpiId null) does not overwrite the '
    'link\'s typed frequency with the library row\'s cadence',
    () async {
      // Reproduces a bug in the old (now-deleted) responsibility-card
      // editor: its `_KpiDraft` never carried the library `kpiId` back from
      // an existing card, so every KPI on an existing card round-tripped
      // through saveRoleScorecardKpis with kpiId == null, cadence == null
      // and goal == null — only the name-match branch of upsertKpi ties it
      // back to its library row.
      final recorded = <_RecordedRequest>[];
      final mock = MockClient((request) async {
        Object? body;
        if (request.body.isNotEmpty) {
          try {
            body = jsonDecode(request.body);
          } catch (_) {
            body = request.body;
          }
        }
        recorded.add(_RecordedRequest(request.method, request.url, body));
        // The library already holds this KPI at the migration's default
        // cadence (WEEKLY) — upsertKpi's GET-then-name-match finds it here.
        if (request.method == 'GET' && request.url.path.endsWith('/kpis')) {
          return http.Response(
            jsonEncode([
              {
                'id': 'kpi-existing',
                'company_id': 'co-1',
                'name': 'On-Time Delivery',
                'category': null,
                'description': null,
                'measurement_unit': null,
                'is_active': true,
                'department_id': null,
                'value_type': 'PERCENT',
                'numerator_label': null,
                'numerator_source': null,
                'denominator_label': null,
                'denominator_source': null,
                'unit': '%',
                'cadence': 'WEEKLY',
                'proof_type': null,
              },
            ]),
            200,
            request: request,
          );
        }
        return http.Response('[]', 200, request: request);
      });

      final client = SupabaseClient(
        'https://stub.supabase.co',
        'stub-anon-key',
        httpClient: mock,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final repo = RoleScorecardRepository(client);

      // Mirrors what the buggy _KpiDraft actually sends today: no kpiId, no
      // cadence, no goal — just whatever free text HR had typed in that
      // session for an existing, already-Monthly KPI.
      const link = KpiLinkInput(
        name: 'On-Time Delivery',
        target: 'At least 98%',
        frequency: 'Monthly',
      );

      await repo.saveRoleScorecardKpis('card-1', 'co-1', [link]);

      final upsertRequests = recorded
          .where(
            (r) => r.method == 'POST' && r.path.endsWith('/role_scorecard_kpis'),
          )
          .toList();
      expect(
        upsertRequests,
        hasLength(1),
        reason: 'expected exactly one upsert POST to role_scorecard_kpis',
      );
      final rows = (upsertRequests.single.body as List).cast<Map>();
      final row = rows.single;

      expect(
        row['frequency'],
        'Monthly',
        reason:
            'must keep the free text the user typed, not silently adopt the '
            "library row's WEEKLY default cadence",
      );
      expect(row['target'], 'At least 98%');
      expect(row['goal_direction'], isNull);
      expect(row['goal_value'], isNull);
      expect(row['goal_value_max'], isNull);
    },
  );

  test(
    'a save with no opinion on the goal omits target and the goal columns '
    'entirely, so the old card editor cannot wipe a workbench-authored goal',
    () async {
      // The regression this guarded: HR sets "≤ 3%" on Return Rate in the
      // workbench, then a colleague opens the old (now-deleted)
      // responsibility-card editor to fix a typo in the mission statement.
      // That editor built every KpiLinkInput with no goal and no cadence,
      // for every KPI on the card, on every save — so its save must not
      // have been able to reach the structured columns at all. The card PDF
      // and the next contract Annex A render the derived `target`, so a
      // wipe here would have reached signed documents.
      final recorded = <_RecordedRequest>[];
      // The server's view of this card's links. Round 1 (the workbench) puts
      // a structured goal there; round 2's read is what tells the repository
      // there is something to protect.
      var storedLinks = <Map<String, dynamic>>[];
      final mock = MockClient((request) async {
        Object? body;
        if (request.body.isNotEmpty) {
          try {
            body = jsonDecode(request.body);
          } catch (_) {
            body = request.body;
          }
        }
        recorded.add(_RecordedRequest(request.method, request.url, body));
        if (request.method == 'GET' &&
            request.url.path.endsWith('/role_scorecard_kpis')) {
          return http.Response(jsonEncode(storedLinks), 200, request: request);
        }
        return http.Response('[]', 200, request: request);
      });

      final client = SupabaseClient(
        'https://stub.supabase.co',
        'stub-anon-key',
        httpClient: mock,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final repo = RoleScorecardRepository(client);

      // Round 1 — the workbench's KPIs pane. It renders the goal editor, so
      // it owns the goal columns (writeGoal: true).
      await repo.saveRoleScorecardKpis('card-1', 'co-1', const [
        KpiLinkInput(
          kpiId: 'kpi-1',
          name: 'Return Rate',
          target: '',
          frequency: '',
          goal: KpiGoal(direction: GoalDirection.lte, value: 3),
          unit: '%',
          cadence: 'WEEKLY',
          writeGoal: true,
        ),
      ]);
      // Only the two columns the repository's protect-check actually selects
      // — PostgREST returns exactly the projection it was asked for.
      storedLinks = [
        {'kpi_id': 'kpi-1', 'goal_direction': 'LTE'},
      ];
      recorded.clear();

      // Round 2 — the old card editor. Exactly what its save loop builds:
      // the free text it loaded, and no structured anything.
      await repo.saveRoleScorecardKpis('card-1', 'co-1', const [
        KpiLinkInput(
          kpiId: 'kpi-1',
          name: 'Return Rate',
          target: '≤ 3%',
          frequency: 'Weekly',
        ),
      ]);

      final upserts = recorded
          .where(
            (r) => r.method == 'POST' && r.path.endsWith('/role_scorecard_kpis'),
          )
          .toList();
      expect(upserts, hasLength(1));
      final row = (upserts.single.body as List).cast<Map>().single;
      expect(row['kpi_id'], 'kpi-1');

      const protectedKeys = [
        'goal_direction',
        'goal_value',
        'goal_value_max',
        'target',
      ];
      for (final key in protectedKeys) {
        expect(
          row.containsKey(key),
          isFalse,
          reason: '$key must be ABSENT from the row, not present-and-null',
        );
        expect(
          upserts.single.columnsParam.contains(key),
          isFalse,
          reason:
              '$key must also be absent from Postgrest\'s ?columns= union — '
              'a column listed there is written (as NULL) even for a row '
              'whose map omitted it',
        );
      }
      // The keys this save legitimately owns are still written.
      expect(row['sort_order'], 0);
      expect(row['frequency'], 'Weekly');
    },
  );

  group('a writeGoal caller and the legacy target column', () {
    // A null goal on a caller that OWNS the goal columns means two different
    // things, and the difference is what the legacy `target` text lives or
    // dies on. The workbench renders the goal editor for every link it shows,
    // so `writeGoal: true` rides on ALL of them — but only some of those
    // links arrived carrying a structured goal. The caller's free text is the
    // signal for which is which: it sends '' for a link whose goal it
    // authored and has now removed, and the stored prose for a legacy link
    // that never had a goal at all. Conflating the two blanked the free-text
    // targets that the role-card PDF and the contract's Annex A print.

    /// Saves one `writeGoal: true` link with no structured goal and returns
    /// the row that reached `role_scorecard_kpis`.
    Future<Map> upsertedRow({
      required String target,
      required bool storedGoal,
    }) async {
      final recorded = <_RecordedRequest>[];
      final mock = MockClient((request) async {
        Object? body;
        if (request.body.isNotEmpty) {
          try {
            body = jsonDecode(request.body);
          } catch (_) {
            body = request.body;
          }
        }
        recorded.add(_RecordedRequest(request.method, request.url, body));
        if (request.method == 'GET' &&
            request.url.path.endsWith('/role_scorecard_kpis')) {
          return http.Response(
            jsonEncode(
              storedGoal
                  ? [
                      {'kpi_id': 'kpi-1', 'goal_direction': 'LTE'},
                    ]
                  : const [],
            ),
            200,
            request: request,
          );
        }
        return http.Response('[]', 200, request: request);
      });
      final client = SupabaseClient(
        'https://stub.supabase.co',
        'stub-anon-key',
        httpClient: mock,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final repo = RoleScorecardRepository(client);

      await repo.saveRoleScorecardKpis('card-1', 'co-1', [
        KpiLinkInput(
          kpiId: 'kpi-1',
          name: 'Return Rate',
          target: target,
          frequency: '',
          goal: null,
          unit: '%',
          cadence: 'WEEKLY',
          writeGoal: true,
        ),
      ]);

      final upserts = recorded.where(
        (r) => r.method == 'POST' && r.path.endsWith('/role_scorecard_kpis'),
      );
      return (upserts.single.body as List).cast<Map>().single;
    }

    test(
      'a writeGoal caller CAN clear a goal — omitting the columns is '
      'reserved for a caller with no opinion, not for one that says '
      '"no goal"',
      () async {
        // If "goal == null means leave it alone" were unconditional,
        // clearing the direction dropdown in the workbench would silently do
        // nothing and the stale bar would keep being printed on the role
        // card. The pane signals the clear by supplying no free text at all.
        final row = await upsertedRow(target: '', storedGoal: true);
        expect(row.containsKey('goal_direction'), isTrue);
        expect(row['goal_direction'], isNull);
        expect(row['goal_value'], isNull);
        expect(row['goal_value_max'], isNull);
        expect(
          row['target'],
          isNull,
          reason:
              'the derived text must go when the goal it was derived from '
              'goes — otherwise the card keeps printing a bar nobody holds',
        );
      },
    );

    test(
      'a writeGoal caller that supplies free text for a goal-less link '
      'keeps that text — a legacy target is not collateral damage of '
      'editing a sibling KPI',
      () async {
        // The live regression: a card carries five KPIs with typed targets,
        // HR sets a structured goal on ONE of them in the workbench and
        // saves. Every link on that card rides in the same save with
        // writeGoal: true, so the other four's prose — the only copy of it,
        // rendered into the role-card PDF and the employment contract's
        // Annex A — must survive a save that had no opinion about them.
        final row = await upsertedRow(
          target: 'Consistently high quality',
          storedGoal: false,
        );
        expect(row.containsKey('goal_direction'), isTrue);
        expect(row['goal_direction'], isNull);
        expect(row['goal_value'], isNull);
        expect(row['goal_value_max'], isNull);
        expect(
          row['target'],
          'Consistently high quality',
          reason:
              'no goal to derive from does not mean no target — the free '
              'text the caller supplied is the only copy that exists',
        );
      },
    );
  });

  group('saveLibraryKpi re-derives the columns its links depend on', () {
    /// One library KPI ('kpi-1') at LTE 3 %, WEEKLY, with two links: one
    /// carrying a structured goal, one with only legacy free text.
    Future<List<_RecordedRequest>> editLibraryKpi({
      required String cadence,
      required String? unit,
    }) async {
      final recorded = <_RecordedRequest>[];
      final mock = MockClient((request) async {
        Object? body;
        if (request.body.isNotEmpty) {
          try {
            body = jsonDecode(request.body);
          } catch (_) {
            body = request.body;
          }
        }
        recorded.add(_RecordedRequest(request.method, request.url, body));
        final path = request.url.path;
        if (request.method == 'GET' && path.endsWith('/kpis')) {
          return http.Response(
            jsonEncode([
              {
                'id': 'kpi-1',
                'company_id': 'co-1',
                'name': 'Return Rate',
                'is_active': true,
                'value_type': 'PERCENT',
                'unit': '%',
                'cadence': 'WEEKLY',
              },
            ]),
            200,
            request: request,
          );
        }
        if (request.method == 'GET' &&
            path.endsWith('/role_scorecard_kpis')) {
          return http.Response(
            jsonEncode([
              {
                'id': 'link-goal',
                'goal_direction': 'LTE',
                'goal_value': 3,
                'goal_value_max': null,
              },
              {
                'id': 'link-freetext',
                'goal_direction': null,
                'goal_value': null,
                'goal_value_max': null,
              },
            ]),
            200,
            request: request,
          );
        }
        if (request.method == 'PATCH' && path.endsWith('/kpis')) {
          return http.Response(
            jsonEncode({
              'id': 'kpi-1',
              'company_id': 'co-1',
              'name': 'Return Rate',
              'is_active': true,
              'cadence': cadence,
              'unit': unit,
            }),
            200,
            request: request,
          );
        }
        return http.Response('[]', 200, request: request);
      });
      final client = SupabaseClient(
        'https://stub.supabase.co',
        'stub-anon-key',
        httpClient: mock,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      await RoleScorecardRepository(client).saveLibraryKpi(
        id: 'kpi-1',
        companyId: 'co-1',
        name: 'Return Rate',
        valueType: 'PERCENT',
        unit: unit,
        cadence: cadence,
        writeDefinition: true,
      );
      return recorded
          .where(
            (r) =>
                r.method == 'PATCH' &&
                r.path.endsWith('/role_scorecard_kpis'),
          )
          .toList();
    }

    test(
      'correcting a cadence rewrites every link\'s derived frequency — the '
      'text the contract Annex A prints',
      () async {
        // frequency is only ever written inside saveRoleScorecardKpis, so
        // moving Return Rate from WEEKLY to MONTHLY used to leave every link
        // saying "Weekly" and the next employment contract printing it.
        final patches = await editLibraryKpi(cadence: 'MONTHLY', unit: '%');
        expect(patches, hasLength(2), reason: 'both links carry a frequency');
        for (final p in patches) {
          expect((p.body as Map)['frequency'], 'Monthly');
        }
        // The unit did not change, so nothing may touch target.
        for (final p in patches) {
          expect((p.body as Map).containsKey('target'), isFalse);
        }
      },
    );

    test(
      'correcting a unit re-renders a goal-carrying link\'s target and '
      'leaves a goal-less one alone',
      () async {
        final patches = await editLibraryKpi(
          cadence: 'WEEKLY',
          unit: 'orders',
        );
        final byLink = {
          for (final p in patches)
            p.url.queryParameters['id']: (p.body as Map),
        };
        expect(
          byLink['eq.link-goal']!['target'],
          '≤ 3 orders',
          reason: 'the stored goal re-rendered with the corrected unit',
        );
        expect(
          byLink['eq.link-freetext']?.containsKey('target') ?? false,
          isFalse,
          reason:
              'a link with no structured goal has no derivable target — its '
              'free text must survive, same rule as a goal-less upsert',
        );
      },
    );

    test(
      'a library edit that changes neither cadence nor unit touches no link',
      () async {
        final patches = await editLibraryKpi(cadence: 'WEEKLY', unit: '%');
        expect(
          patches,
          isEmpty,
          reason:
              'renaming a KPI must not normalise legacy free-text frequency '
              'away — that is what the typed-frequency test above protects',
        );
      },
    );
  });

  group('saveLibraryKpi writeDefinition', () {
    const definitionKeys = [
      'value_type',
      'numerator_label',
      'numerator_source',
      'denominator_label',
      'denominator_source',
      'unit',
      'cadence',
      'proof_type',
    ];

    Future<Map> patchBody({
      required bool writeDefinition,
      String valueType = 'COUNT',
      String? numeratorLabel,
      String? numeratorSource,
      String? denominatorLabel,
      String? denominatorSource,
      String? unit,
      String cadence = 'WEEKLY',
      String? proofType,
    }) async {
      final recorded = <_RecordedRequest>[];
      final mock = MockClient((request) async {
        Object? body;
        if (request.body.isNotEmpty) {
          try {
            body = jsonDecode(request.body);
          } catch (_) {
            body = request.body;
          }
        }
        recorded.add(_RecordedRequest(request.method, request.url, body));
        const row = {
          'id': 'kpi-1',
          'company_id': 'co-1',
          'name': 'Return Rate',
          'is_active': true,
          'cadence': 'WEEKLY',
          'unit': null,
        };
        // This KPI has no links, so re-derivation (covered by the group
        // above) finds nothing to do whatever cadence/unit the call changes.
        if (request.url.path.endsWith('/role_scorecard_kpis')) {
          return http.Response('[]', 200, request: request);
        }
        // Only `.single()`/`.maybeSingle()` reads want an object back; the
        // pre-update `select(...).limit(1)` wants a list.
        return http.Response(
          jsonEncode(request.method == 'GET' ? [row] : row),
          200,
          request: request,
        );
      });
      final client = SupabaseClient(
        'https://stub.supabase.co',
        'stub-anon-key',
        httpClient: mock,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final repo = RoleScorecardRepository(client);

      await repo.saveLibraryKpi(
        id: 'kpi-1',
        companyId: 'co-1',
        name: 'Return Rate',
        valueType: valueType,
        numeratorLabel: numeratorLabel,
        numeratorSource: numeratorSource,
        denominatorLabel: denominatorLabel,
        denominatorSource: denominatorSource,
        unit: unit,
        cadence: cadence,
        proofType: proofType,
        writeDefinition: writeDefinition,
      );

      final patch = recorded.singleWhere(
        (r) => r.method == 'PATCH' && r.path.endsWith('/kpis'),
      );
      return patch.body as Map;
    }

    test(
      'writeDefinition: false (the default) leaves the measurable '
      'definition columns untouched — a rename must not null them',
      () async {
        final body = await patchBody(writeDefinition: false);
        for (final key in definitionKeys) {
          expect(
            body.containsKey(key),
            isFalse,
            reason: '$key must be absent, not present-and-null',
          );
        }
        // The name/category/description/measurement_unit/is_active fields a
        // rename actually intends to change are still written.
        expect(body['name'], 'Return Rate');
        expect(body['is_active'], true);
      },
    );

    test(
      'writeDefinition: true writes all eight definition columns, '
      'including explicit nulls for the ones left unset',
      () async {
        final body = await patchBody(writeDefinition: true);
        for (final key in definitionKeys) {
          expect(body.containsKey(key), isTrue, reason: '$key must be present');
        }
        expect(body['value_type'], 'COUNT');
        expect(body['cadence'], 'WEEKLY');
        expect(body['numerator_label'], isNull);
        expect(body['numerator_source'], isNull);
        expect(body['denominator_label'], isNull);
        expect(body['denominator_source'], isNull);
        expect(body['unit'], isNull);
        expect(body['proof_type'], isNull);
      },
    );

    test(
      'writeDefinition: true carries every passed value through, including '
      'a source outside the autocomplete suggestion list — this is the path '
      'KpiFormDialog._save() and KpiLibraryScreen._openForm wire the '
      'measurable-definition form through, so a real (non-default) value in '
      'every column is what protects that wiring',
      () async {
        final body = await patchBody(
          writeDefinition: true,
          valueType: 'RATIO',
          numeratorLabel: 'Returns',
          // The suggestion list (kpiSourcesProvider) would only ever have
          // offered names already in use elsewhere — Temu is deliberately
          // NOT one of them, proving free text survives untouched.
          numeratorSource: 'Temu',
          denominatorLabel: 'Orders',
          denominatorSource: 'BigSeller',
          unit: '%',
          cadence: 'MONTHLY',
          proofType: 'SCREENSHOT',
        );
        expect(body['value_type'], 'RATIO');
        expect(body['numerator_label'], 'Returns');
        expect(
          body['numerator_source'],
          'Temu',
          reason:
              'a free-text source outside the suggestion list must still '
              'reach Postgrest untouched',
        );
        expect(body['denominator_label'], 'Orders');
        expect(body['denominator_source'], 'BigSeller');
        expect(body['unit'], '%');
        expect(body['cadence'], 'MONTHLY');
        expect(body['proof_type'], 'SCREENSHOT');
      },
    );
  });
}
