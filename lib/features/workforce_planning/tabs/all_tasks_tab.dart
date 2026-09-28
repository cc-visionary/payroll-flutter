import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../data/models/employee.dart';
import '../../../data/models/role_scorecard.dart';
import '../../../data/models/workforce_planning.dart';
import '../../../data/repositories/role_scorecard_repository.dart';
import '../../../data/repositories/workforce_planning_repository.dart';
import '../../../widgets/responsive_table.dart';
import '../area_placement.dart';
import '../frequency.dart' show effortLabel;
import '../role_load.dart';
import '../role_structure.dart';
import '../wp_providers.dart';
import 'task_form_dialog.dart';

/// [archived]: ARCHIVED genuine tasks (restorable). [legacy]: the old
/// capacity-model reference rows (ACTIVE, `external_ref` set, no role), shown
/// only so they can be deleted together. Every other mode lists ACTIVE
/// genuine tasks.
enum AllTasksFilter { all, noRole, flagged, role, archived, legacy }

List<WpTask> filterTasks(
  List<WpTask> tasks, {
  String query = '',
  AllTasksFilter filter = AllTasksFilter.all,
  String? roleId,
}) {
  final q = query.trim().toLowerCase();
  bool inMode(WpTask t) {
    final legacy = isLegacyReference(t);
    return switch (filter) {
      AllTasksFilter.archived => t.status == 'ARCHIVED' && !legacy,
      AllTasksFilter.legacy => t.status == 'ACTIVE' && legacy,
      _ when t.status != 'ACTIVE' || legacy => false,
      AllTasksFilter.noRole => t.roleScorecardId == null,
      AllTasksFilter.flagged => t.allocationReviewNote != null,
      AllTasksFilter.role => t.roleScorecardId == roleId,
      AllTasksFilter.all => true,
    };
  }
  return [
    for (final t in tasks)
      if (inMode(t) && (q.isEmpty || t.name.toLowerCase().contains(q))) t,
  ];
}

/// Every task as one searchable list — for finding a task and bulk tidying.
class AllTasksTab extends ConsumerStatefulWidget {
  const AllTasksTab({super.key});

  @override
  ConsumerState<AllTasksTab> createState() => _AllTasksTabState();
}

class _AllTasksTabState extends ConsumerState<AllTasksTab> {
  String _query = '';
  AllTasksFilter _filter = AllTasksFilter.all;
  String? _roleId;

  void _invalidate() {
    ref.invalidate(wpTasksProvider);
    ref.invalidate(wpAllTaskComputedProvider);
    ref.invalidate(wpPersonLoadsProvider);
    ref.invalidate(roleScorecardListProvider);
  }

  void _snack(String message) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );

  Future<void> _edit(
    WpTask t,
    List<RoleScorecard> roles,
    List<WpTask> all,
    List<Employee> employees,
  ) async {
    final saved = await showDialog<WpTask>(
      context: context,
      builder: (_) => TaskFormDialog(
        existing: t,
        companyId: t.companyId,
        cards: roles,
        nodes: ref.read(wpNodesProvider).asData?.value ?? const [],
        drivers: ref.read(wpDriversProvider).asData?.value ?? const [],
        rates: ref.read(wpRatesProvider).asData?.value ?? const [],
        duplicateCheckPool: all,
        holderCountByRole: holderCountByRole(roles: roles, employees: employees),
      ),
    );
    if (saved == null || !mounted) return;
    try {
      await ref.read(workforcePlanningRepositoryProvider).saveTask(
        placeInArea(previous: t, next: saved, allTasks: all),
      );
    } catch (e) {
      if (mounted) _snack('Could not save task: $e');
      return;
    }
    if (mounted) _invalidate();
  }

  Future<void> _restore(WpTask task) async {
    try {
      await ref.read(workforcePlanningRepositoryProvider).setTaskArchived(task.id, false);
    } catch (e) {
      if (mounted) _snack('Could not restore task: $e');
      return;
    }
    if (mounted) _invalidate();
  }

  /// Deletes every old capacity-model reference row, one at a time, and
  /// reports the ones that could not be deleted.
  Future<void> _confirmDeleteLegacy(List<WpTask> legacy) async {
    final n = legacy.length;
    final rows = n == 1 ? 'row' : 'rows';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete $n old capacity-model $rows?'),
        content: Text(
          'These $n $rows were imported from the old capacity model as a '
          'reference copy. They are not anyone\'s work. Deleting cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final repo = ref.read(workforcePlanningRepositoryProvider);
    var failed = 0;
    for (final t in legacy) {
      try {
        await repo.deleteTask(t.id);
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    _invalidate();
    if (failed > 0) _snack('$failed of $n could not be deleted.');
  }

  Future<void> _confirmArchive(WpTask task) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Archive task?'),
        content: Text(
          'Archive "${task.name}"? It leaves everyone\'s load and the queues '
          'but is kept for reference and can be restored.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(workforcePlanningRepositoryProvider).setTaskArchived(task.id, true);
    } catch (e) {
      if (mounted) _snack('Could not archive task: $e');
      return;
    }
    if (mounted) _invalidate();
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(wpTasksProvider);
    final roles = ref.watch(roleScorecardListProvider);
    final emps = ref.watch(wpActiveEmployeesProvider);
    final computed = ref.watch(wpAllTaskComputedProvider);
    final multiplier = ref.watch(wpGrowthMultiplierProvider);
    if ([tasks, roles, emps, computed].any((a) => a.isLoading)) {
      return const Center(child: CircularProgressIndicator());
    }
    final err = [tasks, roles, emps, computed].where((a) => a.hasError).firstOrNull;
    if (err != null) return Center(child: Text('Error: ${err.error}'));

    final allRoles = roles.requireValue;
    final rolesById = {for (final r in allRoles) r.id: r};
    final hours = {for (final c in computed.requireValue) c.taskId: taskHours(c, multiplier)};
    final rows = filterTasks(tasks.requireValue, query: _query, filter: _filter, roleId: _roleId);
    final legacy = filterTasks(tasks.requireValue, filter: AllTasksFilter.legacy);
    final archivedMode = _filter == AllTasksFilter.archived;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 280,
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search tasks', border: OutlineInputBorder(), isDense: true),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          DropdownButton<String>(
            value: _filter == AllTasksFilter.role ? 'role:$_roleId' : _filter.name,
            items: [
              const DropdownMenuItem(value: 'all', child: Text('All tasks')),
              const DropdownMenuItem(value: 'noRole', child: Text('No role')),
              const DropdownMenuItem(value: 'flagged', child: Text('Check these')),
              const DropdownMenuItem(value: 'archived', child: Text('Archived')),
              if (legacy.isNotEmpty || _filter == AllTasksFilter.legacy)
                DropdownMenuItem(value: 'legacy', child: Text('Old capacity-model rows (${legacy.length})')),
              for (final r in allRoles.where((r) => r.isActive))
                DropdownMenuItem(value: 'role:${r.id}', child: Text(r.jobTitle)),
            ],
            onChanged: (v) => setState(() {
              if (v == null) return;
              if (v.startsWith('role:')) {
                _filter = AllTasksFilter.role;
                _roleId = v.substring(5);
              } else {
                _filter = AllTasksFilter.values.byName(v);
                _roleId = null;
              }
            }),
          ),
          Text('${rows.length} tasks'),
          if (_filter == AllTasksFilter.legacy && legacy.isNotEmpty)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
              onPressed: () => _confirmDeleteLegacy(legacy),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete all of these'),
            ),
        ]),
      ),
      Expanded(
        child: SingleChildScrollView(
          child: ResponsiveTable(
            child: DataTable(
              showCheckboxColumn: false,
              columns: const [
                DataColumn(label: Text('Task')),
                DataColumn(label: Text('How often')),
                DataColumn(label: Text('≈ h/mo'), numeric: true),
                DataColumn(label: Text('Role')),
                DataColumn(label: Text('Checked by')),
                DataColumn(label: Text('')),
              ],
              rows: [
                for (final t in rows)
                  () {
                    final h = hours[t.id] ?? 0;
                    return DataRow(
                      // An archived task is restored, not edited, from here.
                      onSelectChanged: archivedMode
                          ? null
                          : (_) => _edit(t, allRoles, tasks.requireValue, emps.requireValue),
                      cells: [
                        DataCell(Text(t.name)),
                        DataCell(Text(effortLabel(t, h))),
                        DataCell(Text(h.toStringAsFixed(1), style: AppTheme.mono(context))),
                        DataCell(Text(rolesById[t.roleScorecardId]?.jobTitle ?? '—')),
                        DataCell(Text(() {
                          final r = rolesById[t.roleScorecardId];
                          if (r == null) return '—';
                          final by = checkedByTitles(role: r, employees: emps.requireValue, rolesById: rolesById);
                          return by.isEmpty ? '—' : by.join(', ');
                        }())),
                        DataCell(archivedMode
                            ? IconButton(
                                tooltip: 'Restore',
                                icon: const Icon(Icons.unarchive_outlined),
                                onPressed: () => _restore(t),
                              )
                            : IconButton(
                                tooltip: 'Archive',
                                icon: const Icon(Icons.archive_outlined),
                                onPressed: () => _confirmArchive(t),
                              )),
                      ],
                    );
                  }(),
              ],
            ),
          ),
        ),
      ),
    ]);
  }
}
