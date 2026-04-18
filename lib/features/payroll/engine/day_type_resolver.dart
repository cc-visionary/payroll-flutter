import 'package:decimal/decimal.dart';

/// Day-type resolution — ported from payrollos/lib/payroll/day-type-resolver.ts.
/// Note: payrollos uses a richer set of day types here than the Prisma `DayType`
/// enum (it splits REGULAR/SPECIAL_HOLIDAY_REST_DAY combinations). We preserve
/// those as a local enum (ResolvedDayType) so the resolution logic stays
/// faithful to the TS source. Storage-side, these map back to the Prisma DayType.

enum ResolvedDayType {
  REGULAR_WORKING_DAY,
  REST_DAY,
  REGULAR_HOLIDAY,
  SPECIAL_HOLIDAY,
  REGULAR_HOLIDAY_REST_DAY,
  SPECIAL_HOLIDAY_REST_DAY,
  SPECIAL_WORKING_DAY,
  COMPANY_EVENT,
}

final Map<ResolvedDayType, Decimal> DAY_TYPE_MULTIPLIERS = {
  ResolvedDayType.REGULAR_WORKING_DAY: Decimal.parse('1.0'),
  ResolvedDayType.REST_DAY: Decimal.parse('1.3'),
  ResolvedDayType.SPECIAL_HOLIDAY: Decimal.parse('1.3'),
  ResolvedDayType.SPECIAL_HOLIDAY_REST_DAY: Decimal.parse('1.5'),
  ResolvedDayType.REGULAR_HOLIDAY: Decimal.parse('2.0'),
  ResolvedDayType.REGULAR_HOLIDAY_REST_DAY: Decimal.parse('2.6'),
  ResolvedDayType.SPECIAL_WORKING_DAY: Decimal.parse('1.0'),
  ResolvedDayType.COMPANY_EVENT: Decimal.parse('1.0'),
};

final Map<ResolvedDayType, bool> DAY_TYPE_PAID_IF_NOT_WORKED = {
  ResolvedDayType.REGULAR_WORKING_DAY: false,
  ResolvedDayType.REST_DAY: false,
  ResolvedDayType.SPECIAL_HOLIDAY: false,
  ResolvedDayType.SPECIAL_HOLIDAY_REST_DAY: false,
  ResolvedDayType.REGULAR_HOLIDAY: true,
  ResolvedDayType.REGULAR_HOLIDAY_REST_DAY: true,
  ResolvedDayType.SPECIAL_WORKING_DAY: false,
  ResolvedDayType.COMPANY_EVENT: false,
};

class CalendarEvent {
  /// "REGULAR_HOLIDAY", "SPECIAL_HOLIDAY", "SPECIAL_WORKING_DAY", "COMPANY_EVENT"
  final String dayType;
  final String name;
  const CalendarEvent({required this.dayType, required this.name});
}

class DayTypeResolution {
  final ResolvedDayType dayType;
  final Decimal multiplier;
  final bool paidIfNotWorked;
  final String? holidayName;
  final bool isRestDay;

  const DayTypeResolution({
    required this.dayType,
    required this.multiplier,
    required this.paidIfNotWorked,
    required this.holidayName,
    required this.isRestDay,
  });
}

String _dateKey(DateTime d) {
  final y = d.toUtc().year.toString().padLeft(4, '0');
  final m = d.toUtc().month.toString().padLeft(2, '0');
  final day = d.toUtc().day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

/// Default rest days: Sunday (7 in Dart) and Saturday (6).
/// Dart's DateTime.weekday: 1 = Monday ... 7 = Sunday. We normalize to JS's
/// 0 = Sunday ... 6 = Saturday for parity with payrollos.
int _jsDayOfWeek(DateTime d) {
  final w = d.toUtc().weekday; // 1..7 Mon..Sun
  return w == 7 ? 0 : w;
}

const List<int> DEFAULT_REST_DAYS = [0, 6]; // Sunday, Saturday

List<int> getRestDayNumbers() => DEFAULT_REST_DAYS;

DayTypeResolution resolveDayType(
  DateTime date,
  List<int> restDayNumbers,
  Map<String, CalendarEvent> eventMap,
) {
  final dateKey = _dateKey(date);
  final dayOfWeek = _jsDayOfWeek(date);
  final isRestDay = restDayNumbers.contains(dayOfWeek);

  final event = eventMap[dateKey];

  if (event != null) {
    if (event.dayType == 'REGULAR_HOLIDAY' && isRestDay) {
      return DayTypeResolution(
        dayType: ResolvedDayType.REGULAR_HOLIDAY_REST_DAY,
        multiplier: DAY_TYPE_MULTIPLIERS[ResolvedDayType.REGULAR_HOLIDAY_REST_DAY]!,
        paidIfNotWorked: true,
        holidayName: event.name,
        isRestDay: true,
      );
    }
    if (event.dayType == 'SPECIAL_HOLIDAY' && isRestDay) {
      return DayTypeResolution(
        dayType: ResolvedDayType.SPECIAL_HOLIDAY_REST_DAY,
        multiplier: DAY_TYPE_MULTIPLIERS[ResolvedDayType.SPECIAL_HOLIDAY_REST_DAY]!,
        paidIfNotWorked: false,
        holidayName: event.name,
        isRestDay: true,
      );
    }
    final rdt = _parseResolved(event.dayType);
    return DayTypeResolution(
      dayType: rdt,
      multiplier: DAY_TYPE_MULTIPLIERS[rdt]!,
      paidIfNotWorked: DAY_TYPE_PAID_IF_NOT_WORKED[rdt]!,
      holidayName: event.name,
      isRestDay: false,
    );
  }

  if (isRestDay) {
    return DayTypeResolution(
      dayType: ResolvedDayType.REST_DAY,
      multiplier: DAY_TYPE_MULTIPLIERS[ResolvedDayType.REST_DAY]!,
      paidIfNotWorked: false,
      holidayName: null,
      isRestDay: true,
    );
  }

  return DayTypeResolution(
    dayType: ResolvedDayType.REGULAR_WORKING_DAY,
    multiplier: DAY_TYPE_MULTIPLIERS[ResolvedDayType.REGULAR_WORKING_DAY]!,
    paidIfNotWorked: false,
    holidayName: null,
    isRestDay: false,
  );
}

ResolvedDayType _parseResolved(String s) {
  switch (s) {
    case 'REGULAR_HOLIDAY':
      return ResolvedDayType.REGULAR_HOLIDAY;
    case 'SPECIAL_HOLIDAY':
      return ResolvedDayType.SPECIAL_HOLIDAY;
    case 'SPECIAL_WORKING_DAY':
      return ResolvedDayType.SPECIAL_WORKING_DAY;
    case 'REST_DAY':
      return ResolvedDayType.REST_DAY;
    case 'REGULAR_HOLIDAY_REST_DAY':
      return ResolvedDayType.REGULAR_HOLIDAY_REST_DAY;
    case 'SPECIAL_HOLIDAY_REST_DAY':
      return ResolvedDayType.SPECIAL_HOLIDAY_REST_DAY;
    case 'COMPANY_EVENT':
      return ResolvedDayType.COMPANY_EVENT;
    default:
      return ResolvedDayType.REGULAR_WORKING_DAY;
  }
}

Map<String, DayTypeResolution> resolveDayTypesForRange(
  DateTime startDate,
  DateTime endDate,
  Map<String, CalendarEvent> eventMap,
) {
  final restDayNumbers = getRestDayNumbers();
  final results = <String, DayTypeResolution>{};
  var current = DateTime.utc(startDate.year, startDate.month, startDate.day);
  final end = DateTime.utc(endDate.year, endDate.month, endDate.day);
  while (!current.isAfter(end)) {
    results[_dateKey(current)] = resolveDayType(current, restDayNumbers, eventMap);
    current = current.add(const Duration(days: 1));
  }
  return results;
}

// =============================================================================
// Per-day pay helpers (used by payslip-generator)
// =============================================================================

class HolidayPayBreakdown {
  final Decimal basePay;
  final Decimal holidayPremium;
  final Decimal total;
  const HolidayPayBreakdown(this.basePay, this.holidayPremium, this.total);
}

class RestDayPayBreakdown {
  final Decimal basePay;
  final Decimal restDayPremium;
  final Decimal total;
  const RestDayPayBreakdown(this.basePay, this.restDayPremium, this.total);
}

Decimal _div(Decimal a, Decimal b) => (a / b).toDecimal(scaleOnInfinitePrecision: 10);

HolidayPayBreakdown calculateRegularHolidayPay(
  Decimal dailyRate,
  Decimal hoursWorked, {
  int standardHours = 8,
}) {
  final basePay = dailyRate;
  if (hoursWorked == Decimal.zero) {
    return HolidayPayBreakdown(basePay, Decimal.zero, basePay);
  }
  final hourlyRate = _div(dailyRate, Decimal.fromInt(standardHours));
  final holidayPremium = hourlyRate * hoursWorked; // +100%
  return HolidayPayBreakdown(basePay, holidayPremium, basePay + holidayPremium);
}

HolidayPayBreakdown calculateSpecialHolidayPay(
  Decimal dailyRate,
  Decimal hoursWorked, {
  int standardHours = 8,
}) {
  if (hoursWorked == Decimal.zero) {
    return HolidayPayBreakdown(Decimal.zero, Decimal.zero, Decimal.zero);
  }
  final hourlyRate = _div(dailyRate, Decimal.fromInt(standardHours));
  final basePay = hourlyRate * hoursWorked;
  final holidayPremium = basePay * Decimal.parse('0.3');
  return HolidayPayBreakdown(basePay, holidayPremium, basePay + holidayPremium);
}

RestDayPayBreakdown calculateRestDayPay(
  Decimal dailyRate,
  Decimal hoursWorked, {
  int standardHours = 8,
}) {
  if (hoursWorked == Decimal.zero) {
    return RestDayPayBreakdown(Decimal.zero, Decimal.zero, Decimal.zero);
  }
  final hourlyRate = _div(dailyRate, Decimal.fromInt(standardHours));
  final basePay = hourlyRate * hoursWorked;
  final restDayPremium = basePay * Decimal.parse('0.3');
  return RestDayPayBreakdown(basePay, restDayPremium, basePay + restDayPremium);
}
