import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/compensation_change.dart';
import 'package:payroll_flutter/features/payroll/engine/effective_compensation.dart';

CompensationChange _c({
  required String id,
  required String effective,
  String status = 'SCHEDULED',
  String created = '2026-07-08T00:00:00Z',
  bool deleted = false,
}) =>
    CompensationChange(
      id: id,
      companyId: 'CO1',
      employeeId: 'E1',
      changeType: 'SALARY_INCREASE',
      status: status,
      effectiveDate: DateTime.parse(effective),
      initiatedById: 'U1',
      createdAt: DateTime.parse(created),
      deletedAt: deleted ? DateTime.parse('2026-07-09T00:00:00Z') : null,
    );

void main() {
  group('effectiveCompensation', () {
    test('empty list returns null (scorecard fallback)', () {
      expect(effectiveCompensation(const [], DateTime.parse('2026-08-01')), isNull);
    });

    test('future-dated row is not yet effective', () {
      final rows = [_c(id: 'A', effective: '2026-09-01')];
      expect(effectiveCompensation(rows, DateTime.parse('2026-08-15')), isNull);
    });

    test('picks the latest effective_date at or before asOf', () {
      final rows = [
        _c(id: 'A', effective: '2026-06-01'),
        _c(id: 'B', effective: '2026-08-01'),
        _c(id: 'C', effective: '2026-10-01'),
      ];
      expect(effectiveCompensation(rows, DateTime.parse('2026-08-15'))!.id, 'B');
    });

    test('effective_date exactly equal to asOf qualifies', () {
      final rows = [_c(id: 'A', effective: '2026-08-01')];
      expect(effectiveCompensation(rows, DateTime.parse('2026-08-01'))!.id, 'A');
    });

    test('CANCELLED and soft-deleted rows are ignored', () {
      final rows = [
        _c(id: 'A', effective: '2026-08-01', status: 'CANCELLED'),
        _c(id: 'B', effective: '2026-07-01', deleted: true),
        _c(id: 'C', effective: '2026-06-01'),
      ];
      expect(effectiveCompensation(rows, DateTime.parse('2026-08-15'))!.id, 'C');
    });

    test('APPLIED rows count', () {
      final rows = [_c(id: 'A', effective: '2026-08-01', status: 'APPLIED')];
      expect(effectiveCompensation(rows, DateTime.parse('2026-08-15'))!.id, 'A');
    });

    test('same effective_date tie-breaks on newest created_at', () {
      final rows = [
        _c(id: 'OLD', effective: '2026-08-01', created: '2026-07-01T00:00:00Z'),
        _c(id: 'NEW', effective: '2026-08-01', created: '2026-07-05T00:00:00Z'),
      ];
      expect(effectiveCompensation(rows, DateTime.parse('2026-08-15'))!.id, 'NEW');
    });
  });
}
