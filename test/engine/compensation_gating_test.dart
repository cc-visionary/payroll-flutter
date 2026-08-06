import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/compensation_change.dart';
import 'package:payroll_flutter/features/payroll/engine/effective_compensation.dart';

CompensationChange _raise(String effective, String newSalary) =>
    CompensationChange(
      id: 'R-$effective',
      companyId: 'CO1',
      employeeId: 'E1',
      changeType: 'SALARY_INCREASE',
      status: 'SCHEDULED',
      effectiveDate: DateTime.parse(effective),
      prevBaseSalary: Decimal.parse('30000'),
      newBaseSalary: Decimal.parse(newSalary),
      newWageType: 'MONTHLY',
      initiatedById: 'U1',
      createdAt: DateTime.parse('2026-07-08T00:00:00Z'),
    );

void main() {
  final changes = [_raise('2026-09-01', '38000')];

  test('a raise dated 2026-09-01 does not affect an August period', () {
    // Period end 2026-08-31 -> no effective row -> caller uses scorecard.
    final r = effectiveCompensation(changes, DateTime.parse('2026-08-31'));
    expect(r, isNull);
  });

  test('the same raise applies to the September period', () {
    final r = effectiveCompensation(changes, DateTime.parse('2026-09-30'));
    expect(r, isNotNull);
    expect(r!.newBaseSalary, Decimal.parse('38000'));
    expect(r.newWageType, 'MONTHLY');
  });
}
