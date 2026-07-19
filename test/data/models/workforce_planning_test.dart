import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';

void main() {
  test('WpPersonLoad.fromRow parses aggregates', () {
    final p = WpPersonLoad.fromRow({
      'employee_id': 'e1', 'company_id': 'c1', 'tasks_owned': 2,
      'hours_fixed': 2.0, 'hours_growing_base': 20.0,
      'capacity_hours': 160.0, 'growth_multiplier': 2.0,
    });
    expect(p.tasksOwned, 2);
    expect(p.hoursGrowingBase, 20.0);
    expect(p.capacityHours, 160.0);
    expect(p.growthMultiplier, 2.0);
  });

  test('WpTask.toUpsert emits driver source with null manual', () {
    const t = WpTask(id: '', companyId: 'c1', name: 'flash',
      timesSource: 'driver', driverId: 'd1', driverFactor: 1,
      minutesSource: 'manual', minutesManual: 12);
    final m = t.toUpsert('c1');
    expect(m['times_source'], 'driver');
    expect(m['driver_id'], 'd1');
    expect(m['times_manual'], isNull);
    expect(m['minutes_manual'], 12);
  });

  test('WpTask.toUpsert normalizes empty skill_tier/risk to null', () {
    const t = WpTask(id: '', companyId: 'c1', name: 'x',
      skillTier: '', risk: '');
    final m = t.toUpsert('c1');
    expect(m['skill_tier'], isNull);
    expect(m['risk'], isNull);
    const t2 = WpTask(id: '', companyId: 'c1', name: 'x',
      skillTier: 'Managerial', risk: 'High');
    final m2 = t2.toUpsert('c1');
    expect(m2['skill_tier'], 'Managerial');
    expect(m2['risk'], 'High');
  });
}
