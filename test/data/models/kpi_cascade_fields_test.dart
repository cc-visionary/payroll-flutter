import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/kpi.dart';

void main() {
  test('reads the cascade fields off a row', () {
    final k = Kpi.fromRow({
      'id': 'k1',
      'company_id': 'c1',
      'name': 'Fulfillment Accuracy',
      'level': 'DEPARTMENT',
      'parent_kpi_id': 'k-company',
      'rollup_type': 'DIRECT',
      'data_method': 'HYBRID',
    });
    expect(k.level, 'DEPARTMENT');
    expect(k.parentKpiId, 'k-company');
    expect(k.rollupType, 'DIRECT');
    expect(k.dataMethod, 'HYBRID');
  });

  test('a row predating the migration falls back to sane defaults', () {
    // A narrowed select, or a client running before the migration lands,
    // must not throw. Same reason the measurable columns are defaulted.
    final k = Kpi.fromRow({'id': 'k1', 'company_id': 'c1', 'name': 'Old'});
    expect(k.level, 'PERSONAL');
    expect(k.rollupType, 'INDEPENDENT');
    expect(k.dataMethod, 'MANUAL_PERIODIC');
    expect(k.parentKpiId, isNull);
  });

  test('the defaults are the conservative ones', () {
    // INDEPENDENT means "compute only my own level" and MANUAL_PERIODIC means
    // "nobody claims this is automatic". An unconfigured KPI must not claim to
    // roll up into a company number or to be automatically sourced.
    expect(kKpiRollupTypes.first, 'DIRECT');
    expect(kKpiRollupTypes, contains('INDEPENDENT'));
    expect(kKpiDataMethods, contains('MANUAL_PERIODIC'));
    expect(kKpiLevels, ['PERSONAL', 'DEPARTMENT', 'COMPANY']);
  });

  test('toInsert carries the cascade fields', () {
    const k = Kpi(
      id: 'k1',
      companyId: 'c1',
      name: 'Case SLA',
      level: 'DEPARTMENT',
      parentKpiId: 'k0',
      rollupType: 'ALIGNED',
      dataMethod: 'AUTOMATIC',
    );
    final row = k.toInsert('c1');
    expect(row['level'], 'DEPARTMENT');
    expect(row['parent_kpi_id'], 'k0');
    expect(row['rollup_type'], 'ALIGNED');
    expect(row['data_method'], 'AUTOMATIC');
  });
}
