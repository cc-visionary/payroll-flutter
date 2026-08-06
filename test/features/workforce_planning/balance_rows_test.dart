import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';
import 'package:payroll_flutter/features/workforce_planning/balance_rows.dart';
import 'package:payroll_flutter/features/workforce_planning/capacity_math.dart';

void main() {
  test('kpiCountByEmployee counts distinct kpis per employee', () {
    final byKpi = {
      'k1': const [
        KpiAssignee(employeeId: 'e1', name: 'A'),
        KpiAssignee(employeeId: 'e2', name: 'B'),
      ],
      'k2': const [KpiAssignee(employeeId: 'e1', name: 'A')],
    };
    expect(kpiCountByEmployee(byKpi), {'e1': 2, 'e2': 1});
  });

  test(
    'buildBalanceRows joins, computes scaled load, sorts desc, defaults missing',
    () {
      final loads = [
        const WpPersonLoad(
          employeeId: 'e1',
          companyId: 'c',
          tasksOwned: 2,
          hoursFixed: 2,
          hoursGrowingBase: 20,
          capacityHours: 160,
          growthMultiplier: 1,
        ),
        const WpPersonLoad(
          employeeId: 'e2',
          companyId: 'c',
          tasksOwned: 1,
          hoursFixed: 10,
          hoursGrowingBase: 0,
          capacityHours: 160,
          growthMultiplier: 1,
        ),
      ];
      final rows = buildBalanceRows(
        loads: loads,
        employeeById: {'e1': (name: 'Marvin', title: 'Sys')},
        kpiCounts: {'e1': 4},
        multiplier: 2,
      );
      expect(rows.first.employeeId, 'e1'); // higher load first
      expect(rows.first.hoursScaled, 42); // 2 + 20*2
      expect(rows.first.loadScaled, 42 / 160);
      expect(rows.first.status, LoadStatus.under); // 0.2625
      expect(rows.first.kpiCount, 4);
      final e2 = rows.firstWhere((r) => r.employeeId == 'e2');
      expect(e2.name, 'e2'); // no employee record → id fallback
      expect(e2.roleTitle, isNull);
      expect(e2.kpiCount, 0);
    },
  );

  test('buildBalanceRows breaks equal-load ties by name (stable order)', () {
    final loads = [
      const WpPersonLoad(
        employeeId: 'e2',
        companyId: 'c',
        tasksOwned: 1,
        hoursFixed: 80,
        hoursGrowingBase: 0,
        capacityHours: 160,
        growthMultiplier: 1,
      ),
      const WpPersonLoad(
        employeeId: 'e1',
        companyId: 'c',
        tasksOwned: 1,
        hoursFixed: 80,
        hoursGrowingBase: 0,
        capacityHours: 160,
        growthMultiplier: 1,
      ),
    ];
    final rows = buildBalanceRows(
      loads: loads,
      employeeById: {
        'e1': (name: 'Ann', title: null),
        'e2': (name: 'Zed', title: null),
      },
      kpiCounts: const {},
      multiplier: 1,
    );
    expect(rows.map((r) => r.name).toList(), [
      'Ann',
      'Zed',
    ]); // equal load → alphabetical
  });
}
