/// Projected semi-monthly payroll cut-off dates for a penalty's repayment
/// schedule.
///
/// A penalty's installments carry no dates of their own: the compute service
/// picks them up in the first pay period whose `period_end >= effective_date`
/// and one per period after that, so the real deduction dates only exist once
/// those payroll runs are created. The agreement still has to state WHEN each
/// deduction lands, so this projects the standard semi-monthly cut-offs — the
/// 15th and the last day of each month — starting at the first one on or after
/// the penalty's effective date.
///
/// These are defaults, not commitments: HR can overwrite any row on the form
/// when a period is skipped or the deduction is deferred.
List<DateTime> projectedCutoffDates({
  required DateTime from,
  required int count,
}) {
  if (count <= 0) return const [];
  final dates = <DateTime>[];
  var year = from.year;
  var month = from.month;
  // Walk month by month, taking the 15th then the month end, keeping only
  // cut-offs on or after `from`.
  while (dates.length < count) {
    for (final day in [15, _lastDayOfMonth(year, month)]) {
      if (dates.length == count) break;
      final candidate = DateTime(year, month, day);
      if (!candidate.isBefore(DateTime(from.year, from.month, from.day))) {
        dates.add(candidate);
      }
    }
    month++;
    if (month > 12) {
      month = 1;
      year++;
    }
  }
  return dates;
}

/// Day-of-month count, leap years included (`DateTime(y, m + 1, 0)` rolls back
/// to the last day of month `m`).
int _lastDayOfMonth(int year, int month) => DateTime(year, month + 1, 0).day;
