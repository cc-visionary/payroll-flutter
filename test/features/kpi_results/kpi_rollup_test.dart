import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/kpi_result.dart';
import 'package:payroll_flutter/features/kpi_results/kpi_rollup.dart';

void main() {
  test('DIRECT from PERSONAL computes all three', () {
    expect(
      scopesFor(level: 'PERSONAL', rollupType: 'DIRECT'),
      {KpiScope.personal, KpiScope.department, KpiScope.company},
    );
  });

  test('SHARED never computes personal', () {
    // Critical Stockouts: the team owns it; blaming one person is unfair,
    // which is the entire reason SHARED exists.
    expect(
      scopesFor(level: 'DEPARTMENT', rollupType: 'SHARED'),
      {KpiScope.department, KpiScope.company},
    );
  });

  test('ALIGNED computes only its own level', () {
    expect(scopesFor(level: 'PERSONAL', rollupType: 'ALIGNED'),
        {KpiScope.personal});
    expect(scopesFor(level: 'DEPARTMENT', rollupType: 'ALIGNED'),
        {KpiScope.department});
  });

  test('INDEPENDENT computes only its own level', () {
    expect(scopesFor(level: 'COMPANY', rollupType: 'INDEPENDENT'),
        {KpiScope.company});
  });

  test('DIRECT from DEPARTMENT does not invent personal rows', () {
    // Rolling UP is meaningful; rolling DOWN is not. A department KPI has no
    // per-person decomposition just because it is direct.
    expect(
      scopesFor(level: 'DEPARTMENT', rollupType: 'DIRECT'),
      {KpiScope.department, KpiScope.company},
    );
  });

  test('DIRECT from COMPANY is company only', () {
    expect(scopesFor(level: 'COMPANY', rollupType: 'DIRECT'),
        {KpiScope.company});
  });

  test('an unknown roll-up type falls back to the level alone', () {
    // Safe direction: compute less, not more. A bad value must never fan a
    // KPI out across scopes nobody asked for.
    expect(scopesFor(level: 'PERSONAL', rollupType: 'NONSENSE'),
        {KpiScope.personal});
  });

  test('an unknown level with DIRECT produces no rows', () {
    // An unrecognised level computes nothing. If the function cannot tell
    // where a KPI belongs, the honest answer is no rows, visible as absence.
    expect(scopesFor(level: 'UNKNOWN', rollupType: 'DIRECT'), <KpiScope>{});
  });

  test('an unknown level with SHARED produces no rows', () {
    // An unrecognised level computes nothing, even for SHARED. We cannot
    // determine the floor without knowing the level.
    expect(scopesFor(level: 'GARBAGE', rollupType: 'SHARED'), <KpiScope>{});
  });
}
