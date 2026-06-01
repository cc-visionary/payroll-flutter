/// Pure date math for quarterly + probationary review periods. No I/O.
library;

class QuarterBounds {
  final DateTime start;
  final DateTime end;
  final DateTime due;
  const QuarterBounds({required this.start, required this.end, required this.due});
}

int quarterOf(DateTime d) => ((d.month - 1) ~/ 3) + 1;

/// Q1 = Jan 1 → Mar 31, due Apr 15.
/// Q2 = Apr 1 → Jun 30, due Jul 15.
/// Q3 = Jul 1 → Sep 30, due Oct 15.
/// Q4 = Oct 1 → Dec 31, due Jan 15 of next year.
QuarterBounds quarterBoundsFor({required int year, required int quarter}) {
  assert(quarter >= 1 && quarter <= 4, 'quarter must be 1..4');
  final startMonth = (quarter - 1) * 3 + 1;
  final start = DateTime.utc(year, startMonth, 1);
  final endMonthStart = DateTime.utc(year, startMonth + 3, 1);
  final end = endMonthStart.subtract(const Duration(days: 1));
  final dueRaw = DateTime.utc(end.year, end.month, end.day).add(const Duration(days: 15));
  return QuarterBounds(start: start, end: end, due: dueRaw);
}

String quarterNameFor({required int year, required int quarter}) =>
    '$year Q$quarter';

/// Add `months` calendar months to `d`, clamping the day to the target
/// month's last day if necessary. Used for probationary milestone dates.
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
  final lastDayOfTarget = DateTime.utc(year, month + 1, 1).subtract(const Duration(days: 1)).day;
  final day = d.day > lastDayOfTarget ? lastDayOfTarget : d.day;
  return DateTime.utc(year, month, day);
}
