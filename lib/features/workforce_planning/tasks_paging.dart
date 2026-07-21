import '../../data/models/role_scorecard.dart';
import '../../data/models/workforce_planning.dart';
import 'task_costing.dart';
import 'tasks_rows.dart';

/// What subset of the inventory the Tasks tab is showing.
///
/// Scope narrows *before* paging, so "Operations Manager" is 38 rows on one
/// page rather than page 2-of-6 of everything.
class TaskScope {
  const TaskScope({required this.key, required this.label, required this.count});

  /// `all`, `legacy`, `unattributed`, or a role-card id.
  final String key;
  final String label;
  final int count;

  static const allKey = 'all';
  static const legacyKey = 'legacy';
  static const unattributedKey = 'unattributed';
}

/// The selectable scopes for the current data, in display order: All, then one
/// per role card that actually has tasks, then the two buckets. Buckets and
/// cards with nothing in them are omitted — an empty option is a dead end.
List<TaskScope> buildScopes(List<WpTask> tasks, List<RoleScorecard> cards) {
  final groups = groupTasks(tasks, cards);
  return [
    TaskScope(key: TaskScope.allKey, label: 'All tasks', count: tasks.length),
    for (final g in groups.cardGroups)
      TaskScope(
        key: g.cardId,
        label: g.jobTitle,
        count: g.areas.fold(0, (s, a) => s + a.tasks.length),
      ),
    if (groups.legacy.isNotEmpty)
      TaskScope(
          key: TaskScope.legacyKey,
          label: 'From capacity model',
          count: groups.legacy.length),
    if (groups.unattributed.isNotEmpty)
      TaskScope(
          key: TaskScope.unattributedKey,
          label: 'Unattributed',
          count: groups.unattributed.length),
  ];
}

/// Tasks matching [scopeKey], in the same order the grouped view renders them,
/// so paging over this list never reorders or skips a row.
List<WpTask> tasksInScope(
  List<WpTask> tasks,
  List<RoleScorecard> cards,
  String scopeKey,
) {
  final groups = groupTasks(tasks, cards);
  final ordered = <WpTask>[
    for (final g in groups.cardGroups)
      for (final a in g.areas) ...a.tasks,
    ...groups.legacy,
    ...groups.unattributed,
  ];
  switch (scopeKey) {
    case TaskScope.allKey:
      return ordered;
    case TaskScope.legacyKey:
      return groups.legacy;
    case TaskScope.unattributedKey:
      return groups.unattributed;
    default:
      return [for (final t in ordered) if (t.roleScorecardId == scopeKey) t];
  }
}

/// Free-text + status filtering applied before paging.
///
/// 282 sentence-long responsibilities across six pages cannot be found by
/// scrolling; without search the inventory is effectively write-only.
class TaskFilter {
  const TaskFilter({this.query = '', this.state, this.nodeId, this.ownerId});

  /// Matched case-insensitively against the task name and its area.
  final String query;

  /// Costing state, or null for any.
  final TaskCostState? state;
  final String? nodeId;

  /// Explicit owner id, or the sentinel [unownedKey] for rows with none.
  final String? ownerId;

  static const unownedKey = '__unowned__';

  bool get isEmpty =>
      query.trim().isEmpty && state == null && nodeId == null && ownerId == null;
}

List<WpTask> applyTaskFilter(
  List<WpTask> tasks,
  TaskFilter f,
  Map<String, WpDriver> driverById,
  Map<String, WpRate> rateById,
) {
  if (f.isEmpty) return tasks;
  final q = f.query.trim().toLowerCase();
  return [
    for (final t in tasks)
      if ((q.isEmpty ||
              t.name.toLowerCase().contains(q) ||
              (t.responsibilityArea ?? '').toLowerCase().contains(q)) &&
          (f.state == null || taskCostState(t, driverById, rateById) == f.state) &&
          (f.nodeId == null || t.nodeId == f.nodeId) &&
          (f.ownerId == null ||
              (f.ownerId == TaskFilter.unownedKey
                  ? t.ownerEmployeeId == null
                  : t.ownerEmployeeId == f.ownerId)))
        t,
  ];
}

/// Costing progress across the whole inventory. Expectations count as RESOLVED,
/// not outstanding — that is what lets the queue reach zero instead of being a
/// permanent banner nobody reads.
class CostingProgress {
  const CostingProgress({
    required this.costed,
    required this.toCost,
    required this.expectation,
  });

  final int costed;
  final int toCost;
  final int expectation;

  int get total => costed + toCost + expectation;
  int get resolved => costed + expectation;
  double get fraction => total == 0 ? 1 : resolved / total;
  bool get done => toCost == 0;
}

CostingProgress costingProgress(
  List<WpTask> tasks,
  Map<String, WpDriver> driverById,
  Map<String, WpRate> rateById,
) {
  var costed = 0, toCost = 0, expectation = 0;
  for (final t in tasks) {
    switch (taskCostState(t, driverById, rateById)) {
      case TaskCostState.costed:
        costed++;
      case TaskCostState.toCost:
        toCost++;
      case TaskCostState.expectation:
        expectation++;
    }
  }
  return CostingProgress(costed: costed, toCost: toCost, expectation: expectation);
}

/// One page of rows plus the numbers the pager needs to describe itself.
class TaskPage {
  const TaskPage({
    required this.tasks,
    required this.page,
    required this.pageCount,
    required this.total,
    required this.firstIndex,
    required this.lastIndex,
  });

  final List<WpTask> tasks;

  /// Zero-based, already clamped into range.
  final int page;
  final int pageCount;
  final int total;

  /// 1-based inclusive row numbers for "showing X-Y of Z" (both 0 when empty).
  final int firstIndex;
  final int lastIndex;

  bool get hasPrev => page > 0;
  bool get hasNext => page < pageCount - 1;
}

/// Slices [tasks] into a page, clamping [page] into range rather than
/// returning empty — deleting the last rows of the final page must not strand
/// the user on a blank screen with no way back.
TaskPage pageOfTasks(List<WpTask> tasks, int page, int pageSize) {
  if (pageSize <= 0) {
    throw ArgumentError.value(pageSize, 'pageSize', 'must be positive');
  }
  final total = tasks.length;
  final pageCount = total == 0 ? 1 : (total + pageSize - 1) ~/ pageSize;
  final clamped = page.clamp(0, pageCount - 1);
  final from = clamped * pageSize;
  final to = (from + pageSize) > total ? total : from + pageSize;
  return TaskPage(
    tasks: tasks.sublist(from, to),
    page: clamped,
    pageCount: pageCount,
    total: total,
    firstIndex: total == 0 ? 0 : from + 1,
    lastIndex: to,
  );
}
