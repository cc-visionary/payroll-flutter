import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/tabs/organization_tab.dart';
import 'package:payroll_flutter/features/workforce_planning/wp_providers.dart';

Employee _e(String id, String f, String l, String? mgr, {String? roleId}) =>
    Employee(
  id: id,
  companyId: 'c',
  employeeNumber: id,
  firstName: f,
  lastName: l,
  jobTitle: 'Role $id',
  roleScorecardId: roleId,
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
        child: const MaterialApp(home: Scaffold(body: OrganizationTab())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cy Oh'), findsOneWidget);
    expect(find.text('Coo Boss'), findsOneWidget);
  });

  testWidgets('a box lists what its holder\'s role owns', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wpActiveEmployeesProvider.overrideWith(
            (ref) async => [_e('coo', 'Coo', 'Boss', null, roleId: 'rs1')],
          ),
          wpPersonLoadsProvider.overrideWith((ref) async => const []),
          wpTasksProvider.overrideWith(
            (ref) async => [
              WpTask(
                id: 't1',
                companyId: 'c',
                name: 'Ship orders',
                roleScorecardId: 'rs1',
                responsibilityArea: 'Order Fulfillment',
              ),
              WpTask(
                id: 't2',
                companyId: 'c',
                name: 'Count stock',
                roleScorecardId: 'rs1',
                responsibilityArea: 'Inventory',
              ),
              // Another role's work must not leak onto this box.
              WpTask(
                id: 't3',
                companyId: 'c',
                name: 'Post ads',
                roleScorecardId: 'rs2',
                responsibilityArea: 'Marketing',
              ),
            ],
          ),
          wpConfigProvider.overrideWith((ref) async => null),
        ],
        child: const MaterialApp(home: Scaffold(body: OrganizationTab())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Owns'), findsOneWidget);
    expect(find.text('• Order Fulfillment'), findsOneWidget);
    expect(find.text('• Inventory'), findsOneWidget);
    expect(find.text('• Marketing'), findsNothing);
  });

  testWidgets('a holder whose role owns nothing gets no Owns block', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wpActiveEmployeesProvider.overrideWith(
            (ref) async => [_e('coo', 'Coo', 'Boss', null, roleId: 'rs1')],
          ),
          wpPersonLoadsProvider.overrideWith((ref) async => const []),
          wpTasksProvider.overrideWith((ref) async => const []),
          wpConfigProvider.overrideWith((ref) async => null),
        ],
        child: const MaterialApp(home: Scaffold(body: OrganizationTab())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Coo Boss'), findsOneWidget);
    expect(find.text('Owns'), findsNothing);
  });
}
