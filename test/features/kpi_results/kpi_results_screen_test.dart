import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/kpi.dart';
import 'package:payroll_flutter/data/models/kpi_input.dart';
import 'package:payroll_flutter/data/models/kpi_result.dart';
import 'package:payroll_flutter/data/repositories/employee_repository.dart';
import 'package:payroll_flutter/data/repositories/kpi_result_repository.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';
import 'package:payroll_flutter/features/kpi_results/kpi_results_screen.dart';

import '../../support/supabase_stub.dart';

/// Records what `_recompute` hands to `upsertAll`, instead of writing
/// anywhere real. Every other method a recompute could reach
/// (`listByPeriod`, `readingsFor`, `exceptionsFor`) is overridden too, so
/// this repository never touches the stub Supabase client either.
class _FakeKpiResultRepository extends KpiResultRepository {
  _FakeKpiResultRepository(super.client, {this.readings = const []});

  final List<KpiReading> readings;

  /// Null until a recompute calls `upsertAll` -- the load-bearing signal.
  /// A recompute that silently wrote nothing leaves this null, same as one
  /// that was never pressed; only the row CONTENTS distinguish "wrote the
  /// right thing" from "wrote something".
  List<KpiResult>? upserted;

  @override
  Future<List<KpiResult>> listByPeriod(String period, {String? kpiId}) async =>
      const [];

  @override
  Future<List<KpiReading>> readingsFor(String period) async => readings;

  @override
  Future<List<KpiException>> exceptionsFor(String kpiId, String period) async =>
      const [];

  @override
  Future<void> upsertAll(List<KpiResult> rows) async {
    upserted = rows;
  }
}

Employee _employee(String id, {String? roleId}) => Employee(
  id: id,
  companyId: 'c',
  employeeNumber: id,
  firstName: id,
  lastName: 'X',
  roleScorecardId: roleId,
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

KpiResult _r({
  required String kpiId,
  required KpiStatus status,
  num? value,
  num? target,
}) => KpiResult(
  id: 'res-$kpiId',
  companyId: 'c',
  kpiId: kpiId,
  period: '2026-08',
  scope: KpiScope.company,
  value: value,
  targetSnapshot: target,
  status: status,
  sourceCompleteness: status == KpiStatus.noData
      ? SourceCompleteness.missingSource
      : SourceCompleteness.complete,
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initSupabaseStub();
  });

  Future<void> pump(WidgetTester tester, List<KpiResult> rows) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          kpiResultsForPeriodProvider('2026-08').overrideWith((ref) async => rows),
        ],
        child: const MaterialApp(home: KpiResultsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a NO_DATA row does not read the same as an OFF_TRACK row', (
    tester,
  ) async {
    // The whole point of the status rule, made visible. If these two ever
    // render identically the rule is correct and the screen still lies.
    await pump(tester, [
      _r(kpiId: 'k-miss', status: KpiStatus.noData),
      _r(kpiId: 'k-bad', status: KpiStatus.offTrack, value: 0.80, target: 0.99),
    ]);
    expect(find.text('No data'), findsOneWidget);
    expect(find.text('Off track'), findsOneWidget);
  });

  testWidgets('a NO_DATA row shows no invented value', (tester) async {
    await pump(tester, [_r(kpiId: 'k-miss', status: KpiStatus.noData)]);
    expect(find.text('0'), findsNothing);
    expect(find.text('0%'), findsNothing);
  });

  testWidgets('a month with no results says so', (tester) async {
    await pump(tester, const []);
    expect(find.textContaining('No results'), findsOneWidget);
  });

  testWidgets(
    '"Recompute this month" runs computeResults and hands real rows to upsertAll',
    (tester) async {
      // A MANUAL_PERIODIC, COMPANY-level, INDEPENDENT-rollup KPI: the
      // simplest shape that produces exactly one row (company scope only,
      // per kpi_rollup.dart's default case) from a single recorded reading,
      // with no automatic source or role-link plumbing needed to reach it.
      final kpi = Kpi(
        id: 'k-1',
        companyId: 'c',
        name: 'Test KPI',
        level: 'COMPANY',
        rollupType: 'INDEPENDENT',
        dataMethod: 'MANUAL_PERIODIC',
        valueType: 'COUNT',
        targetDirection: 'HIGHER',
        targetValue: 10,
      );
      final reading = KpiReading(
        companyId: 'c',
        kpiId: 'k-1',
        period: '2026-08',
        scope: KpiScope.company,
        numerator: 42,
        reportedVia: ReportedVia.app,
      );
      final fakeRepo = _FakeKpiResultRepository(
        Supabase.instance.client,
        readings: [reading],
      );

      tester.view.physicalSize = const Size(1400, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            kpiResultsForPeriodProvider('2026-08').overrideWith((ref) async => const []),
            kpiLibraryProvider.overrideWith((ref) async => [kpi]),
            employeeListProvider(
              const EmployeeListQuery(),
            ).overrideWith((ref) async => [_employee('e1')]),
            roleScorecardListProvider.overrideWith((ref) async => const []),
            kpiRoleIdsByKpiProvider.overrideWith((ref) async => const {}),
            kpiResultRepositoryProvider.overrideWith((ref) => fakeRepo),
          ],
          child: const MaterialApp(home: KpiResultsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(fakeRepo.upserted, isNull); // nothing written before the press

      await tester.tap(find.text('Recompute this month'));
      await tester.pumpAndSettle();

      final written = fakeRepo.upserted;
      expect(written, isNotNull);
      expect(written, hasLength(1));
      expect(written!.single.kpiId, 'k-1');
      expect(written.single.scope, KpiScope.company);
      // The reading's numerator, not merely "something non-null" -- proves
      // the row came from computeResults reading THIS reading, not from a
      // recompute that ran and wrote an empty or placeholder row.
      expect(written.single.numerator, 42);
      expect(written.single.value, 42);
      expect(written.single.status, KpiStatus.onTrack); // 42 >= target 10
    },
  );
}
