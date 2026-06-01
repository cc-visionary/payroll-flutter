import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/performance/quarter_math.dart';

void main() {
  test('addMonths handles common cases', () {
    expect(addMonths(DateTime.utc(2026, 1, 1), 1), DateTime.utc(2026, 2, 1));
    expect(addMonths(DateTime.utc(2026, 1, 1), 3), DateTime.utc(2026, 4, 1));
    expect(addMonths(DateTime.utc(2026, 1, 1), 5), DateTime.utc(2026, 6, 1));
  });

  test('addMonths clamps day for end-of-month dates', () {
    expect(addMonths(DateTime.utc(2026, 1, 31), 1), DateTime.utc(2026, 2, 28));
    expect(addMonths(DateTime.utc(2024, 1, 31), 1), DateTime.utc(2024, 2, 29));
  });

  test('addMonths handles year rollover', () {
    expect(addMonths(DateTime.utc(2026, 11, 15), 3), DateTime.utc(2027, 2, 15));
  });
}
