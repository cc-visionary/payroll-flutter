import '../../data/models/kpi_goal.dart';
import '../../data/models/kpi_result.dart';

/// Floating-point readings never land exactly on a goal; 1e-9 is far below any
/// unit this app measures in (whole orders, days, pesos, one-decimal percents).
const _epsilon = 1e-9;

/// Derives a period's value and status from raw inputs.
///
/// Pure and total: every combination of inputs returns a record, never throws.
/// `PERCENT` is treated like `COUNT` — the numerator is the value. Only `RATIO`
/// requires both numerator and denominator; the UI is what appends a `%`.
({num? value, KpiStatus status}) evaluateKpi({
  required String valueType,
  num? numerator,
  num? denominator,
  num? target,
  GoalDirection? direction,
  num? targetMax,
}) {
  // Only RATIO divides; other types (including PERCENT) use numerator directly.
  // Unrecognized valueType falls through to this path, treating numerator as value —
  // a recoverable direction when config is incomplete rather than a hard error.
  num? value;
  if (numerator == null) {
    value = null;
  } else if (valueType == 'RATIO') {
    if (denominator == null || denominator == 0) {
      value = null;
    } else {
      value = numerator / denominator;
    }
  } else {
    value = numerator;
  }

  if (value == null || target == null) {
    return (value: value, status: KpiStatus.noData);
  }

  final dir = direction ?? GoalDirection.gte;
  if (dir == GoalDirection.between) {
    if (targetMax == null || targetMax < target) {
      // Missing upper bound or impossible band (min > max) is a config error.
      return (value: value, status: KpiStatus.noData);
    }
  }

  final ok = switch (dir) {
    GoalDirection.gte => value >= target - _epsilon,
    GoalDirection.lte => value <= target + _epsilon,
    GoalDirection.eq => (value - target).abs() <= _epsilon,
    GoalDirection.between => value >= target - _epsilon && value <= targetMax! + _epsilon,
  };
  return (value: value, status: ok ? KpiStatus.onTrack : KpiStatus.offTrack);
}
