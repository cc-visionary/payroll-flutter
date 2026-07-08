import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/compensation_change.dart';

void main() {
  group('CompensationChange.fromRow', () {
    test('parses a full row', () {
      final c = CompensationChange.fromRow({
        'id': 'C1',
        'company_id': 'CO1',
        'employee_id': 'E1',
        'change_type': 'PROMOTION',
        'status': 'SCHEDULED',
        'effective_date': '2026-08-01',
        'prev_base_salary': '30000.00',
        'new_base_salary': '38000.00',
        'prev_wage_type': 'MONTHLY',
        'new_wage_type': 'MONTHLY',
        'prev_scorecard_id': 'S1',
        'new_scorecard_id': 'S2',
        'reason': 'Merit + role move',
        'workflow_id': 'W1',
        'document_id': 'D1',
        'initiated_by_id': 'U1',
        'applied_at': null,
        'created_at': '2026-07-08T00:00:00Z',
        'deleted_at': null,
      });
      expect(c.changeType, 'PROMOTION');
      expect(c.newBaseSalary, Decimal.parse('38000.00'));
      expect(c.effectiveDate, DateTime.parse('2026-08-01'));
      expect(c.isRoleChange, isTrue);
    });

    test('isRoleChange is false when scorecard unchanged', () {
      final c = CompensationChange.fromRow({
        'id': 'C2', 'company_id': 'CO1', 'employee_id': 'E1',
        'change_type': 'SALARY_INCREASE', 'status': 'SCHEDULED',
        'effective_date': '2026-08-01',
        'prev_scorecard_id': 'S1', 'new_scorecard_id': 'S1',
        'initiated_by_id': 'U1', 'created_at': '2026-07-08T00:00:00Z',
      });
      expect(c.isRoleChange, isFalse);
    });
  });
}
