import '../../data/models/kpi_goal.dart';

/// The value a period's raw counts produce, or null when it cannot be computed.
///
/// Null is a first-class answer: a week with nothing shipped has no return
/// RATE, and reporting 0% would read as a perfect week rather than as missing
/// data. Every caller must render null as "—", never as zero.
double? computeReadingValue({
  required String? valueType,
  required String? unit,
  required double? numerator,
  double? denominator,
}) {
  if (numerator == null) return null;
  if (valueType != 'RATIO') return numerator;
  if (denominator == null || denominator == 0) return null;
  final quotient = numerator / denominator;
  return (unit ?? '').trim() == '%' ? quotient * 100 : quotient;
}

/// Floating-point readings never land exactly on a goal; 1e-9 is far below any
/// unit this app measures in (whole orders, days, pesos, one-decimal percents).
const _epsilon = 1e-9;

/// EOS's binary verdict. Null means unknown — no reading yet, or no goal set —
/// and must never be collapsed into "off-track".
bool? isOnTrack(double? value, KpiGoal? goal) {
  if (value == null || goal == null) return null;
  return switch (goal.direction) {
    GoalDirection.gte => value >= goal.value - _epsilon,
    GoalDirection.lte => value <= goal.value + _epsilon,
    GoalDirection.eq => (value - goal.value).abs() <= _epsilon,
    GoalDirection.between =>
      value >= goal.value - _epsilon &&
          value <= (goal.valueMax ?? goal.value) + _epsilon,
  };
}
