import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/tabs/role_view_tab.dart';
import 'package:payroll_flutter/features/workforce_planning/wp_providers.dart';

Employee _emp(String id, String first, String last) => Employee(
      id: id, companyId: 'c', employeeNumber: id, firstName: first, lastName: last,
      jobTitle: 'Sys', employmentType: 'FULL_TIME', employmentStatus: 'ACTIVE',
      hireDate: DateTime(2024, 1, 1), isRankAndFile: true, isOtEligible: false,
      isNdEligible: false, isHolidayPayEligible: false, sssEligibilityOverride: false,
      philhealthEligibilityOverride: false, pagibigEligibilityOverride: false,
      taxOnFullEarnings: false);

void main() {
  testWidgets('picking a person shows their owned tasks', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        wpActiveEmployeesProvider.overrideWith((ref) async => [_emp('e1', 'Marvin', 'Ong')]),
        wpNodesProvider.overrideWith((ref) async => const [
          WpNode(id: 'n2', companyId: 'c', code: '2', name: '2. Configure')]),
        wpPersonLoadsProvider.overrideWith((ref) async => const [
          WpPersonLoad(employeeId: 'e1', companyId: 'c', tasksOwned: 1,
              hoursFixed: 0, hoursGrowingBase: 20, capacityHours: 160, growthMultiplier: 1)]),
        wpTasksProvider.overrideWith((ref) async => const [
          WpTask(id: 't1', companyId: 'c', name: 'SD flash', nodeId: 'n2',
              ownerEmployeeId: 'e1', cadence: 'Per-unit', skillTier: 'Transactional')]),
        wpConfigProvider.overrideWith((ref) async => null),
        ownerComputedProvider('e1').overrideWith((ref) async => const [
          WpTaskComputed(taskId: 't1', companyId: 'c', hoursPerMonthBase: 20,
              isGrowing: true, skillTier: 'Transactional'),
        ]),
      ],
      child: const MaterialApp(home: Scaffold(body: RoleViewTab())),
    ));
    await tester.pumpAndSettle();
    // Person auto-selected (single person):
    expect(find.text('SD flash'), findsOneWidget);
    expect(find.text('2. Configure'), findsOneWidget);
  });
}
