import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/workforce_planning.dart';
import '../../../data/repositories/employee_repository.dart';
import '../../../data/repositories/workforce_planning_repository.dart';
import '../capacity_math.dart';
import '../org_tree_view.dart';
import '../structure_rows.dart';
import '../tasks_rows.dart' show AttributedTask, tasksForPerson;
import '../wp_providers.dart';
import 'load_chip.dart';
import 'role_view_tab.dart' show ownerComputedProvider;

/// Draggable version of the shared [OrgTreeView]: a load chip per person,
/// task chips under each expanded node, and two drag/drop interactions —
/// dragging a task chip onto a person reassigns its owner, dragging a person
/// row onto another re-parents the reporting line (guarded against
/// self/cycles by [reportingDropError]).
class StructureTab extends ConsumerWidget {
  const StructureTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final empsAsync = ref.watch(wpActiveEmployeesProvider);
    final loadsAsync = ref.watch(wpPersonLoadsProvider);
    final tasksAsync = ref.watch(wpTasksProvider);
    final mult = ref.watch(wpGrowthMultiplierProvider);

    // Use .value (nullable, not isLoading) so a post-drop ref.invalidate —
    // which puts the watched provider back into AsyncLoading — doesn't
    // unmount OrgTreeView and lose its _expanded state. Riverpod retains the
    // previous value across a reload, so only the very first load (no value
    // yet) shows a spinner; loads/tasks fall back to empty for the brief
    // refetch window.
    final emps = empsAsync.value;
    if (emps == null) {
      if (empsAsync.hasError) {
        return Center(
            child: Text('Error: ${empsAsync.error}', style: const TextStyle(color: Colors.red)));
      }
      return const Center(child: CircularProgressIndicator());
    }
    final loads = loadsAsync.value ?? const <WpPersonLoad>[];
    final tasks = tasksAsync.value ?? const <WpTask>[];

    final empById = {for (final e in emps) e.id: e};
    final people = [for (final e in emps) (id: e.id, parentId: e.reportsToId)];
    final loadById = {for (final l in loads) l.employeeId: l};
    // Explicitly-owned tasks PLUS the unowned responsibilities on each person's
    // role card — the same rule wp_person_load uses for the load chip rendered
    // beside them. Filtering on ownerEmployeeId alone would show a person with
    // a non-zero load% and no task chips at all.
    final attributedByPerson = <String, List<AttributedTask>>{
      for (final e in emps)
        e.id: tasksForPerson(
          employeeId: e.id,
          roleScorecardId: e.roleScorecardId,
          allTasks: tasks,
          employees: emps,
        ),
    };

    if (people.isEmpty) {
      return const Center(child: Text('No active people to show.'));
    }

    return OrgTreeView(
      people: people,
      empById: empById,
      trailing: (emp) {
        final l = loadById[emp.id];
        return l == null
            ? const SizedBox.shrink()
            : LoadStatusChip(status: loadStatus(personLoad(l, multiplier: mult)));
      },
      expandedExtras: (emp) => [
        for (final a in attributedByPerson[emp.id] ?? const <AttributedTask>[])
          Builder(builder: (_) {
            // Derived chips are marked so it's clear the task reaches this
            // person through their role card rather than an explicit owner.
            // Dragging one is still meaningful — it pins the task to whoever
            // it's dropped on, converting derived into explicit ownership.
            final label = a.derived ? '${a.task.name} · role' : a.task.name;
            return Draggable<_TaskPayload>(
              data: _TaskPayload(a.task.id),
              feedback: Material(
                  color: Colors.transparent, child: Chip(label: Text(label))),
              childWhenDragging:
                  Opacity(opacity: 0.4, child: Chip(label: Text(label))),
              child: Chip(label: Text(label)),
            );
          }),
      ],
      nodeWrapper: (emp, row) => DragTarget<Object>(
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
    );
  }
}

class _TaskPayload {
  final String taskId;
  const _TaskPayload(this.taskId);
}

class _PersonPayload {
  final String employeeId;
  const _PersonPayload(this.employeeId);
}

Future<void> _onDrop(WidgetRef ref, BuildContext context, Object data, String targetId,
    List<({String id, String? parentId})> people) async {
  void snack(String m) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  try {
    if (data is _TaskPayload) {
      await ref.read(workforcePlanningRepositoryProvider).reassignTaskOwner(data.taskId, targetId);
      ref.invalidate(wpTasksProvider);
      ref.invalidate(wpPersonLoadsProvider);
      ref.invalidate(ownerComputedProvider);
    } else if (data is _PersonPayload) {
      if (data.employeeId == targetId) return;
      final err = reportingDropError(movingId: data.employeeId, newParentId: targetId, people: people);
      if (err != null) {
        snack(err);
        return;
      }
      await ref.read(employeeRepositoryProvider).updateReportsTo(data.employeeId, targetId);
      ref.invalidate(employeeListProvider(const EmployeeListQuery()));
    }
  } catch (e) {
    snack('Could not apply the change: $e');
  }
}
