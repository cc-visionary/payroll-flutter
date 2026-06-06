/// Quarterly + probationary review-period date math.
///
/// This is now a thin adapter over the canonical implementation in
/// `lib/data/quarter.dart` (which lives in the data layer so the repository can
/// share it). Kept for its original API and existing callers/tests — all logic
/// delegates to `data/quarter.dart` so there is a single source of truth.
library;

import '../../data/quarter.dart' as q;

class QuarterBounds {
  final DateTime start;
  final DateTime end;
  final DateTime due;
  const QuarterBounds({
    required this.start,
    required this.end,
    required this.due,
  });
}

/// Calendar quarter (1..4) of [d].
int quarterOf(DateTime d) => q.quarterOf(d).quarter;

/// Q1 = Jan 1 → Mar 31, due Apr 15 … Q4 = Oct 1 → Dec 31, due Jan 15 next year.
QuarterBounds quarterBoundsFor({required int year, required int quarter}) {
  final w = q.quarterWindow(year, quarter);
  return QuarterBounds(start: w.start, end: w.end, due: w.due);
}

String quarterNameFor({required int year, required int quarter}) =>
    q.quarterPeriodName(year, quarter);

/// Add `months` calendar months to `d`, clamping to the target month's last day.
DateTime addMonths(DateTime d, int months) => q.addMonths(d, months);
