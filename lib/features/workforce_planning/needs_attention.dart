import '../../data/models/employee.dart';
import '../../data/models/kpi.dart';
import '../../data/models/role_scorecard.dart';
import '../../data/models/workforce_planning.dart';
import '../../data/repositories/role_scorecard_repository.dart'
    show KpiAssignee;
import '../kpi_library/kpi_measurable.dart' show isKpiDefined;
import '../kpi_library/kpi_rows.dart' show kpiIsAssigned;
import 'capacity_math.dart';
import 'role_load.dart';
import 'tasks_rows.dart' show isTaskNotCosted;

enum AttentionCategory { people, process, structure, tools }

enum AttentionSeverity { high, medium }

/// Where the fix lives — the strip maps this to a hub-tab switch or a route.
enum AttentionTarget { roles, tasks, kpiLibrary }

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

String _plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';

/// The ranked list of gaps computable on CURRENT data. People signals read
/// [roleLoads] (one role per task, hours split across its holders).
/// Grouped by category in the UI; ordered here high-severity first, then by
/// descending count. Each signal appears only when its count > 0.
List<AttentionItem> buildNeedsAttention({
  required List<RoleLoad> roleLoads,
  required List<WpTask> tasks,
  required List<Employee> employees,
  required List<RoleScorecard> cards,
  required List<Kpi> kpis,
  required Map<String, List<KpiAssignee>> kpiAssignedByKpi,
}) {
  final items = <AttentionItem>[];
  void add(
    AttentionCategory c,
    AttentionSeverity s,
    int n,
    String label,
    AttentionTarget t,
  ) {
    if (n > 0)
      items.add(
        AttentionItem(
          category: c,
          severity: s,
          count: n,
          label: label,
          target: t,
        ),
      );
  }

  // People — roles, not persons: every holder of a role shares its load.
  final overRoles = roleLoads
      .where((r) => r.holders.isNotEmpty && r.status == LoadStatus.over)
      .length;
  add(
    AttentionCategory.people,
    AttentionSeverity.high,
    overRoles,
    '${_plural(overRoles, 'role', 'roles')} over capacity',
    AttentionTarget.roles,
  );

  final noRole = noRoleTasks(tasks).length;
  add(
    AttentionCategory.people,
    AttentionSeverity.medium,
    noRole,
    '${_plural(noRole, 'task', 'tasks')} with no role',
    AttentionTarget.roles,
  );

  // A person's KPIs are their role's KPIs — pure inheritance, no
  // per-employee curation. So the gap that used to be a PERSON'S (someone
  // with zero of their role's KPIs ticked) is now a ROLE'S: a role that
  // defines no KPIs leaves every current and future holder unmeasured on
  // day one. Counted per role, not per holder, the same way roleNoDept below
  // counts a role once rather than once per person on it.
  final rolesNoKpi = cards.where((c) => c.isActive && c.kpis.isEmpty).length;
  add(
    AttentionCategory.people,
    AttentionSeverity.medium,
    rolesNoKpi,
    '${_plural(rolesNoKpi, 'role', 'roles')} with no KPI',
    AttentionTarget.roles,
  );

  // Process
  final uncostedEssential = tasks
      .where(
        (t) =>
            t.status == 'ACTIVE' &&
            t.isEssential &&
            !t.isExpectation &&
            isTaskNotCosted(t),
      )
      .length;
  add(
    AttentionCategory.process,
    AttentionSeverity.medium,
    uncostedEssential,
    '${_plural(uncostedEssential, 'essential responsibility', 'essential responsibilities')} uncosted',
    AttentionTarget.tasks,
  );

  final flagged = flaggedTasks(tasks).length;
  add(
    AttentionCategory.process,
    AttentionSeverity.medium,
    flagged,
    '${_plural(flagged, 'task', 'tasks')} to check',
    AttentionTarget.roles,
  );

  final activeKpis = kpis.where((k) => k.isActive).toList();
  final measuringNobody = activeKpis
      .where((k) => !kpiIsAssigned(k, kpiAssignedByKpi))
      .length;
  add(
    AttentionCategory.process,
    AttentionSeverity.medium,
    measuringNobody,
    '${_plural(measuringNobody, 'KPI', 'KPIs')} measuring nobody',
    AttentionTarget.kpiLibrary,
  );

  final noMeasurement = activeKpis
      .where((k) => (k.measurementUnit ?? '').trim().isEmpty)
      .length;
  add(
    AttentionCategory.process,
    AttentionSeverity.medium,
    noMeasurement,
    '${_plural(noMeasurement, 'KPI', 'KPIs')} with no measurement',
    AttentionTarget.kpiLibrary,
  );

  // Library-level only: a KPI whose DEFINITION is incomplete. The per-ROLE
  // gap (a link with no goal) is deliberately not counted here — it would
  // double-count a KPI used on four roles, and the workbench's KPIs pane
  // already marks a goal-less link "not measurable yet". The label names the
  // definition explicitly for that reason: "not measurable yet" is the KPIs
  // pane's phrase for the GOAL gap one click away, and the same words must
  // not name two different things.
  final undefined = activeKpis
      .where(
        (k) => !isKpiDefined(
          valueType: k.valueType,
          unit: k.unit,
          numeratorLabel: k.numeratorLabel,
          numeratorSource: k.numeratorSource,
          denominatorLabel: k.denominatorLabel,
          denominatorSource: k.denominatorSource,
        ),
      )
      .length;
  add(
    AttentionCategory.process,
    AttentionSeverity.medium,
    undefined,
    '${_plural(undefined, 'KPI', 'KPIs')} with an incomplete definition',
    AttentionTarget.kpiLibrary,
  );

  // Structure
  final activeCards = cards.where((c) => c.isActive).toList();
  final tasksByCard = <String, List<WpTask>>{};
  for (final t in tasks) {
    final id = t.roleScorecardId;
    if (id != null && t.status == 'ACTIVE') (tasksByCard[id] ??= []).add(t);
  }
  final heldByRole = {
    for (final r in roleLoads) r.role.id: r.holders.isNotEmpty,
  };
  final unstaffedCritical = activeCards
      .where(
        (c) =>
            !(heldByRole[c.id] ?? false) &&
            (tasksByCard[c.id] ?? const []).any(
              (t) => t.criticality == 'CRITICAL',
            ),
      )
      .length;
  add(
    AttentionCategory.structure,
    AttentionSeverity.medium,
    unstaffedCritical,
    '${_plural(unstaffedCritical, 'unstaffed role carries', 'unstaffed roles carry')} critical work',
    AttentionTarget.roles,
  );

  final roleNoDept = activeCards.where((c) => c.departmentId == null).length;
  add(
    AttentionCategory.structure,
    AttentionSeverity.medium,
    roleNoDept,
    '${_plural(roleNoDept, 'role', 'roles')} with no department',
    AttentionTarget.roles,
  );

  final kpiNoDept = activeKpis.where((k) => k.departmentId == null).length;
  add(
    AttentionCategory.structure,
    AttentionSeverity.medium,
    kpiNoDept,
    '${_plural(kpiNoDept, 'KPI', 'KPIs')} with no department',
    AttentionTarget.kpiLibrary,
  );

  // A role nobody holds: real work with an owner on paper and none in
  // practice. Holders come from [roleLoads] (ACTIVE, not soft-deleted — the
  // same notion the Organization tab uses). Each unfilled role counts once,
  // not once per missing person.
  final unfilledRoles = roleLoads.where((r) => r.holders.isEmpty).length;
  add(
    AttentionCategory.structure,
    AttentionSeverity.medium,
    unfilledRoles,
    '${_plural(unfilledRoles, 'role', 'roles')} nobody holds',
    AttentionTarget.roles,
  );

  // Tools — reserved, no signals today.

  items.sort((a, b) {
    if (a.severity != b.severity) {
      return a.severity == AttentionSeverity.high ? -1 : 1;
    }
    return b.count.compareTo(a.count);
  });
  return items;
}
