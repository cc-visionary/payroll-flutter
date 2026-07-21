import '../../data/models/role_scorecard.dart';
import '../../data/models/workforce_planning.dart';
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
