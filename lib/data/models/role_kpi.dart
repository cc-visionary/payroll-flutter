import 'kpi_goal.dart';

/// One KPI on a role card, with its stable library id — used by the per-employee
/// assignment UI (which keys on kpi_id) rather than the display-only KpiItem.
class RoleKpi {
  final String kpiId;
  final String name;

  /// Legacy display text, derived from [goal] on save. Still populated for
  /// links whose goal has not been set yet.
  final String? target;
  final String? frequency;

  /// The structured goal for this role. Null until the link is upgraded.
  final KpiGoal? goal;

  /// Lifted from the embedded library row so a caller can render the goal and
  /// judge a reading without a second query.
  final String? unit;
  final String? cadence;

  /// The `role_outcomes` row this link proves, or null if none has been
  /// picked. See role_outcomes (20260814000002) and `KpiLinkInput.outcomeId`.
  final String? outcomeId;

  const RoleKpi({
    required this.kpiId,
    required this.name,
    this.target,
    this.frequency,
    this.goal,
    this.unit,
    this.cadence,
    this.outcomeId,
  });

  factory RoleKpi.fromRow(Map<String, dynamic> r) {
    final kpi = r['kpis'] as Map?;
    return RoleKpi(
      kpiId: r['kpi_id'] as String,
      name: kpi?['name'] as String? ?? '',
      target: r['target'] as String?,
      frequency: r['frequency'] as String?,
      goal: KpiGoal.fromRow(r),
      unit: kpi?['unit'] as String?,
      cadence: kpi?['cadence'] as String?,
      outcomeId: r['outcome_id'] as String?,
    );
  }
}
