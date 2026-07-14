import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/dashboard/dashboard_period.dart';

void main() {
  group('DashboardPeriod', () {
    test('month mode spans the calendar month', () {
      const p = DashboardPeriod(
          mode: DashboardPeriodMode.month, year: 2026, month: 2);
      expect(p.start, DateTime(2026, 2, 1));
      // 2026 is not a leap year — February ends on the 28th.
      expect(p.endOn(DateTime(2026, 7, 14)), DateTime(2026, 2, 28));
    });

    test('year mode spans the calendar year', () {
      const p = DashboardPeriod(
          mode: DashboardPeriodMode.year, year: 2025, month: 1);
      expect(p.start, DateTime(2025, 1, 1));
      expect(p.endOn(DateTime(2026, 7, 14)), DateTime(2025, 12, 31));
    });

    test('an in-progress month clamps its end to today', () {
      const p = DashboardPeriod(
          mode: DashboardPeriodMode.month, year: 2026, month: 7);
      expect(p.endOn(DateTime(2026, 7, 14)), DateTime(2026, 7, 14));
    });

    test('an in-progress year clamps its end to today', () {
      const p = DashboardPeriod(
          mode: DashboardPeriodMode.year, year: 2026, month: 1);
      expect(p.endOn(DateTime(2026, 7, 14)), DateTime(2026, 7, 14));
    });

    test('a fully past month does not clamp', () {
      const p = DashboardPeriod(
          mode: DashboardPeriodMode.month, year: 2026, month: 6);
      expect(p.endOn(DateTime(2026, 7, 14)), DateTime(2026, 6, 30));
    });

    test('label reflects the mode', () {
      const m = DashboardPeriod(
          mode: DashboardPeriodMode.month, year: 2026, month: 7);
      const y = DashboardPeriod(
          mode: DashboardPeriodMode.year, year: 2026, month: 7);
      expect(m.label, 'July 2026');
      expect(y.label, '2026');
    });

    test('DashboardPeriod.now defaults to month mode on today', () {
      final p = DashboardPeriod.now(DateTime(2026, 7, 14));
      expect(p.mode, DashboardPeriodMode.month);
      expect(p.year, 2026);
      expect(p.month, 7);
    });

    test('value equality holds so Riverpod does not spuriously rebuild', () {
      const a = DashboardPeriod(
          mode: DashboardPeriodMode.month, year: 2026, month: 7);
      const b = DashboardPeriod(
          mode: DashboardPeriodMode.month, year: 2026, month: 7);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.copyWith(month: 8), isNot(a));
    });
  });
}
