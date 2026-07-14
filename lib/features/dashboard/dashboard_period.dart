import 'package:flutter_riverpod/legacy.dart';
import 'package:intl/intl.dart';

enum DashboardPeriodMode { month, year }

/// The dashboard's selected reporting window. Month is the default — HR
/// reads this screen against the current payroll month far more often than
/// against a whole year. Year mode aggregates all 12 months.
///
/// [month] is always carried (1..12) even in year mode, so toggling back to
/// month mode returns you to the month you were last looking at.
class DashboardPeriod {
  final DashboardPeriodMode mode;
  final int year;
  final int month;

  const DashboardPeriod({
    required this.mode,
    required this.year,
    required this.month,
  });

  factory DashboardPeriod.now(DateTime today) => DashboardPeriod(
        mode: DashboardPeriodMode.month,
        year: today.year,
        month: today.month,
      );

  bool get isYear => mode == DashboardPeriodMode.year;

  DateTime get start =>
      isYear ? DateTime(year, 1, 1) : DateTime(year, month, 1);

  /// Inclusive last day of the period, clamped to [today] when the period is
  /// still in progress. Clamping matters: an unclamped end would count the
  /// rest of the month as scheduled-but-absent work days.
  DateTime endOn(DateTime today) {
    // Day 0 of the following month == last day of this one.
    final natural =
        isYear ? DateTime(year, 12, 31) : DateTime(year, month + 1, 0);
    final t = DateTime(today.year, today.month, today.day);
    return natural.isAfter(t) ? t : natural;
  }

  String get label => isYear
      ? '$year'
      : DateFormat('MMMM yyyy').format(DateTime(year, month, 1));

  DashboardPeriod copyWith({
    DashboardPeriodMode? mode,
    int? year,
    int? month,
  }) =>
      DashboardPeriod(
        mode: mode ?? this.mode,
        year: year ?? this.year,
        month: month ?? this.month,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DashboardPeriod &&
          other.mode == mode &&
          other.year == year &&
          other.month == month);

  @override
  int get hashCode => Object.hash(mode, year, month);
}

/// Drives every figure on the Dashboard. Defaults to the current month.
final dashboardPeriodProvider =
    StateProvider<DashboardPeriod>((ref) => DashboardPeriod.now(DateTime.now()));
