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

/// Like [_change], but leaves `newBaseSalary`/`newWageType` unset so the
/// fallback-to-`prev*` path can be exercised (e.g. a role-only change).
CompensationChange _roleOnlyChange({
  required String id,
  required String effective,
  required String prevSalary,
  String status = 'SCHEDULED',
  String? prevWageType = 'MONTHLY',
  String created = '2026-07-01T00:00:00Z',
}) =>
    CompensationChange(
      id: id,
      companyId: 'CO1',
      employeeId: 'E1',
      changeType: 'LATERAL_TRANSFER',
      status: status,
      effectiveDate: DateTime.parse(effective),
      prevBaseSalary: _d(prevSalary),
      newBaseSalary: null,
      prevWageType: prevWageType,
      newWageType: null,
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
    expect(_resolve(raise, '2026-07-20'), isNull);
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

  test('null newBaseSalary carries forward prevBaseSalary, not the scorecard rate', () {
    final comp = [
      _roleOnlyChange(id: 'C1', effective: '2026-07-10', prevSalary: '34000'),
      _change(id: 'C2', effective: '2026-07-20', newSalary: '38000'),
    ];
    // Between C1 and C2 -> C1's regime, but C1.newBaseSalary is null, so this
    // must resolve to C1.prevBaseSalary (34000), NOT scorecardBaseSalary
    // (30000) -- the two differ so the assertion actually discriminates.
    final r = _resolve(comp, '2026-07-15');
    expect(r, isNotNull);
    expect(
      r,
      dailyRateFrom(
        baseSalary: _d('34000'),
        wageType: 'MONTHLY',
        workDaysPerMonth: 26,
        hoursPerDay: 8,
      ),
    );
  });

  test("DAILY wage-type change passes through the change's own wage type, not the scorecard's", () {
    final comp = [
      _change(id: 'C1', effective: '2026-07-10', newSalary: '1500', wageType: 'DAILY'),
      _change(id: 'C2', effective: '2026-07-20', newSalary: '38000'),
    ];
    // scorecardWageType is 'MONTHLY' (per _resolve), so if the wage type were
    // wrongly taken from the scorecard this would come back as 1500/26
    // instead of 1500 flat.
    final r = _resolve(comp, '2026-07-15');
    expect(r, isNotNull);
    expect(
      r,
      dailyRateFrom(
        baseSalary: _d('1500'),
        wageType: 'DAILY',
        workDaysPerMonth: 26,
        hoursPerDay: 8,
      ),
    );
  });

  test('null newWageType carries forward prevWageType, not the scorecard wage type', () {
    final comp = [
      // Role-only change: both new* fields null, so the wage type in force is
      // carried from prevWageType ('DAILY'), not the scorecard's 'MONTHLY'.
      _roleOnlyChange(
        id: 'C1',
        effective: '2026-07-10',
        prevSalary: '34000',
        prevWageType: 'DAILY',
      ),
      // Later change so periodEnd (2026-07-31) resolves to C2, a DIFFERENT id
      // than the day's C1 -> the identity check passes and the fallback runs.
      _change(id: 'C2', effective: '2026-07-20', newSalary: '38000'),
    ];
    // Between C1 and C2 -> C1's regime. C1 has newWageType == null, so the wage
    // type must fall back to prevWageType 'DAILY' (flat 34000). If the fallback
    // regressed to scorecardWageType 'MONTHLY', this would be 34000/26.
    final r = _resolve(comp, '2026-07-15');
    expect(r, isNotNull);
    expect(
      r,
      dailyRateFrom(
        baseSalary: _d('34000'),
        wageType: 'DAILY',
        workDaysPerMonth: 26,
        hoursPerDay: 8,
      ),
    );
  });

  test('role change: pre-change day uses prevBaseSalary, not the repointed scorecard', () {
    // A mid-period PROMOTION moves the role, so applyDue repoints
    // employees.role_scorecard_id to the NEW scorecard BEFORE the employees
    // select. The joined scorecard therefore already reads the NEW salary
    // (45000). A pre-change day must NOT inherit that -- it must use the
    // prevBaseSalary (30000) captured on the change row.
    final comp = [
      CompensationChange(
        id: 'C1',
        companyId: 'CO1',
        employeeId: 'E1',
        changeType: 'PROMOTION',
        status: 'SCHEDULED',
        effectiveDate: DateTime.parse('2026-07-17'),
        prevBaseSalary: _d('30000'),
        newBaseSalary: _d('45000'),
        prevWageType: 'MONTHLY',
        newWageType: 'MONTHLY',
        prevScorecardId: 'S1',
        newScorecardId: 'S2',
        initiatedById: 'U1',
        createdAt: DateTime.parse('2026-07-01T00:00:00Z'),
      ),
    ];
    // Day precedes the change -> dayEff == null. scorecardBaseSalary is 45000,
    // simulating the already-repointed NEW scorecard.
    final r = proratedDailyRateOverride(
      comp: comp,
      attendanceDate: DateTime.parse('2026-07-10'),
      periodEnd: DateTime.parse('2026-07-31'),
      scorecardBaseSalary: _d('45000'),
      scorecardWageType: 'MONTHLY',
      workDaysPerMonth: 26,
      hoursPerDay: 8,
    );
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

  test('pre-change day with multiple changes uses the EARLIEST change prevBaseSalary', () {
    // Two qualifying changes; a day that precedes BOTH must take the baseline
    // from the EARLIEST change's prevBaseSalary (30000), not the latest change's
    // prev (34000) and not the repointed scorecard (45000).
    final comp = [
      // Listed newest-first to prove ordering is by value, not list position.
      CompensationChange(
        id: 'C2',
        companyId: 'CO1',
        employeeId: 'E1',
        changeType: 'PROMOTION',
        status: 'SCHEDULED',
        effectiveDate: DateTime.parse('2026-07-17'),
        prevBaseSalary: _d('34000'),
        newBaseSalary: _d('45000'),
        prevWageType: 'MONTHLY',
        newWageType: 'MONTHLY',
        prevScorecardId: 'S1',
        newScorecardId: 'S2',
        initiatedById: 'U1',
        createdAt: DateTime.parse('2026-07-01T00:00:00Z'),
      ),
      CompensationChange(
        id: 'C1',
        companyId: 'CO1',
        employeeId: 'E1',
        changeType: 'SALARY_INCREASE',
        status: 'SCHEDULED',
        effectiveDate: DateTime.parse('2026-07-05'),
        prevBaseSalary: _d('30000'),
        newBaseSalary: _d('34000'),
        prevWageType: 'MONTHLY',
        newWageType: 'MONTHLY',
        initiatedById: 'U1',
        createdAt: DateTime.parse('2026-07-01T00:00:00Z'),
      ),
    ];
    final r = proratedDailyRateOverride(
      comp: comp,
      attendanceDate: DateTime.parse('2026-07-01'),
      periodEnd: DateTime.parse('2026-07-31'),
      scorecardBaseSalary: _d('45000'),
      scorecardWageType: 'MONTHLY',
      workDaysPerMonth: 26,
      hoursPerDay: 8,
    );
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
}
