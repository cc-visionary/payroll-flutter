import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/payroll/runs/new/default_pay_period.dart';

void main() {
  group('defaultPayPeriod', () {
    final today = DateTime(2026, 7, 3);

    test('with a last release: unpaid window (release+1 .. yesterday), pay today', () {
      final p = defaultPayPeriod(today: today, lastReleasedEnd: DateTime(2026, 6, 30));
      expect(p.start, DateTime(2026, 7, 1)); // day after the last released period end
      expect(p.end, DateTime(2026, 7, 2)); // yesterday (last day with attendance)
      expect(p.payDate, DateTime(2026, 7, 3)); // today
    });

    test('missed a cycle: spans the full unpaid gap (no cap)', () {
      final p = defaultPayPeriod(today: today, lastReleasedEnd: DateTime(2026, 5, 20));
      expect(p.start, DateTime(2026, 5, 21));
      expect(p.end, DateTime(2026, 7, 2));
    });

    test('no last release: 15-day window ending yesterday, pay today', () {
      final p = defaultPayPeriod(today: today, lastReleasedEnd: null);
      expect(p.end, DateTime(2026, 7, 2)); // yesterday
      expect(p.start, DateTime(2026, 6, 18)); // yesterday - 14 => 15-day inclusive window
      expect(p.payDate, DateTime(2026, 7, 3));
    });

    test('already paid up (release end >= yesterday): falls back to 15-day window', () {
      final p = defaultPayPeriod(today: today, lastReleasedEnd: DateTime(2026, 7, 2));
      expect(p.end, DateTime(2026, 7, 2));
      expect(p.start, DateTime(2026, 6, 18)); // fallback, not 7/3 (start would be after end)
      expect(p.payDate, DateTime(2026, 7, 3));
    });

    test('normalizes a today with a time component to date-only', () {
      final p = defaultPayPeriod(
        today: DateTime(2026, 7, 3, 14, 30),
        lastReleasedEnd: DateTime(2026, 6, 30, 9),
      );
      expect(p.start, DateTime(2026, 7, 1));
      expect(p.end, DateTime(2026, 7, 2));
      expect(p.payDate, DateTime(2026, 7, 3));
    });
  });
}
