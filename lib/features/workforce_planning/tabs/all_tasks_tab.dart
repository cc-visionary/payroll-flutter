import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../data/models/role_scorecard.dart';
import '../../../data/models/workforce_planning.dart';
import '../../../data/repositories/role_scorecard_repository.dart';
import '../../../data/repositories/workforce_planning_repository.dart';
import '../../../widgets/responsive_table.dart';
import '../frequency.dart' show effortLabel;
import '../role_load.dart';
import '../wp_providers.dart';
import 'task_form_dialog.dart';

enum AllTasksFilter { all, noRole, flagged, role }

List<WpTask> filterTasks(
  List<WpTask> tasks, {
  String query = '',
  AllTasksFilter filter = AllTasksFilter.all,
  String? roleId,
}) {
  final q = query.trim().toLowerCase();
  return [
    for (final t in tasks)
      if (t.status == 'ACTIVE' &&
          !isLegacyReference(t) &&
          (q.isEmpty || t.name.toLowerCase().contains(q)) &&
          switch (filter) {
            AllTasksFilter.all => true,
            AllTasksFilter.noRole => t.roleScorecardId == null,
            AllTasksFilter.flagged => t.allocationReviewNote != null,
            AllTasksFilter.role => t.roleScorecardId == roleId,
          })
        t,
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

  Future<void> _edit(WpTask t, List<RoleScorecard> roles, List<WpTask> all) async {
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
      ),
    );
    if (saved == null) return;
    await ref.read(workforcePlanningRepositoryProvider).saveTask(saved);
    _invalidate();
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
    if (ok != true) return;
    try {
      await ref.read(workforcePlanningRepositoryProvider).setTaskArchived(task.id, true);
    } catch (e) {
      if (!mounted) return;
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not archive task: $e')));
      return;
    }
    _invalidate();
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
                      onSelectChanged: (_) => _edit(t, allRoles, tasks.requireValue),
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
                        DataCell(IconButton(
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
