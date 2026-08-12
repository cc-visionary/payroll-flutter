import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/compensation_change.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/kpi.dart';
import 'package:payroll_flutter/data/models/kpi_goal.dart';
import 'package:payroll_flutter/data/models/role_kpi.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/repositories/compensation_change_repository.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';
import 'package:payroll_flutter/features/auth/profile_provider.dart';
import 'package:payroll_flutter/features/employees/profile/tabs/role_tab.dart';

import '../../support/supabase_stub.dart';

/// The employee profile's Role tab is a SECOND place HR curates an employee's
/// KPI set, and until now the only one with no validator: it told HR "an
/// employee with no selection isn't scored" and then let them save exactly
/// that. The three readers that still fall back to the full role set
/// (generate_employee_review, seedSkillRatingsForCheckIn, employeesByKpi) are
/// deliberate safety nets, so the empty set has to be stopped where it is
/// AUTHORED, not where it is read.
final _employee = Employee(
  id: 'emp-1',
  companyId: 'co-1',
  employeeNumber: 'E1',
  firstName: 'Marvin',
  lastName: 'X',
  roleScorecardId: 'card-1',
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

final _card = RoleScorecard(
  id: 'card-1',
  companyId: 'co-1',
  jobTitle: 'Brand Handler',
  missionStatement: 'Ship orders on time.',
  responsibilities: const [],
  kpis: const [],
  wageType: 'MONTHLY',
  workHoursPerDay: 8,
  workDaysPerWeek: 'MON_FRI',
  isActive: true,
  effectiveDate: DateTime(2026, 1, 1),
);

const _defined = Kpi(
  id: 'k1',
  companyId: 'co-1',
  name: 'Return Rate',
  valueType: 'RATIO',
  unit: '%',
  numeratorLabel: 'Returns',
  numeratorSource: 'BigSeller',
  denominatorLabel: 'Orders',
  denominatorSource: 'BigSeller',
);

const _roleKpis = [
  RoleKpi(
    kpiId: 'k1',
    name: 'Return Rate',
    goal: KpiGoal(direction: GoalDirection.lte, value: 3),
    unit: '%',
  ),
];

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initSupabaseStub();
  });

  Future<void> pump(
    WidgetTester tester, {
    required Set<String> assigned,
  }) async {
    tester.view.physicalSize = const Size(1400, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userProfileProvider.overrideWith(
            (ref) async => const UserProfile(
              userId: 'u1',
              email: 'hr@example.com',
              companyId: 'co-1',
              employeeId: null,
              appRole: AppRole.HR,
              mustChangePassword: false,
            ),
          ),
          roleScorecardListProvider.overrideWith((ref) async => [_card]),
          pendingCompensationChangesProvider(
            'emp-1',
          ).overrideWith((ref) async => const <CompensationChange>[]),
          compensationChangesByEmployeeProvider(
            'emp-1',
          ).overrideWith((ref) async => const <CompensationChange>[]),
          roleKpisProvider('card-1').overrideWith((ref) async => _roleKpis),
          kpiLibraryProvider.overrideWith((ref) async => const [_defined]),
          employeeAssignedKpiIdsProvider(
            'emp-1',
          ).overrideWith((ref) async => assigned),
        ],
        child: MaterialApp(
          home: Scaffold(body: RoleTab(employee: _employee)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final saveButton = find.widgetWithText(FilledButton, 'Save KPI selection');

  testWidgets('an empty set cannot be saved from the employee profile', (
    tester,
  ) async {
    await pump(tester, assigned: const {});
    await tester.scrollUntilVisible(saveButton, 300);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Pick at least one KPI'),
      findsOneWidget,
      reason: 'the problem must be stated, not just implied by a dead button',
    );
    expect(
      tester.widget<FilledButton>(saveButton).onPressed,
      isNull,
      reason:
          'saving [] here would leave the person un-scored while the review '
          'generator quietly snapshots the whole role set for them',
    );
  });

  testWidgets('a valid set still saves', (tester) async {
    await pump(tester, assigned: {'k1'});
    await tester.scrollUntilVisible(saveButton, 300);
    await tester.pumpAndSettle();

    expect(find.textContaining('Pick at least one KPI'), findsNothing);
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNotNull);
  });
}
