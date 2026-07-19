import 'package:flutter/material.dart';

import '../../data/models/employee.dart';
import 'org_tree.dart';

/// Shared indented, expandable reporting tree built from [buildOrgTree].
///
/// Read-only by default (name + title). Optional hooks let feature-specific
/// consumers layer on a trailing widget (e.g. a load chip), wrap each row
/// (e.g. Draggable/DragTarget for the Structure tab), or show extra widgets
/// when a node is expanded (e.g. task chips).
class OrgTreeView extends StatefulWidget {
  const OrgTreeView({
    super.key,
    required this.people,
    required this.empById,
    this.trailing,
    this.nodeWrapper,
    this.expandedExtras,
  });

  final List<({String id, String? parentId})> people;
  final Map<String, Employee> empById;
  final Widget Function(Employee emp)? trailing;
  final Widget Function(Employee emp, Widget row)? nodeWrapper;
  final List<Widget> Function(Employee emp)? expandedExtras;

  @override
  State<OrgTreeView> createState() => _OrgTreeViewState();
}

class _OrgTreeViewState extends State<OrgTreeView> {
  late Set<String> _expanded;

  @override
  void initState() {
    super.initState();
    final roots = buildOrgTree(widget.people);
    _expanded = {for (final r in roots) r.id};
  }

  @override
  Widget build(BuildContext context) {
    final roots = buildOrgTree(widget.people);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final r in roots) ..._nodes(r, 0)],
      ),
    );
  }

  List<Widget> _nodes(OrgNode node, int depth) {
    final emp = widget.empById[node.id];
    final extras = emp == null ? const <Widget>[] : (widget.expandedExtras?.call(emp) ?? const <Widget>[]);
    final hasKids = node.children.isNotEmpty || extras.isNotEmpty;
    final expanded = _expanded.contains(node.id);
    final row = Padding(
      padding: EdgeInsets.only(left: depth * 24.0, top: 2, bottom: 2),
      child: Row(children: [
        SizedBox(
          width: 28,
          child: hasKids
              ? IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 20,
                  icon: Icon(expanded ? Icons.expand_more : Icons.chevron_right),
                  onPressed: () => setState(() => expanded ? _expanded.remove(node.id) : _expanded.add(node.id)),
                )
              : null,
        ),
        if (emp != null) ...[
          Text('${emp.firstName} ${emp.lastName}', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              emp.jobTitle ?? '',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ] else
          Text(node.id),
        if (emp != null && widget.trailing != null) ...[const SizedBox(width: 8), widget.trailing!(emp)],
      ]),
    );
    final wrapped = (emp != null && widget.nodeWrapper != null) ? widget.nodeWrapper!(emp, row) : row;
    return [
      wrapped,
      if (expanded) ...[
        if (extras.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(left: (depth + 1) * 24.0, top: 2, bottom: 6),
            child: Wrap(spacing: 6, runSpacing: 6, children: extras),
          ),
        for (final c in node.children) ..._nodes(c, depth + 1),
      ],
    ];
  }
}
