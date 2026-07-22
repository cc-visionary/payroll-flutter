import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/workforce_planning.dart';
import '../../../data/repositories/employee_repository.dart';
import '../capacity_math.dart';
import '../org_chart_view.dart';
import '../structure_rows.dart';
import '../wp_providers.dart';
import 'load_chip.dart';
import 'tab_intro.dart';

/// Draggable version of the shared [OrgChartView]: a load chip per person and
/// one drag/drop interaction — dragging a person box onto another re-parents
/// the reporting line (guarded against self/cycles by [reportingDropError]).
///
/// This tab is deliberately about *shape and load*, not task detail; per-task
/// owner assignment lives on the Tasks tab.
class StructureTab extends ConsumerWidget {
  const StructureTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final empsAsync = ref.watch(wpActiveEmployeesProvider);
    final loadsAsync = ref.watch(wpPersonLoadsProvider);
    final mult = ref.watch(wpGrowthMultiplierProvider);

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
            child: Text('Error: ${empsAsync.error}', style: const TextStyle(color: Colors.red)));
      }
      return const Center(child: CircularProgressIndicator());
    }
    final loads = loadsAsync.value ?? const <WpPersonLoad>[];

    final empById = {for (final e in emps) e.id: e};
    final people = [for (final e in emps) (id: e.id, parentId: e.reportsToId)];
    final loadById = {for (final l in loads) l.employeeId: l};

    if (people.isEmpty) {
      return const Center(child: Text('No active people to show.'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TabIntro(
            purpose: 'Who reports to whom. Drag a person onto another to '
                'change their reporting line.',
            details: [
              (
                term: 'Changes here save immediately.',
                meaning: 'Unlike Balance, a re-parent is written as soon as you '
                    'drop it. Self-parenting and cycles are refused.',
              ),
              (
                term: 'Multiple roots are normal.',
                meaning: 'Anyone with no manager set appears as a top-level box. '
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
            : LoadStatusChip(status: loadStatus(personLoad(l, multiplier: mult)));
      },
      nodeWrapper: (emp, row) => DragTarget<_PersonPayload>(
        onAcceptWithDetails: (d) => _onDrop(ref, context, d.data, emp.id, people),
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
                    border: Border.all(color: Theme.of(ctx).colorScheme.primary),
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

Future<void> _onDrop(WidgetRef ref, BuildContext context, _PersonPayload data, String targetId,
    List<({String id, String? parentId})> people) async {
  void snack(String m) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  if (data.employeeId == targetId) return;
  final err = reportingDropError(movingId: data.employeeId, newParentId: targetId, people: people);
  if (err != null) {
    snack(err);
    return;
  }
  try {
    await ref.read(employeeRepositoryProvider).updateReportsTo(data.employeeId, targetId);
    ref.invalidate(employeeListProvider(const EmployeeListQuery()));
  } catch (e) {
    snack('Could not apply the change: $e');
  }
}
