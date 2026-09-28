import 'package:flutter/material.dart';

import '../../../data/models/employee.dart';
import '../../../data/models/role_scorecard.dart';
import '../../../data/models/workforce_planning.dart';
import '../role_load.dart';
import '../tabs/load_chip.dart';
import '../frequency.dart' show effortLabel;

/// Everyone's load at a glance, busiest first. A person's load is their
/// role's load (capacity-weighted split), so this is read off [loads].
class PeopleLoadStrip extends StatelessWidget {
  final List<RoleLoad> loads;
  final List<Employee> employees;
  const PeopleLoadStrip({super.key, required this.loads, required this.employees});

  @override
  Widget build(BuildContext context) {
    final byRole = {for (final l in loads) l.role.id: l};
    final rows = [
      for (final e in employees)
        if (e.employmentStatus == 'ACTIVE' && e.deletedAt == null)
          (e: e, load: e.roleScorecardId == null ? null : byRole[e.roleScorecardId]),
    ]..sort((a, b) => (b.load?.load ?? -1).compareTo(a.load?.load ?? -1));
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final r in rows)
        Chip(
          avatar: r.load == null ? null : LoadStatusChip(status: r.load!.status),
          label: Text(r.load == null
              ? '${r.e.firstName} no role'
              : '${r.e.firstName} ${(r.load!.load * 100).round()}%'),
        ),
    ]);
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    margin: const EdgeInsets.only(bottom: 12),
    child: ExpansionTile(
      initiallyExpanded: true,
      title: Text(title, style: Theme.of(context).textTheme.titleSmall),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: children,
    ),
  );
}

/// Genuine work that reaches nobody. Drag a row onto a role card.
class NoRoleSection extends StatelessWidget {
  final List<WpTask> tasks;
  final Map<String, double> hoursById;
  final void Function(WpTask) onOpenTask;
  const NoRoleSection({super.key, required this.tasks, required this.hoursById, required this.onOpenTask});

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) return const SizedBox.shrink();
    return _Section(title: 'No role yet (${tasks.length})', children: [
      for (final t in tasks)
        Draggable<String>(
          key: ValueKey('task-${t.id}'),
          data: t.id,
          feedback: Material(elevation: 4, child: Padding(padding: const EdgeInsets.all(8), child: Text(t.name))),
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.drag_indicator, size: 16),
            title: Text(t.name),
            trailing: Text(effortLabel(t, hoursById[t.id] ?? 0)),
            onTap: () => onOpenTask(t),
          ),
        ),
    ]);
  }
}

/// Tasks the role-first migration could not convert without losing detail.
class FlaggedSection extends StatelessWidget {
  final List<WpTask> tasks;
  final Map<String, RoleScorecard> rolesById;
  final Future<void> Function(WpTask) onLooksRight;
  final void Function(WpTask) onOpenTask;
  const FlaggedSection({super.key, required this.tasks, required this.rolesById, required this.onLooksRight, required this.onOpenTask});

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) return const SizedBox.shrink();
    return _Section(title: 'Check these (${tasks.length})', children: [
      for (final t in tasks)
        ListTile(
          dense: true,
          title: Text(t.name),
          subtitle: Text(
            'now: ${rolesById[t.roleScorecardId]?.jobTitle ?? 'no role'} · ${t.allocationReviewNote}',
          ),
          onTap: () => onOpenTask(t),
          trailing: TextButton(onPressed: () => onLooksRight(t), child: const Text('Looks right')),
        ),
    ]);
  }
}
