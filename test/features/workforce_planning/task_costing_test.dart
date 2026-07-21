import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/task_costing.dart';

const _shopee = WpDriver(
    id: 'd1', companyId: 'c', name: 'Shopee orders', value: 120, grows: true);
const _units = WpDriver(
    id: 'd2', companyId: 'c', name: 'Units sold', value: 500, grows: false);
const _pack =
    WpRate(id: 'r1', companyId: 'c', name: 'Pick/pack', minutesEach: 8);

final _drivers = {'d1': _shopee, 'd2': _units};
final _rates = {'r1': _pack};

WpTask _task() => const WpTask(
      id: 't1', companyId: 'c', name: 'A responsibility',
      ownerEmployeeId: 'e1', roleScorecardId: 'rs1',
      responsibilityArea: 'Area', externalRef: 'T9', notes: 'keep',
      areaSort: 3, taskSort: 7,
    );

void main() {
  group('hours match the wp_task_computed formula', () {
    test('manual x manual', () {
      const d = CostDraft(
          timesSource: 'manual', timesManual: 20,
          minutesSource: 'manual', minutesManual: 45);
      // 20 * 45 / 60
      expect(draftHoursPerMonth(d, _drivers, _rates), 15.0);
    });

    test('driver x rate applies driver_factor', () {
      const d = CostDraft(
          timesSource: 'driver', driverId: 'd1', driverFactor: 0.5,
          minutesSource: 'rate', rateId: 'r1');
      // (120 * 0.5) * 8 / 60
      expect(draftHoursPerMonth(d, _drivers, _rates), 8.0);
    });

    test('a missing driver or rate contributes zero, not a crash', () {
      const d = CostDraft(
          timesSource: 'driver', driverId: 'gone',
          minutesSource: 'rate', rateId: 'gone');
      expect(draftHoursPerMonth(d, _drivers, _rates), 0.0);
    });

    test('unset manual values read as zero hours', () {
      const d = CostDraft(timesSource: 'manual', minutesSource: 'manual');
      expect(draftHoursPerMonth(d, _drivers, _rates), 0.0);
    });
  });

  group('costed / growing', () {
    test('both halves required to count as costed', () {
      const timesOnly = CostDraft(
          timesSource: 'manual', timesManual: 20, minutesSource: 'manual');
      const minsOnly = CostDraft(
          timesSource: 'manual', minutesSource: 'manual', minutesManual: 45);
      const both = CostDraft(
          timesSource: 'manual', timesManual: 20,
          minutesSource: 'manual', minutesManual: 45);
      expect(draftIsCosted(timesOnly, _drivers, _rates), isFalse);
      expect(draftIsCosted(minsOnly, _drivers, _rates), isFalse);
      expect(draftIsCosted(both, _drivers, _rates), isTrue);
    });

    test('only a growing driver makes the task respond to the multiplier', () {
      const manual = CostDraft(
          timesSource: 'manual', timesManual: 100, minutesSource: 'manual');
      const flatDriver =
          CostDraft(timesSource: 'driver', driverId: 'd2', minutesSource: 'manual');
      const growDriver =
          CostDraft(timesSource: 'driver', driverId: 'd1', minutesSource: 'manual');
      expect(draftIsGrowing(manual, _drivers), isFalse,
          reason: 'a big manual number is still flat forever');
      expect(draftIsGrowing(flatDriver, _drivers), isFalse);
      expect(draftIsGrowing(growDriver, _drivers), isTrue);
    });
  });

  group('draftPatch nulls the losing source', () {
    test('driver-sourced times clears times_manual', () {
      const d = CostDraft(
          timesSource: 'driver', driverId: 'd1', timesManual: 999,
          minutesSource: 'manual', minutesManual: 45);
      final p = draftPatch(d);
      expect(p['times_manual'], isNull);
      expect(p['driver_id'], 'd1');
    });

    test('manual-sourced times clears driver_id', () {
      const d = CostDraft(
          timesSource: 'manual', timesManual: 20, driverId: 'd1',
          minutesSource: 'manual');
      final p = draftPatch(d);
      expect(p['driver_id'], isNull);
      expect(p['times_manual'], 20);
    });

    test('rate-sourced minutes clears minutes_manual and vice versa', () {
      const viaRate = CostDraft(
          timesSource: 'manual', minutesSource: 'rate', rateId: 'r1',
          minutesManual: 999);
      expect(draftPatch(viaRate)['minutes_manual'], isNull);
      expect(draftPatch(viaRate)['rate_id'], 'r1');

      const viaManual = CostDraft(
          timesSource: 'manual', minutesSource: 'manual', minutesManual: 45,
          rateId: 'r1');
      expect(draftPatch(viaManual)['rate_id'], isNull);
      expect(draftPatch(viaManual)['minutes_manual'], 45);
    });

    test('patches only costing columns — never name, owner or card link', () {
      const d = CostDraft(timesSource: 'manual', minutesSource: 'manual');
      expect(draftPatch(d).keys.toSet(), {
        'node_id', 'times_source', 'times_manual', 'driver_id',
        'driver_factor', 'minutes_source', 'minutes_manual', 'rate_id',
      });
    });
  });

  group('round trip', () {
    test('fromTask -> applyTo preserves every non-costing column', () {
      final t = _task();
      final back = CostDraft.fromTask(t).applyTo(t);
      expect(back.name, t.name);
      expect(back.ownerEmployeeId, 'e1');
      expect(back.roleScorecardId, 'rs1');
      expect(back.responsibilityArea, 'Area');
      expect(back.externalRef, 'T9');
      expect(back.notes, 'keep');
      expect(back.areaSort, 3);
      expect(back.taskSort, 7);
    });

    test('an untouched draft equals its origin, so it is not saved', () {
      final t = _task();
      expect(CostDraft.fromTask(t), CostDraft.fromTask(t));
    });
  });

  group('parseCostField', () {
    test('blank is null, not zero', () {
      expect(parseCostField(''), isNull);
      expect(parseCostField('   '), isNull);
    });
    test('zero parses as zero', () => expect(parseCostField('0'), 0.0));
    test('garbage is null', () => expect(parseCostField('abc'), isNull));
    test('decimals and padding', () {
      expect(parseCostField(' 12.5 '), 12.5);
    });
  });

  group('fillGroupDrafts', () {
    List<WpTask> rows() => const [
          WpTask(id: 'a', companyId: 'c', name: 'A'),
          WpTask(id: 'b', companyId: 'c', name: 'B'),
          WpTask(
              id: 'c', companyId: 'c', name: 'C',
              timesSource: 'manual', timesManual: 5,
              minutesSource: 'manual', minutesManual: 60),
        ];

    test('fills only the uncosted rows by default', () {
      final out = fillGroupDrafts(
        tasks: rows(), current: const {}, driverById: _drivers, rateById: _rates,
        timesManual: 20, minutesManual: 30,
      );
      expect(out.keys.toSet(), {'a', 'b'},
          reason: 'row C is already costed and must not be overwritten');
      expect(draftHoursPerMonth(out['a']!, _drivers, _rates), 10.0);
    });

    test('onlyUncosted:false restates the whole group', () {
      final out = fillGroupDrafts(
        tasks: rows(), current: const {}, driverById: _drivers, rateById: _rates,
        timesManual: 20, minutesManual: 30, onlyUncosted: false,
      );
      expect(out.keys.toSet(), {'a', 'b', 'c'});
    });

    test('filling switches the row back to manual and drops driver/rate ids', () {
      final current = {
        'a': const CostDraft(
            timesSource: 'driver', driverId: 'd1',
            minutesSource: 'rate', rateId: 'r1'),
      };
      final out = fillGroupDrafts(
        tasks: rows(), current: current, driverById: _drivers, rateById: _rates,
        timesManual: 20, minutesManual: 30,
      );
      // 'a' was costed via driver+rate, so with onlyUncosted it is skipped.
      expect(out.containsKey('a'), isFalse);

      final forced = fillGroupDrafts(
        tasks: rows(), current: current, driverById: _drivers, rateById: _rates,
        timesManual: 20, minutesManual: 30, onlyUncosted: false,
      );
      expect(forced['a']!.timesSource, 'manual');
      expect(forced['a']!.driverId, isNull);
      expect(forced['a']!.rateId, isNull);
    });

    test('filling with the values a row already has produces no edit', () {
      final out = fillGroupDrafts(
        tasks: rows(), current: const {}, driverById: _drivers, rateById: _rates,
        timesManual: 5, minutesManual: 60, onlyUncosted: false,
      );
      expect(out.containsKey('c'), isFalse,
          reason: 'no-op fills must not show up as unsaved changes');
    });

    test('a blank field leaves that half of the estimate alone', () {
      final out = fillGroupDrafts(
        tasks: rows(), current: const {}, driverById: _drivers, rateById: _rates,
        timesManual: 20,
      );
      expect(out['a']!.timesManual, 20);
      expect(out['a']!.minutesManual, isNull);
    });
  });
}
