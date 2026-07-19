import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/workforce_planning/capacity_math.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';

void main() {
  test('projectedHours scales only the growing component', () {
    expect(projectedHours(2, 20, 1), 22);
    expect(projectedHours(2, 20, 2), 42);
    expect(projectedHours(2, 20, 0.5), 12);
  });

  test('loadFraction guards zero capacity', () {
    expect(loadFraction(80, 160), 0.5);
    expect(loadFraction(80, 0), 0);
  });

  test('personLoad uses stored multiplier by default, override when given', () {
    const p = WpPersonLoad(employeeId: 'e', companyId: 'c',
      hoursFixed: 2, hoursGrowingBase: 20, capacityHours: 160, growthMultiplier: 2);
    expect(personLoad(p), (2 + 20 * 2) / 160);
    expect(personLoad(p, multiplier: 1), (2 + 20) / 160);
  });

  test('loadStatus boundaries: 0.79 under, 0.80 ok, 1.00 ok, 1.01 over', () {
    expect(loadStatus(0.79), LoadStatus.under);
    expect(loadStatus(0.80), LoadStatus.ok);
    expect(loadStatus(1.00), LoadStatus.ok);
    expect(loadStatus(1.01), LoadStatus.over);
  });
}
