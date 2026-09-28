import 'package:flutter/material.dart';

import '../../../app/status_colors.dart';
import '../../../data/models/workforce_planning.dart';
import '../capacity_math.dart';
import '../../../app/theme.dart';
import '../frequency.dart' show effortLabel;
import '../role_load.dart';
import '../tabs/load_chip.dart';

String _pct(double f) => '${(f * 100).round()}%';
String _h(double v) => '${v.toStringAsFixed(v >= 10 ? 0 : 1)}h';

/// One role on the board: headcount headline, holders, tasks. Also the drop
/// target for moving a task into this role.
class RoleLoadCard extends StatelessWidget {
  final RoleLoad current;

  /// Figures under drafts + the in-flight hover (numbers only).
  final RoleLoad planned;

  /// The rows to render: drafts only, never the hover — re-parenting the
  /// Draggable under the pointer mid-drag would cancel the drag.
  final List<WpTask> tasks;
  final List<String> checkedBy;
  final bool highlighted;
  final Map<String, double> taskHoursById;
  final void Function(String taskId) onDropTask;
  final void Function(String? taskId) onHoverTask;
  /// Null disables "Add task" (e.g. no company id to write the task under).
  final VoidCallback? onAddTask;
  final VoidCallback onAddHolder;
  final VoidCallback onOpenRole;
  final void Function(WpTask task) onOpenTask;

  const RoleLoadCard({
    super.key,
    required this.current,
    required this.planned,
    required this.tasks,
    required this.checkedBy,
    required this.highlighted,
    required this.taskHoursById,
    required this.onDropTask,
    required this.onHoverTask,
    required this.onAddTask,
    required this.onAddHolder,
    required this.onOpenRole,
    required this.onOpenTask,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final mono = AppTheme.mono(context);
    final changed = (planned.workHours - current.workHours).abs() > 0.001;
    final danger = planned.status == LoadStatus.over;
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) {
        onHoverTask(d.data);
        return true;
      },
      onLeave: (_) => onHoverTask(null),
      onAcceptWithDetails: (d) => onDropTask(d.data),
      builder: (context, candidates, _) => Card(
        key: ValueKey('role-card-${current.role.id}'),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(
            color: candidates.isNotEmpty || highlighted
                ? cs.primary
                : danger
                    ? StatusPalette.of(context, StatusTone.danger).foreground
                    : cs.outlineVariant,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: InkWell(
                    onTap: onOpenRole,
                    child: Text(current.role.jobTitle, style: text.titleMedium),
                  ),
                ),
                Text(
                  checkedBy.isEmpty ? 'checked by —' : 'checked by ${checkedBy.join(', ')}',
                  style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ]),
              const SizedBox(height: 4),
              Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('Work ${_h(planned.workHours)}/mo', style: mono),
                Text('Has ${planned.holders.length}'),
                Text('Needs ${planned.peopleNeeded.toStringAsFixed(1)} people', style: mono),
                if (planned.shortBy > 0.05)
                  StatusChip(label: 'short ${planned.shortBy.toStringAsFixed(1)}', tone: StatusTone.danger),
                if (changed)
                  Text('${_pct(current.load)} → ${_pct(planned.load)}',
                      style: mono.copyWith(color: cs.primary, fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 8),
              if (planned.holders.isEmpty)
                Text('Nobody holds this role', style: TextStyle(color: cs.onSurfaceVariant))
              else
                Wrap(spacing: 12, runSpacing: 4, children: [
                  for (final h in planned.holders)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(h.employee.firstName),
                      const SizedBox(width: 4),
                      Text(_pct(planned.load), style: mono),
                      const SizedBox(width: 4),
                      LoadStatusChip(status: planned.status),
                    ]),
                ]),
              const Divider(height: 24),
              for (final t in tasks)
                Draggable<String>(
                  key: ValueKey('task-${t.id}'),
                  data: t.id,
                  feedback: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(padding: const EdgeInsets.all(8), child: Text(t.name)),
                  ),
                  childWhenDragging: Opacity(opacity: 0.4, child: _taskRow(context, t)),
                  child: _taskRow(context, t),
                ),
              Row(children: [
                TextButton.icon(onPressed: onAddTask, icon: const Icon(Icons.add), label: const Text('Add task')),
                TextButton.icon(onPressed: onAddHolder, icon: const Icon(Icons.person_add_alt), label: const Text('Add holder')),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _taskRow(BuildContext context, WpTask t) {
    final hours = taskHoursById[t.id] ?? 0;
    final moved = t.roleScorecardId != current.role.id;
    return InkWell(
      onTap: () => onOpenTask(t),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          const Icon(Icons.drag_indicator, size: 16),
          const SizedBox(width: 4),
          Expanded(
            child: Text(t.name,
                style: moved ? TextStyle(color: Theme.of(context).colorScheme.primary) : null),
          ),
          Text(effortLabel(t, hours)),
          const SizedBox(width: 12),
          SizedBox(width: 56, child: Text('≈ ${_h(hours)}', textAlign: TextAlign.right, style: AppTheme.mono(context))),
        ]),
      ),
    );
  }
}
