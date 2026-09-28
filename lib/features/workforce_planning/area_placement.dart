import '../../data/models/role_scorecard.dart';
import '../../data/models/workforce_planning.dart';
import 'role_load.dart' show RoleMoves;

/// The area a task gets on a role card that has none yet.
const kDefaultResponsibilityArea = 'Responsibilities';

/// A card's responsibility areas, in authored order, trimmed and de-duplicated
/// (case-insensitively). These are the areas a task on this role can sit under.
List<String> areaOptionsFor(RoleScorecard? card) {
  final seen = <String>{};
  return [
    for (final r in card?.responsibilities ?? const <ResponsibilityArea>[])
      if (r.area.trim().isNotEmpty && seen.add(r.area.trim().toLowerCase()))
        r.area.trim(),
  ];
}

/// Where a task lands on [card] when nobody picked an area: the card's first
/// area, or [kDefaultResponsibilityArea] when the card has none yet.
///
/// One rule everywhere (ruling R11): a task on a role always has an area
/// belonging to that role. A task with no area is skipped by
/// `responsibilitiesFromTaskRows`, so it would be missing from the role card,
/// its PDF and the contract's Annex A.
String defaultAreaFor(RoleScorecard? card) {
  final options = areaOptionsFor(card);
  return options.isEmpty ? kDefaultResponsibilityArea : options.first;
}

/// Where a responsibility should sit when it joins a card's area.
///
/// The role-card PDF and the employment-contract Annex A render
/// responsibilities in `area_sort` / `task_sort` order, so position is not
/// cosmetic — it decides the wording of a document.
///
/// An existing area keeps its `area_sort` (moving a task into it must not
/// reorder the card's headings); a new area goes after the last one. Within the
/// area the task goes last, which is what "add a responsibility" means.
({int areaSort, int taskSort}) nextSortFor({
  required List<WpTask> allTasks,
  required String cardId,
  required String area,
}) {
  final key = area.trim().toLowerCase();
  var areaSort = -1;
  var maxAreaSort = -1;
  var maxTaskSort = -1;
  for (final t in allTasks) {
    if (t.roleScorecardId != cardId) continue;
    if (t.areaSort > maxAreaSort) maxAreaSort = t.areaSort;
    if ((t.responsibilityArea ?? '').trim().toLowerCase() != key) continue;
    areaSort = t.areaSort;
    if (t.taskSort > maxTaskSort) maxTaskSort = t.taskSort;
  }
  return (
    areaSort: areaSort >= 0 ? areaSort : maxAreaSort + 1,
    taskSort: maxTaskSort + 1,
  );
}

/// True when [next] lands in a different (card, area) than [previous], and so
/// needs a fresh position. A rename or a costing edit must NOT reposition the
/// row — that would silently reorder a contract annex.
bool needsResort(WpTask? previous, WpTask next) {
  if (previous == null) return true;
  if (previous.roleScorecardId != next.roleScorecardId) return true;
  final a = (previous.responsibilityArea ?? '').trim().toLowerCase();
  final b = (next.responsibilityArea ?? '').trim().toLowerCase();
  return a != b;
}

/// [next] positioned for saving: a task that is new, or changes role, or
/// changes area, goes to the END of its area; anything else keeps its place.
/// A task with no role or no area has no card position and is returned as-is.
WpTask placeInArea({
  required WpTask? previous,
  required WpTask next,
  required List<WpTask> allTasks,
}) {
  final cardId = next.roleScorecardId;
  final area = next.responsibilityArea;
  if (cardId == null || area == null || area.trim().isEmpty) return next;
  if (!needsResort(previous, next)) return next;
  final pos = nextSortFor(allTasks: allTasks, cardId: cardId, area: area);
  return next.copyWithSort(areaSort: pos.areaSort, taskSort: pos.taskSort);
}

/// The board's draft [moves] (taskId -> roleId) as writes: each task takes the
/// target card's default area ([defaultAreaFor]) and goes to the end of it.
/// Moves are placed one after another, so several tasks dropped on the same
/// role take consecutive slots instead of colliding on one position.
List<TaskRoleMove> planRoleMoves({
  required RoleMoves moves,
  required List<WpTask> allTasks,
  required Map<String, RoleScorecard> rolesById,
}) {
  final pool = [...allTasks];
  final plan = <TaskRoleMove>[];
  for (final m in moves.entries) {
    final area = defaultAreaFor(rolesById[m.value]);
    final pos = nextSortFor(allTasks: pool, cardId: m.value, area: area);
    plan.add(TaskRoleMove(
      taskId: m.key,
      roleId: m.value,
      area: area,
      areaSort: pos.areaSort,
      taskSort: pos.taskSort,
    ));
    // Only the fields nextSortFor reads matter for the next placement.
    pool.add(WpTask(
      id: m.key,
      companyId: '',
      name: '',
      roleScorecardId: m.value,
      responsibilityArea: area,
      areaSort: pos.areaSort,
      taskSort: pos.taskSort,
    ));
  }
  return plan;
}
