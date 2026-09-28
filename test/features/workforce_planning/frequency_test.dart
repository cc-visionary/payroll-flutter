import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/frequency.dart';

WpTask t({String? cadence, String timesSource = 'manual', double? times, double? minutes, double? hours, String? driverId}) =>
    WpTask(id: 'x', companyId: 'c', name: 'x', cadence: cadence, timesSource: timesSource,
        timesManual: times, minutesManual: minutes, hoursPerMonth: hours, driverId: driverId);

void main() {
  test('preset times per month', () {
    expect(TaskFrequency.daily.timesPerMonth, 26);
    expect(TaskFrequency.weekly.timesPerMonth, closeTo(52 / 12, 1e-9));
    expect(TaskFrequency.monthly.timesPerMonth, 1);
    expect(TaskFrequency.quarterly.timesPerMonth, closeTo(1 / 3, 1e-9));
    expect(TaskFrequency.perOrder.timesPerMonth, isNull);
    expect(TaskFrequency.custom.timesPerMonth, isNull);
  });

  test('tokens round-trip', () {
    for (final f in TaskFrequency.values.where((f) => f != TaskFrequency.custom)) {
      expect(frequencyOf(t(cadence: f.token, times: 1, minutes: 1)), f);
    }
  });

  test('legacy rows open on the right preset', () {
    expect(frequencyOf(t(hours: 12)), TaskFrequency.custom, reason: 'direct hours');
    expect(frequencyOf(t(timesSource: 'driver', driverId: 'd', minutes: 3)), TaskFrequency.perOrder);
    expect(frequencyOf(t(cadence: 'every other day', times: 13, minutes: 30)), TaskFrequency.custom,
        reason: 'free-text cadence with manual times -> custom h/mo');
    expect(frequencyOf(t()), TaskFrequency.weekly, reason: 'blank task defaults to weekly');
  });

  test('custom prefill preserves a legacy manual task\'s hours exactly', () {
    final legacy = t(cadence: 'every other day', times: 13, minutes: 30);
    expect(customHoursOf(legacy), closeTo(6.5, 1e-9));
    expect(customHoursOf(t(hours: 12)), 12);
  });

  test('custom prefill for manual times + RATE-sourced minutes uses the rate', () {
    const rated = WpTask(id: 'x', companyId: 'c', name: 'x', cadence: 'twice a week',
        timesManual: 8, minutesSource: 'rate', rateId: 'r1');
    expect(frequencyOf(rated), TaskFrequency.custom);
    expect(customHoursOf(rated), isNull, reason: 'no rate minutes given');
    expect(customHoursOf(rated, rateMinutes: 45), closeTo(6, 1e-9), reason: '8 x 45 / 60');
    // A manual-minutes task ignores rateMinutes.
    expect(customHoursOf(t(cadence: 'x', times: 13, minutes: 30), rateMinutes: 99), closeTo(6.5, 1e-9));
  });

  test('preview hours per month', () {
    expect(previewHoursPerMonth(frequency: TaskFrequency.daily, minutes: 60), 26);
    expect(previewHoursPerMonth(frequency: TaskFrequency.weekly, minutes: 180), closeTo(13, 1e-9));
    expect(previewHoursPerMonth(frequency: TaskFrequency.perOrder, minutes: 3, driverVolume: 1200, driverFactor: 1), 60);
    expect(previewHoursPerMonth(frequency: TaskFrequency.custom, customHours: 7.5), 7.5);
    expect(previewHoursPerMonth(frequency: TaskFrequency.daily), 0, reason: 'no minutes yet');
  });

  test('effort label reads like a human would say it', () {
    expect(effortLabel(t(cadence: 'DAILY', times: 26, minutes: 60), 26), 'Daily · 60 min');
    expect(effortLabel(t(hours: 7.5), 7.5), '7.5 h/mo');
    expect(effortLabel(t(), 0), 'Weekly');
  });
}
