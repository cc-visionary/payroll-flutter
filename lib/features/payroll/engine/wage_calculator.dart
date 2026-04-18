import 'package:decimal/decimal.dart';
import 'types.dart';

/// Wage calculations — ported verbatim from payrollos/lib/payroll/wage-calculator.ts.
/// DOLE standard formulas; money in Decimal.

class DerivedRates {
  final Decimal monthlyRate;
  final Decimal dailyRate;
  final Decimal hourlyRate;
  final Decimal minuteRate;
  /// Monthly Salary Credit = dailyRate × 26, for statutory contributions.
  final Decimal msc;

  const DerivedRates({
    required this.monthlyRate,
    required this.dailyRate,
    required this.hourlyRate,
    required this.minuteRate,
    required this.msc,
  });
}

Decimal _zero = Decimal.zero;

Decimal _round3(Decimal v) {
  final factor = Decimal.fromInt(1000);
  return ((v * factor).round(scale: 0) / factor).toDecimal(scaleOnInfinitePrecision: 3);
}

Decimal _div(Decimal a, Decimal b) => (a / b).toDecimal(scaleOnInfinitePrecision: 10);

Decimal _fromInt(int i) => Decimal.fromInt(i);

DerivedRates calculateDerivedRates(PayProfileInput profile) {
  final days = _fromInt(profile.standardWorkDaysPerMonth);
  final hours = _fromInt(profile.standardHoursPerDay);
  Decimal monthlyRate;
  Decimal dailyRate;
  Decimal hourlyRate;

  switch (profile.wageType) {
    case WageType.MONTHLY:
      monthlyRate = profile.baseRate;
      dailyRate = _div(monthlyRate, days);
      hourlyRate = _div(dailyRate, hours);
      break;
    case WageType.DAILY:
      dailyRate = profile.baseRate;
      hourlyRate = _div(dailyRate, hours);
      monthlyRate = dailyRate * days;
      break;
    case WageType.HOURLY:
      hourlyRate = profile.baseRate;
      dailyRate = hourlyRate * hours;
      monthlyRate = dailyRate * days;
      break;
  }

  final minuteRate = _div(hourlyRate, _fromInt(60));
  final msc = dailyRate * _fromInt(26);

  return DerivedRates(
    monthlyRate: _round3(monthlyRate),
    dailyRate: _round3(dailyRate),
    hourlyRate: _round3(hourlyRate),
    minuteRate: _round3(minuteRate),
    msc: _round3(msc),
  );
}

DerivedRates getDayRates(
  DerivedRates standardRates,
  int standardHoursPerDay,
  Decimal? overrideDailyRate,
) {
  if (overrideDailyRate == null) return standardRates;
  final hours = _fromInt(standardHoursPerDay);
  final dailyRate = _round3(overrideDailyRate);
  final hourlyRate = _round3(_div(dailyRate, hours));
  final minuteRate = _round3(_div(hourlyRate, _fromInt(60)));
  return DerivedRates(
    monthlyRate: standardRates.monthlyRate,
    dailyRate: dailyRate,
    hourlyRate: hourlyRate,
    minuteRate: minuteRate,
    msc: standardRates.msc,
  );
}

Decimal calculateBasicPay(
  PayProfileInput profile,
  DerivedRates rates,
  int workDays,
  PayFrequency payFrequency,
) {
  return _round3(rates.dailyRate * _fromInt(workDays));
}

Decimal calculateLateDeduction(int lateMinutes, DerivedRates rates) {
  if (lateMinutes <= 0) return _zero;
  return _round3(rates.minuteRate * _fromInt(lateMinutes));
}

Decimal calculateUndertimeDeduction(int undertimeMinutes, DerivedRates rates) {
  if (undertimeMinutes <= 0) return _zero;
  return _round3(rates.minuteRate * _fromInt(undertimeMinutes));
}

Decimal calculateAbsentDeduction(
  int absentMinutes,
  DerivedRates rates,
  int standardMinutesPerDay,
) {
  if (absentMinutes <= 0) return _zero;
  final absentDays = _div(_fromInt(absentMinutes), _fromInt(standardMinutesPerDay));
  return _round3(rates.dailyRate * absentDays);
}

Decimal calculateOvertimePay(int otMinutes, DerivedRates rates, Decimal multiplier) {
  if (otMinutes <= 0) return _zero;
  final otHours = _div(_fromInt(otMinutes), _fromInt(60));
  return _round3(rates.hourlyRate * otHours * multiplier);
}

Decimal calculateNightDiffPay(int ndMinutes, DerivedRates rates, [Decimal? ndMultiplier]) {
  if (ndMinutes <= 0) return _zero;
  final mult = ndMultiplier ?? Decimal.parse('0.10');
  final ndHours = _div(_fromInt(ndMinutes), _fromInt(60));
  return _round3(rates.hourlyRate * ndHours * mult);
}

Decimal calculateHolidayPremiumPay(
  int workedMinutes,
  DerivedRates rates,
  Decimal holidayMultiplier,
  int standardMinutesPerDay,
) {
  if (workedMinutes <= 0 || holidayMultiplier <= Decimal.one) return _zero;
  final premium = holidayMultiplier - Decimal.one;
  final workedHours = _div(_fromInt(workedMinutes), _fromInt(60));
  final regularPay = rates.hourlyRate * workedHours;
  return _round3(regularPay * premium);
}

Decimal calculateRestDayPremiumPay(
  int workedMinutes,
  DerivedRates rates, [
  Decimal? restDayMultiplier,
]) {
  final mult = restDayMultiplier ?? Decimal.parse('1.3');
  if (workedMinutes <= 0 || mult <= Decimal.one) return _zero;
  final premium = mult - Decimal.one;
  final workedHours = _div(_fromInt(workedMinutes), _fromInt(60));
  final regularPay = rates.hourlyRate * workedHours;
  return _round3(regularPay * premium);
}

Decimal calculateUnworkedRegularHolidayPay(DerivedRates rates) => rates.dailyRate;

/// Standard PH multipliers per DOLE.
class PhMultipliers {
  PhMultipliers._();
  static final Decimal OT_REGULAR = Decimal.parse('1.25');
  static final Decimal REST_DAY = Decimal.parse('1.3');
  static final Decimal REST_DAY_OT = Decimal.parse('1.69');
  static final Decimal REGULAR_HOLIDAY = Decimal.parse('2.0');
  static final Decimal REGULAR_HOLIDAY_OT = Decimal.parse('2.6');
  static final Decimal REGULAR_HOLIDAY_REST_DAY = Decimal.parse('2.6');
  static final Decimal REGULAR_HOLIDAY_REST_DAY_OT = Decimal.parse('3.38');
  static final Decimal SPECIAL_HOLIDAY = Decimal.parse('1.3');
  static final Decimal SPECIAL_HOLIDAY_OT = Decimal.parse('1.69');
  static final Decimal SPECIAL_HOLIDAY_REST_DAY = Decimal.parse('1.5');
  static final Decimal SPECIAL_HOLIDAY_REST_DAY_OT = Decimal.parse('1.95');
  static final Decimal NIGHT_DIFF = Decimal.parse('0.10');
  static final Decimal NIGHT_DIFF_OT = Decimal.parse('0.1375');
}
