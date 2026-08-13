import '../../data/models/kpi_goal.dart';
import '../../data/models/kpi_result.dart';

/// Derives a period's value and status from raw inputs.
///
/// Pure and total: every combination of inputs returns a record, never throws.
/// `PERCENT` is treated as a ratio expressed 0..1, the same as `RATIO`; the UI
/// is what appends a `%`.
({num? value, KpiStatus status}) evaluateKpi({
  required String valueType,
  num? numerator,
  num? denominator,
  num? target,
  GoalDirection? direction,
  num? targetMax,
}) {
  final needsDenominator = valueType == 'RATIO' || valueType == 'PERCENT';

  num? value;
  if (numerator == null) {
    value = null;
  } else if (!needsDenominator) {
    value = numerator;
  } else if (denominator == null || denominator == 0) {
    value = null;
  } else {
    value = numerator / denominator;
  }

  if (value == null || target == null) {
    return (value: value, status: KpiStatus.noData);
  }

  final dir = direction ?? GoalDirection.gte;
  if (dir == GoalDirection.between && targetMax == null) {
    return (value: value, status: KpiStatus.noData);
  }

  final ok = switch (dir) {
    GoalDirection.gte => value >= target,
    GoalDirection.lte => value <= target,
    GoalDirection.eq => value == target,
    GoalDirection.between => value >= target && value <= targetMax!,
  };
  return (value: value, status: ok ? KpiStatus.onTrack : KpiStatus.offTrack);
}
