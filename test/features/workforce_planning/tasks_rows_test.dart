import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/tasks_rows.dart';

Employee _emp(String id, String first, String last,
        {String? roleScorecardId, String employmentStatus = 'ACTIVE'}) =>
    Employee(
      id: id, companyId: 'c', employeeNumber: id, firstName: first, lastName: last,
      jobTitle: 'Sys', employmentType: 'FULL_TIME', employmentStatus: employmentStatus,
      hireDate: DateTime(2024, 1, 1), isRankAndFile: true, isOtEligible: false,
      isNdEligible: false, isHolidayPayEligible: false, sssEligibilityOverride: false,
      philhealthEligibilityOverride: false, pagibigEligibilityOverride: false,
      taxOnFullEarnings: false, roleScorecardId: roleScorecardId);

RoleScorecard _card(String id, String jobTitle) => RoleScorecard(
      id: id,
      companyId: 'c',
      jobTitle: jobTitle,
      missionStatement: '',
      responsibilities: const [],
      kpis: const [],
      wageType: 'MONTHLY',
      workHoursPerDay: 8,
      workDaysPerWeek: 'MON_FRI',
      isActive: true,
      effectiveDate: DateTime(2026, 1, 1),
    );

void main() {
  group('groupTasks', () {
    test('buckets a card-linked task under its card, ordered areas/tasks by sort not name', () {
      final tasks = [
        WpTask.fromRow({
          'id': 't1', 'company_id': 'c', 'name': 'Zebra task',
          'role_scorecard_id': 'rc1', 'responsibility_area': 'B area',
          'area_sort': 0, 'task_sort': 1,
        }),
        WpTask.fromRow({
          'id': 't2', 'company_id': 'c', 'name': 'Apple task',
          'role_scorecard_id': 'rc1', 'responsibility_area': 'B area',
          'area_sort': 0, 'task_sort': 0,
        }),
        WpTask.fromRow({
          'id': 't3', 'company_id': 'c', 'name': 'A area task',
          'role_scorecard_id': 'rc1', 'responsibility_area': 'A area',
          'area_sort': 1, 'task_sort': 0,
        }),
      ];
      final groups = groupTasks(tasks, [_card('rc1', 'Ops Lead')]);
      expect(groups.cardGroups, hasLength(1));
      final cg = groups.cardGroups.single;
      expect(cg.jobTitle, 'Ops Lead');
      // "B area" has area_sort 0, "A area" has area_sort 1 -> B area first
      // despite alphabetical order — sort col wins, never name.
      expect(cg.areas.map((a) => a.area).toList(), ['B area', 'A area']);
      // Within "B area", task_sort 0 (Apple) before task_sort 1 (Zebra) —
      // alphabetically Apple would also come first, so also assert the
      // reverse-sort case below to prove it's not accidentally alphabetical.
      expect(cg.areas[0].tasks.map((t) => t.name).toList(), ['Apple task', 'Zebra task']);
    });

    test('task_sort order beats alphabetical order (not merely consistent with it)', () {
      final tasks = [
        WpTask.fromRow({
          'id': 't1', 'company_id': 'c', 'name': 'Apple task',
          'role_scorecard_id': 'rc1', 'responsibility_area': 'Area',
          'area_sort': 0, 'task_sort': 1,
        }),
        WpTask.fromRow({
          'id': 't2', 'company_id': 'c', 'name': 'Zebra task',
          'role_scorecard_id': 'rc1', 'responsibility_area': 'Area',
          'area_sort': 0, 'task_sort': 0,
        }),
      ];
      final groups = groupTasks(tasks, [_card('rc1', 'Ops Lead')]);
      final names = groups.cardGroups.single.areas.single.tasks.map((t) => t.name).toList();
      expect(names, ['Zebra task', 'Apple task']);
    });

    test('area order uses the MIN area_sort across a possibly-inconsistent set of rows', () {
      final tasks = [
        WpTask.fromRow({
          'id': 't1', 'company_id': 'c', 'name': 'x1',
          'role_scorecard_id': 'rc1', 'responsibility_area': 'Late',
          'area_sort': 5, 'task_sort': 0,
        }),
        WpTask.fromRow({
          'id': 't2', 'company_id': 'c', 'name': 'x2',
          'role_scorecard_id': 'rc1', 'responsibility_area': 'Late',
          'area_sort': 1, 'task_sort': 1, // same area, lower area_sort
        }),
        WpTask.fromRow({
          'id': 't3', 'company_id': 'c', 'name': 'x3',
          'role_scorecard_id': 'rc1', 'responsibility_area': 'Early',
          'area_sort': 2, 'task_sort': 0,
        }),
      ];
      final groups = groupTasks(tasks, [_card('rc1', 'Ops Lead')]);
      expect(groups.cardGroups.single.areas.map((a) => a.area).toList(), ['Late', 'Early']);
    });

    test('a task with a null/blank responsibility area is not dropped, grouped as Unspecified', () {
      final tasks = [
        WpTask.fromRow({
          'id': 't1', 'company_id': 'c', 'name': 'x1', 'role_scorecard_id': 'rc1',
        }),
      ];
      final groups = groupTasks(tasks, [_card('rc1', 'Ops Lead')]);
      expect(groups.cardGroups.single.areas.single.area, unspecifiedAreaLabel);
      expect(groups.cardGroups.single.areas.single.tasks.single.id, 't1');
    });

    test('a task pointing at a card outside the active-only fetch still gets a heading', () {
      // roleScorecardListProvider's list() defaults to onlyActive: true, so a
      // task can reference a superseded/inactive card id not present in `cards`.
      final tasks = [
        const WpTask(id: 't1', companyId: 'c', name: 'orphaned', roleScorecardId: 'rc-gone'),
      ];
      final groups = groupTasks(tasks, const []); // rc-gone not in the fetched cards
      expect(groups.cardGroups, hasLength(1));
      expect(groups.cardGroups.single.jobTitle, unknownRoleCardLabel);
      expect(groups.cardGroups.single.areas.single.tasks.single.id, 't1');
    });

    test('only card ids with >=1 task get a heading (no empty-card headings)', () {
      final tasks = [
        const WpTask(id: 't1', companyId: 'c', name: 'a', roleScorecardId: 'rc1'),
      ];
      final groups = groupTasks(tasks, [_card('rc1', 'Ops Lead'), _card('rc2', 'Idle Role')]);
      expect(groups.cardGroups.map((g) => g.jobTitle).toList(), ['Ops Lead']);
    });

    test('legacy bucket: externalRef set and no role card', () {
      final tasks = [
        const WpTask(id: 't1', companyId: 'c', name: 'imported', externalRef: 'cap-model-1'),
      ];
      final groups = groupTasks(tasks, const []);
      expect(groups.cardGroups, isEmpty);
      expect(groups.legacy.map((t) => t.id), ['t1']);
      expect(groups.unattributed, isEmpty);
    });

    test('unattributed bucket is the TRUE complement of buckets 1+2, not "no owner"', () {
      // A task can have an explicit owner with no card and no externalRef —
      // it must still land in bucket 3 rather than vanishing (this is exactly
      // the pre-existing baseline widget-test fixture's shape).
      final tasks = [
        const WpTask(id: 't1', companyId: 'c', name: 'SD flash', ownerEmployeeId: 'e1'),
      ];
      final groups = groupTasks(tasks, const []);
      expect(groups.cardGroups, isEmpty);
      expect(groups.legacy, isEmpty);
      expect(groups.unattributed.map((t) => t.id), ['t1']);
    });

    test('roleScorecardId takes priority over externalRef (bucket 1 before bucket 2)', () {
      final tasks = [
        const WpTask(
          id: 't1', companyId: 'c', name: 'both-set',
          roleScorecardId: 'rc1', externalRef: 'cap-model-1',
        ),
      ];
      final groups = groupTasks(tasks, [_card('rc1', 'Ops Lead')]);
      expect(groups.cardGroups, hasLength(1));
      expect(groups.legacy, isEmpty);
    });

    test('known-card groups follow the (already job-title-sorted) cards order; '
        'unknown-card groups are appended after, sorted by id', () {
      final tasks = [
        const WpTask(id: 't1', companyId: 'c', name: 'a', roleScorecardId: 'rc-unknown-2'),
        const WpTask(id: 't2', companyId: 'c', name: 'b', roleScorecardId: 'rc-unknown-1'),
        const WpTask(id: 't3', companyId: 'c', name: 'c', roleScorecardId: 'rcB'),
        const WpTask(id: 't4', companyId: 'c', name: 'd', roleScorecardId: 'rcA'),
      ];
      // cards pre-sorted by job_title: "Alpha Lead" (rcA) then "Beta Lead" (rcB)
      final groups = groupTasks(tasks, [_card('rcA', 'Alpha Lead'), _card('rcB', 'Beta Lead')]);
      expect(groups.cardGroups.map((g) => g.jobTitle).toList(),
          ['Alpha Lead', 'Beta Lead', unknownRoleCardLabel, unknownRoleCardLabel]);
      expect(groups.cardGroups[2].cardId, 'rc-unknown-1');
      expect(groups.cardGroups[3].cardId, 'rc-unknown-2');
    });
  });

  group('isTaskNotCosted', () {
    test('true when neither times nor minutes is set (freshly-promoted responsibility)', () {
      const t = WpTask(id: 't1', companyId: 'c', name: 'x');
      expect(isTaskNotCosted(t), isTrue);
    });

    test('false when manual times is set even if minutes is not', () {
      const t = WpTask(id: 't1', companyId: 'c', name: 'x', timesManual: 5);
      expect(isTaskNotCosted(t), isFalse);
    });

    test('false when manual minutes is set even if times is not', () {
      const t = WpTask(id: 't1', companyId: 'c', name: 'x', minutesManual: 5);
      expect(isTaskNotCosted(t), isFalse);
    });

    test('driver-sourced times counts as having times when driverId is set, '
        'regardless of timesManual', () {
      const t = WpTask(
        id: 't1', companyId: 'c', name: 'x',
        timesSource: 'driver', driverId: 'd1', minutesManual: 5,
      );
      expect(isTaskNotCosted(t), isFalse);
    });

    test('driver-sourced times with no driverId still counts as no times', () {
      const t = WpTask(id: 't1', companyId: 'c', name: 'x', timesSource: 'driver');
      expect(isTaskNotCosted(t), isTrue);
    });

    test('rate-sourced minutes counts as having minutes when rateId is set', () {
      const t = WpTask(
        id: 't1', companyId: 'c', name: 'x',
        minutesSource: 'rate', rateId: 'r1', timesManual: 5,
      );
      expect(isTaskNotCosted(t), isFalse);
    });
  });

  group('taskHours', () {
    test('manual times * manual minutes / 60', () {
      const t = WpTask(id: 't1', companyId: 'c', name: 'x', timesManual: 10, minutesManual: 30);
      final h = taskHours(task: t, driverById: const {}, rateById: const {});
      expect(h, 5.0); // 10 * 30 / 60
    });

    test('driver-sourced times: driver.value * driverFactor', () {
      const t = WpTask(
        id: 't1', companyId: 'c', name: 'x',
        timesSource: 'driver', driverId: 'd1', driverFactor: 3, minutesManual: 12,
      );
      const d = WpDriver(id: 'd1', companyId: 'c', name: 'D', value: 4);
      final h = taskHours(task: t, driverById: {'d1': d}, rateById: const {});
      expect(h, 2.4); // (4 * 3) * 12 / 60
    });

    test('rate-sourced minutes: rate.minutesEach', () {
      const t = WpTask(
        id: 't1', companyId: 'c', name: 'x',
        timesManual: 5, minutesSource: 'rate', rateId: 'r1',
      );
      const r = WpRate(id: 'r1', companyId: 'c', name: 'R', minutesEach: 24);
      final h = taskHours(task: t, driverById: const {}, rateById: {'r1': r});
      expect(h, 2.0); // 5 * 24 / 60
    });

    test('missing driver/rate lookups fall back to 0, not a crash', () {
      const t = WpTask(
        id: 't1', companyId: 'c', name: 'x',
        timesSource: 'driver', driverId: 'gone',
        minutesSource: 'rate', rateId: 'gone',
      );
      final h = taskHours(task: t, driverById: const {}, rateById: const {});
      expect(h, 0.0);
    });
  });

  group('resolveEffectiveOwner', () {
    test('explicit owner: shows their name, not derived', () {
      const t = WpTask(id: 't1', companyId: 'c', name: 'x', ownerEmployeeId: 'e1');
      final owner = resolveEffectiveOwner(
        task: t, employeeNameById: const {'e1': 'Marvin Ong'}, employees: const [],
      );
      expect(owner.label, 'Marvin Ong');
      expect(owner.derived, isFalse);
    });

    test('explicit owner not resolvable in the active roster falls back to Unassigned, still not derived', () {
      const t = WpTask(id: 't1', companyId: 'c', name: 'x', ownerEmployeeId: 'gone-emp');
      final owner = resolveEffectiveOwner(
        task: t, employeeNameById: const {}, employees: const [],
      );
      expect(owner.label, 'Unassigned');
      expect(owner.derived, isFalse);
    });

    test('one role holder: shows their name, derived', () {
      const t = WpTask(id: 't1', companyId: 'c', name: 'x', roleScorecardId: 'rc1');
      final owner = resolveEffectiveOwner(
        task: t,
        employeeNameById: const {},
        employees: [_emp('e1', 'Marvin', 'Ong', roleScorecardId: 'rc1')],
      );
      expect(owner.label, 'Marvin Ong');
      expect(owner.derived, isTrue);
    });

    test('multiple role holders: "N holders", derived', () {
      const t = WpTask(id: 't1', companyId: 'c', name: 'x', roleScorecardId: 'rc1');
      final owner = resolveEffectiveOwner(
        task: t,
        employeeNameById: const {},
        employees: [
          _emp('e1', 'Marvin', 'Ong', roleScorecardId: 'rc1'),
          _emp('e2', 'Brixter', 'Cruz', roleScorecardId: 'rc1'),
        ],
      );
      expect(owner.label, '2 holders');
      expect(owner.derived, isTrue);
    });

    test('zero role holders: Unassigned, NOT derived (nothing was actually derived)', () {
      const t = WpTask(id: 't1', companyId: 'c', name: 'x', roleScorecardId: 'rc1');
      final owner = resolveEffectiveOwner(
        task: t, employeeNameById: const {}, employees: const [],
      );
      expect(owner.label, 'Unassigned');
      expect(owner.derived, isFalse);
    });

    test('no owner and no card: Unassigned, not derived', () {
      const t = WpTask(id: 't1', companyId: 'c', name: 'x');
      final owner = resolveEffectiveOwner(
        task: t, employeeNameById: const {}, employees: const [],
      );
      expect(owner.label, 'Unassigned');
      expect(owner.derived, isFalse);
    });

    test('a TERMINATED holder is excluded — one ACTIVE + one TERMINATED '
        'resolves to ONE holder, matching wp_person_load (which gives the '
        'ACTIVE holder 100% of the hours, not a 2-way split)', () {
      const t = WpTask(id: 't1', companyId: 'c', name: 'x', roleScorecardId: 'rc1');
      final owner = resolveEffectiveOwner(
        task: t,
        employeeNameById: const {},
        employees: [
          _emp('e1', 'Marvin', 'Ong', roleScorecardId: 'rc1'),
          _emp('e2', 'Gone', 'Person', roleScorecardId: 'rc1', employmentStatus: 'TERMINATED'),
        ],
      );
      expect(owner.label, 'Marvin Ong');
      expect(owner.derived, isTrue);
    });

    test('all holders separated (non-ACTIVE): zero-holder outcome — '
        'Unassigned, not derived', () {
      const t = WpTask(id: 't1', companyId: 'c', name: 'x', roleScorecardId: 'rc1');
      final owner = resolveEffectiveOwner(
        task: t,
        employeeNameById: const {},
        employees: [
          _emp('e1', 'Gone', 'One', roleScorecardId: 'rc1', employmentStatus: 'RESIGNED'),
          _emp('e2', 'Gone', 'Two', roleScorecardId: 'rc1', employmentStatus: 'AWOL'),
        ],
      );
      expect(owner.label, 'Unassigned');
      expect(owner.derived, isFalse);
    });
  });

  group('groupTasks task ordering tie-break', () {
    test('equal task_sort within an area is tie-broken by id for a '
        'deterministic order (List.sort is not stable in Dart)', () {
      final tasks = [
        WpTask.fromRow({
          'id': 'tz', 'company_id': 'c', 'name': 'z-name',
          'role_scorecard_id': 'rc1', 'responsibility_area': 'Area',
          'area_sort': 0, 'task_sort': 0,
        }),
        WpTask.fromRow({
          'id': 'ta', 'company_id': 'c', 'name': 'a-name',
          'role_scorecard_id': 'rc1', 'responsibility_area': 'Area',
          'area_sort': 0, 'task_sort': 0,
        }),
      ];
      final groups = groupTasks(tasks, [_card('rc1', 'Ops Lead')]);
      final ids = groups.cardGroups.single.areas.single.tasks.map((t) => t.id).toList();
      // Same task_sort (0) for both -> tie-break by id ascending: 'ta' < 'tz'.
      expect(ids, ['ta', 'tz']);
    });
  });

}
