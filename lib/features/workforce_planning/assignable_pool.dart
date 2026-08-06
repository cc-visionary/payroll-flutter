import '../../data/models/workforce_planning.dart';

/// Task ids that already sit on [cardId] — either AUTHORED on it
/// (`role_scorecard_id == cardId`) or SHARED to it via a `wp_task_assignments`
/// row targeting it. The picker and the duplicate nudge must both exclude these:
/// offering a task already on this card leads to a self-share (a unique-index
/// 23505) or a duplicate-id draft.
Set<String> tasksOnCard({
  required String? cardId,
  required List<WpTask> allTasks,
  required List<WpTaskAssignment> allAssignments,
}) {
  if (cardId == null) return const {};
  return {
    for (final t in allTasks)
      if (t.roleScorecardId == cardId) t.id,
    for (final a in allAssignments)
      if (a.roleScorecardId == cardId) a.taskId,
  };
}
