import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/status_colors.dart';
import '../../../app/theme.dart';
import '../../../data/models/employee.dart';
import '../../../data/models/role_scorecard.dart';
import '../../../data/models/workforce_planning.dart';
import '../../../data/repositories/role_scorecard_repository.dart';
import '../../../data/repositories/workforce_planning_repository.dart';
import '../../documents/providers.dart' show roleScorecardByIdProvider;
import '../../responsibility_cards/responsibility_rows.dart';
import '../area_placement.dart';
import '../duplicate_check.dart';
import '../duplicate_warning.dart';
import '../removal_lifecycle.dart';
import '../tabs/task_form_dialog.dart';
import '../task_badges.dart';
import '../wp_providers.dart';

/// The second pane of the role workbench: this card's own responsibilities —
/// `wp_tasks` rows unified with the role card by migration
/// `20260720000002` — grouped by area, costed inline, archived or deleted.
///
/// Areas sort by `area_sort`, tasks within an area by `task_sort` — never
/// alphabetically. The role-card PDF and the employment-contract Annex A
/// render in exactly this order, so this pane must show a manager the same
/// order those documents do.
///
/// A row's name renders as plain text; renaming goes through the same "Edit"
/// dialog as costing (`⋮` → Edit), which the Responsibilities tab already uses for the
/// full costing model — a second costing form is exactly what this pane
/// avoids building. "Add" and "Link existing task" reuse that same dialog
/// (Add) or `diffResponsibilities` + `saveResponsibilities` (Link, and a
/// brand-new area) — the same two functions the old (now-deleted) card
/// editor's Save button used.
///
/// Archive/Delete are gated by [removalActionForTask]: a task with
/// `wp_task_assignments` history is archived, never deleted, because costing
/// and load attribution hang off that history. That gate applies ONLY to the
/// `⋮` menu — nothing else in this pane can drop a persisted row, so a batch
/// save can never silently delete one behind the gate's back.
class ResponsibilitiesPane extends ConsumerStatefulWidget {
  const ResponsibilitiesPane({
    super.key,
    required this.cardId,
    required this.companyId,
  });

  final String cardId;
  final String companyId;

  @override
  ConsumerState<ResponsibilitiesPane> createState() =>
      _ResponsibilitiesPaneState();
}

class _ResponsibilitiesPaneState extends ConsumerState<ResponsibilitiesPane> {
  /// True once `_areas`/`_existingRows` have been captured from
  /// `wpTasksProvider`'s first successful load in this build cycle. Reset to
  /// false after any mutation this pane makes (see
  /// `_invalidateAfterTaskChange`) or by [_resync], so the next successful
  /// load recaptures fresh server state — never a stale local guess about
  /// what the server now holds.
  ///
  /// This gate exists purely to keep `_areas`/`RespDraft` object identity
  /// stable across ordinary rebuilds — `_buildArea`/`_buildTaskRow` key their
  /// rows by `identityHashCode` of those objects, and recomputing fresh
  /// objects on every build would change every key on every frame, tearing
  /// down and rebuilding the whole tree even when nothing changed. It is NOT
  /// standing in for unsaved local edits: see [_resync]'s doc comment for why
  /// this pane, unlike `KpisPane`, has none to protect.
  bool _captured = false;
  final List<_AreaDraft> _areas = [];

  /// The card's own ACTIVE wp_tasks rows, captured on load — the baseline
  /// `diffResponsibilities` diffs against. Never re-derived from an upsert's
  /// return (it carries no wp_tasks embed).
  List<Map<String, dynamic>> _existingRows = const [];

  bool _saving = false;
  String? _error;

  void _captureFrom(List<WpTask> allTasks) {
    final mine =
        [
            for (final t in allTasks)
              if (t.roleScorecardId == widget.cardId && t.status == 'ACTIVE')
                t,
          ]
          ..sort((a, b) {
            final c = a.areaSort.compareTo(b.areaSort);
            return c != 0 ? c : a.taskSort.compareTo(b.taskSort);
          });
    _existingRows = [
      for (final t in mine)
        if ((t.responsibilityArea ?? '').trim().isNotEmpty)
          {
            'id': t.id,
            'responsibility_area': t.responsibilityArea,
            'name': t.name,
            'area_sort': t.areaSort,
            'task_sort': t.taskSort,
          },
    ];
    _areas.clear();
    final areaOrder = <String>[];
    final grouped = <String, List<RespDraft>>{};
    for (final t in mine) {
      final area = (t.responsibilityArea ?? '').trim();
      if (area.isEmpty) continue;
      final tasks = grouped.putIfAbsent(area, () {
        areaOrder.add(area);
        return [];
      });
      tasks.add(RespDraft(id: t.id, name: t.name));
    }
    for (final area in areaOrder) {
      _areas.add(_AreaDraft(area, grouped[area]!));
    }
    _captured = true;
  }

  /// Mirrors `responsibilities_tab.dart`'s `_invalidateAfterTaskChange` exactly (a
  /// card-linked task IS a role-card responsibility, so touching one here
  /// changes what Balance, Role View and the card's own detail/PDF/Annex A
  /// read), plus `roleScorecardByIdProvider(cardId)` for THIS card — always,
  /// even when [cardIds] is empty, since every mutation this pane makes
  /// touches this card one way or another.
  void _invalidateAfterTaskChange(Iterable<String?> cardIds) {
    ref.invalidate(wpTasksProvider);
    ref.invalidate(wpPersonLoadsProvider);
    ref.invalidate(wpAllTaskComputedProvider);
    ref.invalidate(ownerComputedProvider);
    ref.invalidate(roleScorecardListProvider);
    ref.invalidate(wpTaskAssignmentsProvider);
    for (final id in {...cardIds, widget.cardId}.whereType<String>()) {
      ref.invalidate(roleScorecardByIdProvider(id));
    }
    // Force a resync from the next successful load rather than trust local
    // state, which a partially-failed save could have left disagreeing with
    // the server.
    _captured = false;
  }

  /// Explicit resync: `wpTasksProvider` is watched, but [_captured] only
  /// flips false right after THIS pane's own mutations (see its doc
  /// comment), so another screen changing the same card's tasks — e.g. the
  /// Responsibilities tab editing one directly, or a different workbench tab — would
  /// otherwise leave [_areas]/[_existingRows] silently stale.
  ///
  /// Unlike `KpisPane._resync`, this never confirms before discarding
  /// anything, because there is nothing local to discard: every mutation
  /// this pane makes (`_addArea`, `_linkExisting`, `_addTask`/`_editTask` via
  /// `TaskFormDialog`, archive, delete) persists to the server the instant
  /// its dialog is confirmed. Area and task names render as plain `Text` in
  /// `_buildArea`/`_buildTaskRow`, never a `TextField` a manager could leave
  /// mid-edit — so a dirty-vs-baseline comparison here would have nothing
  /// that could ever differ, which is worse than no check at all rather than
  /// a safeguard. `KpisPane` stages edits in its own `TextEditingController`s
  /// behind a bottom `Save` button; this pane has no such staging and no
  /// `Save` button to stage behind.
  ///
  /// Invalidates the same set as [_invalidateAfterTaskChange] rather than
  /// `wpTasksProvider` alone: the other screen whose change this is pulling in
  /// could just as easily have recosted a task or moved its owner, and the
  /// hours column and owner badges on this pane read `wpAllTaskComputedProvider`
  /// and `wpTaskAssignmentsProvider`, not the task row. Refetching only the
  /// names would leave a control whose tooltip promises "reload from the
  /// server" showing stale hours next to fresh names.
  void _resync() {
    _invalidateAfterTaskChange(const []);
    setState(() {});
  }

  Future<void> _persistDraft(
    List<({String area, List<RespDraft> tasks})> draft,
  ) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final diff = diffResponsibilities(
        draft: draft,
        existingRows: _existingRows,
        cardId: widget.cardId,
        companyId: widget.companyId,
      );
      await ref
          .read(roleScorecardRepositoryProvider)
          .saveResponsibilities(
            cardId: widget.cardId,
            inserts: diff.inserts,
            updates: diff.updates,
            deleteIds: diff.deleteIds,
          );
      _invalidateAfterTaskChange(const []);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Prompts for a brand-new area and its first responsibility, then inserts
  /// it via `diffResponsibilities` — the one gap the "Edit" dialog can't fill,
  /// since its area field only offers areas the selected card already has.
  ///
  /// The first-responsibility field runs the duplicate nudge as you type (see
  /// [SimilarNameWarning]); it is the one field in this pane that creates a
  /// `wp_tasks` row from a name alone.
  Future<void> _addArea(List<WpTask> allTasks) async {
    final result = await showDialog<({String area, String task})>(
      context: context,
      builder: (ctx) {
        final areaCtl = TextEditingController();
        final taskCtl = TextEditingController();
        var similar = const <SimilarMatch>[];
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('New responsibility area'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: areaCtl,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Area name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: taskCtl,
                  decoration: const InputDecoration(
                    labelText: 'First responsibility',
                  ),
                  onChanged: (v) => setDialogState(
                    () => similar = findSimilarAccountabilities(
                      typed: v,
                      all: allTasks,
                    ),
                  ),
                ),
                SimilarNameWarning(matches: similar),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final area = areaCtl.text.trim();
                  final task = taskCtl.text.trim();
                  if (area.isEmpty || task.isEmpty) return;
                  Navigator.pop(ctx, (area: area, task: task));
                },
                child: const Text('Add'),
              ),
            ],
          ),
        );
      },
    );
    if (result == null) return;
    await _persistDraft([
      for (final a in _areas) (area: a.area, tasks: a.tasks),
      (area: result.area, tasks: [RespDraft(id: null, name: result.task)]),
    ]);
  }

  /// Adopts an ACTIVE, unlinked (`role_scorecard_id == null`) task onto this
  /// card's [areaIndex] via `diffResponsibilities` — its existing costing,
  /// node and cadence come with it. Retyping the name instead would create a
  /// second row describing the same work and double-count the hours.
  Future<void> _linkExisting(int areaIndex, List<WpTask> allTasks) async {
    final drafted = {
      for (final a in _areas)
        for (final t in a.tasks)
          if (t.id != null) t.id!,
    };
    final pool =
        [
            for (final t in allTasks)
              if (t.status == 'ACTIVE' &&
                  !t.isExpectation &&
                  t.roleScorecardId == null &&
                  !drafted.contains(t.id))
                t,
          ]
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (pool.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No unlinked tasks available.')),
      );
      return;
    }
    final picked = await showDialog<WpTask>(
      context: context,
      builder: (_) => _LinkExistingDialog(pool: pool),
    );
    if (picked == null) return;
    await _persistDraft([
      for (var i = 0; i < _areas.length; i++)
        (
          area: _areas[i].area,
          tasks: i == areaIndex
              ? [..._areas[i].tasks, RespDraft(id: picked.id, name: picked.name)]
              : _areas[i].tasks,
        ),
    ]);
  }

  /// Opens the Responsibilities tab's own costing dialog for a brand-new responsibility.
  /// Mirrors `responsibilities_tab.dart`'s `_openForm(existing: null)` exactly — the
  /// user picks this card and an area the same way the Responsibilities tab's "New
  /// task" button does — plus [TaskFormDialog.duplicateCheckPool], since this
  /// is the pane's other path from a typed name to a new `wp_tasks` row.
  Future<void> _addTask({
    required List<WpNode> nodes,
    required List<WpDriver> drivers,
    required List<WpRate> rates,
    required List<Employee> employees,
    required List<RoleScorecard> cards,
    required List<WpTask> allTasks,
  }) async {
    final result = await showDialog<WpTask>(
      context: context,
      builder: (_) => TaskFormDialog(
        companyId: widget.companyId,
        nodes: nodes,
        drivers: drivers,
        rates: rates,
        cards: cards,
        initialRoleId: widget.cardId,
        duplicateCheckPool: allTasks,
      ),
    );
    if (result == null) return;
    await _saveFromDialog(existing: null, result: result);
  }

  Future<void> _editTask(
    WpTask task, {
    required List<WpNode> nodes,
    required List<WpDriver> drivers,
    required List<WpRate> rates,
    required List<Employee> employees,
    required List<RoleScorecard> cards,
  }) async {
    final result = await showDialog<WpTask>(
      context: context,
      builder: (_) => TaskFormDialog(
        existing: task,
        companyId: widget.companyId,
        nodes: nodes,
        drivers: drivers,
        rates: rates,
        cards: cards,
      ),
    );
    if (result == null) return;
    await _saveFromDialog(existing: task, result: result);
  }

  Future<void> _saveFromDialog({
    required WpTask? existing,
    required WpTask result,
  }) async {
    // A new responsibility, or one moved to another card/area, needs a
    // position at the END of its area — moving a row silently reorders the
    // role-card PDF and the contract annex otherwise.
    final toSave = placeInArea(
      previous: existing,
      next: result,
      allTasks: ref.read(wpTasksProvider).asData?.value ?? const <WpTask>[],
    );
    try {
      await ref.read(workforcePlanningRepositoryProvider).saveTask(toSave);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save task: $e')));
      return;
    }
    _invalidateAfterTaskChange([result.roleScorecardId, existing?.roleScorecardId]);
  }

  Future<void> _archiveTask(WpTask task) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Archive responsibility?'),
        content: Text(
          'Archive "${task.name}"? It leaves everyone\'s load and this pane '
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
      await ref
          .read(workforcePlanningRepositoryProvider)
          .setTaskArchived(task.id, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not archive: $e')));
      return;
    }
    _invalidateAfterTaskChange([task.roleScorecardId]);
  }

  Future<void> _deleteTask(WpTask task) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete responsibility?'),
        content: Text(
          'Delete "${task.name}"? It has no assignment history, so this '
          'cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(c).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(workforcePlanningRepositoryProvider).deleteTask(task.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not delete: $e')));
      return;
    }
    _invalidateAfterTaskChange([task.roleScorecardId]);
  }

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(wpTasksProvider);
    final computedById = {
      for (final c
          in ref.watch(wpAllTaskComputedProvider).asData?.value ??
              const <WpTaskComputed>[])
        c.taskId: c,
    };
    final assignmentsByTask =
        ref.watch(wpAssignmentsByTaskProvider).asData?.value ??
        const <String, List<WpTaskAssignment>>{};
    final nodes = ref.watch(wpNodesProvider).asData?.value ?? const <WpNode>[];
    final drivers =
        ref.watch(wpDriversProvider).asData?.value ?? const <WpDriver>[];
    final rates = ref.watch(wpRatesProvider).asData?.value ?? const <WpRate>[];
    final employees =
        ref.watch(wpActiveEmployeesProvider).asData?.value ??
        const <Employee>[];
    final cards =
        ref.watch(roleScorecardListProvider).asData?.value ??
        const <RoleScorecard>[];

    return tasksAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Could not load responsibilities: $e'),
      ),
      data: (allTasks) {
        if (!_captured) _captureFrom(allTasks);
        final taskById = {for (final t in allTasks) t.id: t};
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      'Responsibilities',
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    if (_saving) ...[
                      const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                    ],
                    IconButton(
                      key: const ValueKey('resp-pane-resync'),
                      tooltip:
                          'Reload from the server — every change on this '
                          'pane is already saved, so nothing is discarded',
                      onPressed: _saving ? null : _resync,
                      icon: const Icon(Icons.refresh),
                    ),
                    TextButton.icon(
                      onPressed: _saving
                          ? null
                          : () => _addTask(
                              nodes: nodes,
                              drivers: drivers,
                              rates: rates,
                              employees: employees,
                              cards: cards,
                              allTasks: allTasks,
                            ),
                      icon: const Icon(Icons.add),
                      label: const Text('Add task'),
                    ),
                    TextButton.icon(
                      onPressed: _saving ? null : () => _addArea(allTasks),
                      icon: const Icon(Icons.create_new_folder_outlined),
                      label: const Text('Add area'),
                    ),
                  ],
                ),
                for (var i = 0; i < _areas.length; i++)
                  _buildArea(
                    context,
                    i,
                    taskById,
                    computedById,
                    assignmentsByTask,
                    allTasks,
                    nodes,
                    drivers,
                    rates,
                    employees,
                    cards,
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildArea(
    BuildContext context,
    int areaIndex,
    Map<String, WpTask> taskById,
    Map<String, WpTaskComputed> computedById,
    Map<String, List<WpTaskAssignment>> assignmentsByTask,
    List<WpTask> allTasks,
    List<WpNode> nodes,
    List<WpDriver> drivers,
    List<WpRate> rates,
    List<Employee> employees,
    List<RoleScorecard> cards,
  ) {
    final area = _areas[areaIndex];
    return Padding(
      key: ValueKey('resp-area-${identityHashCode(area)}'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            area.area,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          for (var j = 0; j < area.tasks.length; j++)
            _buildTaskRow(
              context,
              area.tasks[j],
              taskById,
              computedById,
              assignmentsByTask,
              nodes,
              drivers,
              rates,
              employees,
              cards,
            ),
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 4),
            child: TextButton.icon(
              onPressed: _saving
                  ? null
                  : () => _linkExisting(areaIndex, allTasks),
              icon: const Icon(Icons.link, size: 16),
              label: const Text('Link existing task'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskRow(
    BuildContext context,
    RespDraft draft,
    Map<String, WpTask> taskById,
    Map<String, WpTaskComputed> computedById,
    Map<String, List<WpTaskAssignment>> assignmentsByTask,
    List<WpNode> nodes,
    List<WpDriver> drivers,
    List<WpRate> rates,
    List<Employee> employees,
    List<RoleScorecard> cards,
  ) {
    final task = draft.id == null ? null : taskById[draft.id];
    final computed = task == null ? null : computedById[task.id];
    final tone = task == null ? null : criticalityTone(task.criticality);
    return Padding(
      key: ValueKey('resp-row-${identityHashCode(draft)}'),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        children: [
          Expanded(child: Text(draft.name)),
          const SizedBox(width: 8),
          SizedBox(
            width: 56,
            child: Align(
              alignment: Alignment.centerRight,
              // A task has no `wp_task_computed` row until it's actually
              // costed — that's "unknown", not "0 hours" (idle). Rendering a
              // dash here, never `0.0`, is what keeps the two distinguishable.
              child: computed == null
                  ? const Text('—')
                  : Text(
                      computed.hoursPerMonthBase.toStringAsFixed(1),
                      style: AppTheme.mono(context),
                    ),
            ),
          ),
          const SizedBox(width: 8),
          if (task != null && tone != null) ...[
            StatusChip(label: criticalityLabel(task.criticality)!, tone: tone),
            const SizedBox(width: 4),
          ],
          if (task != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (v) {
                switch (v) {
                  case 'edit':
                    _editTask(
                      task,
                      nodes: nodes,
                      drivers: drivers,
                      rates: rates,
                      employees: employees,
                      cards: cards,
                    );
                  case 'archive':
                    _archiveTask(task);
                  case 'delete':
                    _deleteTask(task);
                }
              },
              itemBuilder: (ctx) {
                // Archive/Delete are gated by removalActionForTask: a task
                // carrying wp_task_assignments history is archived, never
                // deleted — costing and load attribution hang off that
                // history.
                final count = assignmentsByTask[task.id]?.length ?? 0;
                final action = removalActionForTask(assignmentCount: count);
                return [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  if (action == RemovalAction.archive)
                    const PopupMenuItem(
                      value: 'archive',
                      child: Text('Archive'),
                    )
                  else
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete'),
                    ),
                ];
              },
            ),
        ],
      ),
    );
  }
}

class _AreaDraft {
  String area;
  final List<RespDraft> tasks;
  _AreaDraft(this.area, this.tasks);
}

/// A minimal picker for "Link existing task" — the true orphans (`ACTIVE`,
/// not an expectation, `role_scorecard_id == null`) not already drafted
/// anywhere on this card.
class _LinkExistingDialog extends StatefulWidget {
  const _LinkExistingDialog({required this.pool});

  final List<WpTask> pool;

  @override
  State<_LinkExistingDialog> createState() => _LinkExistingDialogState();
}

class _LinkExistingDialogState extends State<_LinkExistingDialog> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final rows = [
      for (final t in widget.pool)
        if (q.isEmpty || t.name.toLowerCase().contains(q)) t,
    ];
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Link an existing task',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search, size: 18),
                      hintText: 'Search',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _q = v),
                  ),
                ],
              ),
            ),
            Flexible(
              child: rows.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Nothing matches.'),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: rows.length,
                      itemBuilder: (context, i) {
                        final t = rows[i];
                        return ListTile(
                          title: Text(t.name),
                          onTap: () => Navigator.pop(context, t),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
