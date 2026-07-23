import '../../data/models/employee.dart';
import '../../data/models/role_scorecard.dart';
import '../../data/models/workforce_planning.dart';

const unknownRoleCardLabel = 'Unknown role card';
const unspecifiedAreaLabel = 'Unspecified';

/// One responsibility area within a role card, tasks ordered by `task_sort`.
class TaskAreaGroup {
  final String area;
  final List<WpTask> tasks;
  const TaskAreaGroup({required this.area, required this.tasks});
}

/// One role-card bucket: the card's job title heading plus its ordered area
/// groups. [cardId] is kept (not just the label) so a rename or a duplicate
/// job title across two cards never collides in the UI.
class TaskCardGroup {
  final String cardId;
  final String jobTitle;
  final List<TaskAreaGroup> areas;
  const TaskCardGroup({
    required this.cardId,
    required this.jobTitle,
    required this.areas,
  });
}

/// Result of bucketing every `wp_tasks` row for the Tasks tab.
class TaskGroups {
  final List<TaskCardGroup> cardGroups;
  final List<WpTask> legacy;
  final List<WpTask> unattributed;
  const TaskGroups({
    required this.cardGroups,
    required this.legacy,
    required this.unattributed,
  });
}

/// Buckets [tasks] into, in priority order:
/// 1. one group per role card (`roleScorecardId != null`), nested by
///    responsibility area — areas ordered by their min `area_sort`, tasks by
///    `task_sort` within each area (never alphabetically);
/// 2. legacy "from capacity model" tasks (`externalRef != null &&
///    roleScorecardId == null`);
/// 3. everything else.
///
/// Card lookup is deliberately defensive: `roleScorecardListProvider` calls
/// `.list()`, which defaults to `onlyActive: true`, so a task's
/// `roleScorecardId` can point at a card that fell out of that fetch
/// (superseded/inactive). Tasks are grouped by id first and the label is
/// looked up second, falling back to [unknownRoleCardLabel] — so a task is
/// never dropped just because its card isn't in [cards]. Known cards are
/// headed in [cards]' order (already job-title sorted by the repository);
/// unknown ids are appended afterward, sorted by id for determinism. Only
/// ids with >=1 task ever produce a heading — empty cards are never listed.
///
/// Bucket 3 is deliberately the true complement of 1+2
/// (`roleScorecardId == null && !bucket2`), not "no card and no owner" as
/// the spec's prose narrows it — a task can carry an explicit
/// `ownerEmployeeId` with no card and no `externalRef` (an unattributed row
/// that still has an owner). Narrowing bucket 3 to "no owner" would make
/// that row match none of the three buckets and silently disappear, which
/// is unacceptable for an HR-facing inventory.
TaskGroups groupTasks(List<WpTask> tasks, List<RoleScorecard> cards) {
  final byCardId = <String, List<WpTask>>{};
  final legacy = <WpTask>[];
  final unattributed = <WpTask>[];
  for (final t in tasks) {
    final rsId = t.roleScorecardId;
    if (rsId != null) {
      (byCardId[rsId] ??= []).add(t);
    } else if (t.externalRef != null) {
      legacy.add(t);
    } else {
      unattributed.add(t);
    }
  }

  final cardGroups = <TaskCardGroup>[];
  for (final c in cards) {
    final forCard = byCardId.remove(c.id);
    if (forCard == null || forCard.isEmpty) continue;
    cardGroups.add(TaskCardGroup(
      cardId: c.id,
      jobTitle: c.jobTitle,
      areas: _groupByArea(forCard),
    ));
  }
  // Remaining ids reference cards outside the active-only fetch.
  final unknownIds = byCardId.keys.toList()..sort();
  for (final id in unknownIds) {
    cardGroups.add(TaskCardGroup(
      cardId: id,
      jobTitle: unknownRoleCardLabel,
      areas: _groupByArea(byCardId[id]!),
    ));
  }

  return TaskGroups(cardGroups: cardGroups, legacy: legacy, unattributed: unattributed);
}

/// Splits tasks into ACTIVE (shown, grouped, costed) and ARCHIVED (retained,
/// shown only in the collapsible Archived section, restorable).
({List<WpTask> active, List<WpTask> archived}) partitionByStatus(
    List<WpTask> tasks) {
  final active = <WpTask>[], archived = <WpTask>[];
  for (final t in tasks) {
    (t.status == 'ARCHIVED' ? archived : active).add(t);
  }
  return (active: active, archived: archived);
}

List<TaskAreaGroup> _groupByArea(List<WpTask> tasks) {
  final areaSortMin = <String, int>{};
  final byArea = <String, List<WpTask>>{};
  for (final t in tasks) {
    final raw = t.responsibilityArea?.trim();
    final area = (raw == null || raw.isEmpty) ? unspecifiedAreaLabel : raw;
    final prev = areaSortMin[area];
    if (prev == null || t.areaSort < prev) areaSortMin[area] = t.areaSort;
    (byArea[area] ??= []).add(t);
  }
  final areas = byArea.keys.toList()
    ..sort((a, b) {
      final c = areaSortMin[a]!.compareTo(areaSortMin[b]!);
      return c != 0 ? c : a.compareTo(b);
    });
  return [
    for (final a in areas)
      TaskAreaGroup(
        area: a,
        tasks: (byArea[a]!..sort((x, y) {
          final c = x.taskSort.compareTo(y.taskSort);
          return c != 0 ? c : x.id.compareTo(y.id);
        })),
      ),
  ];
}

/// A task has no times when neither its driver (if `timesSource == 'driver'`)
/// nor its manual value is set, and no minutes when neither its rate (if
/// `minutesSource == 'rate'`) nor its manual value is set. "Not costed" means
/// both are missing — this exactly matches a freshly-promoted responsibility
/// from the unification migration (`times_source='manual',
/// minutes_source='manual'`, both manual values null): a real "0 hours" for
/// the wrong reason (never priced), which should read as "not costed" rather
/// than "0.0 h".
bool isTaskNotCosted(WpTask task) {
  if ((task.hoursPerMonth ?? 0) > 0) return false;
  final hasTimes =
      task.timesSource == 'driver' ? task.driverId != null : task.timesManual != null;
  final hasMinutes =
      task.minutesSource == 'rate' ? task.rateId != null : task.minutesManual != null;
  return !hasTimes && !hasMinutes;
}

/// Replicates the `wp_task_computed` SQL view's per-task hours formula
/// client-side (see supabase/migrations/20260719000002_wp_views.sql):
/// `times_per_month * minutes_each / 60.0`, with `times_per_month` from the
/// driver (value * driverFactor) or the manual value, and `minutes_each`
/// from the rate or the manual value.
double taskHours({
  required WpTask task,
  required Map<String, WpDriver> driverById,
  required Map<String, WpRate> rateById,
}) {
  if (task.hoursPerMonth != null) return task.hoursPerMonth!;
  final timesPerMonth = task.timesSource == 'driver'
      ? (driverById[task.driverId]?.value ?? 0) * task.driverFactor
      : (task.timesManual ?? 0);
  final minutesEach = task.minutesSource == 'rate'
      ? (rateById[task.rateId]?.minutesEach ?? 0)
      : (task.minutesManual ?? 0);
  return timesPerMonth * minutesEach / 60.0;
}

/// The effective-owner label to show for a task, plus whether it was
/// derived from the role card (rather than an explicit assignment).
class EffectiveOwner {
  final String label;
  final bool derived;
  const EffectiveOwner({required this.label, required this.derived});
}

/// Resolves the label shown in the Owner column. Mirrors `wp_person_load`'s
/// attribution order (explicit owner -> else split across role holders ->
/// else unattributed) for the *label* only — the hours split itself is
/// already computed server-side by that view; this never re-derives hours.
///
/// - Explicit `ownerEmployeeId`: that employee's name (falling back to
///   'Unassigned' if they're not in [employeeNameById], e.g. separated), not
///   derived.
/// - Else, a `roleScorecardId`: the card's holders — `employees` filtered to
///   `roleScorecardId == task.roleScorecardId` AND `employmentStatus ==
///   'ACTIVE'`. The ACTIVE filter matters: `employees` here comes from
///   `wpActiveEmployeesProvider`, which only excludes `deleted_at`-set rows,
///   not separated-but-undeleted ones (there are six non-ACTIVE statuses —
///   RESIGNED, TERMINATED, AWOL, DECEASED, END_OF_CONTRACT, RETIRED — and
///   nothing clears `role_scorecard_id` on separation). The migration's
///   `wp_person_load` holders CTE requires both `employment_status =
///   'ACTIVE'` and `deleted_at is null`; without the same filter here, a
///   card with one ACTIVE and one TERMINATED holder would show "2 holders /
///   Derived" while the view gives 100% of the hours to the one ACTIVE
///   holder — a visible disagreement between this tab and Balance/Role-View.
///   One holder -> their name, derived. Multiple -> "N holders", derived.
///   Zero holders -> 'Unassigned', NOT derived (nothing was actually
///   derived from anything).
/// - Else: 'Unassigned', not derived.
EffectiveOwner resolveEffectiveOwner({
  required WpTask task,
  required Map<String, String> employeeNameById,
  required List<Employee> employees,
}) {
  final ownerId = task.ownerEmployeeId;
  if (ownerId != null) {
    return EffectiveOwner(label: employeeNameById[ownerId] ?? 'Unassigned', derived: false);
  }
  final cardId = task.roleScorecardId;
  if (cardId != null) {
    final holders = employees
        .where((e) => e.roleScorecardId == cardId && e.employmentStatus == 'ACTIVE')
        .toList();
    if (holders.isEmpty) {
      return const EffectiveOwner(label: 'Unassigned', derived: false);
    }
    if (holders.length == 1) {
      final h = holders.first;
      return EffectiveOwner(label: '${h.firstName} ${h.lastName}', derived: true);
    }
    return EffectiveOwner(label: '${holders.length} holders', derived: true);
  }
  return const EffectiveOwner(label: 'Unassigned', derived: false);
}

/// One task as attributed to a specific person, together with how many people
/// share it. [holderCount] is 1 for an explicitly-owned task and N for a task
/// derived from a role card held by N people (so that person carries 1/N of
/// its hours).

/// Where a responsibility should sit when it joins a card's area.
///
/// The role-card PDF and the employment-contract Annex A render
/// responsibilities in `area_sort` / `task_sort` order, so position is not
/// cosmetic — it decides the wording of a document. `WpTask.toUpsert` used to
/// omit these columns, which left every row created from the Tasks tab at 0/0,
/// i.e. jumping to the TOP of its area ahead of the responsibility the card
/// author put first.
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
