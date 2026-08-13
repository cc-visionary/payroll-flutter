import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:payroll_flutter/data/models/check_in_period.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/kpi_result.dart';
import 'package:payroll_flutter/data/models/performance_check_in.dart';
import 'package:payroll_flutter/data/repositories/employee_repository.dart';
import 'package:payroll_flutter/data/repositories/kpi_result_repository.dart';
import 'package:payroll_flutter/data/repositories/performance_repository.dart';
import 'package:payroll_flutter/features/auth/profile_provider.dart';
import 'package:payroll_flutter/features/performance/performance_check_in_screen.dart';

import '../../support/supabase_stub.dart';

/// Answers `listByPeriod` from an in-memory list instead of the stub
/// Supabase client -- mirrors the RLS reality the screen must defend
/// against on its own: a period read returns every scope/employee's row the
/// caller's company-wide RLS admits (the employee, their manager, and HR can
/// all see a PERSONAL row belonging to someone else at the same company), so
/// this fake deliberately does NOT pre-filter by employee. Whatever
/// isolation the screen shows has to come from the screen's own code, not
/// from this fake doing the job for it.
class _FakeKpiResultRepository extends KpiResultRepository {
  _FakeKpiResultRepository(super.client, {required this.rows});

  final List<KpiResult> rows;

  @override
  Future<List<KpiResult>> listByPeriod(String period, {String? kpiId}) async {
    return rows.where((r) => r.period == period).toList();
  }
}

KpiResult _personal({
  required String kpiId,
  required String period,
  required KpiStatus status,
  num? value,
  String employeeId = 'e-1',
}) => KpiResult(
  companyId: 'c',
  kpiId: kpiId,
  period: period,
  scope: KpiScope.personal,
  employeeId: employeeId,
  value: value,
  status: status,
);

Employee _employee(String id) => Employee(
  id: id,
  companyId: 'c',
  employeeNumber: id,
  firstName: id,
  lastName: 'X',
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

CheckInPeriod _period({
  required String id,
  required DateTime startDate,
  required DateTime endDate,
}) => CheckInPeriod(
  id: id,
  companyId: 'c',
  name: 'Q',
  periodType: 'QUARTERLY',
  startDate: startDate,
  endDate: endDate,
  dueDate: endDate.add(const Duration(days: 15)),
  isActive: true,
  createdAt: startDate,
  updatedAt: startDate,
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initSupabaseStub();
  });

  /// Defaults to a period ending 2026-08-31, so "the last three months"
  /// resolves to 2026-06/07/08 regardless of the real wall-clock date the
  /// suite happens to run on. `createdAt` defaults to a date INSIDE that
  /// same window on purpose, but is otherwise irrelevant to the months
  /// shown -- see the dedicated test below that puts them in different
  /// quarters to prove the anchor really comes from the period.
  Future<void> pumpCheckIn(
    WidgetTester tester, {
    required String employeeId,
    required List<KpiResult> results,
    CheckInPeriod? period,
    DateTime? createdAt,
  }) async {
    final resolvedPeriod =
        period ??
        _period(
          id: 'p-1',
          startDate: DateTime(2026, 6, 1),
          endDate: DateTime(2026, 8, 31),
        );
    final checkIn = PerformanceCheckIn(
      id: 'ci-1',
      periodId: resolvedPeriod.id,
      employeeId: employeeId,
      status: 'DRAFT',
      createdAt: createdAt ?? DateTime(2026, 8, 15),
      updatedAt: createdAt ?? DateTime(2026, 8, 15),
    );
    final fakeRepo = _FakeKpiResultRepository(
      Supabase.instance.client,
      rows: results,
    );

    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          performanceCheckInByIdProvider('ci-1').overrideWith(
            (ref) async => checkIn,
          ),
          checkInPeriodByIdProvider(
            resolvedPeriod.id,
          ).overrideWith((ref) async => resolvedPeriod),
          checkInGoalsProvider('ci-1').overrideWith((ref) async => const []),
          skillRatingsProvider('ci-1').overrideWith((ref) async => const []),
          employeeByIdProvider(
            employeeId,
          ).overrideWith((ref) async => _employee(employeeId)),
          userProfileProvider.overrideWith(
            (ref) async => UserProfile(
              userId: 'u-$employeeId',
              email: 'x@example.com',
              companyId: 'c',
              employeeId: employeeId,
              appRole: AppRole.EMPLOYEE,
              mustChangePassword: false,
            ),
          ),
          kpiResultRepositoryProvider.overrideWith((ref) => fakeRepo),
        ],
        child: const MaterialApp(
          home: PerformanceCheckInScreen(checkInId: 'ci-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'shows three months of the employee\'s own KPI results, in order',
    (tester) async {
      // Fed deliberately OUT of chronological order -- asserting the order
      // you supplied proves nothing about the sort (kpi_dashboard_screen_test.dart
      // makes the same point for its own off-track-first sort).
      await pumpCheckIn(
        tester,
        employeeId: 'e-1',
        results: [
          _personal(
            kpiId: 'k-1',
            period: '2026-08',
            value: 0.995,
            status: KpiStatus.onTrack,
          ),
          _personal(
            kpiId: 'k-1',
            period: '2026-06',
            value: 0.98,
            status: KpiStatus.onTrack,
          ),
          _personal(
            kpiId: 'k-1',
            period: '2026-07',
            value: 0.91,
            status: KpiStatus.offTrack,
          ),
        ],
      );
      expect(find.text('2026-06'), findsOneWidget);
      expect(find.text('2026-07'), findsOneWidget);
      expect(find.text('2026-08'), findsOneWidget);

      final shownOrder = tester
          .widgetList<Text>(find.byKey(const ValueKey('kpi-history-period')))
          .map((t) => t.data)
          .toList();
      expect(shownOrder, ['2026-06', '2026-07', '2026-08']);
    },
  );

  testWidgets('another employee\'s rows never appear', (tester) async {
    await pumpCheckIn(
      tester,
      employeeId: 'e-1',
      results: [
        _personal(
          kpiId: 'k-1',
          period: '2026-08',
          value: 0.99,
          status: KpiStatus.onTrack,
          employeeId: 'e-2',
        ),
      ],
    );
    expect(find.text('2026-08'), findsNothing);
  });

  testWidgets('a month with no result reads as no data, not as zero', (
    tester,
  ) async {
    await pumpCheckIn(
      tester,
      employeeId: 'e-1',
      results: [
        _personal(kpiId: 'k-1', period: '2026-08', status: KpiStatus.noData),
      ],
    );
    expect(find.text('No data'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets(
    "the window comes from the check-in's period, not from createdAt",
    (tester) async {
      // The period covers Q1 2026 (Jan-Mar), so the correct window is
      // 2026-01/02/03. createdAt is in April -- a DIFFERENT quarter,
      // reproducing a late/off-cycle generation (auto_generate.dart lets an
      // admin run Q1 generation any time, including in April). A `createdAt`
      // anchor would wrongly show Feb/Mar/Apr instead.
      await pumpCheckIn(
        tester,
        employeeId: 'e-1',
        period: _period(
          id: 'p-q1',
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 3, 31),
        ),
        createdAt: DateTime(2026, 4, 15),
        results: [
          // Only inside the CORRECT (period-anchored) window.
          _personal(
            kpiId: 'k-1',
            period: '2026-01',
            value: 1,
            status: KpiStatus.onTrack,
          ),
          // Only inside the WRONG (createdAt-anchored) window.
          _personal(
            kpiId: 'k-1',
            period: '2026-04',
            value: 1,
            status: KpiStatus.onTrack,
          ),
        ],
      );
      expect(find.text('2026-01'), findsOneWidget);
      expect(find.text('2026-04'), findsNothing);
    },
  );
}
