import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:payroll_flutter/data/repositories/kpi_result_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Pins the ONE thing about `listByPeriod`'s ordering a Dart test can
/// actually observe: that the repository asks Postgres for a deterministic
/// order at all. A widget test cannot see what order Postgres itself
/// returns rows in -- that is server-side behaviour, not something this
/// process can execute -- so this test stops at "the outgoing request
/// carries an `order` clause naming a total, deterministic key", which is
/// the repository's own responsibility and the only part of the chain code
/// on this side of the wire can prove.
///
/// A recording `MockClient` stands in for Postgrest's HTTP transport, same
/// pattern as `role_scorecard_kpi_links_test.dart`: no `Supabase.initialize`
/// and no live server, just an in-memory record of the request issued.
void main() {
  test(
    'listByPeriod asks Postgres for a deterministic order, not an unordered read',
    () async {
      Uri? capturedUrl;
      final mock = MockClient((request) async {
        capturedUrl = request.url;
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
      final repo = KpiResultRepository(client);

      await repo.listByPeriod('2026-08');

      final order = capturedUrl?.queryParameters['order'];
      expect(order, isNotNull);
      // A TOTAL order: every column that can distinguish two rows sharing a
      // status (kpi_id, scope) plus the two columns that distinguish rows
      // within the SAME kpi_id/scope (employee_id for PERSONAL,
      // department_id for DEPARTMENT). Asserting the column LIST, not merely
      // "order is non-null" -- an order clause naming only `kpi_id` would
      // satisfy a weaker assertion while leaving every tie (same KPI,
      // different scope or different employee/department) exactly as
      // undefined as before this fix.
      expect(
        order,
        'kpi_id.asc.nullslast,scope.asc.nullslast,'
        'employee_id.asc.nullslast,department_id.asc.nullslast',
      );

      // NOT attempted: proving Postgres actually HONOURS this clause, or
      // that two live reads return identical sequences. Both are server-side
      // facts no Dart test against a mocked transport can observe -- see the
      // "Untested seam" note in kpi_dashboard_screen_test.dart, which is the
      // other half of this same gap (a dashboard test cannot tell
      // "status-correct but arbitrary within status" apart from
      // "status-wrong" either, for the same underlying reason).
    },
  );
}
