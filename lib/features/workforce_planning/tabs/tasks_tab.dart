import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/employee.dart';
import '../../../data/models/workforce_planning.dart';
import '../../../data/repositories/workforce_planning_repository.dart';
import '../../../widgets/responsive_table.dart';
import '../../auth/profile_provider.dart';
import '../wp_providers.dart';
import 'role_view_tab.dart' show ownerComputedProvider;
import 'task_form_dialog.dart';

/// HR-facing task inventory: list + New/Edit/Delete + owner assignment for
/// `wp_tasks`. Mirrors `KpiLibraryScreen`'s dialog-open/SnackBar/invalidate
/// pattern and `BalanceTab`'s async gates. Any save or delete invalidates the
/// three providers whose data is derived from `wp_tasks`
/// (`wpTasksProvider`, `wpPersonLoadsProvider`, `ownerComputedProvider`) so
/// the Balance and Role View tabs never show stale numbers.
class TasksTab extends ConsumerWidget {
  const TasksTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(wpTasksProvider);
    final nodesAsync = ref.watch(wpNodesProvider);
    final driversAsync = ref.watch(wpDriversProvider);
    final ratesAsync = ref.watch(wpRatesProvider);
    final employeesAsync = ref.watch(wpActiveEmployeesProvider);
    final companyId = ref.watch(userProfileProvider).asData?.value?.companyId;

    if (tasksAsync.isLoading ||
        nodesAsync.isLoading ||
        driversAsync.isLoading ||
        ratesAsync.isLoading ||
        employeesAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final err = tasksAsync.error ??
        nodesAsync.error ??
        driversAsync.error ??
        ratesAsync.error ??
        employeesAsync.error;
    if (err != null) {
      return Center(
        child: Text('Error: $err', style: const TextStyle(color: Colors.red)),
      );
    }

    final tasks = tasksAsync.asData!.value;
    final nodes = nodesAsync.asData!.value;
    final drivers = driversAsync.asData!.value;
    final rates = ratesAsync.asData!.value;
    final employees = employeesAsync.asData!.value;
    final nodeNameById = {for (final n in nodes) n.id: n.name};
    final ownerNameById = {
      for (final e in employees) e.id: '${e.firstName} ${e.lastName}',
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.topRight,
            child: FilledButton.icon(
              onPressed: companyId == null
                  ? null
                  : () => _openForm(
                        context,
                        ref,
                        companyId,
                        nodes,
                        drivers,
                        rates,
                        employees,
                      ),
              icon: const Icon(Icons.add),
              label: const Text('New task'),
            ),
          ),
          const SizedBox(height: 16),
          if (tasks.isEmpty)
            const Text('No tasks yet. Click "New task".')
          else
            ResponsiveTable(
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Task')),
                  DataColumn(label: Text('Node')),
                  DataColumn(label: Text('Owner')),
                  DataColumn(label: Text('Cadence')),
                  DataColumn(label: Text('')),
                ],
                rows: [
                  for (final t in tasks)
                    DataRow(cells: [
                      DataCell(Text(t.name)),
                      DataCell(Text(nodeNameById[t.nodeId] ?? '—')),
                      DataCell(
                        Text(ownerNameById[t.ownerEmployeeId] ?? 'Unassigned'),
                      ),
                      DataCell(Text(t.cadence ?? '—')),
                      DataCell(Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Edit',
                            icon: const Icon(Icons.edit, size: 18),
                            onPressed: companyId == null
                                ? null
                                : () => _openForm(
                                      context,
                                      ref,
                                      companyId,
                                      nodes,
                                      drivers,
                                      rates,
                                      employees,
                                      existing: t,
                                    ),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () => _confirmDelete(context, ref, t),
                          ),
                        ],
                      )),
                    ]),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref,
    String companyId,
    List<WpNode> nodes,
    List<WpDriver> drivers,
    List<WpRate> rates,
    List<Employee> employees, {
    WpTask? existing,
  }) async {
    final result = await showDialog<WpTask>(
      context: context,
      builder: (_) => TaskFormDialog(
        existing: existing,
        companyId: companyId,
        nodes: nodes,
        drivers: drivers,
        rates: rates,
        employees: employees,
      ),
    );
    if (result == null) return;
    try {
      await ref.read(workforcePlanningRepositoryProvider).saveTask(result);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save task: $e')),
      );
      return;
    }
    ref.invalidate(wpTasksProvider);
    ref.invalidate(wpPersonLoadsProvider);
    ref.invalidate(ownerComputedProvider);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    WpTask task,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text(
          'Remove "${task.name}" from the task inventory? This cannot be '
          'undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(c).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(workforcePlanningRepositoryProvider).deleteTask(task.id);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete task: $e')),
      );
      return;
    }
    ref.invalidate(wpTasksProvider);
    ref.invalidate(wpPersonLoadsProvider);
    ref.invalidate(ownerComputedProvider);
  }
}
