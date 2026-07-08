import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/repositories/compensation_change_repository.dart';

void main() {
  group('buildCompensationChangeInsert', () {
    test('maps every field to its column', () {
      final p = buildCompensationChangeInsert(
        id: 'C1',
        companyId: 'CO1',
        employeeId: 'E1',
        changeType: 'PROMOTION',
        status: 'SCHEDULED',
        effectiveDate: DateTime.parse('2026-08-01'),
        prevBaseSalary: Decimal.parse('30000'),
        newBaseSalary: Decimal.parse('38000'),
        prevWageType: 'MONTHLY',
        newWageType: 'MONTHLY',
        prevScorecardId: 'S1',
        newScorecardId: 'S2',
        reason: 'Merit',
        initiatedById: 'U1',
      );
      expect(p['id'], 'C1');
      expect(p['change_type'], 'PROMOTION');
      expect(p['status'], 'SCHEDULED');
      expect(p['effective_date'], '2026-08-01'); // date only, no time
      expect(p['prev_base_salary'], '30000');
      expect(p['new_base_salary'], '38000');
      expect(p['new_scorecard_id'], 'S2');
      expect(p['reason'], 'Merit');
      expect(p['initiated_by_id'], 'U1');
    });

    test('null salaries/scorecards serialize as null, not "null"', () {
      final p = buildCompensationChangeInsert(
        id: 'C2', companyId: 'CO1', employeeId: 'E1',
        changeType: 'LATERAL_TRANSFER', status: 'SCHEDULED',
        effectiveDate: DateTime.parse('2026-08-01'),
        prevBaseSalary: null, newBaseSalary: null,
        prevWageType: null, newWageType: null,
        prevScorecardId: 'S1', newScorecardId: 'S2',
        reason: '', initiatedById: 'U1',
      );
      expect(p['prev_base_salary'], isNull);
      expect(p['new_base_salary'], isNull);
    });
  });
}
