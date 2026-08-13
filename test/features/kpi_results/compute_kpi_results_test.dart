import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/kpi.dart';
import 'package:payroll_flutter/data/models/kpi_input.dart';
import 'package:payroll_flutter/data/models/kpi_result.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/features/kpi_results/automatic_sources.dart';
import 'package:payroll_flutter/features/kpi_results/compute_kpi_results.dart';

Employee _employee(
  String id, {
  String? roleId,
  String status = 'ACTIVE',
}) => Employee(
  id: id,
  companyId: 'c',
  employeeNumber: id,
  firstName: id,
  lastName: 'X',
  roleScorecardId: roleId,
  employmentType: 'FULL_TIME',
  employmentStatus: status,
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

Kpi _kpi({
  String id = 'k-1',
  String level = 'COMPANY',
  String rollupType = 'INDEPENDENT',
  String dataMethod = 'MANUAL_PERIODIC',
  String valueType = 'RATIO',
  String? departmentId,
  String? numeratorSource,
  String? targetDirection = 'HIGHER',
  num? targetValue = 1,
}) => Kpi(
  id: id,
  companyId: 'c',
  name: 'KPI $id',
  level: level,
  rollupType: rollupType,
  dataMethod: dataMethod,
  valueType: valueType,
  departmentId: departmentId,
  numeratorSource: numeratorSource,
  targetDirection: targetDirection,
  targetValue: targetValue,
);

KpiException _exception({
  required String kpiId,
  String? employeeId,
  required String occurredOn,
  num quantity = 1,
  DateTime? confirmedAt,
}) => KpiException(
  companyId: 'c',
  kpiId: kpiId,
  employeeId: employeeId,
  occurredOn: DateTime.parse(occurredOn),
  quantity: quantity,
  reportedVia: ReportedVia.app,
  confirmedAt: confirmedAt,
);

KpiReading _reading({
  required String kpiId,
  required String period,
  required KpiScope scope,
  String? employeeId,
  String? departmentId,
  num? numerator,
  num? denominator,
}) => KpiReading(
  companyId: 'c',
  kpiId: kpiId,
  period: period,
  scope: scope,
  employeeId: employeeId,
  departmentId: departmentId,
  numerator: numerator,
  denominator: denominator,
  reportedVia: ReportedVia.app,
);

/// A registry source that answers whatever the test wired it to, by scope.
class _FixedSource implements KpiSource {
  _FixedSource(this._key, this._answer);
  final String _key;
  final KpiSourceInput Function(List<String> employeeIds) _answer;

  @override
  String get key => _key;

  @override
  Future<KpiSourceInput> read({
    required KpiScope scope,
    required String period,
    List<String> employeeIds = const [],
  }) async => _answer(employeeIds);
}

/// A registry source whose answer is the SUM of a per-employee table over
/// whichever population it is asked about — the shape a real automatic
/// source (attendance, reviews) actually has. This is what makes a
/// department row a genuine recompute rather than an average of its
/// employees' personal rows.
class _VolumeSource implements KpiSource {
  _VolumeSource(this._key, this._perEmployee);
  final String _key;
  final Map<String, (num numerator, num denominator)> _perEmployee;

  @override
  String get key => _key;

  @override
  Future<KpiSourceInput> read({
    required KpiScope scope,
    required String period,
    List<String> employeeIds = const [],
  }) async {
    if (employeeIds.isEmpty) return (numerator: null, denominator: null);
    num n = 0, d = 0;
    for (final id in employeeIds) {
      final v = _perEmployee[id];
      if (v == null) continue;
      n += v.$1;
      d += v.$2;
    }
    return (numerator: n, denominator: d);
  }
}

KpiResult _only(List<KpiResult> rows, KpiScope scope, {String? employeeId}) =>
    rows.singleWhere(
      (r) => r.scope == scope && r.employeeId == employeeId,
    );

void main() {
  group('HYBRID: registry minus confirmed exceptions', () {
    test(
      '400 fulfilled, two confirmed exceptions -> 398/400, 0.995, ON_TRACK',
      () async {
        final kpi = _kpi(
          dataMethod: 'HYBRID',
          numeratorSource: 'test.fulfillment',
          targetValue: 0.99,
        );
        final registry = {
          'test.fulfillment': _FixedSource(
            'test.fulfillment',
            (_) => (numerator: 400, denominator: 400),
          ),
        };
        final exceptions = [
          _exception(
            kpiId: kpi.id,
            occurredOn: '2026-08-10',
            confirmedAt: DateTime(2026, 8, 11),
          ),
          _exception(
            kpiId: kpi.id,
            occurredOn: '2026-08-12',
            confirmedAt: DateTime(2026, 8, 13),
          ),
        ];

        final rows = await computeResults(
          period: '2026-08',
          kpis: [kpi],
          employees: [_employee('a')],
          roles: const [],
          registry: registry,
          exceptions: exceptions,
          readings: const [],
          roleKpiLinks: const {},
        );

        final row = _only(rows, KpiScope.company);
        expect(row.numerator, 398);
        expect(row.denominator, 400);
        expect(row.value, 0.995);
        expect(row.status, KpiStatus.onTrack);
        expect(row.sourceCompleteness, SourceCompleteness.complete);
      },
    );

    test(
      'registry returns nulls -> NO_DATA/MISSING_SOURCE, numerator stays '
      'null rather than becoming 0 - 2',
      () async {
        final kpi = _kpi(
          dataMethod: 'HYBRID',
          numeratorSource: 'test.fulfillment',
          targetValue: 0.99,
        );
        final registry = {
          'test.fulfillment': _FixedSource(
            'test.fulfillment',
            (_) => (numerator: null, denominator: null),
          ),
        };
        final exceptions = [
          _exception(
            kpiId: kpi.id,
            occurredOn: '2026-08-10',
            confirmedAt: DateTime(2026, 8, 11),
          ),
          _exception(
            kpiId: kpi.id,
            occurredOn: '2026-08-12',
            confirmedAt: DateTime(2026, 8, 13),
          ),
        ];

        final rows = await computeResults(
          period: '2026-08',
          kpis: [kpi],
          employees: [_employee('a')],
          roles: const [],
          registry: registry,
          exceptions: exceptions,
          readings: const [],
          roleKpiLinks: const {},
        );

        final row = _only(rows, KpiScope.company);
        expect(row.numerator, isNull);
        expect(row.status, KpiStatus.noData);
        expect(row.sourceCompleteness, SourceCompleteness.missingSource);
      },
    );
  });

  test(
    'a DIRECT personal KPI: the department row is a recompute over the '
    "department's population, not an average of the personal rows",
    () async {
      final kpi = _kpi(
        id: 'k-vol',
        level: 'PERSONAL',
        rollupType: 'DIRECT',
        dataMethod: 'AUTOMATIC',
        numeratorSource: 'test.volume',
        departmentId: 'd-ops',
        targetValue: 0.5,
      );
      final registry = {
        'test.volume': _VolumeSource('test.volume', {
          // alice: 30/30 = 1.0. bob: 10/50 = 0.2. Averaging those two
          // personal values gives (1.0 + 0.2) / 2 = 0.6. Recomputing the
          // source over the department's combined population gives
          // 40/80 = 0.5 instead — a different number, which is the point.
          'alice': (30, 30),
          'bob': (10, 50),
        }),
      };
      final roles = [_role('r-ops', deptId: 'd-ops')];
      final employees = [
        _employee('alice', roleId: 'r-ops'),
        _employee('bob', roleId: 'r-ops'),
      ];

      final rows = await computeResults(
        period: '2026-08',
        kpis: [kpi],
        employees: employees,
        roles: roles,
        registry: registry,
        exceptions: const [],
        readings: const [],
        roleKpiLinks: {
          'k-vol': {'r-ops'},
        },
      );

      final alice = _only(rows, KpiScope.personal, employeeId: 'alice');
      final bob = _only(rows, KpiScope.personal, employeeId: 'bob');
      final dept = _only(rows, KpiScope.department);
      final company = _only(rows, KpiScope.company);

      expect(alice.value, 1.0);
      expect(bob.value, closeTo(0.2, 1e-9));

      // The recompute: 40/80.
      expect(dept.numerator, 40);
      expect(dept.denominator, 80);
      expect(dept.value, 0.5);
      // The average an aggregation-from-children implementation would
      // produce instead, proven different so this test cannot pass by
      // accident.
      final average = (alice.value! + bob.value!) / 2;
      expect(average, closeTo(0.6, 1e-9));
      expect(dept.value, isNot(closeTo(average, 1e-9)));

      expect(company.numerator, 40);
      expect(company.denominator, 80);

      // personal(alice) + personal(bob) + department + company.
      expect(rows.length, 4);
    },
  );

  test(
    'a PERSONAL row exists only for a holder whose role links the KPI',
    () async {
      final kpi = _kpi(
        id: 'k-linked',
        level: 'PERSONAL',
        rollupType: 'ALIGNED',
        dataMethod: 'MANUAL_PERIODIC',
        departmentId: 'd-ops',
      );
      final roles = [
        _role('r-linked', deptId: 'd-ops'),
        _role('r-unlinked', deptId: 'd-ops'),
      ];
      final employees = [
        _employee('holder', roleId: 'r-linked'),
        _employee('bystander', roleId: 'r-unlinked'),
      ];

      final rows = await computeResults(
        period: '2026-08',
        kpis: [kpi],
        employees: employees,
        roles: roles,
        registry: const {},
        exceptions: const [],
        readings: const [],
        // Only r-linked links this KPI — pure inheritance: a person's KPIs
        // are their role's KPIs, so bystander (r-unlinked) gets no row.
        roleKpiLinks: {
          'k-linked': {'r-linked'},
        },
      );

      final personalRows = rows.where((r) => r.scope == KpiScope.personal);
      expect(personalRows.map((r) => r.employeeId), ['holder']);
    },
  );

  test('a SHARED KPI produces no personal row', () async {
    final kpi = _kpi(
      id: 'k-shared',
      level: 'PERSONAL',
      rollupType: 'SHARED',
      dataMethod: 'MANUAL_PERIODIC',
      departmentId: 'd-ops',
    );
    final roles = [_role('r-ops', deptId: 'd-ops')];
    final employees = [_employee('alice', roleId: 'r-ops')];

    final rows = await computeResults(
      period: '2026-08',
      kpis: [kpi],
      employees: employees,
      roles: roles,
      registry: const {},
      exceptions: const [],
      readings: const [],
      roleKpiLinks: const {},
    );

    expect(rows.any((r) => r.scope == KpiScope.personal), isFalse);
    expect(rows.where((r) => r.scope == KpiScope.department), hasLength(1));
    expect(rows.where((r) => r.scope == KpiScope.company), hasLength(1));
  });

  test(
    'target snapshotting: the row carries the target as it is now, and a '
    'later change to the definition produces a changed snapshot on the '
    'next call rather than rewriting anything already returned',
    () async {
      final employees = [_employee('a')];
      final before = _kpi(dataMethod: 'MANUAL_PERIODIC', targetValue: 10);
      final beforeRows = await computeResults(
        period: '2026-08',
        kpis: [before],
        employees: employees,
        roles: const [],
        registry: const {},
        exceptions: const [],
        readings: const [
          // unused by this KPI's id below; keep readings empty and let the
          // row be NO_DATA — only the snapshot matters for this test.
        ],
        roleKpiLinks: const {},
      );
      expect(_only(beforeRows, KpiScope.company).targetSnapshot, 10);

      // The definition changes; nothing above this function decided that
      // 2026-08 should be recomputed — computeResults itself has no memory
      // and simply reflects whatever Kpi it is handed for the SAME period.
      final after = _kpi(dataMethod: 'MANUAL_PERIODIC', targetValue: 25);
      final afterRows = await computeResults(
        period: '2026-08',
        kpis: [after],
        employees: employees,
        roles: const [],
        registry: const {},
        exceptions: const [],
        readings: const [],
        roleKpiLinks: const {},
      );
      expect(_only(afterRows, KpiScope.company).targetSnapshot, 25);

      // The first call's own row is untouched by the second call — proving
      // "a closed period is not silently revisited" is a property of the
      // CALLER never re-invoking this function for it, not of this
      // function refusing to compute. Demonstrated here by re-reading the
      // very same list object.
      expect(_only(beforeRows, KpiScope.company).targetSnapshot, 10);
    },
  );

  test(
    'MANUAL_PERIODIC reads the numerator and denominator straight from the '
    "period's recorded reading",
    () async {
      final kpi = _kpi(dataMethod: 'MANUAL_PERIODIC', targetValue: 0.75);
      final readings = [
        _reading(
          kpiId: kpi.id,
          period: '2026-08',
          scope: KpiScope.company,
          numerator: 8,
          denominator: 10,
        ),
      ];

      final rows = await computeResults(
        period: '2026-08',
        kpis: [kpi],
        employees: [_employee('a')],
        roles: const [],
        registry: const {},
        exceptions: const [],
        readings: readings,
        roleKpiLinks: const {},
      );

      final row = _only(rows, KpiScope.company);
      expect(row.numerator, 8);
      expect(row.denominator, 10);
      expect(row.value, 0.8);
      expect(row.status, KpiStatus.onTrack);
      expect(row.sourceCompleteness, SourceCompleteness.complete);
    },
  );

  group('MANUAL_EXCEPTION: three zeros', () {
    test('no exception rows at all -> NO_DATA, source complete', () async {
      final kpi = _kpi(
        dataMethod: 'MANUAL_EXCEPTION',
        valueType: 'COUNT',
        targetDirection: 'LOWER',
        targetValue: 0,
      );
      final rows = await computeResults(
        period: '2026-08',
        kpis: [kpi],
        employees: [_employee('a')],
        roles: const [],
        registry: const {},
        exceptions: const [],
        readings: const [],
        roleKpiLinks: const {},
      );
      final row = _only(rows, KpiScope.company);
      expect(row.numerator, isNull);
      expect(row.status, KpiStatus.noData);
      expect(row.sourceCompleteness, SourceCompleteness.complete);
    });

    test(
      'rows exist but all unconfirmed -> NO_DATA, source MISSING',
      () async {
        final kpi = _kpi(
          dataMethod: 'MANUAL_EXCEPTION',
          valueType: 'COUNT',
          targetDirection: 'LOWER',
          targetValue: 0,
        );
        final exceptions = [
          _exception(kpiId: kpi.id, occurredOn: '2026-08-05'),
          _exception(kpiId: kpi.id, occurredOn: '2026-08-06'),
        ];
        final rows = await computeResults(
          period: '2026-08',
          kpis: [kpi],
          employees: [_employee('a')],
          roles: const [],
          registry: const {},
          exceptions: exceptions,
          readings: const [],
          roleKpiLinks: const {},
        );
        final row = _only(rows, KpiScope.company);
        expect(row.numerator, isNull);
        expect(row.status, KpiStatus.noData);
        expect(row.sourceCompleteness, SourceCompleteness.missingSource);
      },
    );

    test(
      'confirmed rows summing to zero is a real result, not NO_DATA',
      () async {
        final kpi = _kpi(
          dataMethod: 'MANUAL_EXCEPTION',
          valueType: 'COUNT',
          targetDirection: 'LOWER',
          targetValue: 0,
        );
        final exceptions = [
          _exception(
            kpiId: kpi.id,
            occurredOn: '2026-08-05',
            quantity: 0,
            confirmedAt: DateTime(2026, 8, 6),
          ),
        ];
        final rows = await computeResults(
          period: '2026-08',
          kpis: [kpi],
          employees: [_employee('a')],
          roles: const [],
          registry: const {},
          exceptions: exceptions,
          readings: const [],
          roleKpiLinks: const {},
        );
        final row = _only(rows, KpiScope.company);
        expect(row.numerator, 0);
        expect(row.status, KpiStatus.onTrack); // 0 <= target of 0.
        expect(row.sourceCompleteness, SourceCompleteness.complete);
      },
    );
  });

  group('MANUAL_EXCEPTION: unattributed rows (no employee_id)', () {
    test(
      'unattributed-only at COMPANY scope is a real number, not NO_DATA',
      () async {
        final kpi = _kpi(
          dataMethod: 'MANUAL_EXCEPTION',
          valueType: 'COUNT',
          targetDirection: 'LOWER',
          targetValue: 5,
        );
        final exceptions = [
          // employeeId omitted: a Lark lookup miss, or a team-level incident.
          _exception(
            kpiId: kpi.id,
            occurredOn: '2026-08-05',
            quantity: 3,
            confirmedAt: DateTime(2026, 8, 6),
          ),
        ];

        final rows = await computeResults(
          period: '2026-08',
          kpis: [kpi],
          employees: [_employee('a')],
          roles: const [],
          registry: const {},
          exceptions: exceptions,
          readings: const [],
          roleKpiLinks: const {},
        );

        final row = _only(rows, KpiScope.company);
        expect(row.numerator, 3);
        expect(row.sourceCompleteness, SourceCompleteness.complete);
      },
    );

    test(
      'unattributed-only at PERSONAL scope is NO_DATA/MISSING_SOURCE, not '
      'a confident zero',
      () async {
        final kpi = _kpi(
          id: 'k-personal-exc',
          level: 'PERSONAL',
          rollupType: 'ALIGNED',
          dataMethod: 'MANUAL_EXCEPTION',
          valueType: 'COUNT',
          targetDirection: 'LOWER',
          targetValue: 5,
        );
        final roles = [_role('r-ops')];
        final employees = [_employee('alice', roleId: 'r-ops')];
        final exceptions = [
          _exception(
            kpiId: kpi.id,
            occurredOn: '2026-08-05',
            quantity: 3,
            confirmedAt: DateTime(2026, 8, 6),
          ),
        ];

        final rows = await computeResults(
          period: '2026-08',
          kpis: [kpi],
          employees: employees,
          roles: roles,
          registry: const {},
          exceptions: exceptions,
          readings: const [],
          roleKpiLinks: {
            'k-personal-exc': {'r-ops'},
          },
        );

        final row = _only(rows, KpiScope.personal, employeeId: 'alice');
        expect(row.numerator, isNull);
        expect(row.status, KpiStatus.noData);
        expect(row.sourceCompleteness, SourceCompleteness.missingSource);
      },
    );

    test(
      'mixed attributed and unattributed rows both count at DEPARTMENT '
      'scope',
      () async {
        final kpi = _kpi(
          id: 'k-dept-exc',
          level: 'PERSONAL',
          rollupType: 'DIRECT',
          dataMethod: 'MANUAL_EXCEPTION',
          valueType: 'COUNT',
          departmentId: 'd-ops',
          targetDirection: 'LOWER',
          targetValue: 5,
        );
        final roles = [_role('r-ops', deptId: 'd-ops')];
        final employees = [_employee('alice', roleId: 'r-ops')];
        final exceptions = [
          _exception(
            kpiId: kpi.id,
            employeeId: 'alice',
            occurredOn: '2026-08-05',
            quantity: 2,
            confirmedAt: DateTime(2026, 8, 6),
          ),
          _exception(
            kpiId: kpi.id,
            occurredOn: '2026-08-07',
            quantity: 3,
            confirmedAt: DateTime(2026, 8, 8),
          ),
        ];

        final rows = await computeResults(
          period: '2026-08',
          kpis: [kpi],
          employees: employees,
          roles: roles,
          registry: const {},
          exceptions: exceptions,
          readings: const [],
          roleKpiLinks: {
            'k-dept-exc': {'r-ops'},
          },
        );

        final dept = _only(rows, KpiScope.department);
        expect(dept.numerator, 5); // 2 (alice) + 3 (unattributed).
        expect(dept.sourceCompleteness, SourceCompleteness.complete);
      },
    );
  });
}
