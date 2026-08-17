import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/kpi_source_config.dart';

void main() {
  group('SubjectKind code mapping', () {
    test('every kind maps to its column code and back', () {
      for (final kind in SubjectKind.values) {
        final code = subjectKindCode(kind);
        expect(subjectKindFromCode(code), kind);
      }
    });

    test('column codes are the exact strings the CHECK constraint allows', () {
      expect(subjectKindCode(SubjectKind.employee), 'EMPLOYEE');
      expect(subjectKindCode(SubjectKind.department), 'DEPARTMENT');
      expect(subjectKindCode(SubjectKind.none), 'NONE');
    });

    test('an unrecognized code throws rather than guessing', () {
      expect(() => subjectKindFromCode('BOGUS'), throwsArgumentError);
    });
  });

  group('KpiConnection', () {
    test('round-trips a Postgres connection', () {
      final c = KpiConnection.fromRow({
        'id': 'conn-1',
        'company_id': 'c-1',
        'name': 'Cashflow',
        'kind': 'POSTGRES',
        'host': 'db.cashflow.internal',
        'port': 5432,
        'database': 'cashflow',
        'db_schema': 'public',
        'db_user': 'cashflow_ro',
        'credential_kind': 'VAULT',
        'credential_ref': 'cashflow_ro_password',
        'is_active': true,
      });

      expect(c.id, 'conn-1');
      expect(c.kind, 'POSTGRES');
      expect(c.host, 'db.cashflow.internal');
      expect(c.port, 5432);
      expect(c.dbSchema, 'public');
      expect(c.dbUser, 'cashflow_ro');
      expect(c.credentialKind, 'VAULT');
      expect(c.credentialRef, 'cashflow_ro_password');
      expect(c.isActive, isTrue);

      final p = c.toUpsertPayload();
      expect(p['id'], 'conn-1');
      expect(p['company_id'], 'c-1');
      expect(p['name'], 'Cashflow');
      expect(p['kind'], 'POSTGRES');
      expect(p['host'], 'db.cashflow.internal');
      expect(p['port'], 5432);
      expect(p['database'], 'cashflow');
      expect(p['db_schema'], 'public');
      expect(p['db_user'], 'cashflow_ro');
      expect(p['credential_kind'], 'VAULT');
      expect(p['credential_ref'], 'cashflow_ro_password');
      expect(p['is_active'], true);
    });

    test('a freshly-built connection has no id until the repository assigns one', () {
      const c = KpiConnection(
        companyId: 'c-1',
        name: 'Cashflow',
        kind: 'POSTGRES',
        host: 'db.cashflow.internal',
        port: 5432,
        database: 'cashflow',
        dbSchema: 'public',
        dbUser: 'cashflow_ro',
        credentialKind: 'ENV',
        credentialRef: 'CASHFLOW_RO_PASSWORD',
      );
      expect(c.id, isNull);
      expect(c.toUpsertPayload()['id'], isNull);
    });

    test('dbUser is not secret and its VALUE survives fromRow -> toUpsertPayload unchanged', () {
      // Not just "the key is present" -- the actual username string must
      // round-trip byte-for-byte, the same way the password-bearing
      // credentialRef does. A round trip that silently dropped, trimmed,
      // or renamed the username would connect as the wrong role without
      // ever failing a CHECK constraint.
      const username = 'cashflow_ro_reader';
      final c = KpiConnection.fromRow({
        'id': 'conn-2',
        'company_id': 'c-1',
        'name': 'Cashflow',
        'kind': 'POSTGRES',
        'host': 'db.cashflow.internal',
        'port': 5432,
        'database': 'cashflow',
        'db_schema': 'public',
        'db_user': username,
        'credential_kind': 'ENV',
        'credential_ref': 'CASHFLOW_RO_PASSWORD',
        'is_active': true,
      });

      expect(c.dbUser, username);
      expect(c.toUpsertPayload()['db_user'], username);

      // And the round trip through a second fromRow/toUpsertPayload pass
      // (as if the payload were written then read back) still carries the
      // same value -- not merely present, not coerced, not truncated.
      final roundTripped = KpiConnection.fromRow(c.toUpsertPayload());
      expect(roundTripped.dbUser, username);
    });
  });

  group('KpiSourceBinding', () {
    test('round-trips a RATIO binding with a denominator', () {
      final b = KpiSourceBinding.fromRow({
        'id': 'bind-1',
        'company_id': 'c-1',
        'kpi_id': 'kpi-1',
        'connection_id': 'conn-1',
        'object_name': 'attendance_daily',
        'period_column': 'period_month',
        'subject_column': 'staff_email',
        'numerator_column': 'present_days',
        'denominator_column': 'working_days',
        'subject_kind': 'EMPLOYEE',
        'period_format': 'YYYY-MM',
        'is_active': true,
      });

      expect(b.subjectKind, SubjectKind.employee);
      expect(b.denominatorColumn, 'working_days');

      final p = b.toUpsertPayload();
      expect(p['object_name'], 'attendance_daily');
      expect(p['subject_kind'], 'EMPLOYEE');
      expect(p['denominator_column'], 'working_days');
    });

    // The one most likely to be got wrong: a COUNT KPI has no denominator
    // column at all. It must come back as null, not '' -- an empty string
    // would fail the DB's identifier CHECK constraint on write, and would
    // read back as a (wrong) zero-length column name rather than "no
    // denominator" on the next fetch.
    test('a null denominatorColumn round-trips as null, never empty string', () {
      final b = KpiSourceBinding.fromRow({
        'id': 'bind-2',
        'company_id': 'c-1',
        'kpi_id': 'kpi-2',
        'connection_id': 'conn-1',
        'object_name': 'orders',
        'period_column': 'period_month',
        'subject_column': 'staff_email',
        'numerator_column': 'order_count',
        'denominator_column': null,
        'subject_kind': 'EMPLOYEE',
        'period_format': 'YYYY-MM',
        'is_active': true,
      });

      expect(b.denominatorColumn, isNull);
      expect(b.denominatorColumn, isNot(''));

      final p = b.toUpsertPayload();
      expect(p['denominator_column'], isNull);
      expect(p['denominator_column'], isNot(''));
    });

    test('a NONE-subject binding built from blank input has no denominator, not empty', () {
      const b = KpiSourceBinding(
        companyId: 'c-1',
        kpiId: 'kpi-3',
        connectionId: 'conn-1',
        objectName: 'daily_sales_fact',
        periodColumn: 'period_month',
        subjectColumn: 'company_key',
        numeratorColumn: 'revenue',
        subjectKind: SubjectKind.none,
      );
      expect(b.denominatorColumn, isNull);
      expect(b.toUpsertPayload()['denominator_column'], isNull);
    });
  });

  group('KpiSubjectMap', () {
    test('round-trips a row resolved to an employee', () {
      final m = KpiSubjectMap.fromRow({
        'id': 'map-1',
        'company_id': 'c-1',
        'connection_id': 'conn-1',
        'external_key': 'alice@cashflow.example',
        'employee_id': 'emp-1',
        'department_id': null,
      });

      expect(m.employeeId, 'emp-1');
      expect(m.departmentId, isNull);

      final p = m.toUpsertPayload();
      expect(p['employee_id'], 'emp-1');
      expect(p['department_id'], isNull);
      expect(p['external_key'], 'alice@cashflow.example');
    });

    test('round-trips a row resolved to a department', () {
      final m = KpiSubjectMap.fromRow({
        'id': 'map-2',
        'company_id': 'c-1',
        'connection_id': 'conn-1',
        'external_key': 'DEPT-OPS',
        'employee_id': null,
        'department_id': 'dept-1',
      });

      expect(m.employeeId, isNull);
      expect(m.departmentId, 'dept-1');

      final p = m.toUpsertPayload();
      expect(p['employee_id'], isNull);
      expect(p['department_id'], 'dept-1');
    });
  });
}
