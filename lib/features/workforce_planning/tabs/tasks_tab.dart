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
import '../task_costing.dart';
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
class TasksTab extends ConsumerStatefulWidget {
  const TasksTab({super.key});

  @override
  ConsumerState<TasksTab> createState() => _TasksTabState();
}

class _TasksTabState extends ConsumerState<TasksTab> {
  /// Bulk-costing mode: rows become editable so a long uncosted backlog can be
  /// filled in one pass instead of one dialog at a time.
  bool _costMode = false;

  /// Edited-but-unsaved costing per task id. Only rows the user actually
  /// touched appear here; a row equal to its task is dropped so "N changes"
  /// never counts a no-op edit.
  final Map<String, CostDraft> _drafts = {};

  bool _saving = false;

  CostDraft _draftFor(WpTask t) => _drafts[t.id] ?? CostDraft.fromTask(t);

  void _edit(WpTask t, CostDraft next) {
    setState(() {
      if (next == CostDraft.fromTask(t)) {
        _drafts.remove(t.id);
      } else {
        _drafts[t.id] = next;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
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

    Widget table(List<WpTask> rows) => _costMode
        ? _costTable(
            context,
            rows,
            nodes: nodes,
            drivers: drivers,
            rates: rates,
            driverById: driverById,
            rateById: rateById,
          )
        : _taskTable(
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

    final uncosted = tasks.where(isTaskNotCosted).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(context, tasks, uncosted, companyId, nodes, drivers, rates,
              employees, cards),
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

  Widget _header(
    BuildContext context,
    List<WpTask> tasks,
    int uncosted,
    String? companyId,
    List<WpNode> nodes,
    List<WpDriver> drivers,
    List<WpRate> rates,
    List<Employee> employees,
    List<RoleScorecard> cards,
  ) {
    final cs = Theme.of(context).colorScheme;
    if (_costMode) {
      final n = _drafts.length;
      return Row(
        children: [
          Expanded(
            child: Text(
              n == 0
                  ? 'Costing — edit the cells, then save.'
                  : '$n unsaved ${n == 1 ? 'change' : 'changes'}',
              style: TextStyle(color: n == 0 ? cs.onSurfaceVariant : cs.primary),
            ),
          ),
          TextButton(
            onPressed: _saving ? null : _exitCostMode,
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: (_saving || n == 0) ? null : () => _saveCosts(tasks),
            icon: _saving
                ? const SizedBox(
                    width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving…' : (n == 0 ? 'Save' : 'Save $n')),
          ),
        ],
      );
    }
    return Row(
      children: [
        if (uncosted > 0)
          Expanded(
            child: Text(
              '$uncosted of ${tasks.length} tasks are not costed — they contribute 0 hours to load.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          )
        else
          const Spacer(),
        OutlinedButton.icon(
          onPressed: () => setState(() => _costMode = true),
          icon: const Icon(Icons.calculate_outlined),
          label: const Text('Cost tasks'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: companyId == null
              ? null
              : () => _openForm(
                    context, ref, companyId, nodes, drivers, rates, employees, cards),
          icon: const Icon(Icons.add),
          label: const Text('New task'),
        ),
      ],
    );
  }

  Future<void> _exitCostMode() async {
    if (_drafts.isNotEmpty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Discard changes?'),
          content: Text(
              '${_drafts.length} edited ${_drafts.length == 1 ? 'row has' : 'rows have'} not been saved.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep editing')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
          ],
        ),
      );
      if (discard != true) return;
    }
    setState(() {
      _drafts.clear();
      _costMode = false;
    });
  }

  Future<void> _saveCosts(List<WpTask> tasks) async {
    final byId = {for (final t in tasks) t.id: t};
    final patches = <String, Map<String, dynamic>>{
      for (final e in _drafts.entries)
        if (byId.containsKey(e.key)) e.key: draftPatch(e.value),
    };
    setState(() => _saving = true);
    List<String> failed;
    try {
      failed = await ref.read(workforcePlanningRepositoryProvider).updateTaskCosts(patches);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $e')));
      return;
    }
    if (!mounted) return;
    // Keep only the rows that failed still dirty, so a retry re-sends exactly
    // those and the user can see which ones did not land.
    setState(() {
      _saving = false;
      _drafts.removeWhere((id, _) => !failed.contains(id));
    });
    _invalidateAfterTaskChange(ref, patches.keys.map((id) => byId[id]?.roleScorecardId));
    final saved = patches.length - failed.length;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(failed.isEmpty
          ? 'Saved $saved ${saved == 1 ? 'task' : 'tasks'}.'
          : 'Saved $saved, ${failed.length} failed — the failed rows are still highlighted.'),
    ));
  }

  /// Bulk costing grid. Times and minutes each have a source picker (manual, or
  /// a driver/rate) plus a value cell, and hours recompute live using the same
  /// formula as `wp_task_computed` so the number here matches what the Balance
  /// tab will show after saving.
  Widget _costTable(
    BuildContext context,
    List<WpTask> rows, {
    required List<WpNode> nodes,
    required List<WpDriver> drivers,
    required List<WpRate> rates,
    required Map<String, WpDriver> driverById,
    required Map<String, WpRate> rateById,
  }) {
    final cs = Theme.of(context).colorScheme;
    return ResponsiveTable(
      child: DataTable(
        columnSpacing: 16,
        columns: const [
          DataColumn(label: Text('Task')),
          DataColumn(label: Text('Node')),
          DataColumn(label: Text('Times/mo')),
          DataColumn(label: Text('Minutes each')),
          DataColumn(label: Text('Hours/mo')),
        ],
        rows: [
          for (final t in rows)
            DataRow(
              color: _drafts.containsKey(t.id)
                  ? WidgetStatePropertyAll(cs.primaryContainer.withValues(alpha: 0.25))
                  : null,
              cells: [
                DataCell(ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: Text(t.name, overflow: TextOverflow.ellipsis),
                )),
                DataCell(_nodeCell(t, nodes)),
                DataCell(_timesCell(t, drivers, driverById)),
                DataCell(_minutesCell(t, rates, rateById)),
                DataCell(_costedHoursCell(context, t, driverById, rateById)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _nodeCell(WpTask t, List<WpNode> nodes) {
    final d = _draftFor(t);
    return SizedBox(
      width: 170,
      child: DropdownButton<String?>(
        isExpanded: true,
        value: nodes.any((n) => n.id == d.nodeId) ? d.nodeId : null,
        hint: const Text('—'),
        underline: const SizedBox.shrink(),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('—')),
          for (final n in nodes)
            DropdownMenuItem<String?>(value: n.id, child: Text(n.name, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) => _edit(t, v == null ? d.copyWith(clearNodeId: true) : d.copyWith(nodeId: v)),
      ),
    );
  }

  Widget _timesCell(WpTask t, List<WpDriver> drivers, Map<String, WpDriver> driverById) {
    final d = _draftFor(t);
    final isDriver = d.timesSource == 'driver';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 190,
          child: DropdownButton<String>(
            isExpanded: true,
            value: isDriver && driverById.containsKey(d.driverId) ? d.driverId! : 'manual',
            underline: const SizedBox.shrink(),
            items: [
              const DropdownMenuItem(value: 'manual', child: Text('Manual')),
              for (final dr in drivers)
                DropdownMenuItem(
                  value: dr.id,
                  child: Text(
                    dr.grows ? '${dr.name} ↗' : dr.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) => _edit(
              t,
              v == 'manual'
                  ? d.copyWith(timesSource: 'manual', clearDriverId: true)
                  : d.copyWith(timesSource: 'driver', driverId: v, driverFactor: d.driverFactor),
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 66,
          child: TextFormField(
            // The source is part of the key: switching manual<->driver changes
            // what this field means (a count vs a factor), and without it the
            // field would keep showing the previous number while editing the
            // other column.
            key: ValueKey('times-${t.id}-${isDriver ? 'driver' : 'manual'}'),
            initialValue: isDriver
                ? _num(d.driverFactor)
                : (d.timesManual == null ? '' : _num(d.timesManual!)),
            decoration: InputDecoration(
              isDense: true,
              labelText: isDriver ? '×' : null,
              hintText: isDriver ? '1' : '0',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (raw) {
              final v = parseCostField(raw);
              _edit(
                t,
                isDriver
                    ? d.copyWith(driverFactor: v ?? 1)
                    : (v == null
                        ? d.copyWith(clearTimesManual: true)
                        : d.copyWith(timesManual: v)),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _minutesCell(WpTask t, List<WpRate> rates, Map<String, WpRate> rateById) {
    final d = _draftFor(t);
    final isRate = d.minutesSource == 'rate';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 190,
          child: DropdownButton<String>(
            isExpanded: true,
            value: isRate && rateById.containsKey(d.rateId) ? d.rateId! : 'manual',
            underline: const SizedBox.shrink(),
            items: [
              const DropdownMenuItem(value: 'manual', child: Text('Manual')),
              for (final r in rates)
                DropdownMenuItem(value: r.id, child: Text(r.name, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => _edit(
              t,
              v == 'manual'
                  ? d.copyWith(minutesSource: 'manual', clearRateId: true)
                  : d.copyWith(minutesSource: 'rate', rateId: v),
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 66,
          // A rate defines its own minutes, so the cell is read-only there —
          // showing an editable field would imply an override that the schema
          // does not have.
          child: isRate
              ? Text(
                  _num(rateById[d.rateId]?.minutesEach ?? 0),
                  style: AppTheme.mono(context),
                )
              : TextFormField(
                  key: ValueKey('mins-${t.id}-manual'),
                  initialValue: d.minutesManual == null ? '' : _num(d.minutesManual!),
                  decoration: const InputDecoration(isDense: true, hintText: '0'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (raw) {
                    final v = parseCostField(raw);
                    _edit(
                      t,
                      v == null
                          ? d.copyWith(clearMinutesManual: true)
                          : d.copyWith(minutesManual: v),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _costedHoursCell(
    BuildContext context,
    WpTask t,
    Map<String, WpDriver> driverById,
    Map<String, WpRate> rateById,
  ) {
    final d = _draftFor(t);
    if (!draftIsCosted(d, driverById, rateById)) {
      return const StatusChip(label: 'Not costed', tone: StatusTone.neutral);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          draftHoursPerMonth(d, driverById, rateById).toStringAsFixed(1),
          style: AppTheme.mono(context),
        ),
        if (draftIsGrowing(d, driverById)) ...[
          const SizedBox(width: 6),
          const StatusChip(label: 'Scales', tone: StatusTone.info),
        ],
      ],
    );
  }

  /// Trims a trailing `.0` so whole numbers read as "20" not "20.0" in inputs.
  static String _num(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

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
