import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/statutory_payable.dart';
import 'package:payroll_flutter/features/compliance/monthly_contributions_export.dart';

Decimal _d(String s) => Decimal.parse(s);

void main() {
  // ignore: no_leading_underscores_for_local_identifiers
  StatutoryPayableBreakdownRow _b({
    required String empId,
    required StatutoryAgency agency,
    required String ee,
    String er = '0',
  }) =>
      StatutoryPayableBreakdownRow(
        hiringEntityId: 'brand-1',
        periodYear: 2026,
        periodMonth: 7,
        agency: agency,
        employeeId: empId,
        eeShare: _d(ee),
        erShare: _d(er),
        totalAmount: _d(ee) + _d(er),
      );

  // ignore: no_leading_underscores_for_local_identifiers
  MonthlyContributionEmployee _emp(String id, String last, String first) =>
      MonthlyContributionEmployee(
        employeeId: id,
        employeeNumber: 'LX-$id',
        firstName: first,
        lastName: last,
        monthlySalary: _d('15600.00'),
      );

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

  group('buildMonthlyContributionRows', () {
    test('groups agencies into one row per employee, sorted by name', () {
      final rows = buildMonthlyContributionRows(
        breakdown: [
          _b(empId: 'e2', agency: StatutoryAgency.sssContribution, ee: '450', er: '900'),
          _b(empId: 'e1', agency: StatutoryAgency.sssContribution, ee: '500', er: '1000'),
          _b(empId: 'e1', agency: StatutoryAgency.philhealthContribution, ee: '250', er: '250'),
          _b(empId: 'e1', agency: StatutoryAgency.pagibigContribution, ee: '100', er: '100'),
          _b(empId: 'e1', agency: StatutoryAgency.birWithholding, ee: '75'),
        ],
        employeesById: {
          'e1': _emp('e1', 'Alonzo', 'Ana'),
          'e2': _emp('e2', 'Bautista', 'Ben'),
        },
      );
      expect(rows, hasLength(2));
      expect(rows[0].employee.lastName, 'Alonzo');
      expect(rows[0].sssEe, _d('500'));
      expect(rows[0].sssEr, _d('1000'));
      expect(rows[0].philhealthEe, _d('250'));
      expect(rows[0].pagibigEr, _d('100'));
      expect(rows[0].withholdingTax, _d('75'));
      // e2 has no PhilHealth/Pag-IBIG/BIR rows -> zeros.
      expect(rows[1].employee.lastName, 'Bautista');
      expect(rows[1].philhealthEe, Decimal.zero);
      expect(rows[1].withholdingTax, Decimal.zero);
    });

    test('excludes employee loans', () {
      final rows = buildMonthlyContributionRows(
        breakdown: [
          _b(empId: 'e1', agency: StatutoryAgency.sssContribution, ee: '500', er: '1000'),
          _b(empId: 'e1', agency: StatutoryAgency.employeeLoan, ee: '2000'),
        ],
        employeesById: {'e1': _emp('e1', 'Alonzo', 'Ana')},
      );
      expect(rows, hasLength(1));
      expect(rows[0].totalEe, _d('500'));
      expect(rows[0].total, _d('1500'));
    });

    test('unknown employee id keeps the money with placeholder meta', () {
      final rows = buildMonthlyContributionRows(
        breakdown: [
          _b(empId: 'ghost', agency: StatutoryAgency.sssContribution, ee: '500', er: '1000'),
        ],
        employeesById: const {},
      );
      expect(rows, hasLength(1));
      expect(rows[0].employee.lastName, '');
      expect(rows[0].employee.monthlySalary, Decimal.zero);
      expect(rows[0].sssEe, _d('500'));
    });
  });

  group('buildRemittanceStatusLines', () {
    test('four agencies in order with due sums and paid matching', () {
      final rows = buildMonthlyContributionRows(
        breakdown: [
          _b(empId: 'e1', agency: StatutoryAgency.sssContribution, ee: '500', er: '1000'),
          _b(empId: 'e1', agency: StatutoryAgency.philhealthContribution, ee: '250', er: '250'),
        ],
        employeesById: {'e1': _emp('e1', 'Alonzo', 'Ana')},
      );
      final lines = buildRemittanceStatusLines(
        rows: rows,
        paidSummaries: [
          StatutoryPaymentSummary(
            hiringEntityId: 'brand-1',
            periodYear: 2026,
            periodMonth: 7,
            agency: StatutoryAgency.sssContribution,
            amountPaid: _d('1500'),
            paymentCount: 1,
            lastPaidOn: DateTime(2026, 7, 10),
          ),
        ],
      );
      expect(lines, hasLength(4));
      expect(lines[0].agency, StatutoryAgency.sssContribution);
      expect(lines[0].due, _d('1500'));
      expect(lines[0].paid, _d('1500'));
      expect(lines[0].status, PayableStatus.paid);
      expect(lines[0].lastPaidOn, DateTime(2026, 7, 10));
      expect(lines[1].agency, StatutoryAgency.philhealthContribution);
      expect(lines[1].status, PayableStatus.unpaid);
      // Pag-IBIG and BIR have zero due -> status null.
      expect(lines[2].agency, StatutoryAgency.pagibigContribution);
      expect(lines[2].status, isNull);
      expect(lines[3].agency, StatutoryAgency.birWithholding);
      expect(lines[3].status, isNull);
    });
  });
}
