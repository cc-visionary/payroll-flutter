import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/kpi_library/kpi_parentage.dart';

void main() {
  const levels = {
    'p1': 'PERSONAL',
    'p2': 'PERSONAL',
    'd1': 'DEPARTMENT',
    'd2': 'DEPARTMENT',
    'c1': 'COMPANY',
    'u1': 'ARCHIVED', // not in _rank — simulates a mis-tagged/unknown level
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

  test('an unrecognised level on the child refuses', () {
    expect(
      run('u1', 'd1'),
      "A KPI's level isn't recognised, so parentage can't be checked.",
    );
  });

  test('an unrecognised level on the parent refuses', () {
    expect(
      run('d1', 'u1'),
      "A KPI's level isn't recognised, so parentage can't be checked.",
    );
  });

  test('unrecognised-level refusals use a distinct message', () {
    // Neither side should be mistaken for the ordinary level-mismatch case —
    // a corrupt level and a merely-wrong level are different problems and
    // should not share wording.
    final childSide = run('u1', 'd1');
    final parentSide = run('d1', 'u1');
    expect(childSide, isNot('A KPI can only serve a higher level.'));
    expect(parentSide, isNot('A KPI can only serve a higher level.'));
    expect(childSide, parentSide);
  });

  test('cycle guard rejects pre-existing loop', () {
    // This constructs a legal move by level: p1 (PERSONAL) to d1 (DEPARTMENT).
    // The existing data contains corruption: d2 (DEPARTMENT) has p1 as parent,
    // which violates the level rule (data could only exist before the guard).
    // So: p1 is ancestor of d2, d2 is ancestor of d1, making p1 ancestor of d1.
    // Setting d1 as parent of p1 creates: p1 → d1 → d2 → p1 (cycle!).
    // The level rule passes, but the cycle guard refuses it.
    // This tests the guard against pre-existing data corruption.
    expect(
      run('p1', 'd1', kpis: const [
        (id: 'p1', parentId: null),
        (id: 'd1', parentId: 'd2'),
        (id: 'd2', parentId: 'p1'),
      ]),
      isNotNull,
    );
  });
}
