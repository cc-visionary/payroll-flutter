import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/kpi_goal.dart';
import 'package:payroll_flutter/data/models/kpi_result.dart';
import 'package:payroll_flutter/features/kpi_results/kpi_status.dart';

void main() {
  ({num? value, KpiStatus status}) run({
    String valueType = 'RATIO',
    num? numerator,
    num? denominator,
    num? target,
    GoalDirection? direction = GoalDirection.gte,
    num? targetMax,
  }) => evaluateKpi(
    valueType: valueType,
    numerator: numerator,
    denominator: denominator,
    target: target,
    direction: direction,
    targetMax: targetMax,
  );

  group('missing data is never a failure', () {
    test('no numerator at all is NO_DATA', () {
      expect(run(denominator: 100, target: 0.99).status, KpiStatus.noData);
    });

    test('a RATIO with no denominator is NO_DATA, not OFF_TRACK', () {
      // The tempting bug: treat a null denominator as 0, divide, get 0,
      // and report a catastrophic miss on a KPI nobody has data for.
      expect(run(numerator: 398, target: 0.99).status, KpiStatus.noData);
    });

    test('a zero denominator is NO_DATA, not a division error', () {
      final r = run(numerator: 0, denominator: 0, target: 0.99);
      expect(r.status, KpiStatus.noData);
      expect(r.value, isNull);
    });

    test('no target is NO_DATA even with real inputs', () {
      // A number with nothing to judge it against is not a verdict.
      expect(run(numerator: 398, denominator: 400, target: null).status,
          KpiStatus.noData);
    });
  });

  group('a real zero is a real result', () {
    test('zero numerator over a real denominator is a genuine miss', () {
      final r = run(numerator: 0, denominator: 400, target: 0.99);
      expect(r.value, 0);
      expect(r.status, KpiStatus.offTrack);
    });

    test('a COUNT of zero against a LTE target is on track', () {
      // "Confirmed purchasing errors, at most 0" — zero is success, and it
      // must not be mistaken for missing.
      final r = run(
        valueType: 'COUNT',
        numerator: 0,
        target: 0,
        direction: GoalDirection.lte,
      );
      expect(r.value, 0);
      expect(r.status, KpiStatus.onTrack);
    });
  });

  group('the boundary is inclusive both ways', () {
    test('exactly meeting a GTE target is on track', () {
      expect(run(numerator: 99, denominator: 100, target: 0.99).status,
          KpiStatus.onTrack);
    });

    test('exactly meeting a LTE target is on track', () {
      expect(
        run(
          valueType: 'COUNT',
          numerator: 3,
          target: 3,
          direction: GoalDirection.lte,
        ).status,
        KpiStatus.onTrack,
      );
    });

    test('EQ is on track only on the nose', () {
      expect(
        run(valueType: 'COUNT', numerator: 5, target: 5,
            direction: GoalDirection.eq).status,
        KpiStatus.onTrack,
      );
      expect(
        run(valueType: 'COUNT', numerator: 4, target: 5,
            direction: GoalDirection.eq).status,
        KpiStatus.offTrack,
      );
    });

    test('BETWEEN is inclusive at both ends', () {
      final inside = run(
        valueType: 'COUNT', numerator: 5, target: 4, targetMax: 6,
        direction: GoalDirection.between,
      );
      expect(inside.status, KpiStatus.onTrack);
      expect(
        run(valueType: 'COUNT', numerator: 4, target: 4, targetMax: 6,
            direction: GoalDirection.between).status,
        KpiStatus.onTrack,
      );
      expect(
        run(valueType: 'COUNT', numerator: 7, target: 4, targetMax: 6,
            direction: GoalDirection.between).status,
        KpiStatus.offTrack,
      );
    });

    test('BETWEEN with no upper bound is NO_DATA, not a one-sided test', () {
      // A half-configured band cannot judge anything.
      expect(
        run(valueType: 'COUNT', numerator: 5, target: 4,
            direction: GoalDirection.between).status,
        KpiStatus.noData,
      );
    });
  });

  group('value derivation by type', () {
    test('COUNT ignores the denominator entirely', () {
      final r = run(valueType: 'COUNT', numerator: 3, denominator: 999,
          target: 5, direction: GoalDirection.lte);
      expect(r.value, 3);
      expect(r.status, KpiStatus.onTrack);
    });

    test('RATIO divides', () {
      expect(run(numerator: 398, denominator: 400, target: 0.99).value,
          closeTo(0.995, 0.0001));
    });

    test('CURRENCY and DURATION behave like COUNT', () {
      for (final t in ['CURRENCY', 'DURATION']) {
        final r = run(valueType: t, numerator: 250, target: 200);
        expect(r.value, 250, reason: t);
        expect(r.status, KpiStatus.onTrack, reason: t);
      }
    });

    test('a null direction defaults to GTE rather than refusing to judge', () {
      expect(
        run(valueType: 'COUNT', numerator: 10, target: 5, direction: null)
            .status,
        KpiStatus.onTrack,
      );
    });
  });
}
