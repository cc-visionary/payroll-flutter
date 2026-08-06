import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/templates/penalty_schedule_dates.dart';

void main() {
  test('starts at the 15th when the effective date is early in the month', () {
    final dates = projectedCutoffDates(from: DateTime(2026, 8, 5), count: 4);
    expect(dates, [
      DateTime(2026, 8, 15),
      DateTime(2026, 8, 31),
      DateTime(2026, 9, 15),
      DateTime(2026, 9, 30),
    ]);
  });

  test('includes the 15th itself when the penalty is effective that day', () {
    final dates = projectedCutoffDates(from: DateTime(2026, 8, 15), count: 2);
    expect(dates, [DateTime(2026, 8, 15), DateTime(2026, 8, 31)]);
  });

  test('skips to month-end when effective after the 15th', () {
    final dates = projectedCutoffDates(from: DateTime(2026, 8, 20), count: 2);
    expect(dates, [DateTime(2026, 8, 31), DateTime(2026, 9, 15)]);
  });

  test('rolls into the next year', () {
    final dates = projectedCutoffDates(from: DateTime(2026, 12, 20), count: 3);
    expect(dates, [
      DateTime(2026, 12, 31),
      DateTime(2027, 1, 15),
      DateTime(2027, 1, 31),
    ]);
  });

  test('uses the real month length, February and leap years included', () {
    expect(projectedCutoffDates(from: DateTime(2026, 2, 16), count: 1), [
      DateTime(2026, 2, 28),
    ]);
    expect(projectedCutoffDates(from: DateTime(2028, 2, 16), count: 1), [
      DateTime(2028, 2, 29),
    ]);
  });

  test('returns nothing for a non-positive count', () {
    expect(projectedCutoffDates(from: DateTime(2026, 8, 5), count: 0), isEmpty);
    expect(
      projectedCutoffDates(from: DateTime(2026, 8, 5), count: -1),
      isEmpty,
    );
  });

  test('produces exactly the requested number of cut-offs', () {
    expect(
      projectedCutoffDates(from: DateTime(2026, 8, 5), count: 25).length,
      25,
    );
  });
}
