// Pure calendar-quarter helpers shared by the performance repository (period
// generation) and the "New check-in" dialog (quarter picker). No I/O — kept in
// `lib/data/` so both the repository and the features layer can depend on it
// without the repository reaching up into `lib/features/`.

/// A calendar quarter, e.g. 2026 Q2.
class Quarter {
  final int year;
  final int quarter; // 1..4
  const Quarter(this.year, this.quarter);

  /// Period name, matching the auto-generator's naming: `"<year> Q<n>"`.
  String get periodName => '$year Q$quarter';

  /// Returns this quarter offset by [n] quarters (negative = earlier).
  Quarter add(int n) {
    final total = year * 4 + (quarter - 1) + n;
    return Quarter(total ~/ 4, (total % 4) + 1);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Quarter && year == other.year && quarter == other.quarter;

  @override
  int get hashCode => Object.hash(year, quarter);

  @override
  String toString() => periodName;
}

/// The calendar quarter containing [d].
Quarter quarterOf(DateTime d) => Quarter(d.year, ((d.month - 1) ~/ 3) + 1);

/// Period name for an explicit (year, quarter).
String quarterPeriodName(int year, int quarter) =>
    Quarter(year, quarter).periodName;

/// Start/end/due dates for a quarter. `due` is 15 days after the quarter ends,
/// matching the period dates written by `ensureQuarterlyPeriod`.
typedef QuarterWindow = ({DateTime start, DateTime end, DateTime due});

QuarterWindow quarterWindow(int year, int quarter) {
  final startMonth = (quarter - 1) * 3 + 1;
  final start = DateTime.utc(year, startMonth, 1);
  // DateTime tolerates month overflow (e.g. month 13 → next January), so Q4's
  // end and due naturally roll into the following year.
  final end = DateTime.utc(year, startMonth + 3, 1)
      .subtract(const Duration(days: 1));
  final due = end.add(const Duration(days: 15));
  return (start: start, end: end, due: due);
}

/// The quarters offered in the "New check-in" picker, newest first:
/// next quarter, current quarter, then the previous four. Six entries, no
/// duplicates. The current quarter is `quarterOf(now)`.
List<Quarter> quarterOptions(DateTime now) {
  final current = quarterOf(now);
  return [
    for (final offset in const [1, 0, -1, -2, -3, -4]) current.add(offset),
  ];
}

/// Adds [months] calendar months to [d], clamping the day to the target
/// month's last day if necessary (e.g. Jan 31 + 1 month → Feb 28/29). Used for
/// probationary milestone dates.
DateTime addMonths(DateTime d, int months) {
  var year = d.year;
  var month = d.month + months;
  while (month > 12) {
    month -= 12;
    year += 1;
  }
  while (month < 1) {
    month += 12;
    year -= 1;
  }
  final lastDayOfTarget =
      DateTime.utc(year, month + 1, 1).subtract(const Duration(days: 1)).day;
  final day = d.day > lastDayOfTarget ? lastDayOfTarget : d.day;
  return DateTime.utc(year, month, day);
}
