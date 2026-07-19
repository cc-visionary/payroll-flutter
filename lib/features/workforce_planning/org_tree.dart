class OrgNode {
  final String id;
  final String? parentId;
  final List<OrgNode> children;
  OrgNode(this.id, this.parentId) : children = [];
}

Map<String, List<String>> _childrenOf(List<({String id, String? parentId})> people) {
  final ids = {for (final p in people) p.id};
  final map = <String, List<String>>{};
  for (final p in people) {
    final parent = p.parentId;
    if (parent != null && ids.contains(parent)) {
      (map[parent] ??= []).add(p.id);
    }
  }
  return map;
}

/// Roots are people with a null parent OR a parent id not present in the list.
List<OrgNode> buildOrgTree(List<({String id, String? parentId})> people) {
  final ids = {for (final p in people) p.id};
  final nodes = {for (final p in people) p.id: OrgNode(p.id, p.parentId)};
  final roots = <OrgNode>[];
  for (final p in people) {
    final node = nodes[p.id]!;
    final parent = p.parentId;
    if (parent != null && nodes.containsKey(parent) && ids.contains(parent)) {
      nodes[parent]!.children.add(node);
    } else {
      roots.add(node);
    }
  }
  return roots;
}

Set<String> descendantsOf(String id, Map<String, List<String>> childrenOf) {
  final out = <String>{};
  final stack = [...(childrenOf[id] ?? const <String>[])];
  while (stack.isNotEmpty) {
    final cur = stack.removeLast();
    if (out.add(cur)) stack.addAll(childrenOf[cur] ?? const <String>[]);
  }
  return out;
}

/// A re-parent creates a cycle when the new parent is the node itself or any of
/// its descendants.
bool wouldCreateCycle({
  required String movingId,
  required String newParentId,
  required List<({String id, String? parentId})> people,
}) {
  if (movingId == newParentId) return true;
  return descendantsOf(movingId, _childrenOf(people)).contains(newParentId);
}
