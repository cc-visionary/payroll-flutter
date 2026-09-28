import 'dart:math' as math;

import '../../data/models/employee.dart';
import '../../data/models/role_scorecard.dart';
import '../../data/models/workforce_planning.dart';
import 'capacity_math.dart';

/// Draft role changes dragged on the board but not applied: taskId -> roleId.
typedef RoleMoves = Map<String, String>;

/// A task's monthly hours at [multiplier]: growing work scales, fixed doesn't.
double taskHours(WpTaskComputed? c, double multiplier) {
  if (c == null) return 0;
  return c.isGrowing ? c.hoursPerMonthBase * multiplier : c.hoursPerMonthBase;
}

/// The role a task belongs to under the draft [moves].
String? roleOf(WpTask t, RoleMoves moves) => moves[t.id] ?? t.roleScorecardId;

/// The original capacity-model rows: a reference copy, not genuine work.
bool isLegacyReference(WpTask t) =>
    t.externalRef != null && t.roleScorecardId == null;

class RoleHolder {
  final Employee employee;
  final double capacityHours;
  const RoleHolder(this.employee, this.capacityHours);
}

/// One role's workload against the people holding it. Hours split across
/// holders in proportion to capacity (mirrors wp_person_load), so every
/// holder of a role shares the role's load %.
class RoleLoad {
  final RoleScorecard role;
  final List<RoleHolder> holders;
  final List<WpTask> tasks;
  final double workHours;
  final double defaultCapacity;

  const RoleLoad({
    required this.role,
    required this.holders,
    required this.tasks,
    required this.workHours,
    required this.defaultCapacity,
  });

  double get capacityHours =>
      holders.fold<double>(0, (s, h) => s + h.capacityHours);

  double get load => loadFraction(workHours, capacityHours);

  /// How many standard-capacity people this much work needs.
  double get peopleNeeded =>
      defaultCapacity <= 0 ? 0 : workHours / defaultCapacity;

  double get shortBy => math.max(0, peopleNeeded - holders.length);

  bool get unstaffedWithWork => holders.isEmpty && workHours > 0;

  LoadStatus get status =>
      unstaffedWithWork ? LoadStatus.over : loadStatus(load);

  /// [employeeId]'s share of this role's hours; 0 when not a holder.
  double hoursFor(String employeeId) {
    final cap = capacityHours;
    if (cap <= 0) return 0;
    for (final h in holders) {
      if (h.employee.id == employeeId) return workHours * h.capacityHours / cap;
    }
    return 0;
  }
}

bool _isHolder(Employee e, String roleId) =>
    e.employmentStatus == 'ACTIVE' &&
    e.deletedAt == null &&
    e.roleScorecardId == roleId;

List<RoleLoad> buildRoleLoads({
  required List<RoleScorecard> roles,
  required List<Employee> employees,
  required List<WpTask> tasks,
  required Map<String, double> hoursByTaskId,
  required Map<String, double> capacityByEmployee,
  required double defaultCapacity,
  RoleMoves moves = const {},
}) {
  final tasksByRole = <String, List<WpTask>>{};
  for (final t in tasks) {
    if (t.status != 'ACTIVE') continue;
    final r = roleOf(t, moves);
    if (r != null) (tasksByRole[r] ??= []).add(t);
  }
  final out = [
    for (final role in roles)
      RoleLoad(
        role: role,
        holders: [
          for (final e in employees)
            if (_isHolder(e, role.id))
              RoleHolder(e, capacityByEmployee[e.id] ?? defaultCapacity),
        ],
        tasks: tasksByRole[role.id] ?? const [],
        workHours: (tasksByRole[role.id] ?? const <WpTask>[]).fold<double>(
          0,
          (s, t) => s + (hoursByTaskId[t.id] ?? 0),
        ),
        defaultCapacity: defaultCapacity,
      ),
  ];
  out.sort((a, b) {
    if (a.unstaffedWithWork != b.unstaffedWithWork) {
      return a.unstaffedWithWork ? -1 : 1;
    }
    final byLoad = b.load.compareTo(a.load);
    if (byLoad != 0) return byLoad;
    return a.role.jobTitle.compareTo(b.role.jobTitle);
  });
  return out;
}

/// Who checks this role's work: the distinct roles of the holders' managers
/// (RACI "Accountable"). A label only — it carries no hours.
List<String> checkedByTitles({
  required RoleScorecard role,
  required List<Employee> employees,
  required Map<String, RoleScorecard> rolesById,
}) {
  final byId = {for (final e in employees) e.id: e};
  final titles = <String>{};
  for (final e in employees) {
    if (!_isHolder(e, role.id)) continue;
    final manager = e.reportsToId == null ? null : byId[e.reportsToId];
    final managerRole = manager?.roleScorecardId == null
        ? null
        : rolesById[manager!.roleScorecardId];
    if (managerRole != null) titles.add(managerRole.jobTitle);
  }
  return titles.toList()..sort();
}

/// Genuine ACTIVE work with no role under [moves].
List<WpTask> noRoleTasks(List<WpTask> tasks, {RoleMoves moves = const {}}) => [
  for (final t in tasks)
    if (t.status == 'ACTIVE' && !isLegacyReference(t) && roleOf(t, moves) == null)
      t,
];

/// ACTIVE tasks the migration flagged for a human look.
List<WpTask> flaggedTasks(List<WpTask> tasks) => [
  for (final t in tasks)
    if (t.status == 'ACTIVE' && t.allocationReviewNote != null) t,
];
