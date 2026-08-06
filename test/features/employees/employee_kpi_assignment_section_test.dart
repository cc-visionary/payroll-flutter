import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/role_kpi.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';
import 'package:payroll_flutter/features/employees/profile/tabs/role_tab.dart';

void main() {
  testWidgets('shows the role KPIs, all checked when un-curated', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roleKpisProvider('role-1').overrideWith(
            (ref) async => const [
              RoleKpi(kpiId: 'a', name: 'Order Accuracy'),
              RoleKpi(kpiId: 'b', name: 'On-Time Dispatch'),
            ],
          ),
          employeeAssignedKpiIdsProvider(
            'emp-1',
          ).overrideWith((ref) async => <String>{}),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: EmployeeKpiAssignmentSection(
              employeeId: 'emp-1',
              roleScorecardId: 'role-1',
              canManage: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Order Accuracy'), findsOneWidget);
    expect(find.text('On-Time Dispatch'), findsOneWidget);
    // Un-curated: both boxes checked (default = full role set).
    final boxes = tester.widgetList<CheckboxListTile>(
      find.byType(CheckboxListTile),
    );
    expect(boxes.length, 2);
    expect(boxes.every((b) => b.value == true), isTrue);
  });
}
