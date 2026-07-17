import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';

void main() {
  test('KPI uses name, measurement, target, and check frequency', () {
    final kpi = KpiItem.fromJson({
      'name': 'Packing accuracy',
      'measurement': 'Correctly packed orders divided by total orders',
      'target': 'At least 98%',
      'frequency': 'Weekly',
    });

    expect(kpi.name, 'Packing accuracy');
    expect(kpi.metric, 'Packing accuracy');
    expect(kpi.measurement, 'Correctly packed orders divided by total orders');
    expect(kpi.target, 'At least 98%');
    expect(kpi.frequency, 'Weekly');
    expect(kpi.toJson(), {
      'name': 'Packing accuracy',
      'measurement': 'Correctly packed orders divided by total orders',
      'target': 'At least 98%',
      'frequency': 'Weekly',
    });
  });

  test('legacy metric data remains readable', () {
    final kpi = KpiItem.fromJson({
      'metric': 'Sales conversion',
      'frequency': 'Monthly',
    });

    expect(kpi.name, 'Sales conversion');
    expect(kpi.measurement, isEmpty);
    expect(kpi.target, isEmpty);
  });
}
