import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/breakpoints.dart';
import '../../app/shell.dart';
import '../../data/models/role_scorecard.dart';
import '../../data/models/workforce_planning.dart';
import '../../data/repositories/role_scorecard_repository.dart';
import '../documents/providers.dart' show roleScorecardByIdProvider;
import 'org_tree.dart';
import 'seat_tree.dart';
import 'wp_providers.dart';

/// The EOS Accountability Chart: a tree of SEATS (functions), independent of
/// `employees.reports_to_id` (see `structure_tab.dart` for that tree). Boxes
/// come from [seatBoxes] — one per active holder, exactly one OPEN SEAT box
/// for a seat with none — and re-parenting is guarded by [seatDropError].
///
/// This is deliberately NOT `OrgChartView` (`org_chart_view.dart`): that
/// view's node is one box per `Employee`, but a seat here can render as
/// *several* boxes (one per holder) sharing a single position in the tree,
/// and there is no collapse/expand affordance. Reusing `OrgChartView` would
/// mean bifurcating its node renderer on a shape it was never built for —
/// risking the Structure tab's working, tested behaviour to save copying its
/// ~20-line connector painter. [buildOrgTree] — the part that actually
/// carries correctness (cycle-safe roots) — IS reused unmodified from
/// `org_tree.dart`; only the presentational elbow painter is duplicated
/// locally (see `_SeatElbowPainter` below).
class AccountabilityChartScreen extends ConsumerWidget {
  const AccountabilityChartScreen({super.key});

  /// The chart's own copy of what it is (and is not) — see the design spec's
  /// "Risks" section: to anyone expecting an org chart, a seat's owner not
  /// matching their manager reads as a bug rather than a legal EOS state.
  static const String explainer =
      'Maps functions and who owns them, not who reports to whom. '
      'For reporting lines, see Workforce Planning ▸ Structure.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seatsAsync = ref.watch(roleScorecardListProvider);
    final employeesAsync = ref.watch(wpActiveEmployeesProvider);
    final tasksAsync = ref.watch(wpTasksProvider);
    final mobile = isMobile(context);

    // .value (not isLoading) so a post-drop invalidate — which puts a
    // watched provider back into AsyncLoading — doesn't blank the whole
    // chart. Riverpod keeps the previous value across a reload.
    final seats = seatsAsync.value;
    final employees = employeesAsync.value;
    final tasks = tasksAsync.value;

    Widget body;
    if (seats == null || employees == null || tasks == null) {
      final err = seatsAsync.error ?? employeesAsync.error ?? tasksAsync.error;
      body = err != null
          ? Center(
              child: Text(
                'Error: $err',
                style: const TextStyle(color: Colors.red),
              ),
            )
          : const Center(child: CircularProgressIndicator());
    } else if (seats.isEmpty) {
      body = const Center(child: Text('No seats yet.'));
    } else {
      final boxes = seatBoxes(
        seats: seats,
        employees: employees,
        areasBySeat: areasBySeat(tasks),
      );
      body = _ChartBody(seats: seats, boxes: boxes);
    }

    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      drawer: mobile ? const AppDrawer() : null,
      appBar: AppBar(title: const Text('Accountability Chart')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              explainer,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// Seat -> its responsibility-area names, in authored order. Built straight
/// from `wp_tasks` (each task's own `role_scorecard_id`) rather than
/// `RoleScorecard.responsibilities`, which also appends accountabilities
/// SHARED to a card via an assignment (`_withSharedResponsibilities`) — a
/// box's roles are what the seat authors, not what it borrows.
/// [responsibilitiesFromTaskRows] is the same vetted area/task grouping
/// `RoleScorecard.fromRow` itself uses for the authored list, reused here
/// rather than re-derived.
Map<String, List<String>> areasBySeat(List<WpTask> tasks) {
  final rowsBySeat = <String, List<Map<String, dynamic>>>{};
  for (final t in tasks) {
    final seatId = t.roleScorecardId;
    if (seatId == null) continue;
    (rowsBySeat[seatId] ??= []).add({
      'id': t.id,
      'name': t.name,
      'responsibility_area': t.responsibilityArea,
      'area_sort': t.areaSort,
      'task_sort': t.taskSort,
      'status': t.status,
    });
  }
  return {
    for (final entry in rowsBySeat.entries)
      entry.key: [
        for (final area in responsibilitiesFromTaskRows(entry.value))
          area.area,
      ],
  };
}

const double _boxWidth = 220;
const double _gap = 20;
const double _drop = 22;

/// Root(s) down: a seat with no parent, or whose parent id isn't among the
/// seats fetched (e.g. an inactive/archived parent) renders as a root
/// instead of vanishing — [buildOrgTree] already guarantees this.
class _ChartBody extends StatelessWidget {
  const _ChartBody({required this.seats, required this.boxes});

  final List<RoleScorecard> seats;
  final List<SeatBox> boxes;

  @override
  Widget build(BuildContext context) {
    final people = [for (final s in seats) (id: s.id, parentId: s.parentId)];
    final roots = buildOrgTree(people);
    final boxesBySeat = <String, List<SeatBox>>{};
    for (final b in boxes) {
      (boxesBySeat[b.seatId] ??= []).add(b);
    }

    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(24),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final r in roots)
              _SeatSubtree(node: r, boxesBySeat: boxesBySeat, people: people),
          ],
        ),
      ),
    );
  }
}

class _SeatSubtree extends StatelessWidget {
  const _SeatSubtree({
    required this.node,
    required this.boxesBySeat,
    required this.people,
  });

  final OrgNode node;
  final Map<String, List<SeatBox>> boxesBySeat;
  final List<({String id, String? parentId})> people;

  Color _lineColor(BuildContext context) =>
      Theme.of(context).colorScheme.outlineVariant;

  @override
  Widget build(BuildContext context) {
    final nodeBoxes = boxesBySeat[node.id] ?? const <SeatBox>[];
    final kids = node.children;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final b in nodeBoxes)
              _DraggableSeatBox(box: b, seatId: node.id, people: people),
          ],
        ),
        if (kids.isNotEmpty) ...[
          Container(width: 1.5, height: _drop, color: _lineColor(context)),
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
                          painter: _SeatElbowPainter(
                            isFirst: i == 0,
                            isLast: i == kids.length - 1,
                            color: _lineColor(context),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: _gap / 2,
                        ),
                        child: _SeatSubtree(
                          node: kids[i],
                          boxesBySeat: boxesBySeat,
                          people: people,
                        ),
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
}

/// Paints one child's connector: a horizontal bar meeting its siblings' bars
/// plus a vertical drop to the child. Deliberately a local copy of
/// `OrgChartView`'s `_ElbowPainter` rather than a shared extraction — see the
/// class doc on [AccountabilityChartScreen] for why.
class _SeatElbowPainter extends CustomPainter {
  const _SeatElbowPainter({
    required this.isFirst,
    required this.isLast,
    required this.color,
  });

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
    if (right > left) {
      canvas.drawLine(Offset(left, 0), Offset(right, 0), paint);
    }
    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), paint);
  }

  @override
  bool shouldRepaint(_SeatElbowPainter old) =>
      old.isFirst != isFirst || old.isLast != isLast || old.color != color;
}

class _SeatPayload {
  final String seatId;
  const _SeatPayload(this.seatId);
}

/// One box, draggable to re-parent its seat and a drop target for another
/// box's seat to become a child of THIS one. The drag unit is the seat, not
/// the box: dropping any one of a multi-holder seat's boxes onto any one of
/// another seat's boxes re-parents the whole seat — one-seat-one-name means
/// the boxes of a seat always move together.
class _DraggableSeatBox extends ConsumerWidget {
  const _DraggableSeatBox({
    required this.box,
    required this.seatId,
    required this.people,
  });

  final SeatBox box;
  final String seatId;
  final List<({String id, String? parentId})> people;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = _SeatBoxCard(box: box);
    return DragTarget<_SeatPayload>(
      onAcceptWithDetails: (d) =>
          _onDrop(ref, context, d.data.seatId, seatId, people),
      builder: (ctx, candidates, rejected) => Draggable<_SeatPayload>(
        data: _SeatPayload(seatId),
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(width: _boxWidth, child: content),
        ),
        childWhenDragging: Opacity(opacity: 0.4, child: content),
        child: Container(
          decoration: candidates.isNotEmpty
              ? BoxDecoration(
                  border: Border.all(color: Theme.of(ctx).colorScheme.primary),
                  borderRadius: BorderRadius.circular(10),
                )
              : null,
          child: content,
        ),
      ),
    );
  }
}

class _SeatBoxCard extends StatelessWidget {
  const _SeatBoxCard({required this.box});

  final SeatBox box;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: _boxWidth,
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            box.function,
            style: const TextStyle(fontWeight: FontWeight.w700),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            box.isOpen ? 'OPEN SEAT' : box.holderName!,
            style: TextStyle(
              color: box.isOpen ? cs.error : cs.onSurface,
              fontWeight: box.isOpen ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          if (box.roles.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final r in box.roles)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '• $r',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

Future<void> _onDrop(
  WidgetRef ref,
  BuildContext context,
  String movingSeatId,
  String targetSeatId,
  List<({String id, String? parentId})> people,
) async {
  void snack(String m) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  if (movingSeatId == targetSeatId) return;
  final err = seatDropError(
    movingSeatId: movingSeatId,
    newParentId: targetSeatId,
    seats: people,
  );
  if (err != null) {
    snack(err);
    return;
  }
  try {
    await ref
        .read(roleScorecardRepositoryProvider)
        .updateParent(movingSeatId, targetSeatId);
    ref.invalidate(roleScorecardListProvider);
    ref.invalidate(roleScorecardByIdProvider(movingSeatId));
  } catch (e) {
    snack('Could not apply the change: $e');
  }
}
