import 'package:decimal/decimal.dart';

Decimal _div(Decimal a, Decimal b) =>
    (a / b).toDecimal(scaleOnInfinitePrecision: 10);

/// Daily rate implied by a compensation snapshot.
///
/// Mirrors the wage-type switch in `wage_calculator.dart` so the two cannot
/// disagree. Returns an UNROUNDED value — `getDayRates` applies `_round3`
/// when it consumes this as a per-day override.
Decimal dailyRateFrom({
  required Decimal baseSalary,
  required String wageType,
  required int workDaysPerMonth,
  required int hoursPerDay,
}) {
  switch (wageType) {
    case 'DAILY':
      return baseSalary;
    case 'HOURLY':
      return baseSalary * Decimal.fromInt(hoursPerDay);
    case 'MONTHLY':
    default:
      return _div(baseSalary, Decimal.fromInt(workDaysPerMonth));
  }
}
