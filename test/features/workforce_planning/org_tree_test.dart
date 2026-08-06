import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/workforce_planning/org_tree.dart';

void main() {
  // ceo <- coo <- gm ; ceo <- ops
  final people = <({String id, String? parentId})>[
    (id: 'ceo', parentId: null),
    (id: 'coo', parentId: 'ceo'),
    (id: 'gm', parentId: 'coo'),
    (id: 'ops', parentId: 'ceo'),
  ];

  test('buildOrgTree nests under managers, roots have no/absent parent', () {
    final roots = buildOrgTree(people);
    expect(roots.map((n) => n.id), ['ceo']);
    final ceo = roots.single;
    expect(ceo.children.map((n) => n.id).toSet(), {'coo', 'ops'});
    final coo = ceo.children.firstWhere((n) => n.id == 'coo');
    expect(coo.children.single.id, 'gm');
  });

  test('wouldCreateCycle: self, direct descendant, deep descendant', () {
    expect(
      wouldCreateCycle(movingId: 'coo', newParentId: 'coo', people: people),
      isTrue,
    );
    expect(
      wouldCreateCycle(movingId: 'coo', newParentId: 'gm', people: people),
      isTrue,
    );
    expect(
      wouldCreateCycle(movingId: 'ceo', newParentId: 'gm', people: people),
      isTrue,
    );
  });

  test('wouldCreateCycle false for a valid re-parent', () {
    expect(
      wouldCreateCycle(movingId: 'gm', newParentId: 'ops', people: people),
      isFalse,
    );
  });
}
