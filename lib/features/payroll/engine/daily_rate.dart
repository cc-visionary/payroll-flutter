import 'package:decimal/decimal.dart';

import '../../../data/models/compensation_change.dart';
import 'effective_compensation.dart';

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

/// The per-day `dailyRateOverride` implied by an employee's compensation
/// history, or `null` when the day belongs to the same compensation regime as
/// the period end (in which case the engine's period-level standard rate is
/// already correct).
///
/// Regimes are compared by change IDENTITY, not by rate value: two different
/// salaries can round to the same daily rate, and both sides get `_round3`-ed
/// downstream, so a value comparison would be fragile in both directions.
/// `dayEff == periodEndEff == null` (no compensation rows) yields `null`,
/// which is what preserves byte-identical payslips for untouched employees.
Decimal? proratedDailyRateOverride({
  required List<CompensationChange> comp,
  required DateTime attendanceDate,
  required DateTime periodEnd,
  required Decimal scorecardBaseSalary,
  required String scorecardWageType,
  required int workDaysPerMonth,
  required int hoursPerDay,
}) {
  final periodEndEff = effectiveCompensation(comp, periodEnd);
  final dayEff = effectiveCompensation(comp, attendanceDate);
  if (dayEff?.id == periodEndEff?.id) return null;

  if (dayEff == null) {
    // The day predates every change -> the pre-change (scorecard) rate.
    return dailyRateFrom(
      baseSalary: scorecardBaseSalary,
      wageType: scorecardWageType,
      workDaysPerMonth: workDaysPerMonth,
      hoursPerDay: hoursPerDay,
    );
  }
  // Fallback order: new -> prev -> scorecard. `newBaseSalary`/`newWageType`
  // are nullable (e.g. a role-only change that doesn't touch pay), and in
  // that case the salary/wage-type actually in force on this day is whatever
  // was captured as `prevBaseSalary`/`prevWageType` on the SAME row -- not
  // the original role-scorecard values, which would silently discard any
  // raise applied by an earlier change in the history.
  return dailyRateFrom(
    baseSalary: dayEff.newBaseSalary ?? dayEff.prevBaseSalary ?? scorecardBaseSalary,
    wageType: dayEff.newWageType ?? dayEff.prevWageType ?? scorecardWageType,
    workDaysPerMonth: workDaysPerMonth,
    hoursPerDay: hoursPerDay,
  );
}
