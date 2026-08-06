import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/unassigned_workspace.dart';

// NOTE: brief's helper omitted Employee's required fields (employeeNumber,
// employmentType, hireDate, isRankAndFile, isOtEligible, isNdEligible,
// isHolidayPayEligible, taxOnFullEarnings), which fails to compile. Filled
// in with the same neutral defaults rebalance_test.dart uses; intent
// (id/card/status only vary per-case) is unchanged.
Employee _e(String id, {String? card, String status = 'ACTIVE'}) => Employee(
  id: id,
  companyId: 'c',
  employeeNumber: id,
  firstName: id,
  lastName: 'x',
  employmentType: 'FULL_TIME',
  employmentStatus: status,
  roleScorecardId: card,
  hireDate: DateTime(2024, 1, 1),
  isRankAndFile: true,
  isOtEligible: false,
  isNdEligible: false,
  isHolidayPayEligible: false,
  taxOnFullEarnings: false,
);

WpTask _t(
  String id,
  String name, {
  String? card,
  String? owner,
  String? ext,
  String status = 'ACTIVE',
}) => WpTask(
  id: id,
  companyId: 'c',
  name: name,
  roleScorecardId: card,
  ownerEmployeeId: owner,
  externalRef: ext,
  status: status,
);

WpTaskComputed _c(String id, double hours) =>
    WpTaskComputed(taskId: id, companyId: 'c', hoursPerMonthBase: hours);

void main() {
  test('an owned task and a staffed-card task are NOT unassigned', () {
    final res = buildUnassignedWorkspace(
      tasks: [
        _t('owned', 'Owned work', owner: 'e1'),
        _t('staffed', 'Staffed work', card: 'rs1'),
      ],
      employees: [
        _e('e1'),
        _e('e2', card: 'rs1'),
      ],
      computedByTaskId: {},
      multiplier: 1,
    );
    expect(res, isEmpty);
  });

  test('a legacy capacity-model row is excluded', () {
    final res = buildUnassignedWorkspace(
      tasks: [_t('leg', 'Legacy row', ext: 'T9')],
      employees: const [],
      computedByTaskId: {},
      multiplier: 1,
    );
    expect(res, isEmpty);
  });

  test('an archived orphan is excluded', () {
    final res = buildUnassignedWorkspace(
      tasks: [_t('a', 'Old packing', status: 'ARCHIVED')],
      employees: const [],
      computedByTaskId: {},
      multiplier: 1,
    );
    expect(res, isEmpty);
  });

  test(
    'orphans cluster by name similarity, heaviest cluster first, with hours',
    () {
      final res = buildUnassignedWorkspace(
        tasks: [
          _t('p1', 'Pack orders'), // no card, no owner -> orphan
          _t('p2', 'Pack the orders'),
          _t(
            'f1',
            'Reconcile bank statements',
            card: 'empty',
          ), // card w/ no holders -> orphan
        ],
        employees: const [], // 'empty' card has zero active holders
        computedByTaskId: {
          'p1': _c('p1', 10),
          'p2': _c('p2', 5),
          'f1': _c('f1', 20),
        },
        multiplier: 1,
      );
      expect(res.length, 2);
      // finance cluster (20h) outranks packing cluster (15h)
      expect(res.first.totalHours, 20);
      expect(res.first.count, 1);
      final packing = res[1];
      expect(packing.count, 2);
      expect(packing.totalHours, 15);
      expect(packing.items.first.hours, 10); // heaviest item first
    },
  );
}
