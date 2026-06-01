import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/check_in_period.dart';

void main() {
  test('CheckInPeriod constructs with required fields', () {
    final p = CheckInPeriod(
      id: 'p1',
      companyId: 'c1',
      name: '2026 Q2',
      periodType: 'QUARTERLY',
      startDate: DateTime.utc(2026, 4, 1),
      endDate: DateTime.utc(2026, 6, 30),
      dueDate: DateTime.utc(2026, 7, 15),
      isActive: true,
      createdAt: DateTime.utc(2026, 4, 1),
      updatedAt: DateTime.utc(2026, 4, 1),
    );
    expect(p.id, 'p1');
    expect(p.periodType, 'QUARTERLY');
    expect(p.targetEmployeeId, isNull);
  });

  test('CheckInPeriod.fromRow parses all columns including target_employee_id', () {
    final r = <String, dynamic>{
      'id': 'p2',
      'company_id': 'c1',
      'name': 'Probation 1M — Maria Santos',
      'period_type': 'PROBATION_1M',
      'start_date': '2026-04-15',
      'end_date': '2026-05-01',
      'due_date': '2026-05-08',
      'is_active': true,
      'target_employee_id': 'e1',
      'created_at': '2026-04-01T00:00:00Z',
      'updated_at': '2026-04-01T00:00:00Z',
    };
    final p = CheckInPeriodFromRow.fromRow(r);
    expect(p.id, 'p2');
    expect(p.periodType, 'PROBATION_1M');
    expect(p.targetEmployeeId, 'e1');
    expect(p.startDate, DateTime.parse('2026-04-15'));
  });
}
