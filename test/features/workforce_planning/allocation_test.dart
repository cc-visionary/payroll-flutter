import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/workforce_planning/allocation.dart';

void main() {
  test('allocationTotal sums', () {
    expect(allocationTotal([60, 40]), 100);
    expect(allocationTotal(const <double>[]), 0);
  });

  test('splitEqually always totals exactly 100', () {
    for (final n in [1, 2, 3, 4, 6, 7]) {
      final s = splitEqually(n);
      expect(s.length, n);
      expect(allocationTotal(s), closeTo(100, 1e-9), reason: 'n=$n must total 100');
    }
    expect(splitEqually(2), [50, 50]);
    expect(splitEqually(4), [25, 25, 25, 25]);
  });

  test('splitEqually(3) is 33.3/33.3/33.4 — the last absorbs the remainder', () {
    final s = splitEqually(3);
    expect(s[0], 33.3);
    expect(s[1], 33.3);
    expect(s[2], 33.4);
  });

  test('ownerMajority gives the primary 60 and splits 40 across the rest', () {
    expect(ownerMajority(2), [60, 40]);
    final three = ownerMajority(3);
    expect(three[0], 60);
    expect(allocationTotal(three), closeTo(100, 1e-9));
    expect(ownerMajority(1), [100], reason: 'a sole assignee takes everything');
  });

  test('ownerMajority honors a non-zero primaryIndex', () {
    final s = ownerMajority(3, primaryIndex: 1);
    expect(s[1], 60);
    expect(allocationTotal(s), closeTo(100, 1e-9));
  });

  test('clearAllocations zeroes every row', () {
    expect(clearAllocations(3), [0, 0, 0]);
  });
}
