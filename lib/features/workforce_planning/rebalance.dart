import '../../data/models/employee.dart';
import '../../data/models/workforce_planning.dart';
import 'capacity_math.dart';

/// Draft reassignments the user has dragged but not yet applied:
/// `taskId -> employeeId`. Nothing is written until Apply.
typedef MoveDrafts = Map<String, String>;

/// One task as it reaches a person under the current plan.
class PlannedTask {
  const PlannedTask({
    required this.task,
    required this.hours,
    required this.derived,
    required this.holderCount,
    required this.moved,
  });

  final WpTask task;

  /// This person's SHARE of the task's hours, already projected at the
  /// multiplier. A derived task shared by N holders contributes hours/N.
  final double hours;

  /// True when the task reaches this person through their role card rather
  /// than an explicit owner.
  final bool derived;
  final int holderCount;

  /// True when a draft move put it here (or took it away).
  final bool moved;

  bool get shared => derived && holderCount > 1;
}

/// A person's load now versus under the draft moves.
class LoadProjection {
  const LoadProjection({
    required this.employeeId,
    required this.name,
    required this.roleTitle,
    required this.capacityHours,
    required this.currentHours,
    required this.plannedHours,
    required this.taskCount,
    required this.costedCount,
  });

  final String employeeId;
  final String name;
  final String? roleTitle;
  final double capacityHours;
  final double currentHours;
  final double plannedHours;
  final int taskCount;

  /// How many of [taskCount] carry hours. The capacity model only ever costed
  /// transactional work, so managerial responsibilities (training, process
  /// improvement, coordination) largely have none — which means a manager's
  /// load can be badly understated. Every load figure has to travel with the
  /// share of work it actually covers, or people plan off a number that is
  /// missing most of the job.
  final int costedCount;


  double get currentLoad => loadFraction(currentHours, capacityHours);
  double get plannedLoad => loadFraction(plannedHours, capacityHours);
  LoadStatus get currentStatus => loadStatus(currentLoad);
  LoadStatus get plannedStatus => loadStatus(plannedLoad);
  bool get changed => (plannedHours - currentHours).abs() > 0.001;

  /// Hours of headroom left under the plan; negative when over capacity.
  double get headroom => capacityHours - plannedHours;

  /// Weighted responsibilities still awaiting an estimate.
  int get uncostedCount => taskCount - costedCount;

  /// True when some weighted work has no estimate, so the load understates the
  /// real job.
  bool get understated => uncostedCount > 0;

  /// Share of weighted responsibilities that carry hours.
  double get coverage => taskCount == 0 ? 1 : costedCount / taskCount;
}

List<Employee> _activeHolders(List<Employee> employees, String cardId) => [
      for (final e in employees)
        // "Active" here must match wp_person_load exactly: ACTIVE *and* not
        // soft-deleted. Counting either alone changes everyone's split.
        if (e.employmentStatus == 'ACTIVE' &&
            e.deletedAt == null &&
            e.roleScorecardId == cardId)
          e,
    ];

double _hoursOf(WpTaskComputed? c, double multiplier) {
  if (c == null) return 0;
  return c.isGrowing ? c.hoursPerMonthBase * multiplier : c.hoursPerMonthBase;
}

/// Hours per employee under [moves], mirroring `wp_person_load`'s attribution:
/// explicit owner takes the whole task, else it splits evenly across the ACTIVE
/// holders of its role card, else it is unattributed and reaches nobody.
///
/// A draft move sets an explicit owner, so moving a SHARED responsibility takes
/// it away from every holder and gives all of it to one person — see
/// [PlannedTask.shared], which the UI warns about.
Map<String, double> hoursByEmployee({
  required List<WpTask> tasks,
  required Map<String, WpTaskComputed> computedByTaskId,
  required List<Employee> employees,
  required double multiplier,
  MoveDrafts moves = const {},
}) {
  final out = <String, double>{};
  final holdersByCard = <String, List<Employee>>{};
  for (final t in tasks) {
    final hours = _hoursOf(computedByTaskId[t.id], multiplier);
    if (hours <= 0) continue;

    final owner = moves[t.id] ?? t.ownerEmployeeId;
    if (owner != null) {
      out[owner] = (out[owner] ?? 0) + hours;
      continue;
    }
    final cardId = t.roleScorecardId;
    if (cardId == null) continue; // unattributed
    final holders = holdersByCard[cardId] ??= _activeHolders(employees, cardId);
    if (holders.isEmpty) continue; // vacant role — a staffing gap, not load
    final share = hours / holders.length;
    for (final h in holders) {
      out[h.id] = (out[h.id] ?? 0) + share;
    }
  }
  return out;
}

/// Hours that reach nobody, split by WHY.
///
/// The 118 rows imported from the capacity spreadsheet have neither an owner
/// nor a role card, so they are technically unattributed — but their costing
/// was already transferred onto the responsibilities they describe. Counting
/// them as orphaned work reports ~800h of debt that does not exist. Only rows
/// with no `external_ref` are genuinely orphaned.
class OrphanHours {
  const OrphanHours({required this.genuine, required this.legacyReference});

  /// Costed work with no owner and no staffed role — a real gap.
  final double genuine;

  /// The capacity-model reference bucket, already counted elsewhere.
  final double legacyReference;
}

OrphanHours orphanHours({
  required List<WpTask> tasks,
  required Map<String, WpTaskComputed> computedByTaskId,
  required List<Employee> employees,
  required double multiplier,
  MoveDrafts moves = const {},
}) {
  var genuine = 0.0;
  var legacy = 0.0;
  final holdersByCard = <String, List<Employee>>{};
  for (final t in tasks) {
    final hours = _hoursOf(computedByTaskId[t.id], multiplier);
    if (hours <= 0) continue;
    if (moves[t.id] != null || t.ownerEmployeeId != null) continue;
    final cardId = t.roleScorecardId;
    final orphaned = cardId == null ||
        (holdersByCard[cardId] ??= _activeHolders(employees, cardId)).isEmpty;
    if (!orphaned) continue;
    if (t.externalRef != null && cardId == null) {
      legacy += hours;
    } else {
      genuine += hours;
    }
  }
  return OrphanHours(genuine: genuine, legacyReference: legacy);
}

/// Hours that reach nobody: no explicit owner and either no role card or a card
/// with no active holder. Surfaced so work is never silently dropped.
double unattributedHours({
  required List<WpTask> tasks,
  required Map<String, WpTaskComputed> computedByTaskId,
  required List<Employee> employees,
  required double multiplier,
  MoveDrafts moves = const {},
}) {
  var total = 0.0;
  final holdersByCard = <String, List<Employee>>{};
  for (final t in tasks) {
    final hours = _hoursOf(computedByTaskId[t.id], multiplier);
    if (hours <= 0) continue;
    if (moves[t.id] != null || t.ownerEmployeeId != null) continue;
    final cardId = t.roleScorecardId;
    if (cardId == null) {
      total += hours;
      continue;
    }
    final holders = holdersByCard[cardId] ??= _activeHolders(employees, cardId);
    if (holders.isEmpty) total += hours;
  }
  return total;
}

/// One row per active person, ranked by planned load (busiest first) so the
/// people who need work moved off them are at the top.
List<LoadProjection> buildProjections({
  required List<Employee> employees,
  required List<WpTask> tasks,
  required Map<String, WpTaskComputed> computedByTaskId,
  required Map<String, double> capacityByEmployee,
  required double multiplier,
  required double defaultCapacity,
  MoveDrafts moves = const {},
}) {
  final now = hoursByEmployee(
      tasks: tasks, computedByTaskId: computedByTaskId,
      employees: employees, multiplier: multiplier);
  final planned = moves.isEmpty
      ? now
      : hoursByEmployee(
          tasks: tasks, computedByTaskId: computedByTaskId,
          employees: employees, multiplier: multiplier, moves: moves);

  final counts = <String, int>{};
  final costed = <String, int>{};
  for (final t in tasks) {
    // Behavioural standards and skills are role-scorecard concerns that apply
    // across the whole role; they carry no weight and are not workload, so they
    // are not counted or shown anywhere in workforce planning.
    if (t.isExpectation) continue;
    if (t.status != 'ACTIVE') continue; // archived work leaves the derived lists
    final hasHours = (computedByTaskId[t.id]?.hoursPerMonthBase ?? 0) > 0;
    void tally(String id) {
      counts[id] = (counts[id] ?? 0) + 1;
      if (hasHours) costed[id] = (costed[id] ?? 0) + 1;
    }

    final owner = moves[t.id] ?? t.ownerEmployeeId;
    if (owner != null) {
      tally(owner);
      continue;
    }
    final cardId = t.roleScorecardId;
    if (cardId == null) continue;
    for (final h in _activeHolders(employees, cardId)) {
      tally(h.id);
    }
  }

  final rows = <LoadProjection>[
    for (final e in employees)
      if (e.employmentStatus == 'ACTIVE' && e.deletedAt == null)
        LoadProjection(
          employeeId: e.id,
          name: '${e.firstName} ${e.lastName}',
          roleTitle: e.jobTitle,
          capacityHours: capacityByEmployee[e.id] ?? defaultCapacity,
          currentHours: now[e.id] ?? 0,
          plannedHours: planned[e.id] ?? 0,
          taskCount: counts[e.id] ?? 0,
          costedCount: costed[e.id] ?? 0,
        ),
  ];
  rows.sort((a, b) {
    final c = b.plannedLoad.compareTo(a.plannedLoad);
    return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return rows;
}

/// The tasks reaching [employeeId] under [moves], heaviest first — that is the
/// order you want when deciding what to hand off.
List<PlannedTask> plannedTasksFor({
  required String employeeId,
  required List<Employee> employees,
  required List<WpTask> tasks,
  required Map<String, WpTaskComputed> computedByTaskId,
  required double multiplier,
  MoveDrafts moves = const {},
}) {
  final out = <PlannedTask>[];
  for (final t in tasks) {
    // Workload only. Behavioural expectations live on the role scorecard.
    if (t.isExpectation) continue;
    if (t.status != 'ACTIVE') continue; // archived work leaves the derived lists
    final hours = _hoursOf(computedByTaskId[t.id], multiplier);
    final moved = moves.containsKey(t.id);
    final owner = moves[t.id] ?? t.ownerEmployeeId;

    if (owner != null) {
      if (owner == employeeId) {
        out.add(PlannedTask(
            task: t, hours: hours, derived: false, holderCount: 1, moved: moved));
      }
      continue;
    }
    final cardId = t.roleScorecardId;
    if (cardId == null) continue;
    final holders = _activeHolders(employees, cardId);
    if (!holders.any((h) => h.id == employeeId)) continue;
    out.add(PlannedTask(
      task: t,
      hours: holders.isEmpty ? 0 : hours / holders.length,
      derived: true,
      holderCount: holders.length,
      moved: false,
    ));
  }
  out.sort((a, b) {
    final c = b.hours.compareTo(a.hours);
    return c != 0 ? c : a.task.name.toLowerCase().compareTo(b.task.name.toLowerCase());
  });
  return out;
}

/// Sentinel id for the unassigned pool, so it can be a drag SOURCE in the same
/// rail as the people. Triaging orphaned work then uses the same mechanic as
/// every other move, instead of being an invisible number in a header.
const String kUnassignedId = '__unassigned__';

/// The orphan pool as a task list: costed work reaching nobody, heaviest first.
/// Legacy reference rows are excluded — their costing already lives on the
/// responsibilities they describe, so offering them for assignment would
/// double-count the work.
List<PlannedTask> unassignedTasks({
  required List<Employee> employees,
  required List<WpTask> tasks,
  required Map<String, WpTaskComputed> computedByTaskId,
  required double multiplier,
  MoveDrafts moves = const {},
}) {
  final out = <PlannedTask>[];
  final holdersByCard = <String, List<Employee>>{};
  for (final t in tasks) {
    if (moves[t.id] != null || t.ownerEmployeeId != null) continue;
    final cardId = t.roleScorecardId;
    if (cardId == null && t.externalRef != null) continue; // legacy reference
    final orphaned = cardId == null ||
        (holdersByCard[cardId] ??= _activeHolders(employees, cardId)).isEmpty;
    if (!orphaned) continue;
    final hours = _hoursOf(computedByTaskId[t.id], multiplier);
    out.add(PlannedTask(
        task: t, hours: hours, derived: false, holderCount: 0, moved: false));
  }
  out.sort((a, b) {
    final c = b.hours.compareTo(a.hours);
    return c != 0 ? c : a.task.name.toLowerCase().compareTo(b.task.name.toLowerCase());
  });
  return out;
}

/// A drag in flight: what is being dragged, from whom, and where it is
/// currently hovering. Held while the pointer is down so the rail can show the
/// resulting load on BOTH ends before the user commits — deciding a move
/// without seeing the delta is deciding blind.
class HoverPreview {
  const HoverPreview({required this.taskId, required this.fromEmployeeId, this.overEmployeeId});

  final String taskId;
  final String fromEmployeeId;
  final String? overEmployeeId;

  HoverPreview over(String? id) => HoverPreview(
      taskId: taskId, fromEmployeeId: fromEmployeeId, overEmployeeId: id);

  /// The moves to apply on top of the drafts to render the preview. Empty while
  /// the pointer is over nothing, or back over the source.
  MoveDrafts get asMove =>
      (overEmployeeId == null || overEmployeeId == fromEmployeeId)
          ? const {}
          : {taskId: overEmployeeId!};
}

/// Why a drop is not allowed, or null when it is fine.
String? moveError({
  required WpTask task,
  required String toEmployeeId,
  required List<Employee> employees,
  required Map<String, WpTaskComputed> computedByTaskId,
  MoveDrafts moves = const {},
}) {
  final current = moves[task.id] ?? task.ownerEmployeeId;
  if (current == toEmployeeId) return null; // no-op, silently ignored
  final target = employees.where((e) => e.id == toEmployeeId);
  if (target.isEmpty) return 'That person is no longer active.';
  final c = computedByTaskId[task.id];
  if (c == null || c.hoursPerMonthBase <= 0) {
    return 'This responsibility is not costed yet, so moving it changes no load. '
        'Cost it on the Tasks tab first.';
  }
  return null;
}

/// Drafts with no net effect removed, so "3 unsaved moves" never counts a task
/// dragged back to where it started.
MoveDrafts prunedMoves(MoveDrafts moves, List<WpTask> tasks) {
  final byId = {for (final t in tasks) t.id: t};
  return {
    for (final e in moves.entries)
      if (byId[e.key] != null && byId[e.key]!.ownerEmployeeId != e.value)
        e.key: e.value,
  };
}
