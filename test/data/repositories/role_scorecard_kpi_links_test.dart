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
  final String path;
  final Object? body;
  _RecordedRequest(this.method, this.path, this.body);
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
        recorded.add(_RecordedRequest(request.method, request.url.path, body));
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
      expect(
        upsertRequests,
        hasLength(1),
        reason: 'expected exactly one upsert POST to role_scorecard_kpis',
      );
      final rows = (upsertRequests.single.body as List).cast<Map>();
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
      // Reproduces the live form-screen bug: `_KpiDraft` never carries the
      // library `kpiId` back from an existing card (see
      // role_scorecard_form_screen.dart's `_KpiDraft` and its load path), so
      // every KPI on an existing card round-trips through saveRoleScorecardKpis
      // with kpiId == null, cadence == null and goal == null — only the
      // name-match branch of upsertKpi ties it back to its library row.
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
        recorded.add(_RecordedRequest(request.method, request.url.path, body));
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

  group('saveLibraryKpi writeDefinition', () {
    const _definitionKeys = [
      'value_type',
      'numerator_label',
      'numerator_source',
      'denominator_label',
      'denominator_source',
      'unit',
      'cadence',
      'proof_type',
    ];

    Future<Map> _patchBody({required bool writeDefinition}) async {
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
        recorded.add(_RecordedRequest(request.method, request.url.path, body));
        return http.Response(
          jsonEncode({
            'id': 'kpi-1',
            'company_id': 'co-1',
            'name': 'Return Rate',
            'is_active': true,
          }),
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
        final body = await _patchBody(writeDefinition: false);
        for (final key in _definitionKeys) {
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
        final body = await _patchBody(writeDefinition: true);
        for (final key in _definitionKeys) {
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
  });
}
