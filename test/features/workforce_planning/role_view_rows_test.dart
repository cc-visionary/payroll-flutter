import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/role_view_rows.dart';

void main() {
  final tasks = [
    const WpTask(id: 't1', companyId: 'c', name: 'SD flash', nodeId: 'n2',
        cadence: 'Per-unit', skillTier: 'Transactional', risk: 'Medium'),
    const WpTask(id: 't2', companyId: 'c', name: 'Vet', nodeId: 'n0',
        cadence: 'Monthly', skillTier: 'Strategic', risk: 'High'),
  ];
  final computed = {
    't1': const WpTaskComputed(taskId: 't1', companyId: 'c', isGrowing: true,
        timesPerMonthBase: 100, minutesEach: 12, hoursPerMonthBase: 20),
    't2': const WpTaskComputed(taskId: 't2', companyId: 'c', isGrowing: false,
        timesPerMonthBase: 4, minutesEach: 30, hoursPerMonthBase: 2),
  };

  test('buildRoleTaskRows scales only growing tasks and names nodes', () {
    final rows = buildRoleTaskRows(
      ownerTasks: tasks, computedById: computed,
      nodeNameById: {'n2': '2. Configure', 'n0': '0. Opportunity gate'},
      multiplier: 2,
    );
    final flash = rows.firstWhere((r) => r.name == 'SD flash');
    expect(flash.nodeName, '2. Configure');
    expect(flash.hoursScaled, 40); // growing: 20 * 2
    final vet = rows.firstWhere((r) => r.name == 'Vet');
    expect(vet.hoursScaled, 2);    // fixed
  });

  test('hoursByTier sums by tier', () {
    final rows = buildRoleTaskRows(
      ownerTasks: tasks, computedById: computed, nodeNameById: const {}, multiplier: 1);
    final byTier = hoursByTier(rows);
    expect(byTier['Transactional'], 20);
    expect(byTier['Strategic'], 2);
  });
}
