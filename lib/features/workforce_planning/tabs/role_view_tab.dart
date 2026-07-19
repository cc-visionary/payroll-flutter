import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../data/models/employee.dart';
import '../../../data/models/workforce_planning.dart';
import '../../../data/repositories/role_scorecard_repository.dart';
import '../../../data/repositories/workforce_planning_repository.dart';
import '../../../widgets/responsive_table.dart';
import '../capacity_math.dart';
import '../role_view_rows.dart';
import '../wp_providers.dart';
import 'load_chip.dart';

/// A single person's computed owned tasks (times/minutes/hours resolved).
/// Public (not `_`-prefixed) so widget tests can override it directly.
final ownerComputedProvider = FutureProvider.family<List<WpTaskComputed>, String>(
    (ref, employeeId) => ref
        .watch(workforcePlanningRepositoryProvider)
        .taskComputedForOwner(employeeId));

/// Person picker driving one employee's owned-tasks table, hours-by-tier
/// summary, load% + status chip, and assigned KPIs.
class RoleViewTab extends ConsumerStatefulWidget {
  const RoleViewTab({super.key});

  @override
  ConsumerState<RoleViewTab> createState() => _RoleViewTabState();
}

class _RoleViewTabState extends ConsumerState<RoleViewTab> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final empsAsync = ref.watch(wpActiveEmployeesProvider);
    final nodesAsync = ref.watch(wpNodesProvider);
    final loadsAsync = ref.watch(wpPersonLoadsProvider);
    final tasksAsync = ref.watch(wpTasksProvider);
    final multiplier = ref.watch(wpGrowthMultiplierProvider);

    if (empsAsync.isLoading ||
        nodesAsync.isLoading ||
        loadsAsync.isLoading ||
        tasksAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final err = empsAsync.error ?? nodesAsync.error ?? loadsAsync.error ?? tasksAsync.error;
    if (err != null) {
      return Center(child: Text('Error: $err', style: const TextStyle(color: Colors.red)));
    }

    final employees = empsAsync.asData!.value;
    if (employees.isEmpty) {
      return const Center(child: Text('No active people to show.'));
    }
    // Default to the first active employee; keep the current selection if
    // it's still in the list, otherwise fall back to the first.
    final selectedId =
        employees.any((e) => e.id == _selectedId) ? _selectedId! : employees.first.id;
    final selected = employees.firstWhere((e) => e.id == selectedId);

    final nodeNameById = {for (final n in nodesAsync.asData!.value) n.id: n.name};
    final ownerTasks =
        tasksAsync.asData!.value.where((t) => t.ownerEmployeeId == selected.id).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _picker(employees, selected),
          const SizedBox(height: 16),
          _loadSection(context, loadsAsync.asData!.value, selected.id, multiplier),
          const SizedBox(height: 24),
          Text('Owned tasks', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _tasksSection(context, ownerTasks, nodeNameById, multiplier, selected.id),
          const SizedBox(height: 24),
          Text('KPIs', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _kpiSection(context, selected),
        ],
      ),
    );
  }

  Widget _picker(List<Employee> employees, Employee selected) {
    return DropdownButton<String>(
      value: selected.id,
      items: [
        for (final e in employees)
          DropdownMenuItem(value: e.id, child: Text('${e.firstName} ${e.lastName}')),
      ],
      onChanged: (id) => setState(() => _selectedId = id),
    );
  }

  Widget _loadSection(
      BuildContext context, List<WpPersonLoad> loads, String employeeId, double multiplier) {
    WpPersonLoad? load;
    for (final l in loads) {
      if (l.employeeId == employeeId) {
        load = l;
        break;
      }
    }
    if (load == null) {
      return const Text('No load data for this person.');
    }
    final fraction = personLoad(load, multiplier: multiplier);
    final status = loadStatus(fraction);
    return Row(
      children: [
        Text('Load: ', style: Theme.of(context).textTheme.titleMedium),
        Text('${(fraction * 100).round()}%', style: AppTheme.mono(context)),
        const SizedBox(width: 8),
        LoadStatusChip(status: status),
      ],
    );
  }

  Widget _tasksSection(BuildContext context, List<WpTask> ownerTasks,
      Map<String, String> nodeNameById, double multiplier, String employeeId) {
    final computedAsync = ref.watch(ownerComputedProvider(employeeId));
    if (computedAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (computedAsync.error != null) {
      return Text('Error: ${computedAsync.error}', style: const TextStyle(color: Colors.red));
    }
    final computedById = {for (final c in computedAsync.asData!.value) c.taskId: c};
    final rows = buildRoleTaskRows(
      ownerTasks: ownerTasks,
      computedById: computedById,
      nodeNameById: nodeNameById,
      multiplier: multiplier,
    );
    final tierHours = hoursByTier(rows);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (rows.isEmpty)
          const Text('No owned tasks.')
        else
          ResponsiveTable(
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Node')),
                DataColumn(label: Text('Task')),
                DataColumn(label: Text('Cadence')),
                DataColumn(label: Text('Hrs/mo'), numeric: true),
                DataColumn(label: Text('Tier')),
                DataColumn(label: Text('Risk')),
              ],
              rows: [
                for (final r in rows)
                  DataRow(cells: [
                    DataCell(Text(r.nodeName ?? '—')),
                    DataCell(Text(r.name)),
                    DataCell(Text(r.cadence ?? '—')),
                    DataCell(Text(r.hoursScaled.toStringAsFixed(1),
                        style: AppTheme.mono(context))),
                    DataCell(Text(r.skillTier ?? '—')),
                    DataCell(Text(r.risk ?? '—')),
                  ]),
              ],
            ),
          ),
        const SizedBox(height: 24),
        Text('Hours by tier', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (tierHours.isEmpty)
          const Text('No hours yet.')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in tierHours.entries)
                Chip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${entry.key}: '),
                      Text(entry.value.toStringAsFixed(1), style: AppTheme.mono(context)),
                      const Text(' h'),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _kpiSection(BuildContext context, Employee selected) {
    final roleScorecardId = selected.roleScorecardId;
    if (roleScorecardId == null) {
      return const Text('No role card — no KPIs');
    }
    final roleKpisAsync = ref.watch(roleKpisProvider(roleScorecardId));
    final assignedAsync = ref.watch(employeeAssignedKpiIdsProvider(selected.id));
    if (roleKpisAsync.isLoading || assignedAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final err = roleKpisAsync.error ?? assignedAsync.error;
    if (err != null) {
      return Text('Error: $err', style: const TextStyle(color: Colors.red));
    }
    final roleKpis = roleKpisAsync.asData!.value;
    final assigned = assignedAsync.asData!.value;
    final effectiveIds = initialCheckedKpiIds(assigned, [for (final k in roleKpis) k.kpiId]);
    final effective = roleKpis.where((k) => effectiveIds.contains(k.kpiId)).toList();
    if (effective.isEmpty) {
      return const Text('No KPIs assigned');
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [for (final k in effective) Chip(label: Text(k.name))],
    );
  }
}
