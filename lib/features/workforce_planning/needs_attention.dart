import '../../data/models/employee.dart';
import '../../data/models/kpi.dart';
import '../../data/models/role_scorecard.dart';
import '../../data/models/workforce_planning.dart';
import '../../data/repositories/role_scorecard_repository.dart' show KpiAssignee;
import '../kpi_library/kpi_rows.dart' show kpiIsAssigned;
import 'capacity_math.dart';
import 'tasks_rows.dart' show isTaskNotCosted;
import 'unassigned_workspace.dart' show orphanTasks;

enum AttentionCategory { people, process, structure, tools }

enum AttentionSeverity { high, medium }

/// Where the fix lives — the strip maps this to a hub-tab switch or a route.
enum AttentionTarget { balance, roles, tasks, unassigned, kpiLibrary }

/// One derived "needs attention" row: a gap the manager should close.
class AttentionItem {
  final AttentionCategory category;
  final AttentionSeverity severity;
  final String label;
  final int count;
  final AttentionTarget target;
  const AttentionItem({
    required this.category,
    required this.severity,
    required this.label,
    required this.count,
    required this.target,
  });
}

bool _cardHasActiveHolder(List<Employee> employees, String cardId) => employees.any(
    (e) => e.employmentStatus == 'ACTIVE' &&
        e.deletedAt == null &&
        e.roleScorecardId == cardId);

String _plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';

/// The ranked list of gaps computable on CURRENT data (pre-assignments).
/// Grouped by category in the UI; ordered here high-severity first, then by
/// descending count. Each signal appears only when its count > 0.
List<AttentionItem> buildNeedsAttention({
  required List<WpPersonLoad> loads,
  required List<WpTask> tasks,
  required List<Employee> employees,
  required List<RoleScorecard> cards,
  required List<Kpi> kpis,
  required Map<String, List<KpiAssignee>> kpiAssignedByKpi,
}) {
  final items = <AttentionItem>[];
  void add(AttentionCategory c, AttentionSeverity s, int n, String label, AttentionTarget t) {
    if (n > 0) items.add(AttentionItem(category: c, severity: s, count: n, label: label, target: t));
  }

  // People
  final over = loads
      .where((p) => loadStatus(personLoad(p)) == LoadStatus.over)
      .length;
  add(AttentionCategory.people, AttentionSeverity.high, over,
      '${_plural(over, 'person', 'people')} over capacity', AttentionTarget.balance);

  final orphans = orphanTasks(tasks: tasks, employees: employees);
  final criticalOrphans = orphans.where((t) => t.criticality == 'CRITICAL').length;
  add(AttentionCategory.people, AttentionSeverity.high, criticalOrphans,
      '${_plural(criticalOrphans, 'critical responsibility', 'critical responsibilities')} nobody owns',
      AttentionTarget.unassigned);
  add(AttentionCategory.people, AttentionSeverity.medium, orphans.length,
      '${_plural(orphans.length, 'responsibility', 'responsibilities')} unassigned',
      AttentionTarget.unassigned);

  // Process
  final uncostedEssential = tasks
      .where((t) => t.status == 'ACTIVE' && t.isEssential && !t.isExpectation && isTaskNotCosted(t))
      .length;
  add(AttentionCategory.process, AttentionSeverity.medium, uncostedEssential,
      '${_plural(uncostedEssential, 'essential responsibility', 'essential responsibilities')} uncosted',
      AttentionTarget.tasks);

  final activeKpis = kpis.where((k) => k.isActive).toList();
  final measuringNobody = activeKpis.where((k) => !kpiIsAssigned(k, kpiAssignedByKpi)).length;
  add(AttentionCategory.process, AttentionSeverity.medium, measuringNobody,
      '${_plural(measuringNobody, 'KPI', 'KPIs')} measuring nobody', AttentionTarget.kpiLibrary);

  final noMeasurement = activeKpis.where((k) => (k.measurementUnit ?? '').trim().isEmpty).length;
  add(AttentionCategory.process, AttentionSeverity.medium, noMeasurement,
      '${_plural(noMeasurement, 'KPI', 'KPIs')} with no measurement', AttentionTarget.kpiLibrary);

  // Structure
  final activeCards = cards.where((c) => c.isActive).toList();
  final tasksByCard = <String, List<WpTask>>{};
  for (final t in tasks) {
    final id = t.roleScorecardId;
    if (id != null && t.status == 'ACTIVE') (tasksByCard[id] ??= []).add(t);
  }
  final unstaffedCritical = activeCards.where((c) =>
      !_cardHasActiveHolder(employees, c.id) &&
      (tasksByCard[c.id] ?? const []).any((t) => t.criticality == 'CRITICAL')).length;
  add(AttentionCategory.structure, AttentionSeverity.medium, unstaffedCritical,
      '${_plural(unstaffedCritical, 'unstaffed role carries', 'unstaffed roles carry')} critical work',
      AttentionTarget.roles);

  final roleNoDept = activeCards.where((c) => c.departmentId == null).length;
  add(AttentionCategory.structure, AttentionSeverity.medium, roleNoDept,
      '${_plural(roleNoDept, 'role', 'roles')} with no department', AttentionTarget.roles);

  final kpiNoDept = activeKpis.where((k) => k.departmentId == null).length;
  add(AttentionCategory.structure, AttentionSeverity.medium, kpiNoDept,
      '${_plural(kpiNoDept, 'KPI', 'KPIs')} with no department', AttentionTarget.kpiLibrary);

  // Tools — reserved, no signals today.

  items.sort((a, b) {
    if (a.severity != b.severity) {
      return a.severity == AttentionSeverity.high ? -1 : 1;
    }
    return b.count.compareTo(a.count);
  });
  return items;
}
