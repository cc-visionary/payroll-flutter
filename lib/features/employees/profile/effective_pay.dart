import 'package:decimal/decimal.dart';

import '../../../data/models/compensation_change.dart';
import '../../../data/models/role_rate_change.dart';
import '../../payroll/engine/effective_compensation.dart';
import '../../payroll/engine/role_rate.dart';

/// What an employee's Role tab should display as their pay, and where it came
/// from.
class DisplayPay {
  final Decimal? baseSalary;
  final String wageType;

  /// True when the figure came from the employee's own `compensation_changes`
  /// record rather than the role scorecard's default.
  final bool fromCompensationRecord;

  const DisplayPay({
    required this.baseSalary,
    required this.wageType,
    required this.fromCompensationRecord,
  });
}

/// Resolves the pay to show for ONE employee as of [asOf].
///
/// Mirrors how payroll resolves `baseRate` (see `compute_service.dart`): the
/// employee's effective `compensation_changes` record wins, and the role
/// scorecard is only the default for an employee who has never had one. That
/// is why two employees can share a scorecard yet be paid differently — and
/// why this tile must not read the scorecard directly.
///
/// The `new -> prev -> scorecard` fallback matches `proratedDailyRateOverride`
/// in `payroll/engine/daily_rate.dart`, so the displayed figure cannot diverge
/// from the figure payroll actually pays.
DisplayPay displayPayFor({
  required List<CompensationChange> changes,
  required DateTime asOf,
  required Decimal? scorecardBaseSalary,
  required String scorecardWageType,
  List<RoleRateChange> roleRates = const [],
}) {
  final eff = effectiveCompensation(changes, asOf);
  if (eff == null) {
    // Role default, resolved as of the day like payroll does — a future-dated
    // role rate change must not show before it takes effect.
    return DisplayPay(
      baseSalary: roleRateAsOf(roleRates, asOf, scorecardBaseSalary),
      wageType: scorecardWageType,
      fromCompensationRecord: false,
    );
  }
  return DisplayPay(
    baseSalary: eff.newBaseSalary ?? eff.prevBaseSalary ?? scorecardBaseSalary,
    wageType: eff.newWageType ?? eff.prevWageType ?? scorecardWageType,
    fromCompensationRecord: true,
  );
}
