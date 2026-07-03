/// The default pay period a new payroll run opens with.
class DefaultPayPeriod {
  final DateTime start;
  final DateTime end;
  final DateTime payDate;
  const DefaultPayPeriod({
    required this.start,
    required this.end,
    required this.payDate,
  });
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Computes the default period for a new payroll run: the still-unpaid window
/// from the day after the last release up to yesterday, paid today.
///
/// - `end` is always **yesterday** (`today - 1`) — the last day that has
///   attendance to pay (today isn't over yet).
/// - `start` is the day after [lastReleasedEnd] (the last day already paid).
///   When there is no prior release — or the last release already covers
///   through yesterday, so there is nothing new to pay — it falls back to a
///   **15-day window ending yesterday** (`end - 14`, inclusive).
/// - `payDate` is **today**.
///
/// Pure and date-only; callers pass `DateTime.now()` for [today] and the
/// `period_end` of the most recent applicable RELEASED run for
/// [lastReleasedEnd] (or null when none exists).
DefaultPayPeriod defaultPayPeriod({
  required DateTime today,
  DateTime? lastReleasedEnd,
}) {
  final t = _dateOnly(today);
  final end = t.subtract(const Duration(days: 1)); // yesterday
  const fallbackSpan = Duration(days: 14); // 15-day inclusive window

  DateTime start;
  if (lastReleasedEnd != null) {
    start = _dateOnly(lastReleasedEnd).add(const Duration(days: 1));
  } else {
    start = end.subtract(fallbackSpan);
  }

  // Fully paid up (or clock skew): a start after the end is nonsensical —
  // fall back to the 15-day window ending yesterday.
  if (start.isAfter(end)) {
    start = end.subtract(fallbackSpan);
  }

  return DefaultPayPeriod(start: start, end: end, payDate: t);
}
