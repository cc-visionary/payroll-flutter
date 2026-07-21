import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../data/models/employee.dart';
import '../../../data/models/workforce_planning.dart';
import '../../../data/repositories/role_scorecard_repository.dart';
import '../../../data/repositories/workforce_planning_repository.dart';
import '../../../widgets/responsive_table.dart';
import '../capacity_math.dart';
import '../role_rollup.dart';
import '../role_view_rows.dart';
import '../tasks_rows.dart' show tasksForPerson;
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

enum _Lens { person, role }

class _RoleViewTabState extends ConsumerState<RoleViewTab> {
  String? _selectedId;
  _Lens _lens = _Lens.person;

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

    if (_lens == _Lens.role) {
      return _RoleLens(header: _lensToggle(context));
    }
    // Default to the first active employee; keep the current selection if
    // it's still in the list, otherwise fall back to the first.
    final selectedId =
        employees.any((e) => e.id == _selectedId) ? _selectedId! : employees.first.id;
    final selected = employees.firstWhere((e) => e.id == selectedId);

    final nodeNameById = {for (final n in nodesAsync.asData!.value) n.id: n.name};
    // Explicitly-owned tasks PLUS the unowned responsibilities on this person's
    // role card (split across its ACTIVE holders) — the same rule wp_person_load
    // uses. Filtering on ownerEmployeeId alone would show "No owned tasks."
    // directly beneath a non-zero load%.
    final attributed = tasksForPerson(
      employeeId: selected.id,
      roleScorecardId: selected.roleScorecardId,
      allTasks: tasksAsync.asData!.value,
      employees: employees,
    );
    final ownerTasks = [for (final a in attributed) a.task];
    final holderCountByTaskId = {
      for (final a in attributed) a.task.id: a.holderCount,
    };
    final derivedTaskIds = {
      for (final a in attributed)
        if (a.derived) a.task.id,
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _lensToggle(context),
          const SizedBox(height: 16),
          _picker(employees, selected),
          const SizedBox(height: 16),
          _loadSection(context, loadsAsync.asData!.value, selected.id, multiplier),
          const SizedBox(height: 24),
          Text('Owned tasks', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _tasksSection(context, ownerTasks, nodeNameById, multiplier,
              holderCountByTaskId, derivedTaskIds),
          const SizedBox(height: 24),
          Text('KPIs', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _kpiSection(context, selected),
        ],
      ),
    );
  }

  /// Person vs role lens. The per-person view answers "is Jeremy overloaded?";
  /// the per-role view answers "is this ROLE overloaded, whoever holds it?" —
  /// which is the question that survives someone leaving.
  Widget _lensToggle(BuildContext context) => SegmentedButton<_Lens>(
        segments: const [
          ButtonSegment(value: _Lens.person, label: Text('By person'), icon: Icon(Icons.person_outline, size: 16)),
          ButtonSegment(value: _Lens.role, label: Text('By role'), icon: Icon(Icons.badge_outlined, size: 16)),
        ],
        selected: {_lens},
        onSelectionChanged: (s) => setState(() => _lens = s.first),
        showSelectedIcon: false,
      );

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

  Widget _tasksSection(
      BuildContext context,
      List<WpTask> ownerTasks,
      Map<String, String> nodeNameById,
      double multiplier,
      Map<String, int> holderCountByTaskId,
      Set<String> derivedTaskIds) {
    // All computed rows, not just this owner's — derived tasks have no
    // owner_employee_id, so ownerComputedProvider would omit their hours.
    final computedAsync = ref.watch(wpAllTaskComputedProvider);
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
      holderCountByTaskId: holderCountByTaskId,
      derivedTaskIds: derivedTaskIds,
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

/// The per-ROLE lens: one row per active role card with its responsibility
/// count, modelled hours, load against the combined capacity of its holders,
/// monthly cost and cost per hour.
///
/// Deliberately reads "—" rather than 0 wherever a figure is unknown. Most
/// responsibilities are still uncosted, and a 0% load or ₱0/hr would be read as
/// a finding rather than as missing data.
class _RoleLens extends ConsumerWidget {
  const _RoleLens({required this.header});

  final Widget header;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardsAsync = ref.watch(roleScorecardListProvider);
    final empsAsync = ref.watch(wpActiveEmployeesProvider);
    final tasksAsync = ref.watch(wpTasksProvider);
    final computedAsync = ref.watch(wpAllTaskComputedProvider);
    final loadsAsync = ref.watch(wpPersonLoadsProvider);
    final multiplier = ref.watch(wpGrowthMultiplierProvider);

    if (cardsAsync.isLoading ||
        empsAsync.isLoading ||
        tasksAsync.isLoading ||
        computedAsync.isLoading ||
        loadsAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final err = cardsAsync.error ??
        empsAsync.error ??
        tasksAsync.error ??
        computedAsync.error ??
        loadsAsync.error;
    if (err != null) {
      return Center(child: Text('Error: $err', style: const TextStyle(color: Colors.red)));
    }

    // Capacity comes from wp_person_load, which already resolves the per-person
    // override and the company default — re-deriving it here would be a second
    // implementation free to drift from the view.
    final capacityByEmployee = {
      for (final l in loadsAsync.asData!.value) l.employeeId: l.capacityHours,
    };
    final rows = buildRoleRollup(
      cards: cardsAsync.asData!.value,
      employees: empsAsync.asData!.value,
      tasks: tasksAsync.asData!.value,
      computedByTaskId: {
        for (final c in computedAsync.asData!.value) c.taskId: c,
      },
      multiplier: multiplier,
      capacityHoursFor: (id) => capacityByEmployee[id] ?? 0,
    );
    final totals = totalRoleRollup(rows);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 16),
          if (totals.uncosted > 0) ...[
            _uncostedNotice(context, totals),
            const SizedBox(height: 12),
          ],
          if (rows.isEmpty)
            const Text('No active role cards.')
          else
            _table(context, rows, totals),
        ],
      ),
    );
  }

  Widget _uncostedNotice(BuildContext context, RoleRollupTotals t) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${t.uncosted} of ${t.responsibilities} responsibilities are not costed, '
              'so hours and load are incomplete. Cost them on the Tasks tab.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _table(BuildContext context, List<RoleRollupRow> rows, RoleRollupTotals t) {
    final money = NumberFormat.currency(symbol: '₱', decimalDigits: 0);
    final mono = AppTheme.mono(context);
    Widget num(String s) => Text(s, style: mono);

    return ResponsiveTable(
      fullWidth: true,
      child: DataTable(
        columnSpacing: 24,
        columns: const [
          DataColumn(label: Text('Role')),
          DataColumn(label: Text('Held by'), numeric: true),
          DataColumn(label: Text('Resp.'), numeric: true),
          DataColumn(label: Text('Hours/mo'), numeric: true),
          DataColumn(label: Text('Load')),
          DataColumn(label: Text('Cost/mo'), numeric: true),
          DataColumn(label: Text('₱/hour'), numeric: true),
        ],
        rows: [
          for (final r in rows)
            DataRow(cells: [
              DataCell(ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(r.jobTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
              )),
              DataCell(num('${r.holders}')),
              DataCell(num(r.fullyCosted
                  ? '${r.responsibilities}'
                  : '${r.costedResponsibilities}/${r.responsibilities}')),
              DataCell(num(r.costedResponsibilities == 0
                  ? '—'
                  : r.hoursPerMonth.toStringAsFixed(1))),
              DataCell(_loadCell(context, r, mono)),
              DataCell(num(r.monthlyCost == null
                  ? '—'
                  : money.format(r.monthlyCost!.toDouble()))),
              DataCell(num(r.costPerHour == null
                  ? '—'
                  : money.format(r.costPerHour!.toDouble()))),
            ]),
          DataRow(
            cells: [
              const DataCell(Text('Total', style: TextStyle(fontWeight: FontWeight.w600))),
              DataCell(num('${t.holders}')),
              DataCell(num('${t.costedResponsibilities}/${t.responsibilities}')),
              DataCell(num(t.hoursPerMonth == 0 ? '—' : t.hoursPerMonth.toStringAsFixed(1))),
              // No total load%: averaging load across roles is meaningless, and
              // a number here would be read as "the company is N% busy" while
              // most responsibilities are uncosted.
              const DataCell(Text('—')),
              DataCell(num(money.format(t.monthlyCost.toDouble()))),
              const DataCell(Text('—')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _loadCell(BuildContext context, RoleRollupRow r, TextStyle mono) {
    final f = r.loadFraction;
    if (f == null) {
      return Tooltip(
        message: r.holders == 0
            ? 'Nobody holds this role, so there is no capacity to measure against.'
            : 'None of this role\'s responsibilities are costed yet.',
        child: const Text('—'),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${(f * 100).round()}%', style: mono),
        const SizedBox(width: 6),
        LoadStatusChip(status: r.status!),
      ],
    );
  }
}
