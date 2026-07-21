import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/status_colors.dart';
import '../../../app/theme.dart';
import '../../../data/models/employee.dart';
import '../../../data/models/workforce_planning.dart';
import '../../../data/repositories/role_scorecard_repository.dart';
import '../../../data/repositories/workforce_planning_repository.dart';
import '../capacity_math.dart';
import '../rebalance.dart';
import '../wp_providers.dart';
import 'load_chip.dart';
import 'role_view_tab.dart' show ownerComputedProvider;

/// Workload rebalancing: people ranked by load on the left, the selected
/// person's work on the right, drag a task onto anyone to move it.
///
/// Moves are DRAFTS — nothing is written until Apply — so a rebalance can be
/// tried, compared against the current split, and backed out. That is the
/// difference between a report and a planning tool.
class BalanceTab extends ConsumerStatefulWidget {
  const BalanceTab({super.key});

  @override
  ConsumerState<BalanceTab> createState() => _BalanceTabState();
}

class _BalanceTabState extends ConsumerState<BalanceTab> {
  String? _selectedId;
  final MoveDrafts _moves = {};
  bool _applying = false;

  @override
  Widget build(BuildContext context) {
    final empsAsync = ref.watch(wpActiveEmployeesProvider);
    final tasksAsync = ref.watch(wpTasksProvider);
    final computedAsync = ref.watch(wpAllTaskComputedProvider);
    final loadsAsync = ref.watch(wpPersonLoadsProvider);
    final configAsync = ref.watch(wpConfigProvider);
    final multiplier = ref.watch(wpGrowthMultiplierProvider);

    if (empsAsync.isLoading ||
        tasksAsync.isLoading ||
        computedAsync.isLoading ||
        loadsAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final err = empsAsync.error ??
        tasksAsync.error ??
        computedAsync.error ??
        loadsAsync.error;
    if (err != null) {
      return Center(child: Text('Error: $err', style: const TextStyle(color: Colors.red)));
    }

    final employees = empsAsync.asData!.value;
    final tasks = tasksAsync.asData!.value;
    final computed = {for (final c in computedAsync.asData!.value) c.taskId: c};
    // Capacity comes from wp_person_load so the override/default resolution has
    // exactly one implementation and cannot drift from the view.
    final capacity = {
      for (final l in loadsAsync.asData!.value) l.employeeId: l.capacityHours,
    };
    final defaultCapacity = configAsync.asData?.value?.defaultCapacityHours ?? 160;

    final moves = prunedMoves(_moves, tasks);
    final projections = buildProjections(
      employees: employees, tasks: tasks, computedByTaskId: computed,
      capacityByEmployee: capacity, multiplier: multiplier,
      defaultCapacity: defaultCapacity, moves: moves,
    );
    if (projections.isEmpty) {
      return const Center(child: Text('No active people to show.'));
    }
    final selectedId = projections.any((p) => p.employeeId == _selectedId)
        ? _selectedId!
        : projections.first.employeeId;
    final selected = projections.firstWhere((p) => p.employeeId == selectedId);
    final orphan = unattributedHours(
        tasks: tasks, computedByTaskId: computed, employees: employees,
        multiplier: multiplier, moves: moves);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _planBar(context, moves, projections, orphan),
        const Divider(height: 1),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 340,
                child: _peopleList(context, projections, selectedId, tasks,
                    computed, employees, moves,
                    ref.watch(wpKpiCountByEmployeeProvider).asData?.value ?? const {}),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: _taskPanel(context, selected, employees, tasks, computed,
                    multiplier, moves),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---- header ----------------------------------------------------------

  Widget _planBar(BuildContext context, MoveDrafts moves,
      List<LoadProjection> projections, double orphan) {
    final cs = Theme.of(context).colorScheme;
    final over = projections.where((p) => p.plannedStatus == LoadStatus.over).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 16,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  moves.isEmpty
                      ? 'Drag a task onto a person to plan a move.'
                      : '${moves.length} unsaved ${moves.length == 1 ? 'move' : 'moves'}',
                  style: TextStyle(
                    color: moves.isEmpty ? cs.onSurfaceVariant : cs.primary,
                    fontWeight: moves.isEmpty ? null : FontWeight.w600,
                  ),
                ),
                if (over > 0)
                  Text('$over over capacity',
                      style: TextStyle(
                          color: StatusPalette.of(context, StatusTone.danger).foreground)),
                if (orphan > 0)
                  Tooltip(
                    message: 'Costed work with no owner and no staffed role card. '
                        'It reaches nobody, so it is missing from every load figure.',
                    child: Text('${orphan.toStringAsFixed(1)}h unattributed',
                        style: TextStyle(color: cs.onSurfaceVariant)),
                  ),
              ],
            ),
          ),
          if (moves.isNotEmpty) ...[
            TextButton(
              onPressed: _applying ? null : () => setState(_moves.clear),
              child: const Text('Reset'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _applying ? null : () => _apply(moves),
              icon: _applying
                  ? const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: Text(_applying ? 'Applying…' : 'Apply ${moves.length}'),
            ),
          ],
        ],
      ),
    );
  }

  // ---- left: people ----------------------------------------------------

  Widget _peopleList(
    BuildContext context,
    List<LoadProjection> projections,
    String selectedId,
    List<WpTask> tasks,
    Map<String, WpTaskComputed> computed,
    List<Employee> employees,
    MoveDrafts moves,
    Map<String, int> kpiCounts,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: projections.length,
      itemBuilder: (context, i) {
        final p = projections[i];
        return DragTarget<String>(
          onWillAcceptWithDetails: (d) {
            final t = tasks.where((x) => x.id == d.data);
            if (t.isEmpty) return false;
            return moveError(
                  task: t.first, toEmployeeId: p.employeeId,
                  employees: employees, computedByTaskId: computed, moves: moves,
                ) ==
                null;
          },
          onAcceptWithDetails: (d) =>
              _drop(d.data, p.employeeId, tasks, employees, computed),
          builder: (ctx, cand, _) => _personRow(ctx, p,
              p.employeeId == selectedId, cand.isNotEmpty, kpiCounts[p.employeeId] ?? 0),
        );
      },
    );
  }

  Widget _personRow(BuildContext context, LoadProjection p, bool selected,
      bool hovering, int kpiCount) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => setState(() => _selectedId = p.employeeId),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: hovering
              ? cs.primaryContainer.withValues(alpha: 0.45)
              : (selected ? cs.primaryContainer.withValues(alpha: 0.2) : null),
          border: Border(
            left: BorderSide(
                width: 3, color: selected ? cs.primary : Colors.transparent),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(p.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                ),
                LoadStatusChip(status: p.plannedStatus),
              ],
            ),
            if (p.roleTitle != null)
              Text(p.roleTitle!,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            _loadBar(context, p),
            const SizedBox(height: 4),
            Row(
              children: [
                Text('${(p.plannedLoad * 100).round()}%', style: AppTheme.mono(context)),
                if (p.changed) ...[
                  const SizedBox(width: 6),
                  Text('was ${(p.currentLoad * 100).round()}%',
                      style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                          decoration: TextDecoration.lineThrough)),
                ],
                const Spacer(),
                // Flexible + ellipsis: with a struck-through previous load AND
                // a KPI count this row overflows a narrow pane otherwise.
                Flexible(
                  child: Text(
                    '${p.plannedHours.toStringAsFixed(1)} / ${p.capacityHours.toStringAsFixed(0)}h'
                    '${kpiCount > 0 ? '  ·  $kpiCount KPI${kpiCount == 1 ? '' : 's'}' : ''}',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Bar scaled so 100% capacity sits at 80% of the width — over-capacity work
  /// stays visible instead of being clipped at a full bar. A tick marks today's
  /// load so a move's effect reads without comparing numbers.
  Widget _loadBar(BuildContext context, LoadProjection p) {
    final tone = switch (p.plannedStatus) {
      LoadStatus.over => StatusTone.danger,
      LoadStatus.ok => StatusTone.success,
      LoadStatus.under => StatusTone.warning,
    };
    final color = StatusPalette.of(context, tone).foreground;
    const scale = 1.25;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final planned = (p.plannedLoad.clamp(0.0, scale) / scale) * w;
        final current = (p.currentLoad.clamp(0.0, scale) / scale) * w;
        return SizedBox(
          height: 8,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Container(
                width: planned,
                decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(4)),
              ),
              Positioned(
                left: w / scale - 1,
                child: Container(
                    width: 1.5,
                    height: 8,
                    color: Theme.of(context).colorScheme.outline),
              ),
              if (p.changed)
                Positioned(
                  left: (current - 1).clamp(0.0, w - 2),
                  child: Container(
                      width: 2,
                      height: 8,
                      color: Theme.of(context).colorScheme.onSurface),
                ),
            ],
          ),
        );
      },
    );
  }

  // ---- right: the selected person's work --------------------------------

  Widget _taskPanel(
    BuildContext context,
    LoadProjection p,
    List<Employee> employees,
    List<WpTask> tasks,
    Map<String, WpTaskComputed> computed,
    double multiplier,
    MoveDrafts moves,
  ) {
    final cs = Theme.of(context).colorScheme;
    final rows = plannedTasksFor(
      employeeId: p.employeeId, employees: employees, tasks: tasks,
      computedByTaskId: computed, multiplier: multiplier, moves: moves,
    );
    final uncosted = rows.where((r) => r.hours <= 0).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      '${rows.length} ${rows.length == 1 ? 'responsibility' : 'responsibilities'} · '
                      '${p.plannedHours.toStringAsFixed(1)}h of ${p.capacityHours.toStringAsFixed(0)}h · '
                      '${p.headroom >= 0 ? '${p.headroom.toStringAsFixed(1)}h headroom' : 'over by ${(-p.headroom).toStringAsFixed(1)}h'}',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              LoadStatusChip(status: p.plannedStatus),
            ],
          ),
        ),
        if (uncosted > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '$uncosted not costed — they cannot be moved until they have hours.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ),
        const SizedBox(height: 4),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Text('No work assigned.',
                      style: TextStyle(color: cs.onSurfaceVariant)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: rows.length,
                  itemBuilder: (context, i) => _taskCard(context, rows[i]),
                ),
        ),
      ],
    );
  }

  Widget _taskCard(BuildContext context, PlannedTask t) {
    final cs = Theme.of(context).colorScheme;
    final movable = t.hours > 0;
    final card = Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: t.moved ? cs.primaryContainer.withValues(alpha: 0.3) : cs.surface,
        border: Border.all(color: t.moved ? cs.primary : cs.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(movable ? Icons.drag_indicator : Icons.remove,
              size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.task.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                if (t.shared)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Shared by ${t.holderCount} — moving it gives the whole task to one person',
                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(movable ? '${t.hours.toStringAsFixed(1)}h' : '—',
              style: AppTheme.mono(context)),
        ],
      ),
    );
    if (!movable) return Opacity(opacity: 0.55, child: card);
    return Draggable<String>(
      data: t.task.id,
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(10),
          child: Text('${t.task.name}  ·  ${t.hours.toStringAsFixed(1)}h',
              maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: card),
      child: card,
    );
  }

  // ---- actions ----------------------------------------------------------

  void _drop(String taskId, String toEmployeeId, List<WpTask> tasks,
      List<Employee> employees, Map<String, WpTaskComputed> computed) {
    final match = tasks.where((t) => t.id == taskId);
    if (match.isEmpty) return;
    final err = moveError(
      task: match.first, toEmployeeId: toEmployeeId,
      employees: employees, computedByTaskId: computed, moves: _moves,
    );
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    setState(() {
      _moves[taskId] = toEmployeeId;
      // Follow the work: after a move, show where it landed.
      _selectedId = toEmployeeId;
    });
  }

  Future<void> _apply(MoveDrafts moves) async {
    setState(() => _applying = true);
    final repo = ref.read(workforcePlanningRepositoryProvider);
    final failed = <String>[];
    for (final e in moves.entries) {
      try {
        await repo.reassignTaskOwner(e.key, e.value);
      } catch (_) {
        failed.add(e.key);
      }
    }
    if (!mounted) return;
    setState(() {
      _applying = false;
      // Keep only what failed, so a retry re-sends exactly those.
      _moves.removeWhere((id, _) => !failed.contains(id));
    });
    ref.invalidate(wpTasksProvider);
    ref.invalidate(wpPersonLoadsProvider);
    ref.invalidate(wpAllTaskComputedProvider);
    ref.invalidate(ownerComputedProvider);
    ref.invalidate(roleScorecardListProvider);
    final ok = moves.length - failed.length;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(failed.isEmpty
          ? 'Applied $ok ${ok == 1 ? 'move' : 'moves'}.'
          : 'Applied $ok, ${failed.length} failed — those are still pending.'),
    ));
  }
}
