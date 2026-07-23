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
import 'needs_attention_strip.dart';
import 'tab_intro.dart';
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

  /// The drag in flight. Held while the pointer is down so both ends of the
  /// move can show their resulting load BEFORE the drop — committing a move
  /// without seeing the delta is committing blind.
  HoverPreview? _hover;

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
    // What the rail RENDERS includes the hovered move, so the bars move under
    // the cursor. What Apply writes is `moves` only — the preview is never
    // committed by hovering.
    final preview = {...moves, ...?_hover?.asMove};
    final projections = buildProjections(
      employees: employees, tasks: tasks, computedByTaskId: computed,
      capacityByEmployee: capacity, multiplier: multiplier,
      defaultCapacity: defaultCapacity, moves: preview,
    );
    if (projections.isEmpty) {
      return const Center(child: Text('No active people to show.'));
    }
    final orphans = orphanHours(
        tasks: tasks, computedByTaskId: computed, employees: employees,
        multiplier: multiplier, moves: preview);
    final pool = unassignedTasks(
        employees: employees, tasks: tasks, computedByTaskId: computed,
        multiplier: multiplier, moves: preview);

    final selectedId = (_selectedId == kUnassignedId && pool.isNotEmpty)
        ? kUnassignedId
        : (projections.any((p) => p.employeeId == _selectedId)
            ? _selectedId!
            : projections.first.employeeId);
    final selected = selectedId == kUnassignedId
        ? projections.first
        : projections.firstWhere((p) => p.employeeId == selectedId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const NeedsAttentionStrip(),
        _planBar(context, moves, projections, orphans),
        const Divider(height: 1),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 340,
                child: _peopleList(context, projections, selectedId, tasks,
                    computed, employees, preview, pool,
                    ref.watch(wpKpiCountByEmployeeProvider).asData?.value ?? const {}),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: selectedId == kUnassignedId
                    ? _poolPanel(context, pool, orphans)
                    : _taskPanel(context, selected, employees, tasks, computed,
                        multiplier, preview),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---- header ----------------------------------------------------------

  Widget _planBar(BuildContext context, MoveDrafts moves,
      List<LoadProjection> projections, OrphanHours orphans) {
    final cs = Theme.of(context).colorScheme;
    final over = projections.where((p) => p.plannedStatus == LoadStatus.over).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TabIntro(
            purpose: 'Move work until nobody is over capacity. '
                'Drag a task from one person onto another.',
            details: [
              (
                term: 'Nothing saves until Apply.',
                meaning: 'Drag freely to try a rebalance — each person shows '
                    'their planned load with the current one struck through '
                    'beside it. Reset throws the draft away.',
              ),
              WpGlossary.load,
              WpGlossary.derived,
              WpGlossary.weighted,
              WpGlossary.unassigned,
              WpGlossary.notCosted,
            ],
          ),
          const SizedBox(height: 8),
          Row(
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
                // Only GENUINE orphans are reported. The legacy capacity-model
                // rows are also technically unattributed, but their costing
                // already lives on the responsibilities they describe, so
                // counting them announced ~800h of debt that does not exist.
                if (orphans.genuine > 0)
                  Tooltip(
                    message: 'Costed work with no owner and no staffed role card. '
                        'It reaches nobody, so it is missing from every load figure. '
                        'Open Unassigned in the rail to hand it out.',
                    child: Text(
                        '${orphans.genuine.toStringAsFixed(1)}h unassigned '
                        '(${(orphans.genuine / 160).toStringAsFixed(1)} FTE)',
                        style: TextStyle(
                            color:
                                StatusPalette.of(context, StatusTone.warning).foreground)),
                  ),
                if (orphans.legacyReference > 0)
                  Tooltip(
                    message: 'The original capacity-model rows. Their hours were '
                        'transferred onto the role-card responsibilities, so they are '
                        'a reference copy and are NOT counted anywhere. Delete them '
                        'from the Tasks tab once these numbers are trusted.',
                    child: Text(
                        '${orphans.legacyReference.toStringAsFixed(0)}h reference (not counted)',
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                  ),
              ],
            ),
          ),
          if (moves.isNotEmpty) ...[
            TextButton(
              onPressed: _applying
                  ? null
                  : () => setState(() {
                        _moves.clear();
                        _hover = null;
                      }),
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
    List<PlannedTask> pool,
    Map<String, int> kpiCounts,
  ) {
    // The pool is pinned first: it is the largest single block of work in the
    // system, and as a header footnote it read as an accounting curiosity
    // rather than a queue somebody has to empty.
    final showPool = pool.isNotEmpty;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: projections.length + (showPool ? 1 : 0),
      itemBuilder: (context, i) {
        if (showPool && i == 0) {
          return _poolRow(context, pool, selectedId == kUnassignedId);
        }
        final p = projections[i - (showPool ? 1 : 0)];
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
          // Hovering re-renders the rail with the move applied, so both the
          // source and the target show their resulting load before the drop.
          onMove: (_) {
            if (_hover?.overEmployeeId != p.employeeId) {
              setState(() => _hover = _hover?.over(p.employeeId));
            }
          },
          onLeave: (_) {
            if (_hover?.overEmployeeId == p.employeeId) {
              setState(() => _hover = _hover?.over(null));
            }
          },
          onAcceptWithDetails: (d) =>
              _drop(d.data, p.employeeId, tasks, employees, computed),
          builder: (ctx, cand, _) => _personRow(ctx, p,
              p.employeeId == selectedId, cand.isNotEmpty, kpiCounts[p.employeeId] ?? 0),
        );
      },
    );
  }

  /// The unassigned pool as the first row in the rail — a place you can open
  /// and drag work out of, not a number in a header.
  Widget _poolRow(BuildContext context, List<PlannedTask> pool, bool selected) {
    final cs = Theme.of(context).colorScheme;
    final warn = StatusPalette.of(context, StatusTone.warning);
    final hours = pool.fold(0.0, (s, p) => s + p.hours);
    return InkWell(
      onTap: () => setState(() => _selectedId = kUnassignedId),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? warn.background : warn.background.withValues(alpha: 0.45),
          border: Border(
            left: BorderSide(
                width: 3, color: selected ? warn.foreground : Colors.transparent),
            bottom: BorderSide(color: cs.outlineVariant),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.inbox_outlined, size: 16, color: warn.foreground),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Unassigned',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, color: warn.foreground)),
                ),
                Text('${hours.toStringAsFixed(1)}h', style: AppTheme.mono(context)),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${pool.length} ${pool.length == 1 ? 'task' : 'tasks'} reaching nobody'
              '${hours > 0 ? ' · ${(hours / 160).toStringAsFixed(1)} FTE' : ''}',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  /// The pool's contents, draggable onto anyone in the rail.
  Widget _poolPanel(
      BuildContext context, List<PlannedTask> pool, OrphanHours orphans) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Unassigned', style: Theme.of(context).textTheme.titleMedium),
              Text(
                '${pool.length} ${pool.length == 1 ? 'task' : 'tasks'} · '
                '${orphans.genuine.toStringAsFixed(1)}h reaching nobody. '
                'Drag onto a person in the rail to hand it out.',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: pool.length,
            itemBuilder: (context, i) => _taskCard(context, pool[i]),
          ),
        ),
      ],
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
            if (p.understated)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 12,
                        color: StatusPalette.of(context, StatusTone.warning).foreground),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${p.uncostedCount} of ${p.taskCount} uncosted — understated',
                        style: TextStyle(
                            fontSize: 11,
                            color:
                                StatusPalette.of(context, StatusTone.warning).foreground),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
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
    // An expectation and an un-estimated task both show no hours, but they are
    // NOT the same thing: one is resolved and will never carry hours, the other
    // is outstanding work. Calling both "not costed" told HR there was a
    // backlog where there was none.
    // Only weighted responsibilities appear here. Behavioural standards and
    // required skills are role-scorecard concerns: they apply across the whole
    // role rather than being units of work, so they carry no hours and have no
    // place in a workload view. plannedTasksFor already excludes them.
    final movable = [for (final r in rows) if (r.hours > 0) r];
    final toCost = [for (final r in rows) if (r.hours <= 0) r];

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
                      '${rows.length} weighted '
                      '${rows.length == 1 ? 'responsibility' : 'responsibilities'} · '
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
        const SizedBox(height: 4),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Text('No work assigned.',
                      style: TextStyle(color: cs.onSurfaceVariant)))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    for (final r in movable) _taskCard(context, r),
                    if (toCost.isNotEmpty) ...[
                      _sectionHeader(
                        context,
                        '${toCost.length} still to cost',
                        'No hours yet, so moving one would change nothing. '
                            'Cost them on the Tasks tab.',
                        StatusTone.warning,
                      ),
                      for (final r in toCost) _taskCard(context, r),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  /// Divider between weighted work that can be moved and weighted work that is
  /// blocked on an estimate.
  Widget _sectionHeader(
      BuildContext context, String label, String help, StatusTone tone) {
    final cs = Theme.of(context).colorScheme;
    final pal = StatusPalette.of(context, tone);
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: pal.background,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, color: pal.foreground)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(help,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _taskCard(BuildContext context, PlannedTask t) {
    final cs = Theme.of(context).colorScheme;
    final movable = t.hours > 0;
    // An expectation gets a quieter, borderless treatment rather than the same
    // card at lower opacity: dimming a card that looks identical reads as
    // "broken", when the row is simply a different kind of thing.
    final quiet = !movable;
    final card = Container(
      margin: EdgeInsets.only(bottom: quiet ? 2 : 6),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: quiet ? 7 : 10),
      decoration: BoxDecoration(
        color: t.moved
            ? cs.primaryContainer.withValues(alpha: 0.3)
            : (quiet ? Colors.transparent : cs.surface),
        border: Border.all(
            color: t.moved
                ? cs.primary
                : (quiet ? Colors.transparent : cs.outlineVariant)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(
              movable
                  ? Icons.drag_indicator
                  : (t.task.isExpectation
                      ? Icons.check_circle_outline
                      : Icons.schedule),
              size: 15,
              color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.task.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: quiet
                        ? TextStyle(fontSize: 13, color: cs.onSurfaceVariant)
                        : null),
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
          if (movable)
            Text('${t.hours.toStringAsFixed(1)}h', style: AppTheme.mono(context))
          else
            Text('needs costing',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ],
      ),
    );
    if (!movable) return card;
    return Draggable<String>(
      data: t.task.id,
      onDragStarted: () => setState(() => _hover = HoverPreview(
            taskId: t.task.id,
            fromEmployeeId: _selectedId ?? kUnassignedId,
          )),
      // Cleared on BOTH completion and cancellation — a preview left behind
      // would render a move that was never made.
      onDragEnd: (_) => setState(() => _hover = null),
      onDraggableCanceled: (_, _) => setState(() => _hover = null),
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
      // Clear the preview HERE, not only in Draggable.onDragEnd: selecting the
      // destination unmounts the card being dragged, and a disposed Draggable
      // never fires onDragEnd — the stale hover would then keep rendering a
      // move that Reset could not clear.
      _hover = null;
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
