import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/tabs/balance_tab.dart';
import 'package:payroll_flutter/features/workforce_planning/wp_providers.dart';

Employee _emp(String id, String first, String last, String title) => Employee(
      id: id, companyId: 'c', employeeNumber: id, firstName: first,
      lastName: last, jobTitle: title, employmentType: 'FULL_TIME',
      employmentStatus: 'ACTIVE', hireDate: DateTime(2024, 1, 1),
      isRankAndFile: true, isOtEligible: false, isNdEligible: false,
      isHolidayPayEligible: false, sssEligibilityOverride: false,
      philhealthEligibilityOverride: false, pagibigEligibilityOverride: false,
      taxOnFullEarnings: false);

void main() {
  testWidgets('renders one row per person with an Over chip for >100%', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        wpPersonLoadsProvider.overrideWith((ref) async => const [
          WpPersonLoad(employeeId: 'e1', companyId: 'c', tasksOwned: 6,
              hoursFixed: 210, hoursGrowingBase: 0, capacityHours: 160, growthMultiplier: 1),
        ]),
        wpActiveEmployeesProvider.overrideWith((ref) async => [_emp('e1', 'Marvin', 'Ong', 'Sys')]),
        wpKpiCountByEmployeeProvider.overrideWith((ref) async => {'e1': 4}),
        wpConfigProvider.overrideWith((ref) async => null),
      ],
      child: const MaterialApp(home: Scaffold(body: BalanceTab())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Marvin Ong'), findsOneWidget);
    expect(find.text('Over'), findsOneWidget);   // 210/160 = 131%
    expect(find.text('131%'), findsOneWidget);
    expect(find.text('4'), findsWidgets);        // KPIs column
  });
}
