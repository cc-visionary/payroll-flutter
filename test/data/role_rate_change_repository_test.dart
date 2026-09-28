import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/compensation_change.dart';
import 'package:payroll_flutter/data/models/role_rate_change.dart';
import 'package:payroll_flutter/data/repositories/role_rate_change_repository.dart';

void main() {
  test('only employees without their own pay record are role-default', () {
    final own = CompensationChange(
      id: 'x',
      companyId: 'c',
      employeeId: 'raised',
      changeType: 'SALARY_INCREASE',
      status: 'APPLIED',
      effectiveDate: DateTime(2026, 1, 1),
      newBaseSalary: Decimal.parse('720'),
      initiatedById: 'u',
      createdAt: DateTime(2026, 1, 1),
    );
    final future = CompensationChange(
      id: 'y',
      companyId: 'c',
      employeeId: 'later',
      changeType: 'SALARY_INCREASE',
      status: 'SCHEDULED',
      effectiveDate: DateTime(2027, 1, 1),
      newBaseSalary: Decimal.parse('800'),
      initiatedById: 'u',
      createdAt: DateTime(2026, 1, 1),
    );
    expect(
      roleDefaultEmployeeIds(
        employeeIds: ['plain', 'raised', 'later'],
        compByEmployee: {
          'raised': [own],
          'later': [future],
        },
        asOf: DateTime(2026, 10, 1),
      ),
      ['plain', 'later'],
    );
  });

  test('latestRoleRate is the newest by effective date, not by insert', () {
    RoleRateChange c(String id, DateTime eff, String rate, DateTime created) =>
        RoleRateChange(
          id: id,
          companyId: 'c',
          roleScorecardId: 'card',
          effectiveDate: eff,
          newBaseSalary: Decimal.parse(rate),
          createdAt: created,
        );
    expect(
      latestRoleRate([
        c('a', DateTime(2027, 1, 1), '800', DateTime(2026, 9, 1)),
        c('b', DateTime(2026, 10, 1), '755', DateTime(2026, 9, 2)),
      ]),
      Decimal.parse('800'),
    );
  });
}
