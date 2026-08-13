import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/kpi_goal.dart';
import 'package:payroll_flutter/data/models/kpi_result.dart';

void main() {
  test('round-trips a personal row', () {
    final r = KpiResult.fromRow({
      'id': 'res-1',
      'company_id': 'c',
      'kpi_id': 'k-1',
      'period': '2026-08',
      'scope': 'PERSONAL',
      'employee_id': 'e-1',
      'department_id': null,
      'numerator': 398,
      'denominator': 400,
      'value': 0.995,
      'target_snapshot': 0.99,
      'target_max_snapshot': null,
      'direction_snapshot': 'GTE',
      'status': 'ON_TRACK',
      'source_completeness': 'COMPLETE',
    });
    expect(r.scope, KpiScope.personal);
    expect(r.status, KpiStatus.onTrack);
    expect(r.direction, GoalDirection.gte);
    expect(r.employeeId, 'e-1');

    final p = r.toUpsertPayload();
    expect(p['scope'], 'PERSONAL');
    expect(p['status'], 'ON_TRACK');
    expect(p['direction_snapshot'], 'GTE');
    expect(p['numerator'], 398);
  });

  test('a NO_DATA row keeps its nulls rather than defaulting to zero', () {
    // Writing 0 here would turn "we do not know" into "it was nothing",
    // which is the same lie the status rule exists to prevent.
    final r = KpiResult.fromRow({
      'id': 'res-2',
      'company_id': 'c',
      'kpi_id': 'k-1',
      'period': '2026-08',
      'scope': 'COMPANY',
      'numerator': null,
      'denominator': null,
      'value': null,
      'status': 'NO_DATA',
      'source_completeness': 'MISSING_SOURCE',
    });
    expect(r.value, isNull);
    expect(r.numerator, isNull);
    expect(r.status, KpiStatus.noData);
    expect(r.sourceCompleteness, SourceCompleteness.missingSource);
    expect(r.toUpsertPayload()['value'], isNull);
  });

  test('a company row carries neither employee nor department', () {
    final r = KpiResult.fromRow({
      'id': 'res-3',
      'company_id': 'c',
      'kpi_id': 'k-1',
      'period': '2026-08',
      'scope': 'COMPANY',
      'status': 'NO_DATA',
      'source_completeness': 'COMPLETE',
    });
    expect(r.employeeId, isNull);
    expect(r.departmentId, isNull);
  });
}
