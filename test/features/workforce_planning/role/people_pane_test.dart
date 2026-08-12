import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/role_kpi.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';
import 'package:payroll_flutter/features/workforce_planning/role/people_pane.dart';
import 'package:payroll_flutter/features/workforce_planning/wp_providers.dart';

import '../../../support/supabase_stub.dart';

Employee _emp(String id, String name) => Employee(
  id: id,
  companyId: 'co-1',
  employeeNumber: id,
  firstName: name,
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

WpPersonLoad _load(String id) => WpPersonLoad(
  employeeId: id,
  companyId: 'co-1',
  capacityHours: 160,
  growthMultiplier: 1,
);

const _roleKpis = [
  RoleKpi(kpiId: 'k1', name: 'Return Rate'),
  RoleKpi(kpiId: 'k2', name: 'Setup Accuracy'),
  RoleKpi(kpiId: 'k3', name: 'On-Time Dispatch'),
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
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wpActiveEmployeesProvider.overrideWith(
            (ref) async => [_emp('e1', 'Marvin')],
          ),
          wpPersonLoadsProvider.overrideWith((ref) async => [_load('e1')]),
          roleKpisProvider('card-1').overrideWith((ref) async => _roleKpis),
          employeeAssignedKpiIdsProvider(
            'e1',
          ).overrideWith((ref) async => assigned),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PeoplePane(cardId: 'card-1'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a holder with no stored set is flagged, not shown as full', (
    tester,
  ) async {
    // Before 20260811000002 an empty set meant "tracks everything", so this
    // person would have read as tracking all three. Under scoring that is the
    // difference between measured-on-three and measured-on-ten.
    await pump(tester, assigned: const {});
    expect(find.textContaining('No KPI set'), findsOneWidget);
    expect(find.textContaining('tracks 3 of 3'), findsNothing);
  });

  testWidgets("shows how many of the role's KPIs a holder tracks", (
    tester,
  ) async {
    await pump(tester, assigned: {'k1', 'k2'});
    expect(find.textContaining('tracks 2 of 3'), findsOneWidget);
    expect(find.textContaining('No KPI set'), findsNothing);
  });

  testWidgets('names the holder and their load', (tester) async {
    await pump(tester, assigned: {'k1'});
    expect(find.textContaining('Marvin'), findsOneWidget);
  });

  testWidgets(
    'a stored set that is entirely off this role reads as no set, not as '
    'zero of three',
    (tester) async {
      // The count line already intersects with the role's KPIs, and
      // initialCheckedKpiIds defines an off-role id as absent — so a holder
      // whose only tracked KPI was just removed from the role read
      // "tracks 0 of 3" with no warning beside it, the one state the chip
      // exists to catch.
      await pump(tester, assigned: {'removed-from-this-role'});
      expect(find.textContaining('No KPI set'), findsOneWidget);
      expect(find.textContaining('tracks 0 of 3'), findsNothing);
    },
  );
}
