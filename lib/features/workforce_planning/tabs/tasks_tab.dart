import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/status_colors.dart';
import '../../../app/theme.dart';
import '../../../data/models/employee.dart';
import '../../../data/models/role_scorecard.dart';
import '../../../data/models/workforce_planning.dart';
import '../../../data/repositories/role_scorecard_repository.dart';
import '../../../data/repositories/workforce_planning_repository.dart';
import '../../../widgets/responsive_table.dart';
import '../../auth/profile_provider.dart';
import '../../documents/providers.dart' show roleScorecardByIdProvider;
import '../tasks_rows.dart';
import '../wp_providers.dart';
import 'role_view_tab.dart' show ownerComputedProvider;
import 'task_form_dialog.dart';

/// HR-facing task inventory: list + New/Edit/Delete + owner assignment for
/// `wp_tasks`. Mirrors `KpiLibraryScreen`'s dialog-open/SnackBar/invalidate
/// pattern and `BalanceTab`'s async gates. Any save or delete invalidates the
/// three providers whose data is derived from `wp_tasks`
/// (`wpTasksProvider`, `wpPersonLoadsProvider`, `ownerComputedProvider`) so
/// the Balance and Role View tabs never show stale numbers.
///
/// Tasks are grouped into 3 buckets (see [groupTasks] in tasks_rows.dart):
/// one section per role card (nested by responsibility area), a collapsible
/// "From capacity model" bucket for legacy imports, and an "Unattributed"
/// bucket that is the true complement of the first two — never just "no
/// owner" — so a task is never silently dropped from the inventory.
class TasksTab extends ConsumerWidget {
  const TasksTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(wpTasksProvider);
    final nodesAsync = ref.watch(wpNodesProvider);
    final driversAsync = ref.watch(wpDriversProvider);
    final ratesAsync = ref.watch(wpRatesProvider);
    final employeesAsync = ref.watch(wpActiveEmployeesProvider);
    final cardsAsync = ref.watch(roleScorecardListProvider);
    final companyId = ref.watch(userProfileProvider).asData?.value?.companyId;

    if (tasksAsync.isLoading ||
        nodesAsync.isLoading ||
        driversAsync.isLoading ||
        ratesAsync.isLoading ||
        employeesAsync.isLoading ||
        cardsAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final err = tasksAsync.error ??
        nodesAsync.error ??
        driversAsync.error ??
        ratesAsync.error ??
        employeesAsync.error ??
        cardsAsync.error;
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
    final cards = cardsAsync.asData!.value;
    final nodeNameById = {for (final n in nodes) n.id: n.name};
    final driverById = {for (final d in drivers) d.id: d};
    final rateById = {for (final r in rates) r.id: r};
    final employeeNameById = {
      for (final e in employees) e.id: '${e.firstName} ${e.lastName}',
    };
    final groups = groupTasks(tasks, cards);

    Widget table(List<WpTask> rows) => _taskTable(
          context,
          ref,
          rows,
          companyId: companyId,
          nodes: nodes,
          drivers: drivers,
          rates: rates,
          employees: employees,
          cards: cards,
          nodeNameById: nodeNameById,
          driverById: driverById,
          rateById: rateById,
          employeeNameById: employeeNameById,
        );

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
                        cards,
                      ),
              icon: const Icon(Icons.add),
              label: const Text('New task'),
            ),
          ),
          const SizedBox(height: 16),
          if (tasks.isEmpty)
            const Text('No tasks yet. Click "New task".')
          else ...[
            for (final cardGroup in groups.cardGroups) ...[
              Text(cardGroup.jobTitle, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final areaGroup in cardGroup.areas) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 6),
                  child: Text(areaGroup.area, style: Theme.of(context).textTheme.labelLarge),
                ),
                table(areaGroup.tasks),
                const SizedBox(height: 16),
              ],
              const SizedBox(height: 8),
            ],
            if (groups.legacy.isNotEmpty) ...[
              ExpansionTile(
                initiallyExpanded: true,
                tilePadding: EdgeInsets.zero,
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'From capacity model (${groups.legacy.length})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _confirmBulkDeleteLegacy(context, ref, groups.legacy),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Delete all'),
                    ),
                  ],
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: table(groups.legacy),
                  ),
                ],
              ),
            ],
            if (groups.unattributed.isNotEmpty) ...[
              Text(
                'Unattributed (${groups.unattributed.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              table(groups.unattributed),
            ],
          ],
        ],
      ),
    );
  }

  Widget _taskTable(
    BuildContext context,
    WidgetRef ref,
    List<WpTask> rows, {
    required String? companyId,
    required List<WpNode> nodes,
    required List<WpDriver> drivers,
    required List<WpRate> rates,
    required List<Employee> employees,
    required List<RoleScorecard> cards,
    required Map<String, String> nodeNameById,
    required Map<String, WpDriver> driverById,
    required Map<String, WpRate> rateById,
    required Map<String, String> employeeNameById,
  }) {
    return ResponsiveTable(
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Task')),
          DataColumn(label: Text('Node')),
          DataColumn(label: Text('Hours/mo')),
          DataColumn(label: Text('Owner')),
          DataColumn(label: Text('Cadence')),
          DataColumn(label: Text('')),
        ],
        rows: [
          for (final t in rows)
            DataRow(cells: [
              DataCell(Text(t.name)),
              DataCell(Text(nodeNameById[t.nodeId] ?? '—')),
              DataCell(_hoursCell(context, t, driverById, rateById)),
              DataCell(_ownerCell(context, t, employees, employeeNameById)),
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
                              cards,
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
    );
  }

  Widget _hoursCell(
    BuildContext context,
    WpTask t,
    Map<String, WpDriver> driverById,
    Map<String, WpRate> rateById,
  ) {
    if (isTaskNotCosted(t)) {
      return const StatusChip(label: 'Not costed', tone: StatusTone.neutral);
    }
    final hours = taskHours(task: t, driverById: driverById, rateById: rateById);
    return Text(hours.toStringAsFixed(1), style: AppTheme.mono(context));
  }

  Widget _ownerCell(
    BuildContext context,
    WpTask t,
    List<Employee> employees,
    Map<String, String> employeeNameById,
  ) {
    final owner = resolveEffectiveOwner(
      task: t,
      employeeNameById: employeeNameById,
      employees: employees,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(owner.label),
        if (owner.derived) ...[
          const SizedBox(width: 6),
          const StatusChip(label: 'Derived', tone: StatusTone.info),
        ],
      ],
    );
  }

  /// Refreshes the workforce views AND the role-card views. A card-linked task
  /// IS a role-card responsibility now, so renaming or deleting one here also
  /// changes that card's detail screen, its PDF, and future contract prefills —
  /// without these invalidations they'd keep showing the old wording until an
  /// app restart. (The card editor already invalidates in the other direction.)
  void _invalidateAfterTaskChange(WidgetRef ref, Iterable<String?> cardIds) {
    ref.invalidate(wpTasksProvider);
    ref.invalidate(wpPersonLoadsProvider);
    ref.invalidate(ownerComputedProvider);
    ref.invalidate(roleScorecardListProvider);
    for (final id in cardIds.whereType<String>().toSet()) {
      ref.invalidate(roleScorecardByIdProvider(id));
    }
  }

  Future<void> _confirmBulkDeleteLegacy(
    BuildContext context,
    WidgetRef ref,
    List<WpTask> legacyTasks,
  ) async {
    final n = legacyTasks.length;
    final plural = n == 1 ? '' : 's';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete $n capacity-model task$plural?'),
        content: Text(
          'Remove all $n task$plural imported from the capacity model? This '
          'cannot be undone.',
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
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final repo = ref.read(workforcePlanningRepositoryProvider);
      await Future.wait([for (final t in legacyTasks) repo.deleteTask(t.id)]);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete tasks: $e')),
      );
      return;
    }
    // Legacy bucket rows have no role_scorecard_id, so no card to refresh.
    _invalidateAfterTaskChange(ref, const []);
  }

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref,
    String companyId,
    List<WpNode> nodes,
    List<WpDriver> drivers,
    List<WpRate> rates,
    List<Employee> employees,
    List<RoleScorecard> cards, {
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
        cards: cards,
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
    // Both cards: an edit can move a task from one card to another, and the
    // card it LEFT needs refreshing just as much as the one it joined.
    _invalidateAfterTaskChange(
      ref,
      [result.roleScorecardId, existing?.roleScorecardId],
    );
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
    _invalidateAfterTaskChange(ref, [task.roleScorecardId]);
  }
}
