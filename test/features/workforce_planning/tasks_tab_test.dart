import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/tabs/task_form_dialog.dart';
import 'package:payroll_flutter/features/workforce_planning/tabs/tasks_tab.dart';
import 'package:payroll_flutter/features/workforce_planning/wp_providers.dart';

void main() {
  testWidgets('lists tasks with owner name and node', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        wpTasksProvider.overrideWith((ref) async => const [
          WpTask(id: 't1', companyId: 'c', name: 'SD flash', nodeId: 'n2',
              ownerEmployeeId: 'e1'),
        ]),
        wpNodesProvider.overrideWith((ref) async => const [
          WpNode(id: 'n2', companyId: 'c', code: '2', name: '2. Configure')]),
        wpDriversProvider.overrideWith((ref) async => const []),
        wpRatesProvider.overrideWith((ref) async => const []),
        wpActiveEmployeesProvider.overrideWith((ref) async => const []),
      ],
      child: const MaterialApp(home: Scaffold(body: TasksTab())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('SD flash'), findsOneWidget);
    expect(find.text('2. Configure'), findsWidgets);
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
