import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/features/workforce_planning/seat_tree.dart';

RoleScorecard seat(String id, String title) => RoleScorecard(
  id: id,
  companyId: 'c',
  jobTitle: title,
  missionStatement: '',
  responsibilities: const [],
  kpis: const [],
  baseSalary: null,
  wageType: 'DAILY',
  workHoursPerDay: 8,
  workDaysPerWeek: 'MON_FRI',
  isActive: true,
  effectiveDate: DateTime(2026, 1, 1),
);

Employee emp(
  String id,
  String name,
  String? cardId, {
  String status = 'ACTIVE',
  bool deleted = false,
}) => Employee(
  id: id,
  companyId: 'c',
  employeeNumber: id,
  firstName: name,
  lastName: 'X',
  roleScorecardId: cardId,
  employmentType: 'FULL_TIME',
  employmentStatus: status,
  hireDate: DateTime(2024, 1, 1),
  isRankAndFile: true,
  isOtEligible: false,
  isNdEligible: false,
  isHolidayPayEligible: false,
  sssEligibilityOverride: false,
  philhealthEligibilityOverride: false,
  pagibigEligibilityOverride: false,
  taxOnFullEarnings: false,
  deletedAt: deleted ? DateTime(2026, 1, 1) : null,
);

void main() {
  group('seatBoxes', () {
    test('one box per active holder', () {
      final boxes = seatBoxes(
        seats: [seat('s1', 'Brand Handling')],
        employees: [emp('e1', 'Christian', 's1'), emp('e2', 'Evander', 's1')],
        areasBySeat: const {
          's1': ['Packing', 'Customer service'],
        },
      );
      expect(boxes, hasLength(2));
      expect(boxes.map((b) => b.holderName), ['Christian', 'Evander']);
      expect(boxes.every((b) => b.function == 'Brand Handling'), isTrue);
      expect(boxes.first.roles, ['Packing', 'Customer service']);
    });

    test('a seat with no holder yields ONE open box, not zero', () {
      // EOS's open seat. Collapsing it to nothing hides the finding the chart
      // exists to surface.
      final boxes = seatBoxes(
        seats: [seat('s1', 'Marketing')],
        employees: const [],
        areasBySeat: const {
          's1': ['Campaigns'],
        },
      );
      expect(boxes, hasLength(1));
      expect(boxes.single.isOpen, isTrue);
      expect(boxes.single.holderName, isNull);
      expect(boxes.single.function, 'Marketing');
    });

    test('ignores separated and deleted holders', () {
      final boxes = seatBoxes(
        seats: [seat('s1', 'Ops')],
        employees: [
          emp('e1', 'Live', 's1'),
          emp('e2', 'Resigned', 's1', status: 'RESIGNED'),
          emp('e3', 'Deleted', 's1', deleted: true),
        ],
        areasBySeat: const {},
      );
      expect(boxes, hasLength(1));
      expect(boxes.single.holderName, 'Live');
    });

    test('a seat with no areas has no roles, and does not throw', () {
      final boxes = seatBoxes(
        seats: [seat('s1', 'Ops')],
        employees: [emp('e1', 'Live', 's1')],
        areasBySeat: const {},
      );
      expect(boxes.single.roles, isEmpty);
    });
  });

  group('seatDropError', () {
    const seats = [
      (id: 'a', parentId: null),
      (id: 'b', parentId: 'a'),
      (id: 'c', parentId: 'b'),
    ];

    test('a seat cannot parent itself', () {
      expect(
        seatDropError(movingSeatId: 'a', newParentId: 'a', seats: seats),
        isNotNull,
      );
    });

    test('a seat cannot move under its own descendant', () {
      expect(
        seatDropError(movingSeatId: 'a', newParentId: 'c', seats: seats),
        isNotNull,
      );
    });

    test('a legal move returns null', () {
      expect(
        seatDropError(movingSeatId: 'c', newParentId: 'a', seats: seats),
        isNull,
      );
    });
  });
}
