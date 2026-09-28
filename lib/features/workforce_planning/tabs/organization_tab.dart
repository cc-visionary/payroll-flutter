import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/workforce_planning.dart';
import '../../../data/repositories/employee_repository.dart';
import '../capacity_math.dart';
import '../org_chart_view.dart';
import '../role_structure.dart';
import '../structure_rows.dart';
import '../wp_providers.dart';
import 'load_chip.dart';
import 'tab_intro.dart';

/// Draggable version of the shared [OrgChartView], answering the three
/// questions the org asks together: who holds each role, who reports to whom,
/// and what that role is accountable for. A load chip per person, the role's
/// owned responsibility areas under the title, and one drag/drop interaction —
/// dragging a person box onto another re-parents the reporting line (guarded
/// against self/cycles by [reportingDropError]).
///
/// The tree is `employees.reports_to_id`: people reporting to people. The
/// owned-areas block is what a role is accountable for, drawn from
/// [areasByRole] — so one box carries both without the two being conflated.
///
/// Which role does a task is set on the Roles board (drag a task onto a role)
/// or in a task's form; this tab is about shape, load, and ownership at a
/// glance.
class OrganizationTab extends ConsumerWidget {
  const OrganizationTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final empsAsync = ref.watch(wpActiveEmployeesProvider);
    final loadsAsync = ref.watch(wpPersonLoadsProvider);
    final mult = ref.watch(wpGrowthMultiplierProvider);
    // Read defensively: the owned-areas block is an enrichment, and must
    // never hold up the tree that is this tab's actual job. No areas yet
    // simply means no block yet.
    final tasks = ref.watch(wpTasksProvider).asData?.value ?? const <WpTask>[];

    // Use .value (nullable, not isLoading) so a post-drop ref.invalidate —
    // which puts the watched provider back into AsyncLoading — doesn't
    // unmount OrgChartView and lose its collapse state. Riverpod retains the
    // previous value across a reload, so only the very first load (no value
    // yet) shows a spinner; loads fall back to empty for the brief refetch
    // window.
    final emps = empsAsync.value;
    if (emps == null) {
      if (empsAsync.hasError) {
        return Center(
          child: Text(
            'Error: ${empsAsync.error}',
            style: const TextStyle(color: Colors.red),
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    final loads = loadsAsync.value ?? const <WpPersonLoad>[];

    final empById = {for (final e in emps) e.id: e};
    final people = [for (final e in emps) (id: e.id, parentId: e.reportsToId)];
    final loadById = {for (final l in loads) l.employeeId: l};
    final areas = areasByRole(tasks);

    if (people.isEmpty) {
      return const Center(child: Text('No active people to show.'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TabIntro(
            purpose:
                'Who holds each role, who reports to whom, and what that '
                'role owns. Drag a person onto another to change their '
                'reporting line.',
            details: [
              (
                term: 'Owns',
                meaning:
                    'The responsibility areas this person\'s role authors. '
                    'Work merely shared to the role is left out — it has its '
                    'primary owner on someone else\'s box.',
              ),
              (
                term: 'Changes here save immediately.',
                meaning:
                    'Unlike Balance, a re-parent is written as soon as you '
                    'drop it. Self-parenting and cycles are refused.',
              ),
              (
                term: 'Multiple roots are normal.',
                meaning:
                    'Anyone with no manager set appears as a top-level box. '
                    'Several roots simply means several people report to nobody.',
              ),
              WpGlossary.load,
            ],
          ),
        ),
        Expanded(
          child: OrgChartView(
            people: people,
            empById: empById,
            trailing: (emp) {
              final l = loadById[emp.id];
              return l == null
                  ? const SizedBox.shrink()
                  : LoadStatusChip(
                      status: loadStatus(personLoad(l, multiplier: mult)),
                    );
            },
            details: (emp) {
              final owned = areas[emp.roleScorecardId] ?? const <String>[];
              if (owned.isEmpty) return const SizedBox.shrink();
              return _OwnedAreas(areas: owned);
            },
            nodeWrapper: (emp, row) => DragTarget<_PersonPayload>(
              onAcceptWithDetails: (d) =>
                  _onDrop(ref, context, d.data, emp.id, people),
              builder: (ctx, cand, rej) => Draggable<_PersonPayload>(
                data: _PersonPayload(emp.id),
                feedback: Material(
                  color: Colors.transparent,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text('${emp.firstName} ${emp.lastName}'),
                    ),
                  ),
                ),
                childWhenDragging: Opacity(opacity: 0.4, child: row),
                child: Container(
                  decoration: cand.isNotEmpty
                      ? BoxDecoration(
                          border: Border.all(
                            color: Theme.of(ctx).colorScheme.primary,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        )
                      : null,
                  child: row,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PersonPayload {
  final String employeeId;
  const _PersonPayload(this.employeeId);
}

/// "Owns" plus one bulleted line per responsibility area. Capped so a role
/// with a dozen areas cannot stretch one box past the rest of the tree — the
/// remainder is counted, not silently dropped, because a box that quietly
/// showed four of eleven areas would read as the whole truth.
class _OwnedAreas extends StatelessWidget {
  const _OwnedAreas({required this.areas});

  static const int _maxShown = 5;

  final List<String> areas;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shown = areas.take(_maxShown).toList();
    final hidden = areas.length - shown.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Owns',
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        for (final a in shown)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              '• $a',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (hidden > 0)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              '+$hidden more',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
            ),
          ),
      ],
    );
  }
}

Future<void> _onDrop(
  WidgetRef ref,
  BuildContext context,
  _PersonPayload data,
  String targetId,
  List<({String id, String? parentId})> people,
) async {
  void snack(String m) {
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  if (data.employeeId == targetId) return;
  final err = reportingDropError(
    movingId: data.employeeId,
    newParentId: targetId,
    people: people,
  );
  if (err != null) {
    snack(err);
    return;
  }
  try {
    await ref
        .read(employeeRepositoryProvider)
        .updateReportsTo(data.employeeId, targetId);
    ref.invalidate(employeeListProvider(const EmployeeListQuery()));
  } catch (e) {
    snack('Could not apply the change: $e');
  }
}
