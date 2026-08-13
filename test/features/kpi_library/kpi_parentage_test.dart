import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/kpi_library/kpi_parentage.dart';

void main() {
  const levels = {
    'p1': 'PERSONAL',
    'p2': 'PERSONAL',
    'd1': 'DEPARTMENT',
    'd2': 'DEPARTMENT',
    'c1': 'COMPANY',
  };
  String levelOf(String id) => levels[id]!;

  String? run(
    String kpiId,
    String parentId, {
    List<({String id, String? parentId})> kpis = const [],
  }) => kpiParentError(
    kpiId: kpiId,
    newParentId: parentId,
    kpis: kpis,
    levelOf: levelOf,
  );

  test('personal may serve department', () {
    expect(run('p1', 'd1'), isNull);
  });

  test('department may serve company', () {
    expect(run('d1', 'c1'), isNull);
  });

  test('personal may serve company directly', () {
    // Not every function has a department KPI in between. Skipping a level is
    // legal; going sideways or down is not.
    expect(run('p1', 'c1'), isNull);
  });

  test('a KPI may not serve its own level', () {
    expect(run('d1', 'd2'), 'A KPI can only serve a higher level.');
  });

  test('a KPI may not serve a lower level', () {
    expect(run('c1', 'd1'), 'A KPI can only serve a higher level.');
  });

  test('a KPI may not be its own parent', () {
    expect(run('d1', 'd1'), "A KPI can't serve itself.");
  });

  test('a cycle is refused', () {
    // d1 -> c1 already; making c1 serve d1 closes the loop.
    expect(
      run('c1', 'd1', kpis: const [
        (id: 'd1', parentId: 'c1'),
        (id: 'c1', parentId: null),
      ]),
      isNotNull,
    );
  });
}
