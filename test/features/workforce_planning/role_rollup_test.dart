import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/capacity_math.dart';
import 'package:payroll_flutter/features/workforce_planning/role_rollup.dart';

RoleScorecard _card(
  String id,
  String title, {
  String? base,
  String wageType = 'DAILY',
  int hoursPerDay = 8,
}) =>
    RoleScorecard(
      id: id, companyId: 'c', jobTitle: title, missionStatement: '',
      responsibilities: const [], kpis: const [],
      baseSalary: base == null ? null : Decimal.parse(base),
      wageType: wageType, workHoursPerDay: hoursPerDay,
      workDaysPerWeek: 'MON_FRI', isActive: true,
      effectiveDate: DateTime(2026, 1, 1),
    );

Employee _emp(
  String id,
  String? cardId, {
  String status = 'ACTIVE',
  DateTime? deletedAt,
}) =>
    Employee(
      id: id, companyId: 'c', employeeNumber: id, firstName: 'F', lastName: id,
      roleScorecardId: cardId, employmentType: 'FULL_TIME',
      employmentStatus: status, deletedAt: deletedAt,
      hireDate: DateTime(2024, 1, 1), isRankAndFile: true, isOtEligible: false,
      isNdEligible: false, isHolidayPayEligible: false,
      sssEligibilityOverride: false, philhealthEligibilityOverride: false,
      pagibigEligibilityOverride: false, taxOnFullEarnings: false,
    );

WpTask _task(String id, String? cardId, {String status = 'ACTIVE'}) =>
    WpTask(id: id, companyId: 'c', name: id, roleScorecardId: cardId, status: status);

WpTaskComputed _computed(String id, double hours, {bool growing = false}) =>
    WpTaskComputed(
        taskId: id, companyId: 'c', hoursPerMonthBase: hours, isGrowing: growing);

List<RoleRollupRow> _build({
  required List<RoleScorecard> cards,
  required List<Employee> employees,
  required List<WpTask> tasks,
  required Map<String, WpTaskComputed> computed,
  double multiplier = 1.0,
  double capacity = 160,
}) =>
    buildRoleRollup(
      cards: cards, employees: employees, tasks: tasks,
      computedByTaskId: computed, multiplier: multiplier,
      capacityHoursFor: (_) => capacity,
    );

void main() {
  group('monthlyCostPerHolder mirrors the payroll wage-type switch', () {
    test('DAILY x 26 working days', () {
      expect(monthlyCostPerHolder(_card('a', 'A', base: '1076.92')),
          Decimal.parse('27999.92'));
    });

    test('MONTHLY is already monthly', () {
      expect(
          monthlyCostPerHolder(_card('a', 'A', base: '30000', wageType: 'MONTHLY')),
          Decimal.parse('30000'));
    });

    test('HOURLY x hours/day x 26', () {
      expect(
          monthlyCostPerHolder(
              _card('a', 'A', base: '100', wageType: 'HOURLY', hoursPerDay: 8)),
          Decimal.parse('20800'));
    });

    test('no base salary -> null, never zero', () {
      expect(monthlyCostPerHolder(_card('a', 'A')), isNull,
          reason: 'a missing salary must read as unknown, not free');
    });

    test('the working-day constant matches payroll', () {
      expect(kRoleCostWorkDaysPerMonth, 26);
    });
  });

  group('rollup', () {
    test('sums the role\'s whole responsibility set, undivided by headcount', () {
      final rows = _build(
        cards: [_card('rs1', 'Ops', base: '1000')],
        employees: [_emp('e1', 'rs1'), _emp('e2', 'rs1')],
        tasks: [_task('t1', 'rs1'), _task('t2', 'rs1')],
        computed: {'t1': _computed('t1', 40), 't2': _computed('t2', 60)},
      );
      final r = rows.single;
      expect(r.hoursPerMonth, 100.0, reason: 'the role\'s work is 100h either way');
      expect(r.holders, 2);
      expect(r.capacityHours, 320.0, reason: 'two holders carry it');
      expect(r.loadFraction, closeTo(100 / 320, 0.0001));
      expect(r.status, LoadStatus.under);
    });

    test('cost scales with holders', () {
      final rows = _build(
        cards: [_card('rs1', 'Kiosk', base: '695')],
        employees: [_emp('e1', 'rs1'), _emp('e2', 'rs1')],
        tasks: const [], computed: const {},
      );
      // 695 * 26 * 2
      expect(rows.single.monthlyCost, Decimal.parse('36140'));
    });

    test('only ACTIVE, non-deleted employees count as holders', () {
      final rows = _build(
        cards: [_card('rs1', 'Ops', base: '1000')],
        employees: [
          _emp('live', 'rs1'),
          _emp('resigned', 'rs1', status: 'SEPARATED'),
          _emp('archived', 'rs1', deletedAt: DateTime(2026, 1, 1)),
        ],
        tasks: const [], computed: const {},
      );
      expect(rows.single.holders, 1,
          reason: 'must match wp_person_load: ACTIVE *and* not soft-deleted');
      expect(rows.single.monthlyCost, Decimal.parse('26000'));
    });

    test('growing tasks scale with the multiplier, fixed ones do not', () {
      final rows = _build(
        cards: [_card('rs1', 'Ops')],
        employees: [_emp('e1', 'rs1')],
        tasks: [_task('t1', 'rs1'), _task('t2', 'rs1')],
        computed: {
          't1': _computed('t1', 100, growing: true),
          't2': _computed('t2', 50),
        },
        multiplier: 2.0,
      );
      expect(rows.single.hoursPerMonth, 250.0);
    });

    test('an uncosted role reports unknown load, not 0%', () {
      final rows = _build(
        cards: [_card('rs1', 'HR', base: '1000')],
        employees: [_emp('e1', 'rs1')],
        tasks: [_task('t1', 'rs1'), _task('t2', 'rs1')],
        computed: const {},
      );
      final r = rows.single;
      expect(r.responsibilities, 2);
      expect(r.costedResponsibilities, 0);
      expect(r.loadFraction, isNull, reason: '0% would read as "this role is idle"');
      expect(r.status, isNull);
      expect(r.costPerHour, isNull);
      expect(r.fullyCosted, isFalse);
      expect(r.monthlyCost, Decimal.parse('26000'),
          reason: 'cost is known even when effort is not');
    });

    test('a role with no holders costs nothing and has no capacity', () {
      final rows = _build(
        cards: [_card('rs1', 'Vacant', base: '1000')],
        employees: const [],
        tasks: [_task('t1', 'rs1')],
        computed: {'t1': _computed('t1', 40)},
      );
      final r = rows.single;
      expect(r.holders, 0);
      expect(r.monthlyCost, Decimal.zero);
      expect(r.capacityHours, 0);
      expect(r.loadFraction, isNull,
          reason: 'unstaffed work is a staffing gap, not an infinite load');
      expect(r.hoursPerMonth, 40.0, reason: 'the work still exists');
    });

    test('costPerHour divides money by costed hours', () {
      final rows = _build(
        cards: [_card('rs1', 'Ops', base: '1000')],
        employees: [_emp('e1', 'rs1')],
        tasks: [_task('t1', 'rs1')],
        computed: {'t1': _computed('t1', 100)},
      );
      // 1000 * 26 = 26000 over 100h
      expect(rows.single.costPerHour, Decimal.parse('260'));
    });

    test('tasks on other cards and unlinked tasks are excluded', () {
      final rows = _build(
        cards: [_card('rs1', 'Ops')],
        employees: [_emp('e1', 'rs1')],
        tasks: [_task('t1', 'rs1'), _task('t2', 'other'), _task('t3', null)],
        computed: {
          't1': _computed('t1', 10),
          't2': _computed('t2', 999),
          't3': _computed('t3', 999),
        },
      );
      expect(rows.single.responsibilities, 1);
      expect(rows.single.hoursPerMonth, 10.0);
    });

    test('an ARCHIVED task on a card is not counted in that card\'s rollup row', () {
      final rows = _build(
        cards: [_card('rs1', 'Ops', base: '1000')],
        employees: [_emp('e1', 'rs1')],
        tasks: [_task('t1', 'rs1'), _task('t2', 'rs1', status: 'ARCHIVED')],
        computed: {'t1': _computed('t1', 40), 't2': _computed('t2', 999)},
      );
      final r = rows.single;
      expect(r.responsibilities, 1,
          reason: 'the archived task must not inflate the responsibility count');
      expect(r.costedResponsibilities, 1);
      expect(r.hoursPerMonth, 40.0,
          reason: 'the archived task\'s hours must not leak into the role\'s workload');
      expect(r.fullyCosted, isTrue,
          reason: 'fullyCosted must not be flipped by an archived, uncounted task');
    });

    test('rows are sorted by job title', () {
      final rows = _build(
        cards: [_card('b', 'Zebra'), _card('a', 'Alpha')],
        employees: const [], tasks: const [], computed: const {},
      );
      expect(rows.map((r) => r.jobTitle), ['Alpha', 'Zebra']);
    });
  });

  group('totals', () {
    test('sum across roles, treating an unpriced card as zero money', () {
      final rows = _build(
        cards: [_card('rs1', 'Ops', base: '1000'), _card('rs2', 'Free')],
        employees: [_emp('e1', 'rs1'), _emp('e2', 'rs2')],
        tasks: [_task('t1', 'rs1'), _task('t2', 'rs2')],
        computed: {'t1': _computed('t1', 40)},
      );
      final t = totalRoleRollup(rows);
      expect(t.holders, 2);
      expect(t.responsibilities, 2);
      expect(t.costedResponsibilities, 1);
      expect(t.uncosted, 1);
      expect(t.hoursPerMonth, 40.0);
      expect(t.monthlyCost, Decimal.parse('26000'));
    });
  });
}
