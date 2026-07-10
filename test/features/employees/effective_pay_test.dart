import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/compensation_change.dart';
import 'package:payroll_flutter/features/employees/profile/effective_pay.dart';

Decimal _d(String s) => Decimal.parse(s);

CompensationChange _change({
  required String id,
  required String effective,
  String status = 'APPLIED',
  Decimal? newSalary,
  String? newWageType,
  Decimal? prevSalary,
  String? prevWageType,
}) =>
    CompensationChange(
      id: id,
      companyId: 'CO1',
      employeeId: 'E1',
      changeType: 'SALARY_INCREASE',
      status: status,
      effectiveDate: DateTime.parse(effective),
      prevBaseSalary: prevSalary,
      newBaseSalary: newSalary,
      prevWageType: prevWageType,
      newWageType: newWageType,
      initiatedById: 'U1',
      createdAt: DateTime.parse('2026-07-01T00:00:00Z'),
    );

DisplayPay _resolve(List<CompensationChange> changes, String asOf) => displayPayFor(
      changes: changes,
      asOf: DateTime.parse(asOf),
      scorecardBaseSalary: _d('1184.61'),
      scorecardWageType: 'DAILY',
    );

void main() {
  group('displayPayFor', () {
    test('no compensation records -> the role scorecard is the default', () {
      final pay = _resolve(const [], '2026-07-20');
      expect(pay.baseSalary, _d('1184.61'));
      expect(pay.wageType, 'DAILY');
      expect(pay.fromCompensationRecord, isFalse);
    });

    test('an effective record wins over the scorecard', () {
      final pay = _resolve([
        _change(id: 'C1', effective: '2026-07-01', newSalary: _d('1400'), newWageType: 'DAILY'),
      ], '2026-07-20');
      expect(pay.baseSalary, _d('1400'));
      expect(pay.wageType, 'DAILY');
      expect(pay.fromCompensationRecord, isTrue);
    });

    test('two employees on one scorecard can differ: only the adjusted one moves', () {
      // Alice has a record; Bob has none. Same scorecard inputs.
      final alice = _resolve([
        _change(id: 'C1', effective: '2026-07-01', newSalary: _d('1400'), newWageType: 'DAILY'),
      ], '2026-07-20');
      final bob = _resolve(const [], '2026-07-20');

      expect(alice.baseSalary, _d('1400'));
      expect(bob.baseSalary, _d('1184.61'));
      expect(alice.baseSalary, isNot(bob.baseSalary));
    });

    test('a future-dated record is NOT yet shown', () {
      final pay = _resolve([
        _change(id: 'C1', effective: '2026-08-01', newSalary: _d('1400')),
      ], '2026-07-20');
      expect(pay.baseSalary, _d('1184.61'));
      expect(pay.fromCompensationRecord, isFalse);
    });

    test('a CANCELLED record is ignored', () {
      final pay = _resolve([
        _change(id: 'C1', effective: '2026-07-01', newSalary: _d('1400'), status: 'CANCELLED'),
      ], '2026-07-20');
      expect(pay.baseSalary, _d('1184.61'));
      expect(pay.fromCompensationRecord, isFalse);
    });

    test('a role-only record (null newBaseSalary) carries prevBaseSalary forward', () {
      final pay = _resolve([
        _change(
          id: 'C1',
          effective: '2026-07-01',
          prevSalary: _d('1300'),
          prevWageType: 'DAILY',
        ),
      ], '2026-07-20');
      expect(pay.baseSalary, _d('1300'));
      expect(pay.wageType, 'DAILY');
      expect(pay.fromCompensationRecord, isTrue);
    });
  });
}
