import '../../data/models/kpi_input.dart';

/// The exception-aggregation rule: how many confirmed exceptions [period]
/// (and optionally [employeeId]) accumulated.
///
/// Only CONFIRMED exceptions count — every KPI in the owner's draft says
/// "confirmed" errors, and a metric that moves on an unverified claim is one
/// people learn to game or resent. Buckets by [KpiException.occurredOn], NOT
/// by when the row was recorded or confirmed, so an exception confirmed in a
/// later month still lands in the month it actually happened. Sums
/// [KpiException.quantity] rather than counting rows, so a single row
/// recording "3 errors" contributes 3.
///
/// Zero confirmed rows returns `0`, never `null` — the caller decides what
/// that means. The compute service (Task 7) knows whether ANY exception rows
/// exist at all for this KPI/period, so it alone can distinguish "nothing
/// happened" from "nothing confirmed yet"; this function only ever answers
/// "how many confirmed", and that answer is always a number.
num confirmedCountFor({
  required List<KpiException> exceptions,
  required String period,
  String? employeeId,
}) {
  num total = 0;
  for (final e in exceptions) {
    if (e.confirmedAt == null) continue;
    if (employeeId != null && e.employeeId != employeeId) continue;
    final occurredPeriod =
        '${e.occurredOn.year.toString().padLeft(4, '0')}-'
        '${e.occurredOn.month.toString().padLeft(2, '0')}';
    if (occurredPeriod != period) continue;
    total += e.quantity;
  }
  return total;
}
