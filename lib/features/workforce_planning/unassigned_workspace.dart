import '../../data/models/employee.dart';
import '../../data/models/workforce_planning.dart';
import 'text_similarity.dart';

/// One ACTIVE accountability that reaches nobody, with its projected hours.
class UnassignedItem {
  final WpTask task;
  final double hours;
  const UnassignedItem({required this.task, required this.hours});
}

/// A group of similar unassigned accountabilities — the unit a manager acts on
/// (archive each, assign each, or draft one role from the whole group).
class UnassignedCluster {
  final String label;
  final List<UnassignedItem> items;
  const UnassignedCluster({required this.label, required this.items});
  double get totalHours =>
      items.fold(0.0, (sum, i) => sum + i.hours);
  int get count => items.length;
}

bool _cardStaffed(List<Employee> employees, String cardId) => employees.any((e) =>
    e.employmentStatus == 'ACTIVE' &&
    e.deletedAt == null &&
    e.roleScorecardId == cardId);

double _hoursOf(WpTaskComputed? c, double multiplier) {
  if (c == null) return 0;
  return c.isGrowing ? c.hoursPerMonthBase * multiplier : c.hoursPerMonthBase;
}

/// The ACTIVE accountabilities reaching nobody — the shared orphan predicate
/// (mirrors rebalance.dart's `unassignedTasks`): ACTIVE, no owner, and either
/// (no card AND no externalRef) or (a card with no ACTIVE non-deleted holder).
/// Legacy capacity-model rows (no card + externalRef) are excluded.
List<WpTask> orphanTasks({
  required List<WpTask> tasks,
  required List<Employee> employees,
}) {
  final out = <WpTask>[];
  for (final t in tasks) {
    if (t.status != 'ACTIVE') continue;
    if (t.ownerEmployeeId != null) continue;
    final cardId = t.roleScorecardId;
    if (cardId == null && t.externalRef != null) continue;
    final orphaned = cardId == null || !_cardStaffed(employees, cardId);
    if (!orphaned) continue;
    out.add(t);
  }
  return out;
}

/// Every ACTIVE accountability reaching nobody, grouped into name-similarity
/// clusters ordered heaviest-first. Orphan predicate mirrors rebalance.dart's
/// `unassignedTasks` exactly (see the plan's Global Constraints).
List<UnassignedCluster> buildUnassignedWorkspace({
  required List<WpTask> tasks,
  required List<Employee> employees,
  required Map<String, WpTaskComputed> computedByTaskId,
  required double multiplier,
  double threshold = 0.6,
}) {
  final orphans = orphanTasks(tasks: tasks, employees: employees);

  final clusters = clusterBySimilarity<WpTask>(
      orphans, (t) => t.name, threshold: threshold);

  final out = <UnassignedCluster>[];
  for (final group in clusters) {
    final items = [
      for (final t in group)
        UnassignedItem(task: t, hours: _hoursOf(computedByTaskId[t.id], multiplier)),
    ]..sort((a, b) {
        final c = b.hours.compareTo(a.hours);
        return c != 0 ? c : a.task.name.toLowerCase().compareTo(b.task.name.toLowerCase());
      });
    // Shortest name is the most readable representative label.
    final label = group
        .map((t) => t.name)
        .reduce((a, b) => a.length <= b.length ? a : b);
    out.add(UnassignedCluster(label: label, items: items));
  }
  out.sort((a, b) => b.totalHours.compareTo(a.totalHours));
  return out;
}
