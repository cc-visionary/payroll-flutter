import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/role_kpi.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';
import 'package:payroll_flutter/features/employees/profile/tabs/role_tab.dart';
import 'package:payroll_flutter/features/kpi_library/kpi_set_rules.dart';

void main() {
  testWidgets('shows the role KPIs, none checked when un-curated', (
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
    // Un-curated (empty stored set): neither box checked — nobody has chosen
    // yet, which is the gap this task now lets the app flag.
    final boxes = tester.widgetList<CheckboxListTile>(
      find.byType(CheckboxListTile),
    );
    expect(boxes.length, 2);
    expect(boxes.every((b) => b.value == false), isTrue);
    // The un-curated copy must not claim everything is tracked — that would
    // contradict the zero ticked boxes right below it.
    expect(find.textContaining('Tracking all role KPIs'), findsNothing);
    expect(find.textContaining('No KPIs selected yet'), findsOneWidget);
  });

  testWidgets(
    'ticking an unmeasurable KPI disables Save and shows the problem',
    (tester) async {
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
            ).overrideWith((ref) async => {'a'}),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: EmployeeKpiAssignmentSection(
                employeeId: 'emp-1',
                roleScorecardId: 'role-1',
                canManage: true,
                // Only 'a' has a goal/definition on this role — 'b' is
                // still one of the role's own KPIs (so it's tickable) but
                // is not yet measurable.
                validate: (checked) => validateKpiSet(
                  selectedKpiIds: checked,
                  roleKpiIds: const {'a', 'b'},
                  measurableKpiIds: const {'a'},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Sanity: starts enabled — one measurable KPI selected is only a
      // below-band warning, not a problem.
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );

      // 'b' is the second CheckboxListTile (role order: a, then b).
      await tester.tap(find.byType(CheckboxListTile).at(1));
      await tester.pump();

      expect(find.textContaining('not measurable yet'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'two measurable KPIs show the 3-5 warning and Save stays enabled',
    (tester) async {
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
            ).overrideWith((ref) async => {'a', 'b'}),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: EmployeeKpiAssignmentSection(
                employeeId: 'emp-1',
                roleScorecardId: 'role-1',
                canManage: true,
                validate: (checked) => validateKpiSet(
                  selectedKpiIds: checked,
                  roleKpiIds: const {'a', 'b'},
                  measurableKpiIds: const {'a', 'b'},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Below the 3-5 band is a warning, never a problem — Save must stay
      // enabled, proving warnings and problems are not conflated.
      expect(find.textContaining('Fewer than 3 KPIs'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'without a validator, the existing employee-profile behaviour is unchanged',
    (tester) async {
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
                // No `validate` passed. Both real call sites supply one now
                // (see role_tab_kpi_set_test.dart); this pins the widget's
                // own null-validator contract so a future read-only host is
                // not forced to invent a verdict.
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // An empty set is a `problem` under validateKpiSet, but with no
      // validator supplied this widget must behave exactly as it did before
      // this task: no banner, Save always enabled.
      expect(find.textContaining('Pick at least one KPI'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    },
  );
}
