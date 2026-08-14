import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/kpi_result.dart';
import 'package:payroll_flutter/features/kpi_results/source_rows.dart';

const _toEmployee = {'alice@x': 'e-alice', 'bob@x': 'e-bob'};
const _toDepartment = {'e-alice': 'd-ops', 'e-bob': 'd-ops', 'e-cara': 'd-mkt'};

List<SourceRow> get _rows => const [
  SourceRow(subjectKey: 'alice@x', numerator: 30, denominator: 30),
  SourceRow(subjectKey: 'bob@x', numerator: 10, denominator: 50),
];

({num? numerator, num? denominator, bool unresolvedPresent}) run({
  List<SourceRow>? rows,
  KpiScope scope = KpiScope.company,
  SubjectKind subjectKind = SubjectKind.employee,
  Map<String, String> subjectToEmployee = _toEmployee,
  String? employeeId,
  String? departmentId,
}) => aggregateSourceRows(
  rows: rows ?? _rows,
  scope: scope,
  subjectKind: subjectKind,
  subjectToEmployee: subjectToEmployee,
  employeeToDepartment: _toDepartment,
  employeeId: employeeId,
  departmentId: departmentId,
);

void main() {
  group('wider scopes SUM, they do not average', () {
    test('company sums numerator and denominator separately', () {
      // The whole reason rows carry both. Averaging the two ratios would
      // give 0.6; the correct answer is 40/80 = 0.5. The fixture uses
      // DIFFERENT volumes so the two answers cannot coincide.
      final r = run();
      expect(r.numerator, 40);
      expect(r.denominator, 80);
    });

    test('department sums only that department', () {
      final r = run(scope: KpiScope.department, departmentId: 'd-ops');
      expect(r.numerator, 40);
      expect(r.denominator, 80);
    });

    test('a department nobody belongs to is empty, not everyone', () {
      final r = run(scope: KpiScope.department, departmentId: 'd-mkt');
      expect(r.numerator, isNull);
      expect(r.denominator, isNull);
    });
  });

  group('personal scope', () {
    test('picks that employee only', () {
      final r = run(scope: KpiScope.personal, employeeId: 'e-bob');
      expect(r.numerator, 10);
      expect(r.denominator, 50);
    });

    test('an employee with no row is NO DATA, not zero', () {
      final r = run(scope: KpiScope.personal, employeeId: 'e-cara');
      expect(r.numerator, isNull);
      expect(r.denominator, isNull);
    });

    test('personal with no employeeId resolves to nobody, never everyone', () {
      final r = run(scope: KpiScope.personal);
      expect(r.numerator, isNull);
    });
  });

  group('unresolved subjects', () {
    test('count toward COMPANY and flag the result', () {
      // An unmapped key still happened. It must not vanish from a company
      // total, but it cannot be attributed to a department either.
      final r = run(
        rows: const [
          SourceRow(subjectKey: 'alice@x', numerator: 30, denominator: 30),
          SourceRow(subjectKey: 'ghost@x', numerator: 5, denominator: 5),
        ],
      );
      expect(r.numerator, 35);
      expect(r.denominator, 35);
      expect(r.unresolvedPresent, isTrue);
    });

    test('are EXCLUDED from a department but still flag it', () {
      final r = run(
        rows: const [
          SourceRow(subjectKey: 'alice@x', numerator: 30, denominator: 30),
          SourceRow(subjectKey: 'ghost@x', numerator: 5, denominator: 5),
        ],
        scope: KpiScope.department,
        departmentId: 'd-ops',
      );
      expect(r.numerator, 30, reason: 'the ghost has no department');
      expect(r.unresolvedPresent, isTrue);
    });

    test('all-resolved does not flag', () {
      expect(run().unresolvedPresent, isFalse);
    });

    test(
      'an unresolved row still flags PERSONAL even though it cannot be '
      "this employee's own row",
      () {
        // ghost@x cannot literally be e-bob's row, but there is no way to
        // know that from here — an unmapped key might be a second identity
        // for the requested employee (see the doc comment on
        // unresolvedPresent's computation in source_rows.dart). So the flag
        // stays global: Bob's own figure (10/50) is untouched, but the
        // result still says "incomplete", never a bare COMPLETE 10/50.
        final r = run(
          rows: const [
            SourceRow(subjectKey: 'bob@x', numerator: 10, denominator: 50),
            SourceRow(subjectKey: 'ghost@x', numerator: 5, denominator: 5),
          ],
          scope: KpiScope.personal,
          employeeId: 'e-bob',
        );
        expect(r.numerator, 10);
        expect(r.denominator, 50);
        expect(r.unresolvedPresent, isTrue);
      },
    );
  });

  group('subject kinds', () {
    test('DEPARTMENT rows key on the department directly', () {
      final r = aggregateSourceRows(
        rows: const [
          SourceRow(subjectKey: 'd-ops', numerator: 8, denominator: 10),
          SourceRow(subjectKey: 'd-mkt', numerator: 2, denominator: 10),
        ],
        scope: KpiScope.department,
        subjectKind: SubjectKind.department,
        subjectToEmployee: const {},
        employeeToDepartment: const {},
        departmentId: 'd-ops',
      );
      expect(r.numerator, 8);
      expect(r.denominator, 10);
    });

    test(
      'DEPARTMENT rows roll up into COMPANY the same way employee rows do',
      () {
        // No department filter at COMPANY scope — every department's rows
        // contribute, mirroring how an employee-kind row rolls up to
        // COMPANY regardless of which department it belongs to.
        final r = aggregateSourceRows(
          rows: const [
            SourceRow(subjectKey: 'd-ops', numerator: 8, denominator: 10),
            SourceRow(subjectKey: 'd-mkt', numerator: 2, denominator: 10),
          ],
          scope: KpiScope.company,
          subjectKind: SubjectKind.department,
          subjectToEmployee: const {},
          employeeToDepartment: const {},
        );
        expect(r.numerator, 10);
        expect(r.denominator, 20);
      },
    );

    test('DEPARTMENT rows cannot produce a personal figure', () {
      final r = aggregateSourceRows(
        rows: const [SourceRow(subjectKey: 'd-ops', numerator: 8)],
        scope: KpiScope.personal,
        subjectKind: SubjectKind.department,
        subjectToEmployee: const {},
        employeeToDepartment: const {},
        employeeId: 'e-alice',
      );
      expect(r.numerator, isNull);
    });

    test('NONE is a single company figure', () {
      final r = aggregateSourceRows(
        rows: const [SourceRow(subjectKey: '', numerator: 123)],
        scope: KpiScope.company,
        subjectKind: SubjectKind.none,
        subjectToEmployee: const {},
        employeeToDepartment: const {},
      );
      expect(r.numerator, 123);
    });

    test('NONE cannot produce a department figure', () {
      final r = aggregateSourceRows(
        rows: const [SourceRow(subjectKey: '', numerator: 123)],
        scope: KpiScope.department,
        subjectKind: SubjectKind.none,
        subjectToEmployee: const {},
        employeeToDepartment: const {},
        departmentId: 'd-ops',
      );
      expect(r.numerator, isNull);
    });

    test('NONE cannot produce a personal figure', () {
      final r = aggregateSourceRows(
        rows: const [SourceRow(subjectKey: '', numerator: 123)],
        scope: KpiScope.personal,
        subjectKind: SubjectKind.none,
        subjectToEmployee: const {},
        employeeToDepartment: const {},
        employeeId: 'e-alice',
      );
      expect(r.numerator, isNull);
    });
  });

  group('degenerate input', () {
    test('no rows at all is NO DATA, not zero', () {
      final r = run(rows: const []);
      expect(r.numerator, isNull);
      expect(r.denominator, isNull);
    });

    test('a null denominator column stays null, it does not become zero', () {
      // COUNT KPIs have no denominator. Coercing to 0 would make every
      // ratio a division by zero instead of an honest count.
      final r = run(
        rows: const [SourceRow(subjectKey: 'alice@x', numerator: 4)],
      );
      expect(r.numerator, 4);
      expect(r.denominator, isNull);
    });

    test('rows present but all values null is NO DATA', () {
      final r = run(rows: const [SourceRow(subjectKey: 'alice@x')]);
      expect(r.numerator, isNull);
    });
  });
}
