import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/features/workforce_planning/org_tree_view.dart';

Employee _e(String id, String f, String l, String? mgr) => Employee(
      id: id, companyId: 'c', employeeNumber: id, firstName: f, lastName: l,
      jobTitle: 'Role $id', reportsToId: mgr, employmentType: 'FULL_TIME',
      employmentStatus: 'ACTIVE', hireDate: DateTime(2024, 1, 1), isRankAndFile: true,
      isOtEligible: false, isNdEligible: false, isHolidayPayEligible: false,
      sssEligibilityOverride: false, philhealthEligibilityOverride: false,
      pagibigEligibilityOverride: false, taxOnFullEarnings: false);

void main() {
  testWidgets('renders the reporting hierarchy (manager + report)', (tester) async {
    final emps = {'ceo': _e('ceo', 'Cy', 'Oh', null), 'coo': _e('coo', 'Coo', 'Boss', 'ceo')};
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: OrgTreeView(
      people: const [(id: 'ceo', parentId: null), (id: 'coo', parentId: 'ceo')],
      empById: emps,
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Cy Oh'), findsOneWidget);
    expect(find.text('Coo Boss'), findsOneWidget);
  });
}
