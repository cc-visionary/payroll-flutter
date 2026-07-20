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
  });

  final String timesSource; // 'manual' | 'driver'
  final double? timesManual;
  final String? driverId;
  final double driverFactor;
  final String minutesSource; // 'manual' | 'rate'
  final double? minutesManual;
  final String? rateId;
  final String? nodeId;

  factory CostDraft.fromTask(WpTask t) => CostDraft(
        timesSource: t.timesSource,
        timesManual: t.timesManual,
        driverId: t.driverId,
        driverFactor: t.driverFactor,
        minutesSource: t.minutesSource,
        minutesManual: t.minutesManual,
        rateId: t.rateId,
        nodeId: t.nodeId,
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
    bool clearTimesManual = false,
    bool clearDriverId = false,
    bool clearMinutesManual = false,
    bool clearRateId = false,
    bool clearNodeId = false,
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
      other.nodeId == nodeId;

  @override
  int get hashCode => Object.hash(timesSource, timesManual, driverId,
      driverFactor, minutesSource, minutesManual, rateId, nodeId);
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
) =>
    draftTimesPerMonth(d, driverById) * draftMinutesEach(d, rateById) / 60.0;

/// A task counts as costed only when BOTH halves resolve to something non-zero;
/// this is what the Tasks tab's "Not costed" badge keys off.
bool draftIsCosted(
  CostDraft d,
  Map<String, WpDriver> driverById,
  Map<String, WpRate> rateById,
) =>
    draftTimesPerMonth(d, driverById) > 0 && draftMinutesEach(d, rateById) > 0;

/// Whether the task's hours respond to the growth multiplier — true only when
/// times come from a driver flagged `grows`. This is the property that makes
/// scenario planning move; a manual times figure is flat forever.
bool draftIsGrowing(CostDraft d, Map<String, WpDriver> driverById) =>
    d.timesSource == 'driver' && (driverById[d.driverId]?.grows ?? false);

/// Parses a user-typed number, treating blank/garbage as "not set" rather than
/// as zero — zero is a meaningful costing answer and must stay distinguishable
/// from an empty cell.
double? parseCostField(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  return double.tryParse(s);
}

/// The costing-only column patch for one row. Mirrors the source/id nulling
/// rules in [WpTask.toUpsert] so a driver-sourced task never keeps a stale
/// `times_manual` (and vice versa) — leaving both set would make the row read
/// differently depending on which source flag won.
Map<String, dynamic> draftPatch(CostDraft d) => {
      'node_id': d.nodeId,
      'times_source': d.timesSource,
      'times_manual': d.timesSource == 'driver' ? null : d.timesManual,
      'driver_id': d.timesSource == 'driver' ? d.driverId : null,
      'driver_factor': d.driverFactor,
      'minutes_source': d.minutesSource,
      'minutes_manual': d.minutesSource == 'rate' ? null : d.minutesManual,
      'rate_id': d.minutesSource == 'rate' ? d.rateId : null,
    };
