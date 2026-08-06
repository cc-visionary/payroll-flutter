import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/features/workforce_planning/tabs/structure_tab.dart';
import 'package:payroll_flutter/features/workforce_planning/wp_providers.dart';

Employee _e(String id, String f, String l, String? mgr) => Employee(
  id: id,
  companyId: 'c',
  employeeNumber: id,
  firstName: f,
  lastName: l,
  jobTitle: 'Role $id',
  reportsToId: mgr,
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
  testWidgets('renders the reporting tree (manager + report)', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wpActiveEmployeesProvider.overrideWith(
            (ref) async => [
              _e('ceo', 'Cy', 'Oh', null),
              _e('coo', 'Coo', 'Boss', 'ceo'),
            ],
          ),
          wpPersonLoadsProvider.overrideWith((ref) async => const []),
          wpTasksProvider.overrideWith((ref) async => const []),
          wpConfigProvider.overrideWith((ref) async => null),
        ],
        child: const MaterialApp(home: Scaffold(body: StructureTab())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cy Oh'), findsOneWidget);
    expect(find.text('Coo Boss'), findsOneWidget);
  });
}
