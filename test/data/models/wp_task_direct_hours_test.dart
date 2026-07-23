import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';

void main() {
  test('fromRow reads hours_per_month', () {
    final t = WpTask.fromRow({
      'id': 't1', 'company_id': 'c', 'name': 'Pack', 'hours_per_month': 65.8,
    });
    expect(t.hoursPerMonth, 65.8);
  });

  test('fromRow leaves hoursPerMonth null when absent', () {
    final t = WpTask.fromRow({'id': 't1', 'company_id': 'c', 'name': 'Pack'});
    expect(t.hoursPerMonth, isNull);
  });

  test('toUpsert writes hours_per_month and nulls the driver path when direct', () {
    const t = WpTask(
      id: 't1', companyId: 'c', name: 'Pack', hoursPerMonth: 65.8,
      timesSource: 'driver', driverId: 'd1', minutesSource: 'rate', rateId: 'r1',
    );
    final u = t.toUpsert('c');
    expect(u['hours_per_month'], 65.8);
    expect(u['times_manual'], isNull);
    expect(u['driver_id'], isNull);
    expect(u['minutes_manual'], isNull);
    expect(u['rate_id'], isNull);
    expect(u['times_source'], 'manual');
    expect(u['minutes_source'], 'manual');
  });

  test('toUpsert keeps the driver path when there is no direct figure', () {
    const t = WpTask(
      id: 't1', companyId: 'c', name: 'Pack',
      timesSource: 'driver', driverId: 'd1', minutesSource: 'manual', minutesManual: 30,
    );
    final u = t.toUpsert('c');
    expect(u['hours_per_month'], isNull);
    expect(u['driver_id'], 'd1');
    expect(u['minutes_manual'], 30);
  });

  test('copyWithSort carries hoursPerMonth', () {
    const t = WpTask(id: 't1', companyId: 'c', name: 'Pack', hoursPerMonth: 10);
    expect(t.copyWithSort(areaSort: 1, taskSort: 2).hoursPerMonth, 10);
  });
}
