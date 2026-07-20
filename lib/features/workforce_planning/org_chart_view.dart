import 'package:flutter/material.dart';

import '../../data/models/employee.dart';
import 'org_tree.dart';

/// Shared top-down org chart built from [buildOrgTree]: fixed-width person
/// boxes joined by elbow connectors, each manager centred above their direct
/// reports. Multiple roots render side by side (the org legitimately has
/// several people who report to nobody).
///
/// Read-only by default (name + title). Optional hooks let feature-specific
/// consumers layer on a trailing widget (e.g. a load chip), wrap each box
/// (e.g. Draggable/DragTarget for the Structure tab), or supply extra widgets
/// shown in a panel under the box (e.g. task chips).
///
/// Layout note: each child subtree is measured with [IntrinsicWidth] so the
/// elbow connector can span exactly that subtree's width and meet its
/// neighbours. The inter-sibling gap is padded *inside* that measured width —
/// putting it between siblings instead would break the horizontal bar.
class OrgChartView extends StatefulWidget {
  const OrgChartView({
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
  final Widget Function(Employee emp, Widget box)? nodeWrapper;
  final List<Widget> Function(Employee emp)? expandedExtras;

  @override
  State<OrgChartView> createState() => _OrgChartViewState();
}

const double _boxW = 240;
const double _gap = 20;
const double _drop = 22;

class _OrgChartViewState extends State<OrgChartView> {
  /// Ids whose subtree is hidden. Tracking *collapsed* rather than *expanded*
  /// means nodes default to open, so a node that appears after a later data
  /// load (tasks and loads resolve after people do) is not stuck collapsed
  /// because it did not exist when this state was first built.
  final Set<String> _collapsed = {};

  /// Ids whose task panel is open. Closed by default to keep the chart compact.
  final Set<String> _openTasks = {};

  @override
  Widget build(BuildContext context) {
    final roots = buildOrgTree(widget.people);
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(24),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final r in roots) _subtree(r)],
        ),
      ),
    );
  }

  Widget _subtree(OrgNode node) {
    final emp = widget.empById[node.id];
    final extras = emp == null
        ? const <Widget>[]
        : (widget.expandedExtras?.call(emp) ?? const <Widget>[]);
    final box = _box(node, emp, extras.length);
    // The person drag source wraps the box only, so the task chips below stay
    // outside it — nesting a Draggable inside a Draggable makes the gesture
    // arena ambiguous and can swallow the chip drag.
    final wrapped =
        (emp != null && widget.nodeWrapper != null) ? widget.nodeWrapper!(emp, box) : box;

    final kids = node.children;
    final showKids = kids.isNotEmpty && !_collapsed.contains(node.id);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        wrapped,
        if (_openTasks.contains(node.id) && extras.isNotEmpty) _taskPanel(extras),
        if (showKids) ...[
          _stub(),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < kids.length; i++)
                IntrinsicWidth(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: _drop,
                        child: CustomPaint(
                          painter: _ElbowPainter(
                            isFirst: i == 0,
                            isLast: i == kids.length - 1,
                            color: _lineColor(context),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: _gap / 2),
                        child: _subtree(kids[i]),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Color _lineColor(BuildContext context) => Theme.of(context).colorScheme.outlineVariant;

  Widget _stub() => Container(width: 1.5, height: _drop, color: _lineColor(context));

  Widget _box(OrgNode node, Employee? emp, int taskCount) {
    final cs = Theme.of(context).colorScheme;
    final kids = node.children;
    final collapsed = _collapsed.contains(node.id);
    final tasksOpen = _openTasks.contains(node.id);

    return Container(
      width: _boxW,
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  emp == null ? node.id : '${emp.firstName} ${emp.lastName}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (emp != null && widget.trailing != null) ...[
                const SizedBox(width: 6),
                widget.trailing!(emp),
              ],
            ],
          ),
          if (emp?.jobTitle != null && emp!.jobTitle!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                emp.jobTitle!,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (taskCount > 0 || kids.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  if (taskCount > 0)
                    _footerButton(
                      icon: tasksOpen ? Icons.expand_more : Icons.chevron_right,
                      label: '$taskCount ${taskCount == 1 ? 'task' : 'tasks'}',
                      onTap: () => setState(() =>
                          tasksOpen ? _openTasks.remove(node.id) : _openTasks.add(node.id)),
                    ),
                  const Spacer(),
                  if (kids.isNotEmpty)
                    _footerButton(
                      icon: collapsed ? Icons.add_circle_outline : Icons.remove_circle_outline,
                      label: '${kids.length} ${kids.length == 1 ? 'report' : 'reports'}',
                      onTap: () => setState(() =>
                          collapsed ? _collapsed.remove(node.id) : _collapsed.add(node.id)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _footerButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: cs.onSurfaceVariant),
            const SizedBox(width: 3),
            Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _taskPanel(List<Widget> extras) => Container(
        width: _boxW,
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Wrap(spacing: 6, runSpacing: 6, children: extras),
      );
}

/// Draws one child's connector: a horizontal bar along the top edge that meets
/// its siblings' bars, plus a vertical drop to the child box. The bar stops at
/// the centre for the first/last child so the run spans exactly first-centre to
/// last-centre.
class _ElbowPainter extends CustomPainter {
  const _ElbowPainter({required this.isFirst, required this.isLast, required this.color});

  final bool isFirst;
  final bool isLast;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final cx = size.width / 2;
    final left = isFirst ? cx : 0.0;
    final right = isLast ? cx : size.width;
    if (right > left) canvas.drawLine(Offset(left, 0), Offset(right, 0), paint);
    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), paint);
  }

  @override
  bool shouldRepaint(_ElbowPainter old) =>
      old.isFirst != isFirst || old.isLast != isLast || old.color != color;
}
