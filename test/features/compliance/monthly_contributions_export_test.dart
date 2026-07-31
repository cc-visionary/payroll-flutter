import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/compliance/monthly_contributions_export.dart';

Decimal _d(String s) => Decimal.parse(s);

void main() {
  group('declaredMonthlySalary', () {
    test('DAILY override: 600 x 26 = 15600.00', () {
      final v = declaredMonthlySalary(
        declaredWageOverride: _d('600'),
        declaredWageType: 'DAILY',
        scorecardBaseSalary: _d('900'),
        scorecardWageType: 'DAILY',
      );
      expect(v, _d('15600.00'));
    });

    test('HOURLY override: 100 x 8h x 26 = 20800.00', () {
      final v = declaredMonthlySalary(
        declaredWageOverride: _d('100'),
        declaredWageType: 'HOURLY',
        scorecardBaseSalary: _d('900'),
        scorecardWageType: 'DAILY',
        workHoursPerDay: 8,
      );
      expect(v, _d('20800.00'));
    });

    test('MONTHLY override round-trips to itself', () {
      final v = declaredMonthlySalary(
        declaredWageOverride: _d('25000'),
        declaredWageType: 'MONTHLY',
        scorecardBaseSalary: _d('900'),
        scorecardWageType: 'DAILY',
      );
      expect(v, _d('25000.00'));
    });

    test('no override falls back to scorecard rate', () {
      final v = declaredMonthlySalary(
        declaredWageOverride: null,
        declaredWageType: null,
        scorecardBaseSalary: _d('645'),
        scorecardWageType: 'DAILY',
      );
      expect(v, _d('16770.00'));
    });

    test('override amount without type falls back to scorecard', () {
      final v = declaredMonthlySalary(
        declaredWageOverride: _d('600'),
        declaredWageType: null,
        scorecardBaseSalary: _d('645'),
        scorecardWageType: 'DAILY',
      );
      expect(v, _d('16770.00'));
    });

    test('zero override falls back to scorecard', () {
      final v = declaredMonthlySalary(
        declaredWageOverride: Decimal.zero,
        declaredWageType: 'DAILY',
        scorecardBaseSalary: _d('645'),
        scorecardWageType: 'DAILY',
      );
      expect(v, _d('16770.00'));
    });

    test('no override, no scorecard -> zero', () {
      final v = declaredMonthlySalary(
        declaredWageOverride: null,
        declaredWageType: null,
        scorecardBaseSalary: null,
        scorecardWageType: null,
      );
      expect(v, _d('0.00'));
    });

    test('unknown wage type string treated as DAILY', () {
      final v = declaredMonthlySalary(
        declaredWageOverride: _d('600'),
        declaredWageType: 'WEEKLY',
        scorecardBaseSalary: null,
        scorecardWageType: null,
      );
      expect(v, _d('15600.00'));
    });
  });

  group('MonthlyContributionRow totals', () {
    test('totalEe includes withholding tax; totalEr does not', () {
      final row = MonthlyContributionRow(
        employee: MonthlyContributionEmployee(
          employeeId: 'e1',
          employeeNumber: 'LX-001',
          firstName: 'Juan',
          lastName: 'Dela Cruz',
          monthlySalary: _d('15600.00'),
        ),
        sssEe: _d('500'),
        sssEr: _d('1000'),
        philhealthEe: _d('250'),
        philhealthEr: _d('250'),
        pagibigEe: _d('100'),
        pagibigEr: _d('100'),
        withholdingTax: _d('50'),
      );
      expect(row.totalEe, _d('900'));
      expect(row.totalEr, _d('1350'));
      expect(row.total, _d('2250'));
    });
  });
}
