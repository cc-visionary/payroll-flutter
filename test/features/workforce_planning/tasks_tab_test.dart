import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';
import 'package:payroll_flutter/features/workforce_planning/tabs/task_form_dialog.dart';
import 'package:payroll_flutter/features/workforce_planning/tabs/tasks_tab.dart';
import 'package:payroll_flutter/features/workforce_planning/wp_providers.dart';

RoleScorecard _card(String id, String jobTitle) => RoleScorecard(
      id: id,
      companyId: 'c',
      jobTitle: jobTitle,
      missionStatement: '',
      responsibilities: const [],
      kpis: const [],
      wageType: 'MONTHLY',
      workHoursPerDay: 8,
      workDaysPerWeek: 'MON_FRI',
      isActive: true,
      effectiveDate: DateTime(2026, 1, 1),
    );

void main() {
  testWidgets('lists tasks with owner name and node', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        wpTasksProvider.overrideWith((ref) async => const [
          // No card, no externalRef, but an explicit owner: this is the
          // deliberately-widened bucket-3 (Unattributed) case — a task with
          // an owner but no card/externalRef must still render, not vanish.
          WpTask(id: 't1', companyId: 'c', name: 'SD flash', nodeId: 'n2',
              ownerEmployeeId: 'e1'),
        ]),
        wpNodesProvider.overrideWith((ref) async => const [
          WpNode(id: 'n2', companyId: 'c', code: '2', name: '2. Configure')]),
        wpDriversProvider.overrideWith((ref) async => const []),
        wpRatesProvider.overrideWith((ref) async => const []),
        wpActiveEmployeesProvider.overrideWith((ref) async => const []),
        roleScorecardListProvider.overrideWith((ref) async => const []),
      ],
      child: const MaterialApp(home: Scaffold(body: TasksTab())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('SD flash'), findsOneWidget);
    expect(find.text('2. Configure'), findsWidgets);
  });

  testWidgets('a card-linked task renders under its card + area heading', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        wpTasksProvider.overrideWith((ref) async => const [
          WpTask(id: 't1', companyId: 'c', name: 'Reconcile inventory',
              roleScorecardId: 'rc1', responsibilityArea: 'Warehousing'),
        ]),
        wpNodesProvider.overrideWith((ref) async => const []),
        wpDriversProvider.overrideWith((ref) async => const []),
        wpRatesProvider.overrideWith((ref) async => const []),
        wpActiveEmployeesProvider.overrideWith((ref) async => const []),
        roleScorecardListProvider.overrideWith((ref) async => [_card('rc1', 'Ops Lead')]),
      ],
      child: const MaterialApp(home: Scaffold(body: TasksTab())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Ops Lead'), findsOneWidget);
    expect(find.text('Warehousing'), findsOneWidget);
    expect(find.text('Reconcile inventory'), findsOneWidget);
  });

  testWidgets('a legacy task (externalRef set, no role card) renders under '
      '"From capacity model"', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        wpTasksProvider.overrideWith((ref) async => const [
          WpTask(id: 't1', companyId: 'c', name: 'Imported task',
              externalRef: 'capacity-model-row-9'),
        ]),
        wpNodesProvider.overrideWith((ref) async => const []),
        wpDriversProvider.overrideWith((ref) async => const []),
        wpRatesProvider.overrideWith((ref) async => const []),
        wpActiveEmployeesProvider.overrideWith((ref) async => const []),
        roleScorecardListProvider.overrideWith((ref) async => const []),
      ],
      child: const MaterialApp(home: Scaffold(body: TasksTab())),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('From capacity model'), findsOneWidget);
  });

  testWidgets('an uncosted task (no times, no minutes) shows the "not costed" chip',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        wpTasksProvider.overrideWith((ref) async => const [
          WpTask(id: 't1', companyId: 'c', name: 'Never priced'),
        ]),
        wpNodesProvider.overrideWith((ref) async => const []),
        wpDriversProvider.overrideWith((ref) async => const []),
        wpRatesProvider.overrideWith((ref) async => const []),
        wpActiveEmployeesProvider.overrideWith((ref) async => const []),
        roleScorecardListProvider.overrideWith((ref) async => const []),
      ],
      child: const MaterialApp(home: Scaffold(body: TasksTab())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Not costed'), findsOneWidget);
  });

  testWidgets(
      'edit dialog opens without throwing when the owner is a separated '
      'employee not in the active-employees list', (tester) async {
    // Simulates a task owned by staff who has since left: `employees` (the
    // active roster) does not contain 'gone-emp', which is the crash case
    // for a DropdownButtonFormField whose initialValue isn't among its items.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () => showDialog<WpTask>(
              context: context,
              builder: (_) => const TaskFormDialog(
                existing: WpTask(
                  id: 't1',
                  companyId: 'c',
                  name: 'Legacy task',
                  ownerEmployeeId: 'gone-emp',
                ),
                companyId: 'c',
                nodes: [],
                drivers: [],
                rates: [],
                employees: [],
              ),
            ),
            child: const Text('open'),
          );
        }),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Edit task'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
