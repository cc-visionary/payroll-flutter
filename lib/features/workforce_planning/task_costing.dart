import '../../data/models/workforce_planning.dart';

/// One row's in-progress costing edit on the Tasks tab's bulk grid.
///
/// Mirrors the four `wp_tasks` columns that decide a task's hours, so the grid
/// can show a live hours/month figure without a round trip. Everything here is
/// pure so it can be unit-tested against the `wp_task_computed` formula.
class CostDraft {
  const CostDraft({
    required this.timesSource,
    this.timesManual,
    this.driverId,
    this.driverFactor = 1,
    required this.minutesSource,
    this.minutesManual,
    this.rateId,
    this.nodeId,
    this.hoursPerMonth,
  });

  final String timesSource; // 'manual' | 'driver'
  final double? timesManual;
  final String? driverId;
  final double driverFactor;
  final String minutesSource; // 'manual' | 'rate'
  final double? minutesManual;
  final String? rateId;
  final String? nodeId;

  /// Direct monthly hours. When non-null it wins over the driver calc.
  final double? hoursPerMonth;

  factory CostDraft.fromTask(WpTask t) => CostDraft(
        timesSource: t.timesSource,
        timesManual: t.timesManual,
        driverId: t.driverId,
        driverFactor: t.driverFactor,
        minutesSource: t.minutesSource,
        minutesManual: t.minutesManual,
        rateId: t.rateId,
        nodeId: t.nodeId,
        hoursPerMonth: t.hoursPerMonth,
      );

  CostDraft copyWith({
    String? timesSource,
    double? timesManual,
    String? driverId,
    double? driverFactor,
    String? minutesSource,
    double? minutesManual,
    String? rateId,
    String? nodeId,
    double? hoursPerMonth,
    bool clearTimesManual = false,
    bool clearDriverId = false,
    bool clearMinutesManual = false,
    bool clearRateId = false,
    bool clearNodeId = false,
    bool clearHoursPerMonth = false,
  }) =>
      CostDraft(
        timesSource: timesSource ?? this.timesSource,
        timesManual: clearTimesManual ? null : (timesManual ?? this.timesManual),
        driverId: clearDriverId ? null : (driverId ?? this.driverId),
        driverFactor: driverFactor ?? this.driverFactor,
        minutesSource: minutesSource ?? this.minutesSource,
        minutesManual:
            clearMinutesManual ? null : (minutesManual ?? this.minutesManual),
        rateId: clearRateId ? null : (rateId ?? this.rateId),
        nodeId: clearNodeId ? null : (nodeId ?? this.nodeId),
        hoursPerMonth:
            clearHoursPerMonth ? null : (hoursPerMonth ?? this.hoursPerMonth),
      );

  /// Applies this draft onto its task, leaving every non-costing column alone.
  WpTask applyTo(WpTask t) => WpTask(
        id: t.id,
        companyId: t.companyId,
        name: t.name,
        nodeId: nodeId,
        brandScope: t.brandScope,
        cadence: t.cadence,
        timesSource: timesSource,
        timesManual: timesManual,
        driverId: driverId,
        driverFactor: driverFactor,
        minutesSource: minutesSource,
        minutesManual: minutesManual,
        rateId: rateId,
        hoursPerMonth: hoursPerMonth,
        skillTier: t.skillTier,
        risk: t.risk,
        capability: t.capability,
        ownerEmployeeId: t.ownerEmployeeId,
        roleScorecardId: t.roleScorecardId,
        responsibilityArea: t.responsibilityArea,
        notes: t.notes,
        externalRef: t.externalRef,
        areaSort: t.areaSort,
        taskSort: t.taskSort,
        criticality: t.criticality,
        isEssential: t.isEssential,
        status: t.status,
        isExpectation: t.isExpectation,
      );

  @override
  bool operator ==(Object other) =>
      other is CostDraft &&
      other.timesSource == timesSource &&
      other.timesManual == timesManual &&
      other.driverId == driverId &&
      other.driverFactor == driverFactor &&
      other.minutesSource == minutesSource &&
      other.minutesManual == minutesManual &&
      other.rateId == rateId &&
      other.nodeId == nodeId &&
      other.hoursPerMonth == hoursPerMonth;

  @override
  int get hashCode => Object.hash(timesSource, timesManual, driverId,
      driverFactor, minutesSource, minutesManual, rateId, nodeId, hoursPerMonth);
}

/// Times per month, matching `wp_task_computed.times_per_month_base`:
/// driver -> `driver.value * driver_factor`, else `times_manual`.
double draftTimesPerMonth(CostDraft d, Map<String, WpDriver> driverById) {
  if (d.timesSource == 'driver') {
    final v = driverById[d.driverId]?.value ?? 0;
    return v * d.driverFactor;
  }
  return d.timesManual ?? 0;
}

/// Minutes per occurrence, matching `wp_task_computed.minutes_each`:
/// rate -> `rate.minutes_each`, else `minutes_manual`.
double draftMinutesEach(CostDraft d, Map<String, WpRate> rateById) {
  if (d.minutesSource == 'rate') return rateById[d.rateId]?.minutesEach ?? 0;
  return d.minutesManual ?? 0;
}

/// Hours per month, matching `wp_task_computed.hours_per_month_base`
/// (`times_per_month_base * minutes_each / 60`).
double draftHoursPerMonth(
  CostDraft d,
  Map<String, WpDriver> driverById,
  Map<String, WpRate> rateById,
) {
  if (d.hoursPerMonth != null) return d.hoursPerMonth!;
  return draftTimesPerMonth(d, driverById) * draftMinutesEach(d, rateById) / 60.0;
}

/// A task counts as costed when a direct hours figure is set, OR when BOTH
/// driver-calc halves resolve to something non-zero; this is what the Tasks
/// tab's "Not costed" badge keys off.
bool draftIsCosted(
  CostDraft d,
  Map<String, WpDriver> driverById,
  Map<String, WpRate> rateById,
) {
  if ((d.hoursPerMonth ?? 0) > 0) return true;
  return draftTimesPerMonth(d, driverById) > 0 && draftMinutesEach(d, rateById) > 0;
}

/// Whether the task's hours respond to the growth multiplier — true only when
/// times come from a driver flagged `grows`. This is the property that makes
/// scenario planning move; a manual times figure is flat forever, and so is a
/// direct hours figure, which always wins over the driver calc.
bool draftIsGrowing(CostDraft d, Map<String, WpDriver> driverById) =>
    d.hoursPerMonth == null &&
    d.timesSource == 'driver' &&
    (driverById[d.driverId]?.grows ?? false);

/// Where a responsibility sits in the costing workflow.
///
/// `costed` is DERIVED from having hours, never stored — a stored three-way
/// status would let a row claim it is costed while its times/minutes are null,
/// and then the queue and the load math would disagree about the same task.
enum TaskCostState {
  /// Carries hours and contributes to load.
  costed,

  /// Real workload that nobody has estimated yet — the costing queue's backlog.
  toCost,

  /// A behavioural expectation from the job description. Will never have hours,
  /// and excluding it is what lets the queue reach zero.
  expectation,
}

TaskCostState taskCostState(
  WpTask t,
  Map<String, WpDriver> driverById,
  Map<String, WpRate> rateById,
) {
  if (draftIsCosted(CostDraft.fromTask(t), driverById, rateById)) {
    return TaskCostState.costed;
  }
  return t.isExpectation ? TaskCostState.expectation : TaskCostState.toCost;
}

/// Parses a user-typed number, treating blank/garbage as "not set" rather than
/// as zero — zero is a meaningful costing answer and must stay distinguishable
/// from an empty cell.
double? parseCostField(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  return double.tryParse(s);
}

/// Applies one estimate to a whole group of tasks — the bulk accelerator for
/// the 164 promoted responsibilities, where typing two numbers per row means
/// 328 entries but one estimate per responsibility area means 42.
///
/// Returns the drafts to merge in. Rows whose resulting draft matches the task
/// unchanged are omitted, so filling a group twice doesn't invent edits.
///
/// [onlyUncosted] defaults to true: a deliberate per-task figure is worth more
/// than a group default, so filling must never silently overwrite one. Pass
/// false to restate the whole group.
Map<String, CostDraft> fillGroupDrafts({
  required List<WpTask> tasks,
  required Map<String, CostDraft> current,
  required Map<String, WpDriver> driverById,
  required Map<String, WpRate> rateById,
  double? timesManual,
  double? minutesManual,
  bool onlyUncosted = true,
}) {
  final out = <String, CostDraft>{};
  for (final t in tasks) {
    final existing = current[t.id] ?? CostDraft.fromTask(t);
    if (onlyUncosted && draftIsCosted(existing, driverById, rateById)) continue;
    final next = existing.copyWith(
      timesSource: 'manual',
      minutesSource: 'manual',
      clearDriverId: true,
      clearRateId: true,
      timesManual: timesManual ?? existing.timesManual,
      minutesManual: minutesManual ?? existing.minutesManual,
    );
    if (next != CostDraft.fromTask(t)) out[t.id] = next;
  }
  return out;
}

/// The costing-only column patch for one row. Mirrors the source/id nulling
/// rules in [WpTask.toUpsert] so a driver-sourced task never keeps a stale
/// `times_manual` (and vice versa) — leaving both set would make the row read
/// differently depending on which source flag won.
Map<String, dynamic> draftPatch(CostDraft d) {
  if (d.hoursPerMonth != null) {
    return {
      'node_id': d.nodeId,
      'hours_per_month': d.hoursPerMonth,
      'times_source': 'manual', 'times_manual': null, 'driver_id': null,
      'driver_factor': d.driverFactor,
      'minutes_source': 'manual', 'minutes_manual': null, 'rate_id': null,
    };
  }
  return {
    'node_id': d.nodeId,
    'hours_per_month': null,
    'times_source': d.timesSource,
    'times_manual': d.timesSource == 'driver' ? null : d.timesManual,
    'driver_id': d.timesSource == 'driver' ? d.driverId : null,
    'driver_factor': d.driverFactor,
    'minutes_source': d.minutesSource,
    'minutes_manual': d.minutesSource == 'rate' ? null : d.minutesManual,
    'rate_id': d.minutesSource == 'rate' ? d.rateId : null,
  };
}
