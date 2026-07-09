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

/// Resolves an attendance day's `dailyRateOverride`.
///
/// A manual per-day override (`attendance_day_records.daily_rate_override`)
/// ALWAYS beats the compensation-derived rate — it is an explicit human edit.
/// An unparseable manual value is treated as absent.
Decimal? resolveDailyRateOverride({
  required Object? manualRaw,
  required Decimal? compensationDerived,
}) {
  if (manualRaw != null) {
    final parsed = Decimal.tryParse(manualRaw.toString());
    if (parsed != null) return parsed;
  }
  return compensationDerived;
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
    // The day predates every change. The pre-change baseline is NOT the joined
    // role scorecard: `applyDue` repoints `employees.role_scorecard_id` to the
    // NEW scorecard whenever a change moves the role, and it runs BEFORE the
    // employees select, so `scorecardBaseSalary`/`scorecardWageType` may already
    // read the POST-change values (e.g. a promotion's new 45000). Trusting them
    // would pay the pre-change days at the new rate -- the exact overpayment
    // this feature exists to eliminate.
    //
    // Instead, take the pre-change compensation captured on the EARLIEST
    // qualifying change (`prevBaseSalary`/`prevWageType`), which is immune to
    // scorecard repointing. `dayEff == null` here is only reachable when
    // `periodEndEff != null` (the identity check above already returned for the
    // both-null case), so a qualifying change always exists -- but fall back to
    // the scorecard defensively if none is found.
    final earliest = _earliestQualifyingChange(comp);
    return dailyRateFrom(
      baseSalary:
          earliest?.prevBaseSalary ?? scorecardBaseSalary,
      wageType: earliest?.prevWageType ?? scorecardWageType,
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

/// The earliest qualifying compensation change, or `null` when none qualify.
///
/// "Qualifying" mirrors [effectiveCompensation]'s filter exactly: status
/// SCHEDULED or APPLIED and not soft-deleted. "Earliest" is the smallest
/// `effectiveDate`; ties break on oldest `createdAt`, then smallest `id` --
/// the inverse of the resolver's newest-wins tie-break.
CompensationChange? _earliestQualifyingChange(List<CompensationChange> comp) {
  CompensationChange? best;
  for (final c in comp) {
    if (c.deletedAt != null) continue;
    if (c.status != 'SCHEDULED' && c.status != 'APPLIED') continue;
    if (best == null || _precedes(c, best)) best = c;
  }
  return best;
}

bool _precedes(CompensationChange a, CompensationChange b) {
  final byDate = a.effectiveDate.compareTo(b.effectiveDate);
  if (byDate != 0) return byDate < 0;
  final byCreated = a.createdAt.compareTo(b.createdAt);
  if (byCreated != 0) return byCreated < 0;
  return a.id.compareTo(b.id) < 0;
}
