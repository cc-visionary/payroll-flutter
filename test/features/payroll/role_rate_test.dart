import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/compensation_change.dart';
import 'package:payroll_flutter/data/models/role_rate_change.dart';
import 'package:payroll_flutter/features/payroll/engine/daily_rate.dart';
import 'package:payroll_flutter/features/payroll/engine/role_rate.dart';

Decimal d(String s) => Decimal.parse(s);

RoleRateChange rr(String id, DateTime eff, String? prev, String next,
        {DateTime? created}) =>
    RoleRateChange(
      id: id,
      companyId: 'c',
      roleScorecardId: 'card',
      effectiveDate: eff,
      prevBaseSalary: prev == null ? null : d(prev),
      newBaseSalary: d(next),
      createdAt: created ?? DateTime(2026, 9, 1),
    );

void main() {
  group('roleRateAsOf', () {
    final hist = [rr('a', DateTime(2026, 10, 1), '695', '755')];

    test('no history returns the stored base salary', () {
      expect(roleRateAsOf(const [], DateTime(2026, 9, 1), d('695')), d('695'));
    });

    test('before the first change pays its prev rate, not the new base', () {
      // base_salary already reads 755 once the change is saved.
      expect(roleRateAsOf(hist, DateTime(2026, 9, 30), d('755')), d('695'));
    });

    test('on and after the effective date pays the new rate', () {
      expect(roleRateAsOf(hist, DateTime(2026, 10, 1), d('755')), d('755'));
      expect(roleRateAsOf(hist, DateTime(2026, 12, 1), d('755')), d('755'));
    });

    test('latest effective change wins; same-day ties go to newest created',
        () {
      final h = [
        rr('a', DateTime(2026, 10, 1), '695', '7550',
            created: DateTime(2026, 9, 1)),
        rr('b', DateTime(2026, 10, 1), '7550', '755',
            created: DateTime(2026, 9, 2)),
      ];
      expect(roleRateAsOf(h, DateTime(2026, 10, 5), d('755')), d('755'));
    });

    test('a first change with no prev falls back to the stored base', () {
      final h = [rr('a', DateTime(2026, 10, 1), null, '755')];
      expect(roleRateAsOf(h, DateTime(2026, 9, 1), d('755')), d('755'));
    });
  });

  group('proratedDailyRateOverride with role rate history', () {
    final hist = [rr('a', DateTime(2026, 9, 16), '695', '755')];

    Decimal? at(DateTime day, {List<CompensationChange> comp = const []}) =>
        proratedDailyRateOverride(
          comp: comp,
          attendanceDate: day,
          periodEnd: DateTime(2026, 9, 30),
          scorecardBaseSalary: d('755'),
          scorecardWageType: 'DAILY',
          workDaysPerMonth: 26,
          hoursPerDay: 8,
          roleRates: hist,
        );

    test('role-default employee: days before the change pay the old rate', () {
      expect(at(DateTime(2026, 9, 10)), d('695'));
    });

    test('role-default employee: days in the period-end regime need no '
        'override', () {
      expect(at(DateTime(2026, 9, 20)), isNull);
    });

    test('employee with their own record ignores the role rate', () {
      final own = CompensationChange(
        id: 'x',
        companyId: 'c',
        employeeId: 'e',
        changeType: 'SALARY_INCREASE',
        status: 'APPLIED',
        effectiveDate: DateTime(2026, 1, 1),
        prevBaseSalary: d('695'),
        newBaseSalary: d('800'),
        prevWageType: 'DAILY',
        newWageType: 'DAILY',
        initiatedById: 'u',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(at(DateTime(2026, 9, 10), comp: [own]), isNull);
    });
  });
}
