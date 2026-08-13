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
    required List<Employee> holders,
    List<RoleKpi> roleKpis = _roleKpis,
  }) async {
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wpActiveEmployeesProvider.overrideWith((ref) async => holders),
          wpPersonLoadsProvider.overrideWith(
            (ref) async => [for (final h in holders) _load(h.id)],
          ),
          roleKpisProvider('card-1').overrideWith((ref) async => roleKpis),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: PeoplePane(cardId: 'card-1')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Pure inheritance's whole point: two holders of the same role can no
  // longer disagree about which of the role's KPIs they track. Before this,
  // one holder could have a narrower stored subset than another on the same
  // card — the exact discrepancy this test now proves is impossible.
  testWidgets(
    'every holder of the same role tracks all of the same KPIs',
    (tester) async {
      await pump(
        tester,
        holders: [_emp('e1', 'Marvin'), _emp('e2', 'Alice')],
      );
      expect(find.textContaining('tracks all 3 of 3'), findsNWidgets(2));
    },
  );

  testWidgets('names the holder and their load', (tester) async {
    await pump(tester, holders: [_emp('e1', 'Marvin')]);
    expect(find.textContaining('Marvin'), findsOneWidget);
  });

  testWidgets(
    'a role with no KPIs is flagged on the holder row, not hidden as zero '
    'of zero',
    (tester) async {
      await pump(tester, holders: [_emp('e1', 'Marvin')], roleKpis: const []);
      expect(find.textContaining('Role has no KPIs'), findsOneWidget);
      expect(find.textContaining('tracks all'), findsNothing);
    },
  );

  testWidgets('no per-employee KPI picker remains on this pane', (
    tester,
  ) async {
    await pump(tester, holders: [_emp('e1', 'Marvin')]);
    // The retired curation surface (checkboxes, expandable per-person editor)
    // is gone; the row is a plain read-out.
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.byType(ExpansionTile), findsNothing);
  });
}
