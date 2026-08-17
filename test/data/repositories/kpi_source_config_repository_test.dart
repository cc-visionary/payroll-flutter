import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:payroll_flutter/data/models/kpi_source_config.dart';
import 'package:payroll_flutter/data/repositories/kpi_source_config_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Covers [KpiSourceConfigRepository] against the actual HTTP requests it
/// issues, same technique as `kpi_result_repository_test.dart` and
/// `role_scorecard_kpi_links_test.dart`: a recording [MockClient] stands in
/// for Postgrest's transport, no `Supabase.initialize` and no live server.
///
/// Every save test asserts field VALUES, not `containsKey` -- the brief for
/// this task names an exact prior bug this repo is not allowed to repeat: a
/// caller reconstructing a model field-by-field and dropping one, which
/// `containsKey` alone would not catch (the key can be present, carrying the
/// wrong -- or a default-constructor -- value).
class _RecordedRequest {
  final String method;
  final Uri url;
  final Object? body;
  _RecordedRequest(this.method, this.url, this.body);
  String get path => url.path;
}

typedef _Responder = http.Response Function(http.Request request);

(SupabaseClient, List<_RecordedRequest>) _stubClient([_Responder? respond]) {
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
    if (respond != null) return respond(request);
    return http.Response('[]', 200, request: request);
  });
  final client = SupabaseClient(
    'https://stub.supabase.co',
    'stub-anon-key',
    httpClient: mock,
    // Prevent the GoTrue auto-refresh periodic timer, which otherwise leaks
    // past the test and trips flutter_test's "Timer still pending" invariant.
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  return (client, recorded);
}

/// Unwraps a Postgrest write body to the single row map, whether the client
/// sent a bare object (single-row `.insert`/`.update`) or a one-element
/// array.
Map<String, dynamic> _row(Object? body) => body is List
    ? (body).cast<Map<String, dynamic>>().single
    : (body as Map).cast<String, dynamic>();

void main() {
  group('kpi_connections', () {
    test('listConnections maps every row', () async {
      final (client, _) = _stubClient(
        (request) => http.Response(
          jsonEncode([
            {
              'id': 'conn-1',
              'company_id': 'co-1',
              'name': 'Cashflow',
              'kind': 'POSTGRES',
              'host': 'db.example.com',
              'port': 5432,
              'database': 'cashflow',
              'db_schema': 'public',
              'db_user': 'cashflow_ro',
              'credential_kind': 'VAULT',
              'credential_ref': 'cashflow-pg',
              'is_active': true,
            },
          ]),
          200,
          request: request,
        ),
      );
      final rows = await KpiSourceConfigRepository(client).listConnections();
      expect(rows, hasLength(1));
      expect(rows.single.id, 'conn-1');
      expect(rows.single.companyId, 'co-1');
      expect(rows.single.name, 'Cashflow');
      expect(rows.single.credentialRef, 'cashflow-pg');
    });

    test(
      'upsertConnection insert carries every field, and never sends an '
      'explicit null id',
      () async {
        final (client, recorded) = _stubClient();
        const c = KpiConnection(
          companyId: 'co-1',
          name: 'Cashflow',
          kind: 'POSTGRES',
          host: 'db.example.com',
          port: 6543,
          database: 'cashflow',
          dbSchema: 'reporting',
          dbUser: 'cashflow_ro',
          credentialKind: 'ENV',
          credentialRef: 'CASHFLOW_PG_PASSWORD',
          isActive: false,
        );
        await KpiSourceConfigRepository(client).upsertConnection(c);

        final post = recorded.singleWhere(
          (r) => r.method == 'POST' && r.path.endsWith('/kpi_connections'),
        );
        final row = _row(post.body);
        expect(
          row.containsKey('id'),
          isFalse,
          reason:
              'an explicit null id would violate the NOT NULL primary key '
              'and skip the column default (gen_random_uuid())',
        );
        expect(row['company_id'], 'co-1');
        expect(row['name'], 'Cashflow');
        expect(row['kind'], 'POSTGRES');
        expect(row['host'], 'db.example.com');
        expect(row['port'], 6543);
        expect(row['database'], 'cashflow');
        expect(row['db_schema'], 'reporting');
        expect(row['db_user'], 'cashflow_ro');
        expect(row['credential_kind'], 'ENV');
        expect(row['credential_ref'], 'CASHFLOW_PG_PASSWORD');
        expect(row['is_active'], false);
      },
    );

    test(
      'upsertConnection update targets the row by id and carries every '
      'field',
      () async {
        final (client, recorded) = _stubClient();
        const c = KpiConnection(
          id: 'conn-1',
          companyId: 'co-1',
          name: 'Cashflow (renamed)',
          kind: 'SUPABASE',
          host: 'db2.example.com',
          port: 5432,
          database: 'cashflow2',
          dbSchema: 'public',
          dbUser: 'cashflow_ro_2',
          credentialKind: 'VAULT',
          credentialRef: 'cashflow-pg-2',
          isActive: true,
        );
        await KpiSourceConfigRepository(client).upsertConnection(c);

        final patch = recorded.singleWhere(
          (r) => r.method == 'PATCH' && r.path.endsWith('/kpi_connections'),
        );
        expect(patch.url.queryParameters['id'], 'eq.conn-1');
        final row = _row(patch.body);
        expect(row['company_id'], 'co-1');
        expect(row['name'], 'Cashflow (renamed)');
        expect(row['kind'], 'SUPABASE');
        expect(row['host'], 'db2.example.com');
        expect(row['port'], 5432);
        expect(row['database'], 'cashflow2');
        expect(row['db_schema'], 'public');
        expect(row['db_user'], 'cashflow_ro_2');
        expect(row['credential_kind'], 'VAULT');
        expect(row['credential_ref'], 'cashflow-pg-2');
        expect(row['is_active'], true);
      },
    );
  });

  group('kpi_source_bindings', () {
    test('listBindings maps every row', () async {
      final (client, _) = _stubClient(
        (request) => http.Response(
          jsonEncode([
            {
              'id': 'binding-1',
              'company_id': 'co-1',
              'kpi_id': 'kpi-1',
              'connection_id': 'conn-1',
              'object_name': 'orders',
              'period_column': 'period',
              'subject_column': 'staff_email',
              'numerator_column': 'return_count',
              'denominator_column': 'order_count',
              'subject_kind': 'EMPLOYEE',
              'period_format': 'YYYY-MM',
              'is_active': true,
            },
          ]),
          200,
          request: request,
        ),
      );
      final rows = await KpiSourceConfigRepository(client).listBindings();
      expect(rows, hasLength(1));
      expect(rows.single.id, 'binding-1');
      expect(rows.single.objectName, 'orders');
      expect(rows.single.denominatorColumn, 'order_count');
      expect(rows.single.subjectKind, SubjectKind.employee);
    });

    test(
      'upsertBinding insert carries every field, including a null '
      'denominatorColumn as present-and-null -- not omitted, not empty '
      'string',
      () async {
        final (client, recorded) = _stubClient();
        const b = KpiSourceBinding(
          companyId: 'co-1',
          kpiId: 'kpi-1',
          connectionId: 'conn-1',
          objectName: 'orders',
          periodColumn: 'period',
          subjectColumn: 'staff_email',
          numeratorColumn: 'return_count',
          denominatorColumn: null,
          subjectKind: SubjectKind.employee,
          periodFormat: 'YYYY-MM',
          isActive: true,
        );
        await KpiSourceConfigRepository(client).upsertBinding(b);

        final post = recorded.singleWhere(
          (r) =>
              r.method == 'POST' && r.path.endsWith('/kpi_source_bindings'),
        );
        final row = _row(post.body);
        expect(row.containsKey('id'), isFalse);
        expect(row['company_id'], 'co-1');
        expect(row['kpi_id'], 'kpi-1');
        expect(row['connection_id'], 'conn-1');
        expect(row['object_name'], 'orders');
        expect(row['period_column'], 'period');
        expect(row['subject_column'], 'staff_email');
        expect(row['numerator_column'], 'return_count');
        expect(
          row.containsKey('denominator_column'),
          isTrue,
          reason:
              'must be present-and-null so an update can clear a previously '
              'set denominator, not merely absent',
        );
        expect(row['denominator_column'], isNull);
        expect(row['subject_kind'], 'EMPLOYEE');
        expect(row['period_format'], 'YYYY-MM');
        expect(row['is_active'], true);
      },
    );

    test(
      'upsertBinding carries a non-null denominatorColumn VALUE through, '
      'not just key presence -- guards a save that reconstructs the model '
      "and silently keeps the prior binding's column name instead of the "
      'new one',
      () async {
        final (client, recorded) = _stubClient();
        const b = KpiSourceBinding(
          companyId: 'co-1',
          kpiId: 'kpi-1',
          connectionId: 'conn-1',
          objectName: 'orders',
          periodColumn: 'period',
          subjectColumn: 'staff_email',
          numeratorColumn: 'return_count',
          denominatorColumn: 'order_count',
          subjectKind: SubjectKind.employee,
        );
        await KpiSourceConfigRepository(client).upsertBinding(b);

        final post = recorded.singleWhere(
          (r) =>
              r.method == 'POST' && r.path.endsWith('/kpi_source_bindings'),
        );
        expect(_row(post.body)['denominator_column'], 'order_count');
      },
    );

    test('upsertBinding update targets the row by id', () async {
      final (client, recorded) = _stubClient();
      const b = KpiSourceBinding(
        id: 'binding-1',
        companyId: 'co-1',
        kpiId: 'kpi-1',
        connectionId: 'conn-1',
        objectName: 'orders_v2',
        periodColumn: 'period',
        subjectColumn: 'staff_email',
        numeratorColumn: 'return_count',
        denominatorColumn: 'order_count',
        subjectKind: SubjectKind.department,
        isActive: false,
      );
      await KpiSourceConfigRepository(client).upsertBinding(b);

      final patch = recorded.singleWhere(
        (r) => r.method == 'PATCH' && r.path.endsWith('/kpi_source_bindings'),
      );
      expect(patch.url.queryParameters['id'], 'eq.binding-1');
      final row = _row(patch.body);
      expect(row['object_name'], 'orders_v2');
      expect(row['subject_kind'], 'DEPARTMENT');
      expect(row['is_active'], false);
    });

    test('deleteBinding issues a DELETE filtered by id', () async {
      final (client, recorded) = _stubClient();
      await KpiSourceConfigRepository(client).deleteBinding('binding-1');
      final del = recorded.singleWhere(
        (r) =>
            r.method == 'DELETE' && r.path.endsWith('/kpi_source_bindings'),
      );
      expect(del.url.queryParameters['id'], 'eq.binding-1');
    });

    group('bindingForKpi', () {
      test(
        'returns null when no active binding exists -- a normal, common '
        'state (most KPIs are still app-computed), not an error, so this '
        'must not throw the way .single() would on zero rows',
        () async {
          final (client, recorded) = _stubClient(
            (request) => http.Response('[]', 200, request: request),
          );
          final result = await KpiSourceConfigRepository(
            client,
          ).bindingForKpi('kpi-1');
          expect(result, isNull);
          final get = recorded.single;
          expect(get.url.queryParameters['kpi_id'], 'eq.kpi-1');
          expect(
            get.url.queryParameters['is_active'],
            'eq.true',
            reason:
                'the partial unique index only constrains ACTIVE rows -- an '
                'inactive binding for the same kpi can legitimately coexist '
                'and must be excluded by this filter, not merely unreached',
          );
        },
      );

      test('returns the one active binding for the kpi', () async {
        final (client, recorded) = _stubClient(
          (request) => http.Response(
            jsonEncode([
              {
                'id': 'binding-1',
                'company_id': 'co-1',
                'kpi_id': 'kpi-1',
                'connection_id': 'conn-1',
                'object_name': 'orders',
                'period_column': 'period',
                'subject_column': 'staff_email',
                'numerator_column': 'return_count',
                'denominator_column': null,
                'subject_kind': 'EMPLOYEE',
                'period_format': 'YYYY-MM',
                'is_active': true,
              },
            ]),
            200,
            request: request,
          ),
        );
        final result = await KpiSourceConfigRepository(
          client,
        ).bindingForKpi('kpi-1');
        expect(result, isNotNull);
        expect(result!.id, 'binding-1');
        expect(result.denominatorColumn, isNull);
        expect(recorded.single.url.queryParameters['kpi_id'], 'eq.kpi-1');
      });
    });
  });

  group('kpi_subject_map', () {
    test('subjectMapFor filters by connection and maps every row', () async {
      final (client, recorded) = _stubClient(
        (request) => http.Response(
          jsonEncode([
            {
              'id': 'map-1',
              'company_id': 'co-1',
              'connection_id': 'conn-1',
              'external_key': 'staff-42',
              'employee_id': 'emp-1',
              'department_id': null,
            },
          ]),
          200,
          request: request,
        ),
      );
      final rows = await KpiSourceConfigRepository(
        client,
      ).subjectMapFor('conn-1');
      expect(rows, hasLength(1));
      expect(rows.single.externalKey, 'staff-42');
      expect(rows.single.employeeId, 'emp-1');
      expect(rows.single.departmentId, isNull);
      expect(recorded.single.url.queryParameters['connection_id'], 'eq.conn-1');
    });

    test(
      'upsertSubjectMapping insert carries every field for an '
      'employee-scoped mapping',
      () async {
        final (client, recorded) = _stubClient();
        const m = KpiSubjectMap(
          companyId: 'co-1',
          connectionId: 'conn-1',
          externalKey: 'staff-42',
          employeeId: 'emp-1',
        );
        await KpiSourceConfigRepository(client).upsertSubjectMapping(m);

        final post = recorded.singleWhere(
          (r) => r.method == 'POST' && r.path.endsWith('/kpi_subject_map'),
        );
        final row = _row(post.body);
        expect(row.containsKey('id'), isFalse);
        expect(row['company_id'], 'co-1');
        expect(row['connection_id'], 'conn-1');
        expect(row['external_key'], 'staff-42');
        expect(row['employee_id'], 'emp-1');
        expect(row.containsKey('department_id'), isTrue);
        expect(row['department_id'], isNull);
      },
    );

    test(
      'upsertSubjectMapping insert carries every field for a '
      'department-scoped mapping',
      () async {
        final (client, recorded) = _stubClient();
        const m = KpiSubjectMap(
          companyId: 'co-1',
          connectionId: 'conn-1',
          externalKey: 'dept-code-9',
          departmentId: 'dept-1',
        );
        await KpiSourceConfigRepository(client).upsertSubjectMapping(m);

        final post = recorded.singleWhere(
          (r) => r.method == 'POST' && r.path.endsWith('/kpi_subject_map'),
        );
        final row = _row(post.body);
        expect(row['external_key'], 'dept-code-9');
        expect(row.containsKey('employee_id'), isTrue);
        expect(row['employee_id'], isNull);
        expect(row['department_id'], 'dept-1');
      },
    );

    test('upsertSubjectMapping update targets the row by id', () async {
      final (client, recorded) = _stubClient();
      const m = KpiSubjectMap(
        id: 'map-1',
        companyId: 'co-1',
        connectionId: 'conn-1',
        externalKey: 'staff-42-renamed',
        employeeId: 'emp-1',
      );
      await KpiSourceConfigRepository(client).upsertSubjectMapping(m);

      final patch = recorded.singleWhere(
        (r) => r.method == 'PATCH' && r.path.endsWith('/kpi_subject_map'),
      );
      expect(patch.url.queryParameters['id'], 'eq.map-1');
      expect(_row(patch.body)['external_key'], 'staff-42-renamed');
    });

    test('deleteSubjectMapping issues a DELETE filtered by id', () async {
      final (client, recorded) = _stubClient();
      await KpiSourceConfigRepository(client).deleteSubjectMapping('map-1');
      final del = recorded.singleWhere(
        (r) => r.method == 'DELETE' && r.path.endsWith('/kpi_subject_map'),
      );
      expect(del.url.queryParameters['id'], 'eq.map-1');
    });
  });

  group('fetchSourceRows', () {
    test(
      'invokes fetch-kpi-source with binding_id/period and returns the '
      'status/body pair on 200',
      () async {
        final (client, recorded) = _stubClient(
          (request) => http.Response(
            jsonEncode({
              'rows': [
                {'subject_key': 'alice@x', 'numerator': 4, 'denominator': 5},
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          ),
        );

        final result = await KpiSourceConfigRepository(
          client,
        ).fetchSourceRows(bindingId: 'binding-1', period: '2026-08');

        expect(result.statusCode, 200);
        expect(result.body, {
          'rows': [
            {'subject_key': 'alice@x', 'numerator': 4, 'denominator': 5},
          ],
        });

        final post = recorded.singleWhere(
          (r) => r.path.endsWith('/fetch-kpi-source'),
        );
        expect(post.method.toUpperCase(), 'POST');
        expect(post.body, {'binding_id': 'binding-1', 'period': '2026-08'});
      },
    );

    test(
      'a non-2xx response is returned as a status/body pair, NOT thrown -- '
      'ConfiguredSource already maps every status outside 200-299 to '
      'NO_DATA, and letting this throw would defeat that mapping',
      () async {
        final (client, _) = _stubClient(
          (request) => http.Response(
            jsonEncode({'error': 'Forbidden', 'code': 'NOT_AUTHORIZED'}),
            403,
            headers: {'content-type': 'application/json'},
            request: request,
          ),
        );

        final result = await KpiSourceConfigRepository(
          client,
        ).fetchSourceRows(bindingId: 'binding-1', period: '2026-08');

        expect(result.statusCode, 403);
        expect(result.body, {'error': 'Forbidden', 'code': 'NOT_AUTHORIZED'});
      },
    );
  });
}
