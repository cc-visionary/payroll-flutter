import '../../data/models/employee.dart';
import '../../data/models/role_scorecard.dart';
import '../../data/models/workforce_planning.dart';

/// Role card id -> its responsibility-area names, in authored order.
///
/// Built straight from `wp_tasks` (each task's own `role_scorecard_id` — the
/// one role a task belongs to) with [responsibilitiesFromTaskRows], the same
/// area/task grouping `RoleScorecard.fromRow` uses. So the Organization tab
/// shows exactly the areas the role card, its PDF and the contract's Annex A
/// list, in the same order.
Map<String, List<String>> areasByRole(List<WpTask> tasks) {
  final rowsByRole = <String, List<Map<String, dynamic>>>{};
  for (final t in tasks) {
    final roleId = t.roleScorecardId;
    if (roleId == null) continue;
    (rowsByRole[roleId] ??= []).add({
      'id': t.id,
      'name': t.name,
      'responsibility_area': t.responsibilityArea,
      'area_sort': t.areaSort,
      'task_sort': t.taskSort,
      'status': t.status,
    });
  }
  return {
    for (final entry in rowsByRole.entries)
      entry.key: [
        for (final area in responsibilitiesFromTaskRows(entry.value))
          area.area,
      ],
  };
}

/// Role card id -> how many people currently hold it.
///
/// A holder is an employee whose `employmentStatus` is `'ACTIVE'` and who has
/// not been soft-deleted — the same filter `role/people_pane.dart` uses for a
/// role's roster. Every role in [roles] appears in the result, including the
/// ones with zero holders: a role nobody fills is the finding, so it must not
/// be absent from the map.
Map<String, int> holderCountByRole({
  required List<RoleScorecard> roles,
  required List<Employee> employees,
}) {
  final counts = {for (final r in roles) r.id: 0};
  for (final e in employees) {
    final roleId = e.roleScorecardId;
    if (roleId == null) continue;
    if (e.employmentStatus != 'ACTIVE' || e.deletedAt != null) continue;
    if (!counts.containsKey(roleId)) continue;
    counts[roleId] = counts[roleId]! + 1;
  }
  return counts;
}
