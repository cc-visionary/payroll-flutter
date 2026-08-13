import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initSupabaseStub();
  });

  /// `createdAt` is fixed at 2026-08-15 so "the last three months" always
  /// resolves to 2026-06/07/08 regardless of the real wall-clock date the
  /// suite happens to run on.
  Future<void> pumpCheckIn(
    WidgetTester tester, {
    required String employeeId,
    required List<KpiResult> results,
  }) async {
    final checkIn = PerformanceCheckIn(
      id: 'ci-1',
      periodId: 'p-1',
      employeeId: employeeId,
      status: 'DRAFT',
      createdAt: DateTime(2026, 8, 15),
      updatedAt: DateTime(2026, 8, 15),
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
          checkInPeriodByIdProvider('p-1').overrideWith((ref) async => null),
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

  testWidgets('shows three months of the employee\'s own KPI results', (
    tester,
  ) async {
    await pumpCheckIn(
      tester,
      employeeId: 'e-1',
      results: [
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
        _personal(
          kpiId: 'k-1',
          period: '2026-08',
          value: 0.995,
          status: KpiStatus.onTrack,
        ),
      ],
    );
    expect(find.text('2026-06'), findsOneWidget);
    expect(find.text('2026-07'), findsOneWidget);
    expect(find.text('2026-08'), findsOneWidget);
  });

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
}
