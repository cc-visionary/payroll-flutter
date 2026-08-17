import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/kpi_result.dart';
import 'package:payroll_flutter/data/models/kpi_source_config.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/features/kpi_results/configured_source.dart';

Employee _employee(
  String id, {
  String? roleId,
  String? deptId,
  String status = 'ACTIVE',
  DateTime? deletedAt,
}) => Employee(
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
  employmentStatus: status,
  deletedAt: deletedAt,
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
    test('is cfg: plus the KPI id, not the binding id', () {
      final source = buildSource(fetcher: ({required bindingId, required period}) async => (statusCode: 200, body: {'rows': []}));
      expect(source.key, 'cfg:kpi-1');
    });

    test('stays stable across a re-binding that mints a new binding id for the same KPI', () {
      // Retiring a binding and creating a replacement is legal -- the
      // partial unique index (kpi_source_bindings_kpi_active) only
      // constrains ACTIVE rows -- and mints a brand new binding id. Keying
      // by kpiId means a KPI's numerator_source never has to change when
      // that happens; keying by bindingId would silently orphan it into
      // NO_DATA until someone remembered to rewrite numerator_source.
      final rebound = ConfiguredSource(
        binding: _binding(id: 'b-2'), // new binding id, same kpiId 'kpi-1'
        subjectMapReader: (connectionId) async => const [],
        fetcher: ({required bindingId, required period}) async =>
            (statusCode: 200, body: {'rows': []}),
        employees: employees,
        roles: roles,
      );
      expect(rebound.key, 'cfg:kpi-1');
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
      'a row whose numerator is a string does not crash, but the malformed '
      'value still collapses read() to (null, null)',
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
        // Must not throw -- bob's valid row is still parsed and summed
        // (readDetailed shows it), but the read()-level pair must NOT
        // report that partial sum as though it were complete: a wrong-typed
        // numerator anywhere means the total might be short by an unknown
        // amount, so `read` (the interface `computeResults` actually
        // calls) answers the same way every other failure in this class
        // does.
        final detailed = await source.readDetailed(
          scope: KpiScope.company,
          period: '2026-08',
        );
        expect(detailed.numerator, 10); // alice's malformed field contributed nothing
        expect(detailed.denominator, 80);
        expect(detailed.hasMalformedValues, isTrue);

        final result = await source.read(scope: KpiScope.company, period: '2026-08');
        expect(result.numerator, isNull);
        expect(result.denominator, isNull);
      },
    );
  });

  group('malformed values flag the result as incomplete', () {
    test('a wrong-typed numerator sets the flag', () async {
      final source = buildSource(
        fetcher: ({required bindingId, required period}) async => (
          statusCode: 200,
          body: {
            'rows': [_row('alice@x', numerator: 'not-a-number', denominator: 30)],
          },
        ),
      );
      final detailed = await source.readDetailed(scope: KpiScope.company, period: '2026-08');
      expect(detailed.hasMalformedValues, isTrue);
    });

    test('a wrong-typed denominator sets the flag', () async {
      final source = buildSource(
        fetcher: ({required bindingId, required period}) async => (
          statusCode: 200,
          body: {
            'rows': [_row('alice@x', numerator: 30, denominator: 'not-a-number')],
          },
        ),
      );
      final detailed = await source.readDetailed(scope: KpiScope.company, period: '2026-08');
      expect(detailed.hasMalformedValues, isTrue);
    });

    test('a clean read does not set the flag', () async {
      final source = buildSource(
        fetcher: ({required bindingId, required period}) async => (
          statusCode: 200,
          body: {
            'rows': [
              _row('alice@x', numerator: 30, denominator: 30),
              // A genuinely absent denominator (a COUNT KPI) is NOT
              // malformed -- only a value that arrived as the wrong type
              // counts.
              _row('bob@x', numerator: 10, denominator: null),
            ],
          },
        ),
      );
      final detailed = await source.readDetailed(scope: KpiScope.company, period: '2026-08');
      expect(detailed.hasMalformedValues, isFalse);
      final result = await source.read(scope: KpiScope.company, period: '2026-08');
      expect(result.numerator, 40);
      expect(result.denominator, 30);
    });

    test(
      'a mapped subject with BOTH numbers malformed still appears (not treated as absent) -- '
      'it contributes nothing to the sum and is NOT unresolved, but still sets the flag',
      () async {
        final source = buildSource(
          fetcher: ({required bindingId, required period}) async => (
            statusCode: 200,
            body: {
              'rows': [
                _row('alice@x', numerator: 'bad', denominator: 'also-bad'),
                _row('bob@x', numerator: 10, denominator: 50),
              ],
            },
          ),
        );
        final detailed = await source.readDetailed(scope: KpiScope.company, period: '2026-08');
        // alice resolved fine (she IS in the subject map) -- she is not
        // "unresolved", she is "resolved, with no usable figure".
        expect(detailed.unresolvedSubjectKeys, isEmpty);
        expect(detailed.hasMalformedValues, isTrue);
        expect(detailed.numerator, 10); // only bob's row contributes
        expect(detailed.denominator, 50);
      },
    );

    test('a row that is not even a JSON object sets the flag, dropped with no crash', () async {
      final source = buildSource(
        fetcher: ({required bindingId, required period}) async => (
          statusCode: 200,
          body: {
            'rows': [
              'not an object', // e.g. the source emitted a bare string row
              _row('bob@x', numerator: 10, denominator: 50),
            ],
          },
        ),
      );
      final detailed = await source.readDetailed(scope: KpiScope.company, period: '2026-08');
      expect(detailed.hasMalformedValues, isTrue);
      expect(detailed.numerator, 10); // bob's valid row still parsed
      expect(detailed.denominator, 50);
    });

    test('a row with no usable subject_key sets the flag, dropped with no crash', () async {
      final source = buildSource(
        fetcher: ({required bindingId, required period}) async => (
          statusCode: 200,
          body: {
            'rows': [
              {'subject_key': 42, 'numerator': 5, 'denominator': 5}, // wrong type
              _row('bob@x', numerator: 10, denominator: 50),
            ],
          },
        ),
      );
      final detailed = await source.readDetailed(scope: KpiScope.company, period: '2026-08');
      expect(detailed.hasMalformedValues, isTrue);
      expect(detailed.numerator, 10);
      expect(detailed.denominator, 50);
    });
  });

  group('unresolved subjects: scope-dependent collapse via read()', () {
    // These three mirror aggregateSourceRows' own scope rules
    // (source_rows.dart): COMPANY counts an unresolved row, so its total is
    // correct and must not be blanked; PERSONAL/DEPARTMENT exclude it, so
    // their totals may genuinely be short and must collapse.
    ConfiguredSourceFetcher fetcherWithUnmapped() =>
        ({required bindingId, required period}) async => (
          statusCode: 200,
          body: {
            'rows': [
              _row('alice@x', numerator: 30, denominator: 30), // maps to e-alice, d-ops
              _row('unknown@x', numerator: 5, denominator: 5), // unmapped
            ],
          },
        );

    test('company scope does NOT collapse -- the unresolved row is already counted', () async {
      final source = buildSource(fetcher: fetcherWithUnmapped());
      final result = await source.read(scope: KpiScope.company, period: '2026-08');
      expect(result.numerator, 35);
      expect(result.denominator, 35);
    });

    test('department scope DOES collapse -- the total may be short', () async {
      final source = buildSource(fetcher: fetcherWithUnmapped());
      final result = await source.read(
        scope: KpiScope.department,
        period: '2026-08',
        employeeIds: ['e-alice'],
      );
      expect(result.numerator, isNull);
      expect(result.denominator, isNull);
    });

    test('personal scope DOES collapse -- the unmapped key might be this person', () async {
      final source = buildSource(fetcher: fetcherWithUnmapped());
      final result = await source.read(
        scope: KpiScope.personal,
        period: '2026-08',
        employeeIds: ['e-alice'],
      );
      expect(result.numerator, isNull);
      expect(result.denominator, isNull);
    });

    test('no unresolved subjects: no scope collapses', () async {
      final source = buildSource(
        fetcher: ({required bindingId, required period}) async => (
          statusCode: 200,
          body: {
            'rows': [_row('alice@x', numerator: 30, denominator: 30)],
          },
        ),
      );
      final company = await source.read(scope: KpiScope.company, period: '2026-08');
      expect(company.numerator, 30);
      final personal = await source.read(
        scope: KpiScope.personal,
        period: '2026-08',
        employeeIds: ['e-alice'],
      );
      expect(personal.numerator, 30);
    });
  });

  group('employeeToDepartment excludes terminated/deleted employees', () {
    test(
      'a terminated employee\'s leftover source row does not land in the department sum',
      () async {
        // Frank was ACTIVE in r-ops (d-ops) but has since been terminated.
        // Cashflow (the external source) has no idea and still emits a row
        // for him -- populationFor's own holds() rule would never include
        // him, and this map must not either.
        final frank = _employee('e-frank', roleId: 'r-ops', status: 'TERMINATED');
        final dana = _employee('e-dana', roleId: 'r-ops');
        final source = ConfiguredSource(
          binding: _binding(),
          subjectMapReader: (connectionId) async => [
            _map('frank@x', employeeId: 'e-frank'),
            _map('dana@x', employeeId: 'e-dana'),
          ],
          fetcher: ({required bindingId, required period}) async => (
            statusCode: 200,
            body: {
              'rows': [
                _row('frank@x', numerator: 100, denominator: 100),
                _row('dana@x', numerator: 10, denominator: 10),
              ],
            },
          ),
          employees: [frank, dana],
          roles: roles,
        );

        final result = await source.readDetailed(
          scope: KpiScope.department,
          period: '2026-08',
          employeeIds: ['e-dana'],
        );
        // If frank's terminated row still counted, this would be 110/110.
        expect(result.numerator, 10);
        expect(result.denominator, 10);
      },
    );

    test('a soft-deleted employee is excluded the same way', () async {
      final gina = _employee('e-gina', roleId: 'r-ops', deletedAt: DateTime(2026, 1, 1));
      final dana = _employee('e-dana', roleId: 'r-ops');
      final source = ConfiguredSource(
        binding: _binding(),
        subjectMapReader: (connectionId) async => [
          _map('gina@x', employeeId: 'e-gina'),
          _map('dana@x', employeeId: 'e-dana'),
        ],
        fetcher: ({required bindingId, required period}) async => (
          statusCode: 200,
          body: {
            'rows': [
              _row('gina@x', numerator: 100, denominator: 100),
              _row('dana@x', numerator: 10, denominator: 10),
            ],
          },
        ),
        employees: [gina, dana],
        roles: roles,
      );

      final result = await source.readDetailed(
        scope: KpiScope.department,
        period: '2026-08',
        employeeIds: ['e-dana'],
      );
      expect(result.numerator, 10);
      expect(result.denominator, 10);
    });
  });

  group('DEPARTMENT-kind subject resolution', () {
    // A DEPARTMENT-kind binding's raw subject_key is an EXTERNAL code (a
    // cost-centre code, the source's own department id) -- not this app's
    // department uuid -- so it goes through kpi_subject_map exactly the
    // way an EMPLOYEE-kind key does, just resolving to departmentId instead
    // of employeeId. Task 9 wires this up; before it, a DEPARTMENT-kind
    // binding's `unresolved` set stayed empty no matter what the source
    // returned (see the plan's Task 9 report for why that made the
    // Settings surface unable to say anything true about it).
    test('a mapped external department code resolves and sums at department scope', () async {
      final source = ConfiguredSource(
        binding: _binding(subjectKind: SubjectKind.department),
        subjectMapReader: (connectionId) async => [
          _map('CC-OPS', deptId: 'd-ops'),
          _map('CC-MKT', deptId: 'd-mkt'),
        ],
        fetcher: ({required bindingId, required period}) async => (
          statusCode: 200,
          body: {
            'rows': [
              _row('CC-OPS', numerator: 30, denominator: 30),
              _row('CC-MKT', numerator: 10, denominator: 50),
            ],
          },
        ),
        employees: employees,
        roles: roles,
      );

      final ops = await source.read(
        scope: KpiScope.department,
        period: '2026-08',
        employeeIds: ['e-alice'], // alice -> r-ops -> d-ops
      );
      expect(ops.numerator, 30);
      expect(ops.denominator, 30);

      final company = await source.read(scope: KpiScope.company, period: '2026-08');
      expect(company.numerator, 40);
      expect(company.denominator, 80);
    });

    test('an unmapped external department code is reported, excluded from department, still counted in company', () async {
      final source = ConfiguredSource(
        binding: _binding(subjectKind: SubjectKind.department),
        subjectMapReader: (connectionId) async => [_map('CC-OPS', deptId: 'd-ops')],
        fetcher: ({required bindingId, required period}) async => (
          statusCode: 200,
          body: {
            'rows': [
              _row('CC-OPS', numerator: 30, denominator: 30),
              _row('CC-UNKNOWN', numerator: 5, denominator: 5),
            ],
          },
        ),
        employees: employees,
        roles: roles,
      );

      final detailed = await source.readDetailed(scope: KpiScope.company, period: '2026-08');
      expect(detailed.numerator, 35); // unmapped code still counts here
      expect(detailed.unresolvedSubjectKeys, ['CC-UNKNOWN']);

      final ops = await source.readDetailed(
        scope: KpiScope.department,
        period: '2026-08',
        employeeIds: ['e-alice'],
      );
      expect(ops.numerator, 30); // unmapped code excluded here
      expect(ops.unresolvedSubjectKeys, ['CC-UNKNOWN']);
    });
  });
}
