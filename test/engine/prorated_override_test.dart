import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/compensation_change.dart';
import 'package:payroll_flutter/features/payroll/engine/daily_rate.dart';

Decimal _d(String s) => Decimal.parse(s);

CompensationChange _change({
  required String id,
  required String effective,
  required String newSalary,
  String status = 'SCHEDULED',
  String wageType = 'MONTHLY',
  String created = '2026-07-01T00:00:00Z',
}) =>
    CompensationChange(
      id: id,
      companyId: 'CO1',
      employeeId: 'E1',
      changeType: 'SALARY_INCREASE',
      status: status,
      effectiveDate: DateTime.parse(effective),
      prevBaseSalary: _d('30000'),
      newBaseSalary: _d(newSalary),
      newWageType: wageType,
      initiatedById: 'U1',
      createdAt: DateTime.parse(created),
    );

Decimal? _resolve(List<CompensationChange> comp, String day) =>
    proratedDailyRateOverride(
      comp: comp,
      attendanceDate: DateTime.parse(day),
      periodEnd: DateTime.parse('2026-07-31'),
      scorecardBaseSalary: _d('30000'),
      scorecardWageType: 'MONTHLY',
      workDaysPerMonth: 26,
      hoursPerDay: 8,
    );

void main() {
  final raise = [_change(id: 'C1', effective: '2026-07-17', newSalary: '38000')];

  test('no compensation rows -> null on every day (invariant 2)', () {
    expect(_resolve(const [], '2026-07-05'), isNull);
    expect(_resolve(const [], '2026-07-31'), isNull);
  });

  test('day BEFORE the effective date overrides down to the old scorecard rate', () {
    final r = _resolve(raise, '2026-07-16');
    expect(r, isNotNull);
    expect(
      r,
      dailyRateFrom(
        baseSalary: _d('30000'),
        wageType: 'MONTHLY',
        workDaysPerMonth: 26,
        hoursPerDay: 8,
      ),
    );
  });

  test('the effective date itself uses the new rate -> null (matches standard)', () {
    // periodEnd resolves to C1 too, so the day is in the same regime.
    expect(_resolve(raise, '2026-07-17'), isNull);
  });

  test('day AFTER the effective date -> null (same regime as period end)', () {
    expect(_resolve(raise, '2026-07-31'), isNull);
  });

  test('CANCELLED change is ignored -> null everywhere', () {
    final cancelled = [
      _change(id: 'C1', effective: '2026-07-17', newSalary: '38000', status: 'CANCELLED'),
    ];
    expect(_resolve(cancelled, '2026-07-05'), isNull);
    expect(_resolve(cancelled, '2026-07-31'), isNull);
  });

  test('two changes in one period: each day resolves to its own regime', () {
    final comp = [
      _change(id: 'C1', effective: '2026-07-10', newSalary: '34000'),
      _change(id: 'C2', effective: '2026-07-20', newSalary: '38000'),
    ];
    // Before any change -> scorecard rate.
    expect(
      _resolve(comp, '2026-07-05'),
      dailyRateFrom(baseSalary: _d('30000'), wageType: 'MONTHLY', workDaysPerMonth: 26, hoursPerDay: 8),
    );
    // Between C1 and C2 -> C1's rate.
    expect(
      _resolve(comp, '2026-07-15'),
      dailyRateFrom(baseSalary: _d('34000'), wageType: 'MONTHLY', workDaysPerMonth: 26, hoursPerDay: 8),
    );
    // On/after C2 -> same regime as period end -> null.
    expect(_resolve(comp, '2026-07-25'), isNull);
  });
}
