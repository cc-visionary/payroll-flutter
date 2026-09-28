import '../../data/models/workforce_planning.dart';

/// Working days in a month — the same 26 the payroll engine uses.
const double kWorkingDaysPerMonth = 26;

/// How often a task happens. Stored as a token in `wp_tasks.cadence` so the
/// form reopens on the same preset; the times/month it implies is written to
/// `times_manual` (or, for [perOrder], read from a driver).
enum TaskFrequency { daily, weekly, monthly, quarterly, perOrder, custom }

extension TaskFrequencyX on TaskFrequency {
  String get token => switch (this) {
    TaskFrequency.daily => 'DAILY',
    TaskFrequency.weekly => 'WEEKLY',
    TaskFrequency.monthly => 'MONTHLY',
    TaskFrequency.quarterly => 'QUARTERLY',
    TaskFrequency.perOrder => 'PER_ORDER',
    TaskFrequency.custom => 'CUSTOM',
  };

  String get label => switch (this) {
    TaskFrequency.daily => 'Daily',
    TaskFrequency.weekly => 'Weekly',
    TaskFrequency.monthly => 'Monthly',
    TaskFrequency.quarterly => 'Quarterly',
    TaskFrequency.perOrder => 'Per order',
    TaskFrequency.custom => 'Custom (hours / month)',
  };

  double? get timesPerMonth => switch (this) {
    TaskFrequency.daily => kWorkingDaysPerMonth,
    TaskFrequency.weekly => 52 / 12,
    TaskFrequency.monthly => 1,
    TaskFrequency.quarterly => 1 / 3,
    TaskFrequency.perOrder => null,
    TaskFrequency.custom => null,
  };
}

TaskFrequency frequencyOf(WpTask t) {
  if (t.hoursPerMonth != null) return TaskFrequency.custom;
  for (final f in TaskFrequency.values) {
    if (f != TaskFrequency.custom && f.token == t.cadence) return f;
  }
  if (t.timesSource == 'driver') return TaskFrequency.perOrder;
  if (t.timesManual != null || t.minutesManual != null) {
    return TaskFrequency.custom;
  }
  return TaskFrequency.weekly;
}

double? minutesOf(WpTask t) => t.minutesManual;

/// The h/mo to show when a task opens as [TaskFrequency.custom]: its direct
/// hours, or its legacy manual times x minutes, so Save-without-edits keeps
/// the same workload.
double? customHoursOf(WpTask t) {
  if (t.hoursPerMonth != null) return t.hoursPerMonth;
  final times = t.timesManual, minutes = t.minutesManual;
  if (times == null || minutes == null) return null;
  return times * minutes / 60;
}

double previewHoursPerMonth({
  required TaskFrequency frequency,
  double? minutes,
  double? customHours,
  double driverVolume = 0,
  double driverFactor = 1,
}) {
  if (frequency == TaskFrequency.custom) return customHours ?? 0;
  final m = minutes ?? 0;
  final times = frequency == TaskFrequency.perOrder
      ? driverVolume * driverFactor
      : frequency.timesPerMonth!;
  return times * m / 60;
}

/// How a task's effort reads on the board and in lists.
String effortLabel(WpTask t, double hours) {
  final f = frequencyOf(t);
  if (f == TaskFrequency.custom) return '${hours.toStringAsFixed(1)} h/mo';
  final m = t.minutesManual;
  return m == null ? f.label : '${f.label} · ${m.toStringAsFixed(0)} min';
}
