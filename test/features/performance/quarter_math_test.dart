import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/performance/quarter_math.dart';

void main() {
  test('quarterOf returns 1-4 based on month', () {
    expect(quarterOf(DateTime.utc(2026, 1, 15)), 1);
    expect(quarterOf(DateTime.utc(2026, 3, 31)), 1);
    expect(quarterOf(DateTime.utc(2026, 4, 1)), 2);
    expect(quarterOf(DateTime.utc(2026, 6, 30)), 2);
    expect(quarterOf(DateTime.utc(2026, 7, 1)), 3);
    expect(quarterOf(DateTime.utc(2026, 9, 30)), 3);
    expect(quarterOf(DateTime.utc(2026, 10, 1)), 4);
    expect(quarterOf(DateTime.utc(2026, 12, 31)), 4);
  });

  test('quarterBoundsFor returns (start, end, due) dates', () {
    final b = quarterBoundsFor(year: 2026, quarter: 2);
    expect(b.start, DateTime.utc(2026, 4, 1));
    expect(b.end, DateTime.utc(2026, 6, 30));
    expect(b.due, DateTime.utc(2026, 7, 15));
  });

  test('quarterNameFor produces the canonical period name', () {
    expect(quarterNameFor(year: 2026, quarter: 2), '2026 Q2');
  });
}
