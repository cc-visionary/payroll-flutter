import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/kpi_result.dart';
import 'package:payroll_flutter/data/models/kpi_source_config.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/features/kpi_results/configured_source.dart';

Employee _employee(String id, {String? roleId, String? deptId}) => Employee(
  id: id,
  companyId: 'c',
  employeeNumber: id,
  firstName: id,
  lastName: 'X',
  roleScorecardId: roleId,
  // The stale, denormalised copy `employee_form_screen.dart` writes at
  // save time -- deliberately settable here so a test can prove the role
  // wins even when this disagrees with it.
  departmentId: deptId,
  employmentType: 'FULL_TIME',
  employmentStatus: 'ACTIVE',
  hireDate: DateTime(2024, 1, 1),
  isRankAndFile: true,
  isOtEligible: false,
  isNdEligible: false,
  isHolidayPayEligible: false,
  sssEligibilityOverride: false,
  philhealthEligibilityOverride: false,
  pagibigEligibilityOverride: false,
  taxOnFullEarnings: false,
);

RoleScorecard _role(String id, {String? deptId}) => RoleScorecard(
  id: id,
  companyId: 'c',
  departmentId: deptId,
  jobTitle: 'Role $id',
  missionStatement: '',
  responsibilities: const [],
  kpis: const [],
  wageType: 'MONTHLY',
  workHoursPerDay: 8,
  workDaysPerWeek: 'MON_FRI',
  isActive: true,
  effectiveDate: DateTime(2026),
);

KpiSourceBinding _binding({
  String id = 'b-1',
  SubjectKind subjectKind = SubjectKind.employee,
}) => KpiSourceBinding(
  id: id,
  companyId: 'c',
  kpiId: 'kpi-1',
  connectionId: 'conn-1',
  objectName: 'daily_sales_fact',
  periodColumn: 'period',
  subjectColumn: 'staff_id',
  numeratorColumn: 'revenue',
  denominatorColumn: 'target',
  subjectKind: subjectKind,
);

KpiSubjectMap _map(String externalKey, {String? employeeId, String? deptId}) =>
    KpiSubjectMap(
      id: 'm-$externalKey',
      companyId: 'c',
      connectionId: 'conn-1',
      externalKey: externalKey,
      employeeId: employeeId,
      departmentId: deptId,
    );

Map<String, dynamic> _row(
  String subjectKey, {
  dynamic numerator,
  dynamic denominator,
}) => {'subject_key': subjectKey, 'numerator': numerator, 'denominator': denominator};

void main() {
  final roles = [_role('r-ops', deptId: 'd-ops'), _role('r-mkt', deptId: 'd-mkt')];
  final employees = [
    // Alice's employees.departmentId (if it existed) is irrelevant -- the
    // model has no such stale field to even set here; her role is d-ops.
    _employee('e-alice', roleId: 'r-ops'),
    _employee('e-bob', roleId: 'r-ops'),
    _employee('e-cara', roleId: 'r-mkt'),
  ];

  ConfiguredSource buildSource({
    SubjectKind subjectKind = SubjectKind.employee,
    required ConfiguredSourceFetcher fetcher,
    SubjectMapReader? subjectMapReader,
  }) => ConfiguredSource(
    binding: _binding(subjectKind: subjectKind),
    subjectMapReader:
        subjectMapReader ??
        (connectionId) async => [
          _map('alice@x', employeeId: 'e-alice'),
          _map('bob@x', employeeId: 'e-bob'),
        ],
    fetcher: fetcher,
    employees: employees,
    roles: roles,
  );

  group('key', () {
    test('is cfg: plus the binding id', () {
      final source = buildSource(fetcher: ({required bindingId, required period}) async => (statusCode: 200, body: {'rows': []}));
      expect(source.key, 'cfg:b-1');
    });
  });

  group('happy path', () {
    test('aggregates rows from the fetcher into a company-scope total', () async {
      final source = buildSource(
        fetcher: ({required bindingId, required period}) async {
          expect(bindingId, 'b-1');
          expect(period, '2026-08');
          return (
            statusCode: 200,
            body: {
              'rows': [
                _row('alice@x', numerator: 30, denominator: 30),
                _row('bob@x', numerator: 10, denominator: 50),
              ],
            },
          );
        },
      );

      final result = await source.read(scope: KpiScope.company, period: '2026-08');
      // SUM, not average: 40/80, not the 0.6 averaging the two ratios
      // would give.
      expect(result.numerator, 40);
      expect(result.denominator, 80);
    });

    test('department scope sums only that department, via the ROLE', () async {
      final source = buildSource(
        fetcher: ({required bindingId, required period}) async => (
          statusCode: 200,
          body: {
            'rows': [
              _row('alice@x', numerator: 30, denominator: 30), // d-ops
              _row('bob@x', numerator: 10, denominator: 50), // d-ops
            ],
          },
        ),
      );

      final result = await source.read(
        scope: KpiScope.department,
        period: '2026-08',
        // The population passed by computeResults is every holder of ONE
        // department -- both alice and bob belong to r-ops -> d-ops.
        employeeIds: ['e-alice', 'e-bob'],
      );
      expect(result.numerator, 40);
      expect(result.denominator, 80);
    });

    test('personal scope picks that one employee only', () async {
      final source = buildSource(
        fetcher: ({required bindingId, required period}) async => (
          statusCode: 200,
          body: {
            'rows': [
              _row('alice@x', numerator: 30, denominator: 30),
              _row('bob@x', numerator: 10, denominator: 50),
            ],
          },
        ),
      );

      final result = await source.read(
        scope: KpiScope.personal,
        period: '2026-08',
        employeeIds: ['e-bob'],
      );
      expect(result.numerator, 10);
      expect(result.denominator, 50);
    });

    test(
      'employeeToDepartment is resolved through the ROLE, not a stale employees.department_id',
      () async {
        // Dana's ROLE (r-ops) puts her in d-ops, but her employees row
        // still carries the STALE d-mkt from before her role moved. Erin's
        // role (r-mkt) genuinely is d-mkt, with no stale disagreement.
        // If department resolution used the role (correct), the
        // department-scoped call below -- whose population is dana alone
        // -- derives departmentId=d-ops, so dana's OWN row (also mapped by
        // the role to d-ops) matches and erin's does not.
        // If it used the stale employees.department_id instead (the bug
        // this test exists to catch), the same call would derive
        // departmentId=d-mkt from dana's stale field, and it would be
        // ERIN's row that matches instead -- a different number, not a
        // crash, which is why this needs an assertion on the VALUE rather
        // than merely "did not throw".
        final dana = _employee('e-dana', roleId: 'r-ops', deptId: 'd-mkt');
        final erin = _employee('e-erin', roleId: 'r-mkt');
        final source = ConfiguredSource(
          binding: _binding(),
          subjectMapReader: (connectionId) async => [
            _map('dana@x', employeeId: 'e-dana'),
            _map('erin@x', employeeId: 'e-erin'),
          ],
          fetcher: ({required bindingId, required period}) async => (
            statusCode: 200,
            body: {
              'rows': [
                _row('dana@x', numerator: 10, denominator: 10),
                _row('erin@x', numerator: 100, denominator: 100),
              ],
            },
          ),
          employees: [dana, erin],
          roles: roles,
        );

        final result = await source.read(
          scope: KpiScope.department,
          period: '2026-08',
          employeeIds: ['e-dana'],
        );
        expect(result.numerator, 10);
        expect(result.denominator, 10);
      },
    );

    test('an unmapped subject counts toward company but not department, and is reported', () async {
      final source = buildSource(
        fetcher: ({required bindingId, required period}) async => (
          statusCode: 200,
          body: {
            'rows': [
              _row('alice@x', numerator: 30, denominator: 30),
              _row('unknown@x', numerator: 5, denominator: 5),
            ],
          },
        ),
      );

      final company = await source.readDetailed(scope: KpiScope.company, period: '2026-08');
      expect(company.numerator, 35); // unmapped subject still counts here
      expect(company.unresolvedSubjectKeys, ['unknown@x']);

      final dept = await source.readDetailed(
        scope: KpiScope.department,
        period: '2026-08',
        employeeIds: ['e-alice'],
      );
      expect(dept.numerator, 30); // unmapped subject excluded here
      expect(dept.unresolvedSubjectKeys, ['unknown@x']);
    });
  });

  group('every failure becomes (null, null)', () {
    test('the fetcher throwing', () async {
      final source = buildSource(
        fetcher: ({required bindingId, required period}) async => throw Exception('boom'),
      );
      final result = await source.read(scope: KpiScope.company, period: '2026-08');
      expect(result.numerator, isNull);
      expect(result.denominator, isNull);
    });

    test('a non-2xx status', () async {
      final source = buildSource(
        fetcher: ({required bindingId, required period}) async => (
          statusCode: 500,
          body: {
            'rows': [_row('alice@x', numerator: 30, denominator: 30)],
          },
        ),
      );
      final result = await source.read(scope: KpiScope.company, period: '2026-08');
      expect(result.numerator, isNull);
      expect(result.denominator, isNull);
    });

    test('a malformed body that is not even a JSON object', () async {
      final source = buildSource(
        fetcher: ({required bindingId, required period}) async => (statusCode: 200, body: 'not json'),
      );
      final result = await source.read(scope: KpiScope.company, period: '2026-08');
      expect(result.numerator, isNull);
      expect(result.denominator, isNull);
    });

    test('a body missing the rows key', () async {
      final source = buildSource(
        fetcher: ({required bindingId, required period}) async => (statusCode: 200, body: {'not_rows': []}),
      );
      final result = await source.read(scope: KpiScope.company, period: '2026-08');
      expect(result.numerator, isNull);
      expect(result.denominator, isNull);
    });

    test(
      'a row whose numerator is a string contributes nothing rather than crashing the whole read',
      () async {
        final source = buildSource(
          fetcher: ({required bindingId, required period}) async => (
            statusCode: 200,
            body: {
              'rows': [
                _row('alice@x', numerator: 'thirty', denominator: 30),
                _row('bob@x', numerator: 10, denominator: 50),
              ],
            },
          ),
        );
        // Must not throw, and bob's valid row must still be counted -- a
        // single bad field does not poison the whole read.
        final result = await source.read(scope: KpiScope.company, period: '2026-08');
        expect(result.numerator, 10);
        expect(result.denominator, 80);
      },
    );
  });
}
