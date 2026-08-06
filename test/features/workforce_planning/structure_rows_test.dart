import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/workforce_planning/structure_rows.dart';

void main() {
  final people = <({String id, String? parentId})>[
    (id: 'ceo', parentId: null),
    (id: 'coo', parentId: 'ceo'),
    (id: 'gm', parentId: 'coo'),
    (id: 'ops', parentId: 'ceo'),
  ];
  test('rejects self-drop', () {
    expect(
      reportingDropError(movingId: 'coo', newParentId: 'coo', people: people),
      "A person can't report to themselves.",
    );
  });
  test('rejects a reporting loop', () {
    expect(
      reportingDropError(movingId: 'coo', newParentId: 'gm', people: people),
      'That would create a reporting loop.',
    );
  });
  test('allows a valid re-parent', () {
    expect(
      reportingDropError(movingId: 'gm', newParentId: 'ops', people: people),
      isNull,
    );
  });
  test('drop onto the current manager is a no-op (returns null)', () {
    expect(
      reportingDropError(movingId: 'gm', newParentId: 'coo', people: people),
      isNull,
    );
  });
}
