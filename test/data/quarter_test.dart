import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/quarter.dart';

void main() {
  group('quarterOf', () {
    test('maps months to calendar quarters', () {
      expect(quarterOf(DateTime.utc(2026, 1, 15)).quarter, 1);
      expect(quarterOf(DateTime.utc(2026, 3, 31)).quarter, 1);
      expect(quarterOf(DateTime.utc(2026, 4, 1)).quarter, 2);
      expect(quarterOf(DateTime.utc(2026, 6, 5)).quarter, 2);
      expect(quarterOf(DateTime.utc(2026, 9, 30)).quarter, 3);
      expect(quarterOf(DateTime.utc(2026, 10, 1)).quarter, 4);
      expect(quarterOf(DateTime.utc(2026, 12, 31)).quarter, 4);
    });

    test('carries the year', () {
      expect(quarterOf(DateTime.utc(2025, 11, 2)).year, 2025);
    });
  });

  group('quarterPeriodName', () {
    test('formats as "<year> Q<n>" (matches existing auto-gen naming)', () {
      expect(const Quarter(2026, 2).periodName, '2026 Q2');
      expect(quarterPeriodName(2025, 4), '2025 Q4');
    });
  });

  group('quarterWindow', () {
    test('Q1 2026 spans Jan 1 → Mar 31, due Apr 15', () {
      final w = quarterWindow(2026, 1);
      expect(w.start, DateTime.utc(2026, 1, 1));
      expect(w.end, DateTime.utc(2026, 3, 31));
      expect(w.due, DateTime.utc(2026, 4, 15));
    });

    test('Q4 rolls the end into Dec 31 and due into next January', () {
      final w = quarterWindow(2026, 4);
      expect(w.start, DateTime.utc(2026, 10, 1));
      expect(w.end, DateTime.utc(2026, 12, 31));
      expect(w.due, DateTime.utc(2027, 1, 15));
    });
  });

  group('addQuarters', () {
    test('advances and wraps across year boundaries', () {
      expect(const Quarter(2026, 4).add(1), const Quarter(2027, 1));
      expect(const Quarter(2026, 1).add(-1), const Quarter(2025, 4));
      expect(const Quarter(2026, 2).add(-3), const Quarter(2025, 3));
    });
  });

  group('quarterOptions', () {
    test('returns next + current + last four, newest first, no duplicates', () {
      final opts = quarterOptions(DateTime.utc(2026, 6, 5)); // 2026 Q2
      expect(opts, const [
        Quarter(2026, 3), // next
        Quarter(2026, 2), // current
        Quarter(2026, 1),
        Quarter(2025, 4),
        Quarter(2025, 3),
        Quarter(2025, 2),
      ]);
    });

    test('current quarter is identifiable in the list', () {
      final now = DateTime.utc(2026, 6, 5);
      expect(quarterOptions(now).contains(quarterOf(now)), isTrue);
    });
  });
}
