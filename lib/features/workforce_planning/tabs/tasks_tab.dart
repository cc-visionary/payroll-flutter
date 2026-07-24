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
import '../task_badges.dart';
import '../task_costing.dart';
import '../tasks_paging.dart';
import '../tasks_rows.dart';
import '../wp_providers.dart';
import 'role_view_tab.dart' show ownerComputedProvider;
import 'tab_intro.dart';
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

  /// Which slice of the inventory is on screen. The whole 282-row inventory
  /// used to render eagerly inside one Column — ~1,700 cells, and in cost mode
  /// every keystroke rebuilt all of them along with a driver and a rate
  /// dropdown per row. Scoping and paging bound that work.
  String _scope = TaskScope.allKey;
  int _page = 0;
  int _pageSize = 50;

  /// Search + status/node/owner filters, applied before paging. 282
  /// sentence-long responsibilities cannot be found by scrolling six pages.
  TaskFilter _filter = const TaskFilter();
  final _searchCtl = TextEditingController();

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

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
    final partition = partitionByStatus(tasks);
    final activeTasks = partition.active;
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
    // Scope first, then page: "Operations Manager" should be its own 38 rows,
    // not page 2-of-6 of everything.
    final scopes = buildScopes(activeTasks, cards);
    final scopeKey =
        scopes.any((s) => s.key == _scope) ? _scope : TaskScope.allKey;
    final withHolders = cardsWithActiveHolders(employees);
    final scoped = applyTaskFilter(
        tasksInScope(activeTasks, cards, scopeKey), _filter, driverById, rateById,
        cardsWithHolders: withHolders);
    final pageInfo = pageOfTasks(scoped, _page, _pageSize);
    final groups = groupTasks(pageInfo.tasks, cards);
    // Counts and bulk actions must see the WHOLE inventory, never the page —
    // otherwise "Delete all" would silently delete only what is on screen.
    final allGroups = groupTasks(activeTasks, cards);
    // (card, area) -> every task in it, so "Fill area" covers the whole area
    // rather than whatever happens to be on the current page.
    final wholeArea = <String, List<WpTask>>{
      for (final g in allGroups.cardGroups)
        for (final a in g.areas) '${g.cardId} ${a.area}': a.tasks,
    };

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

    final progress = costingProgress(activeTasks, driverById, rateById);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TabIntro(
            purpose: 'Every responsibility in the business, what it costs in '
                'hours, and who it reaches.',
            details: [
              (
                term: 'A responsibility IS a task.',
                meaning: 'The same row appears on the role card and here. Edit '
                    'it in either place — rename, re-area, re-card — and both '
                    'update, because there is only one record.',
              ),
              (
                term: 'Three costing states.',
                meaning: 'Costed (has hours) · Needs costing (real work, no '
                    'estimate yet) · Expectation (a behavioural standard that '
                    'will never carry hours). Only the middle one is a backlog.',
              ),
              WpGlossary.derived,
              WpGlossary.node,
              WpGlossary.multiplier,
              (
                term: 'From capacity model',
                meaning: 'The original spreadsheet rows. Their hours were moved '
                    'onto the responsibilities they describe, so they are kept '
                    'only as a reference and are counted nowhere.',
              ),
            ],
          ),
          const SizedBox(height: 12),
          _header(context, activeTasks, progress, companyId, nodes, drivers, rates,
              employees, cards),
          const SizedBox(height: 12),
          _scopeBar(context, scopes, scopeKey, pageInfo),
          const SizedBox(height: 8),
          _filterBar(context, nodes, employees, employeeNameById,
              tallyAssignments(activeTasks, withHolders)),
          const SizedBox(height: 12),
          if (activeTasks.isEmpty)
            const Text('No tasks yet. Click "New task".')
          else ...[
            for (final cardGroup in groups.cardGroups) ...[
              Text(cardGroup.jobTitle, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final areaGroup in cardGroup.areas) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 6),
                  child: Row(
                    children: [
                      Text(areaGroup.area, style: Theme.of(context).textTheme.labelLarge),
                      if (_costMode) ...[
                        const SizedBox(width: 12),
                        TextButton.icon(
                          onPressed: () => _fillArea(
                              areaGroup.area,
                              wholeArea['${cardGroup.cardId} ${areaGroup.area}'] ??
                                  areaGroup.tasks,
                              driverById,
                              rateById),
                          icon: const Icon(Icons.playlist_add_check, size: 16),
                          label: const Text('Fill area'),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                table(areaGroup.tasks),
                const SizedBox(height: 16),
              ],
              const SizedBox(height: 8),
            ],
            if (groups.legacy.isNotEmpty) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      // Total, not the page — the count is about the bucket.
                      'From capacity model (${allGroups.legacy.length})',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () =>
                        _confirmBulkDeleteLegacy(context, ref, allGroups.legacy),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Delete all'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              table(groups.legacy),
              const SizedBox(height: 16),
            ],
            if (groups.unattributed.isNotEmpty) ...[
              Text(
                'Unattributed (${allGroups.unattributed.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              table(groups.unattributed),
            ],
          ],
          // Sibling of the if/else above, not nested inside it — an all-archived
          // card (zero active tasks) must still show its Archived section, not
          // just the "No tasks yet" empty state.
          if (partition.archived.isNotEmpty) ...[
            const SizedBox(height: 24),
            _ArchivedSection(
              tasks: partition.archived,
              onRestore: (t) async {
                await ref.read(workforcePlanningRepositoryProvider)
                    .setTaskArchived(t.id, false);
                _invalidateAfterTaskChange(ref, [t.roleScorecardId]);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _header(
    BuildContext context,
    List<WpTask> tasks,
    CostingProgress progress,
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
        Expanded(
          child: progress.done
              ? Text('All ${progress.total} tasks resolved — '
                  '${progress.costed} costed, ${progress.expectation} expectations.',
                  style: TextStyle(
                      color: StatusPalette.of(context, StatusTone.success).foreground))
              : Text(
                  '${progress.resolved} of ${progress.total} resolved · '
                  '${progress.toCost} still to cost'
                  '${progress.expectation > 0 ? ' · ${progress.expectation} expectations' : ''}',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
        ),
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

  /// One estimate applied to every uncosted task in a responsibility area.
  /// Costing 164 responsibilities one cell at a time is 328 entries; most
  /// responsibilities inside an area take roughly the same effort, so this
  /// turns it into ~42 estimates plus the exceptions HR chooses to override.
  /// Search + status/node/owner filters. Any change resets to page 0 —
  /// filtering down to two results while sitting on page 4 shows nothing.
  Widget _filterBar(BuildContext context, List<WpNode> nodes,
      List<Employee> employees, Map<String, String> employeeNameById,
      AssignmentTally tally) {
    void set(TaskFilter f) => setState(() {
          _filter = f;
          _page = 0;
        });

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 280,
          child: TextField(
            controller: _searchCtl,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 18),
              hintText: 'Search tasks and areas',
              border: const OutlineInputBorder(),
              suffixIcon: _filter.query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchCtl.clear();
                        set(TaskFilter(
                            state: _filter.state,
                            nodeId: _filter.nodeId,
                            ownerId: _filter.ownerId,
                            assignment: _filter.assignment));
                      },
                    ),
            ),
            onChanged: (v) => set(TaskFilter(
                query: v,
                state: _filter.state,
                nodeId: _filter.nodeId,
                ownerId: _filter.ownerId,
                assignment: _filter.assignment)),
          ),
        ),
        DropdownButton<TaskCostState?>(
          value: _filter.state,
          hint: const Text('Any status'),
          underline: const SizedBox.shrink(),
          items: const [
            DropdownMenuItem(value: null, child: Text('Any status')),
            DropdownMenuItem(value: TaskCostState.toCost, child: Text('To cost')),
            DropdownMenuItem(value: TaskCostState.costed, child: Text('Costed')),
            DropdownMenuItem(
                value: TaskCostState.expectation, child: Text('Expectation')),
          ],
          onChanged: (v) => set(TaskFilter(
              query: _filter.query,
              state: v,
              nodeId: _filter.nodeId,
              ownerId: _filter.ownerId,
              assignment: _filter.assignment)),
        ),
        DropdownButton<String?>(
          value: _filter.nodeId,
          hint: const Text('Any node'),
          underline: const SizedBox.shrink(),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Any node')),
            for (final n in nodes)
              DropdownMenuItem<String?>(value: n.id, child: Text(n.name)),
          ],
          onChanged: (v) => set(TaskFilter(
              query: _filter.query,
              state: _filter.state,
              nodeId: v,
              ownerId: _filter.ownerId,
              assignment: _filter.assignment)),
        ),
        // Assignment is NOT the same question as owner: every card
        // responsibility has a null owner, but most of them still reach
        // somebody through their role. Only "unassigned" is a gap.
        DropdownButton<TaskAssignment?>(
          value: _filter.assignment,
          hint: const Text('Any assignment'),
          underline: const SizedBox.shrink(),
          items: [
            const DropdownMenuItem<TaskAssignment?>(
                value: null, child: Text('Any assignment')),
            DropdownMenuItem(
                value: TaskAssignment.explicit,
                child: Text('Assigned to a person (${tally.explicit})')),
            DropdownMenuItem(
                value: TaskAssignment.derived,
                child: Text('Via role holders (${tally.derived})')),
            DropdownMenuItem(
                value: TaskAssignment.unassigned,
                child: Text('Unassigned — reaches nobody (${tally.unassigned})')),
          ],
          onChanged: (v) => set(TaskFilter(
              query: _filter.query,
              state: _filter.state,
              nodeId: _filter.nodeId,
              ownerId: _filter.ownerId,
              assignment: v)),
        ),
        DropdownButton<String?>(
          value: _filter.ownerId,
          hint: const Text('Any owner'),
          underline: const SizedBox.shrink(),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Any owner')),
            const DropdownMenuItem<String?>(
                value: TaskFilter.unownedKey, child: Text('No explicit owner')),
            for (final e in employees)
              DropdownMenuItem<String?>(
                  value: e.id, child: Text(employeeNameById[e.id] ?? e.id)),
          ],
          onChanged: (v) => set(TaskFilter(
              query: _filter.query,
              state: _filter.state,
              nodeId: _filter.nodeId,
              ownerId: v,
              assignment: _filter.assignment)),
        ),
        if (!_filter.isEmpty)
          TextButton.icon(
            onPressed: () {
              _searchCtl.clear();
              set(const TaskFilter());
            },
            icon: const Icon(Icons.filter_alt_off, size: 16),
            label: const Text('Clear filters'),
          ),
      ],
    );
  }

  /// Flags a responsibility as a behavioural expectation, or back to costable.
  ///
  /// Marking one CLEARS its costing — the DB forbids an expectation that
  /// carries hours — so a costed row asks first rather than silently discarding
  /// an estimate somebody made.
  Future<void> _toggleExpectation(WpTask t) async {
    final becoming = !t.isExpectation;
    final costed = !isTaskNotCosted(t);
    if (becoming && costed) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Discard the hours?'),
          content: const Text(
              'An expectation carries no hours. Marking this one will clear its '
              'costing and remove it from everyone\'s load.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Mark as expectation')),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await ref
          .read(workforcePlanningRepositoryProvider)
          .setTaskExpectation(t.id, becoming);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not update: $e')));
      return;
    }
    if (!mounted) return;
    _invalidateAfterTaskChange(ref, [t.roleScorecardId]);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(becoming
          ? 'Marked as an expectation — excluded from costing.'
          : 'Back to costable work.'),
    ));
  }

  Future<void> _fillArea(
    String area,
    List<WpTask> tasks,
    Map<String, WpDriver> driverById,
    Map<String, WpRate> rateById,
  ) async {
    double? times;
    double? minutes;
    var onlyUncosted = true;

    final apply = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Fill “$area”'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Applies to ${tasks.length} '
                  '${tasks.length == 1 ? 'responsibility' : 'responsibilities'} in this area.'),
              const SizedBox(height: 16),
              TextFormField(
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: 'Times per month', hintText: 'e.g. 20'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (v) => times = parseCostField(v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                decoration: const InputDecoration(
                    labelText: 'Minutes each', hintText: 'e.g. 30'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (v) => minutes = parseCostField(v),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: onlyUncosted,
                onChanged: (v) => setLocal(() => onlyUncosted = v ?? true),
                title: const Text('Skip rows that are already costed'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apply')),
          ],
        ),
      ),
    );
    if (apply != true || !mounted) return;

    final filled = fillGroupDrafts(
      tasks: tasks,
      current: _drafts,
      driverById: driverById,
      rateById: rateById,
      timesManual: times,
      minutesManual: minutes,
      onlyUncosted: onlyUncosted,
    );
    setState(() => _drafts.addAll(filled));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(filled.isEmpty
          ? 'Nothing to fill — those rows are already costed.'
          : 'Filled ${filled.length} of ${tasks.length}. Review, then Save.'),
    ));
  }

  /// Scope picker + page size + pager. Changing scope or size resets to page 0
  /// — staying on page 4 of a scope that now has two pages strands the user on
  /// a blank screen.
  Widget _scopeBar(
    BuildContext context,
    List<TaskScope> scopes,
    String scopeKey,
    TaskPage page,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DropdownButton<String>(
          value: scopeKey,
          underline: const SizedBox.shrink(),
          items: [
            for (final s in scopes)
              DropdownMenuItem(value: s.key, child: Text('${s.label} (${s.count})')),
          ],
          onChanged: (v) => setState(() {
            _scope = v ?? TaskScope.allKey;
            _page = 0;
          }),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Rows', style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(width: 6),
            DropdownButton<int>(
              value: _pageSize,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 25, child: Text('25')),
                DropdownMenuItem(value: 50, child: Text('50')),
                DropdownMenuItem(value: 100, child: Text('100')),
              ],
              onChanged: (v) => setState(() {
                _pageSize = v ?? 50;
                _page = 0;
              }),
            ),
          ],
        ),
        Text(
          page.total == 0
              ? 'No tasks in this view'
              : 'Showing ${page.firstIndex}–${page.lastIndex} of ${page.total}',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
        if (page.pageCount > 1)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Previous page',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_left),
                onPressed: page.hasPrev ? () => setState(() => _page = page.page - 1) : null,
              ),
              Text('${page.page + 1} / ${page.pageCount}', style: AppTheme.mono(context)),
              IconButton(
                tooltip: 'Next page',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_right),
                onPressed: page.hasNext ? () => setState(() => _page = page.page + 1) : null,
              ),
            ],
          ),
        if (_costMode && _drafts.isNotEmpty)
          Text(
            'Unsaved edits are kept when you change page.',
            style: TextStyle(color: cs.onSurfaceVariant, fontStyle: FontStyle.italic),
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
    // Editors are fixed-width, so the name column gets whatever is left.
    const double others = 70 + 170 + 262 + 262 + 110 + (16 * 5) + 48;
    return LayoutBuilder(
      builder: (context, c) => ResponsiveTable(
        fullWidth: true,
        child: DataTable(
          columnSpacing: 16,
          dataRowMinHeight: 48,
          dataRowMaxHeight: 72,
          columns: const [
            DataColumn(label: Text('Task')),
            DataColumn(label: Text('Hours (direct)')),
            DataColumn(label: Text('Node')),
            DataColumn(label: Text('Times/mo')),
            DataColumn(label: Text('Minutes each')),
            DataColumn(label: Text('Hours (computed)')),
          ],
          rows: [
            for (final t in rows)
              DataRow(
                color: _drafts.containsKey(t.id)
                    ? WidgetStatePropertyAll(cs.primaryContainer.withValues(alpha: 0.25))
                    : null,
                cells: [
                  DataCell(_nameCell(t.name, _nameWidth(c.maxWidth, others))),
                  DataCell(_directHoursCell(t)),
                  DataCell(_deemphasise(t, _nodeCell(t, nodes))),
                  DataCell(_deemphasise(t, _timesCell(t, drivers, driverById))),
                  DataCell(_deemphasise(t, _minutesCell(t, rates, rateById))),
                  DataCell(_costedHoursCell(context, t, driverById, rateById)),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// Direct monthly-hours override: typing a figure here wins over the
  /// times/minutes-or-driver calc entirely (see `draftHoursPerMonth`), so a
  /// role whose hours are simply known does not need a fabricated driver.
  Widget _directHoursCell(WpTask t) {
    final d = _draftFor(t);
    return SizedBox(
      width: 70,
      child: TextFormField(
        key: ValueKey('hours-${t.id}'),
        initialValue: d.hoursPerMonth == null ? '' : _num(d.hoursPerMonth!),
        decoration: const InputDecoration(isDense: true, hintText: 'direct'),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (raw) {
          final v = parseCostField(raw);
          _edit(
            t,
            v == null
                ? d.copyWith(clearHoursPerMonth: true)
                : d.copyWith(hoursPerMonth: v),
          );
        },
      ),
    );
  }

  /// Fades the times/minutes/node path when a direct Hours figure is set, so
  /// it reads as inactive rather than as a second, conflicting answer.
  Widget _deemphasise(WpTask t, Widget child) => Opacity(
        opacity: _draftFor(t).hoursPerMonth == null ? 1 : 0.4,
        child: child,
      );

  /// Width left for the task name once the fixed columns have taken their
  /// share. Without this the name — a full responsibility sentence — sets the
  /// table's natural width, pushing the right-hand columns past the viewport
  /// and out of reach (the table scrolls, but the clipped column reads as a
  /// rendering bug).
  static double _nameWidth(double available, double others) =>
      (available - others).clamp(200.0, 720.0);

  /// Two lines then ellipsis: enough for the long responsibility sentences
  /// promoted from role cards, without letting one row tower over the rest.
  static Widget _nameCell(String name, double width) => SizedBox(
        width: width,
        child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, softWrap: true),
      );

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
    // Node · Hours · Owner · Cadence · actions, plus spacing and margins.
    const double others = 120 + 96 + 210 + 96 + 96 + (24 * 5) + 48;
    return LayoutBuilder(
      builder: (context, c) => ResponsiveTable(
      fullWidth: true,
      child: DataTable(
        columnSpacing: 24,
        dataRowMinHeight: 48,
        dataRowMaxHeight: 72,
        columns: const [
          DataColumn(label: Text('Task')),
          DataColumn(
              label: Tooltip(
                  message: 'Value-chain stage. Grouping only — it does not '
                      'affect the hours.',
                  child: Text('Node'))),
          DataColumn(
              label: Tooltip(
                  message: 'Estimated hours per month at the current growth '
                      'multiplier.',
                  child: Text('Hours/mo'))),
          DataColumn(
              label: Tooltip(
                  message: 'A named owner carries the whole task. "Derived" '
                      'means it reaches whoever holds the role card instead, '
                      'split between them.',
                  child: Text('Owner'))),
          DataColumn(
              label: Tooltip(
                  message: 'How often the work recurs. Descriptive — the hours '
                      'come from times × minutes.',
                  child: Text('Cadence'))),
          DataColumn(label: Text('')),
        ],
        rows: [
          for (final t in rows)
            DataRow(cells: [
              DataCell(_nameWithBadges(context, t, _nameWidth(c.maxWidth, others))),
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
                    tooltip: t.isExpectation
                        ? 'Treat as costable work again'
                        : 'Mark as an expectation (no hours, ever)',
                    icon: Icon(
                      t.isExpectation
                          ? Icons.flag
                          : Icons.outlined_flag,
                      size: 18,
                    ),
                    onPressed: () => _toggleExpectation(t),
                  ),
                  IconButton(
                    tooltip: 'Archive (no longer needed)',
                    icon: const Icon(Icons.archive_outlined, size: 18),
                    onPressed: () => _confirmArchive(context, ref, t),
                  ),
                ],
              )),
            ]),
        ],
      ),
    ),
    );
  }

  Widget _nameWithBadges(BuildContext context, WpTask t, double width) {
    final tone = criticalityTone(t.criticality);
    final chips = <Widget>[
      if (tone != null)
        StatusChip(label: criticalityLabel(t.criticality)!, tone: tone),
      if (!t.isEssential && !t.isExpectation)
        const StatusChip(label: 'Non-essential', tone: StatusTone.neutral),
    ];
    if (chips.isEmpty) return _nameCell(t.name, width);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _nameCell(t.name, width),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 4, children: chips),
      ],
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
    // wp_task_computed is where Balance and Roles read HOURS from. Without
    // this, costing a task left both showing the old figure until restart —
    // and costing is the main activity right now.
    ref.invalidate(wpAllTaskComputedProvider);
    ref.invalidate(ownerComputedProvider);
    ref.invalidate(roleScorecardListProvider);
    // The Balance rail reads assignments, not the task row — without this a
    // changed owner here still shows the OLD owner there until restart.
    ref.invalidate(wpTaskAssignmentsProvider);
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
    // A new responsibility, or one moved to another card/area, needs a position
    // at the END of its area. Renames and costing edits keep theirs — moving a
    // row silently reorders the role-card PDF and the contract annex.
    var toSave = result;
    final cardId = result.roleScorecardId;
    final area = result.responsibilityArea;
    if (cardId != null && area != null && needsResort(existing, result)) {
      final all = ref.read(wpTasksProvider).asData?.value ?? const <WpTask>[];
      final pos = nextSortFor(allTasks: all, cardId: cardId, area: area);
      toSave = result.copyWithSort(areaSort: pos.areaSort, taskSort: pos.taskSort);
    }
    try {
      await ref.read(workforcePlanningRepositoryProvider).saveTask(toSave);
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

  Future<void> _confirmArchive(
    BuildContext context,
    WidgetRef ref,
    WpTask task,
  ) async {
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
      await ref.read(workforcePlanningRepositoryProvider)
          .setTaskArchived(task.id, true);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not archive task: $e')),
      );
      return;
    }
    _invalidateAfterTaskChange(ref, [task.roleScorecardId]);
  }
}

class _ArchivedSection extends StatelessWidget {
  final List<WpTask> tasks;
  final Future<void> Function(WpTask) onRestore;
  const _ArchivedSection({required this.tasks, required this.onRestore});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text('Archived (${tasks.length})'),
      childrenPadding: const EdgeInsets.symmetric(horizontal: 8),
      children: [
        for (final t in tasks)
          ListTile(
            dense: true,
            title: Text(t.name),
            trailing: TextButton.icon(
              icon: const Icon(Icons.unarchive_outlined, size: 18),
              label: const Text('Restore'),
              onPressed: () => onRestore(t),
            ),
          ),
      ],
    );
  }
}
