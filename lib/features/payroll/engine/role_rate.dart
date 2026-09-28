import 'package:decimal/decimal.dart';

import '../../../data/models/role_rate_change.dart';

/// A role's default base rate in force on [asOf].
///
/// The newest change effective on or before [asOf] wins (same-day ties go to
/// the newest `createdAt`, then `id` — the same tie-break as
/// `effectiveCompensation`). A day before every change is paid the EARLIEST
/// change's `prevBaseSalary`: `role_scorecards.base_salary` already holds the
/// new rate once a change is saved, so trusting [storedBaseSalary] there
/// would pay pre-change days at the new rate.
///
/// [storedBaseSalary] (`role_scorecards.base_salary`) is returned when there
/// is no history, or when the earliest change captured no previous rate.
Decimal? roleRateAsOf(
  List<RoleRateChange> history,
  DateTime asOf,
  Decimal? storedBaseSalary,
) {
  RoleRateChange? latest;
  RoleRateChange? earliest;
  for (final c in history) {
    if (!c.effectiveDate.isAfter(asOf) &&
        (latest == null || _newer(c, latest))) {
      latest = c;
    }
    if (earliest == null || _newer(earliest, c)) earliest = c;
  }
  if (latest != null) return latest.newBaseSalary;
  return earliest?.prevBaseSalary ?? storedBaseSalary;
}

bool _newer(RoleRateChange a, RoleRateChange b) {
  final byDate = a.effectiveDate.compareTo(b.effectiveDate);
  if (byDate != 0) return byDate > 0;
  final byCreated = a.createdAt.compareTo(b.createdAt);
  if (byCreated != 0) return byCreated > 0;
  return a.id.compareTo(b.id) > 0;
}
