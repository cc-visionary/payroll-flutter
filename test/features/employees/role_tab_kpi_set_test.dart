import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/compensation_change.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/repositories/compensation_change_repository.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';
import 'package:payroll_flutter/features/auth/profile_provider.dart';
import 'package:payroll_flutter/features/employees/profile/tabs/role_tab.dart';

import '../../support/supabase_stub.dart';

/// Pure inheritance retired the employee profile's KPI-set editor: an
/// employee's KPIs are their role's KPIs, with no per-employee subset to
/// curate. The Role tab's "Current Role" section already renders the role's
/// KPIs read-only (from `card.kpis`); this file used to guard the second,
/// now-removed curation surface (`EmployeeKpiAssignmentSection` mounted here)
/// and is retargeted to guard its absence instead of being deleted outright,
/// since "the Role tab shows an employee's KPIs" is still a real rule — it
/// just means something different now.
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
  kpis: const [
    KpiItem(
      name: 'Return Rate',
      measurement: '%',
      target: '≤3%',
      frequency: 'Weekly',
    ),
  ],
  wageType: 'MONTHLY',
  workHoursPerDay: 8,
  workDaysPerWeek: 'MON_FRI',
  isActive: true,
  effectiveDate: DateTime(2026, 1, 1),
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initSupabaseStub();
  });

  Future<void> pump(WidgetTester tester) async {
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
        ],
        child: MaterialApp(
          home: Scaffold(body: RoleTab(employee: _employee)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    "shows the role's KPIs, inherited and read-only — no curation UI",
    (tester) async {
      await pump(tester);

      expect(find.textContaining('Return Rate'), findsOneWidget);
      // The retired curation surface is gone entirely: no Save button, no
      // per-KPI checkboxes.
      expect(
        find.widgetWithText(FilledButton, 'Save KPI selection'),
        findsNothing,
      );
      expect(find.byType(CheckboxListTile), findsNothing);
    },
  );
}
