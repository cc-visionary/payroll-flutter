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
}
