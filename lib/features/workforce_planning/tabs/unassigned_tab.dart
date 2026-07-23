import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/status_colors.dart';
import '../../../app/theme.dart';
import '../../../data/models/role_scorecard.dart';
import '../../../data/models/workforce_planning.dart';
import '../../../data/repositories/role_scorecard_repository.dart';
import '../../../data/repositories/workforce_planning_repository.dart';
import '../../auth/profile_provider.dart';
import '../task_badges.dart';
import '../unassigned_workspace.dart';
import '../wp_providers.dart';
import 'role_view_tab.dart' show ownerComputedProvider;
import 'tab_intro.dart';

/// Every ACTIVE accountability that reaches nobody, clustered by name
/// similarity so a manager can act on a group at once instead of hunting
/// through one row at a time. Per cluster: archive an item, hand it to a
/// staffed role card, or draft a brand-new (inactive) card seeded with the
/// whole cluster's tasks.
///
/// Mirrors `TasksTab`'s provider-watch/spinner/error shape and its
/// archive-confirm + invalidate pattern (see `_invalidateAfterTaskChange`
/// there) so the two tabs never drift into different conventions for the
/// same underlying `wp_tasks` mutations.
class UnassignedTab extends ConsumerStatefulWidget {
  const UnassignedTab({super.key});

  @override
  ConsumerState<UnassignedTab> createState() => _UnassignedTabState();
}

class _UnassignedTabState extends ConsumerState<UnassignedTab> {
  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(wpTasksProvider);
    final employeesAsync = ref.watch(wpActiveEmployeesProvider);
    final computedAsync = ref.watch(wpAllTaskComputedProvider);
    final cardsAsync = ref.watch(roleScorecardListProvider);
    final companyId = ref.watch(userProfileProvider).asData?.value?.companyId;

    if (tasksAsync.isLoading ||
        employeesAsync.isLoading ||
        computedAsync.isLoading ||
        cardsAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final err = tasksAsync.error ??
        employeesAsync.error ??
        computedAsync.error ??
        cardsAsync.error;
    if (err != null) {
      return Center(
        child: Text('Error: $err', style: const TextStyle(color: Colors.red)),
      );
    }

    final tasks = tasksAsync.asData!.value;
    final employees = employeesAsync.asData!.value;
    final allComputed = computedAsync.asData!.value;
    final cards = cardsAsync.asData!.value;
    final computedByTaskId = {for (final c in allComputed) c.taskId: c};
    final multiplier = ref.watch(wpGrowthMultiplierProvider);

    final clusters = buildUnassignedWorkspace(
      tasks: tasks,
      employees: employees,
      computedByTaskId: computedByTaskId,
      multiplier: multiplier,
    );
    // Only a staffed, live card is a sane assign target — an inactive/draft
    // card has no holder to reach, so it would just recreate the orphan.
    final activeCards = cards.where((c) => c.isActive).toList();
    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TabIntro(
            purpose: 'Work that reaches nobody — archive it, assign it, or '
                'draft a role for it.',
            details: [
              WpGlossary.unassigned,
              WpGlossary.derived,
              WpGlossary.proposeRole,
            ],
          ),
          const SizedBox(height: 16),
          if (clusters.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'Nothing unassigned — every accountability reaches someone.',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            )
          else
            for (final cluster in clusters) ...[
              _clusterCard(context, cluster, activeCards, companyId),
              const SizedBox(height: 16),
            ],
        ],
      ),
    );
  }

  Widget _clusterCard(
    BuildContext context,
    UnassignedCluster cluster,
    List<RoleScorecard> activeCards,
    String? companyId,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(cluster.label,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                const SizedBox(width: 8),
                StatusChip(
                  label: '${cluster.count} ${cluster.count == 1 ? 'item' : 'items'} · '
                      '${cluster.totalHours.toStringAsFixed(1)}h',
                  tone: StatusTone.neutral,
                ),
                // A single orphan is just an item to assign or archive — a
                // "role" needs more than one responsibility to be coherent.
                if (cluster.count >= 2) ...[
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => _proposeRole(cluster, companyId),
                    icon: const Icon(Icons.auto_awesome, size: 16),
                    label: const Text('Propose role from these'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            for (final item in cluster.items) _itemRow(context, item, activeCards),
          ],
        ),
      ),
    );
  }

  Widget _itemRow(
    BuildContext context,
    UnassignedItem item,
    List<RoleScorecard> activeCards,
  ) {
    final t = item.task;
    final tone = criticalityTone(t.criticality);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(t.name),
                if (tone != null) StatusChip(label: criticalityLabel(t.criticality)!, tone: tone),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text('${item.hours.toStringAsFixed(1)}h', style: AppTheme.mono(context)),
          const SizedBox(width: 12),
          PopupMenuButton<String>(
            tooltip: 'Assign to a role card',
            enabled: activeCards.isNotEmpty,
            onSelected: (cardId) => _assign(t, cardId, activeCards),
            itemBuilder: (_) => [
              for (final c in activeCards)
                PopupMenuItem<String>(value: c.id, child: Text(c.jobTitle)),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [Text('Assign'), Icon(Icons.arrow_drop_down, size: 18)],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Archive',
            icon: const Icon(Icons.archive_outlined, size: 18),
            onPressed: () => _confirmArchive(t),
          ),
        ],
      ),
    );
  }

  Future<void> _assign(WpTask task, String cardId, List<RoleScorecard> activeCards) async {
    final card = activeCards.firstWhere((c) => c.id == cardId);
    try {
      await ref.read(workforcePlanningRepositoryProvider).setTaskCard(task.id, cardId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not assign: $e')));
      return;
    }
    if (!mounted) return;
    _invalidate();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Assigned to ${card.jobTitle}.')));
  }

  Future<void> _confirmArchive(WpTask task) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Archive task?'),
        content: Text(
          'Archive "${task.name}"? It leaves the unassigned list and everyone\'s '
          'load but is kept and can be restored.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Archive')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(workforcePlanningRepositoryProvider).setTaskArchived(task.id, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not archive task: $e')));
      return;
    }
    if (!mounted) return;
    _invalidate();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Archived "${task.name}".')));
  }

  Future<void> _proposeRole(UnassignedCluster cluster, String? companyId) async {
    // Local var + onChanged (not a TextEditingController) mirrors TasksTab's
    // `_fillArea` dialog — no controller to dispose once the dialog pops.
    var jobTitle = cluster.label;
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Propose role from these'),
        content: TextFormField(
          autofocus: true,
          initialValue: cluster.label,
          decoration: const InputDecoration(labelText: 'Job title'),
          onChanged: (v) => jobTitle = v,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, jobTitle),
            child: const Text('Draft role'),
          ),
        ],
      ),
    );
    if (title == null || title.trim().isEmpty || !mounted) return;

    final taskIds = [for (final i in cluster.items) i.task.id];
    try {
      await ref.read(roleScorecardRepositoryProvider).createDraftRoleFromTasks(
            companyId: companyId ?? '',
            jobTitle: title.trim(),
            taskIds: taskIds,
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not draft role: $e')));
      return;
    }
    if (!mounted) return;
    _invalidate();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          "Drafted '${title.trim()}' (inactive) with ${taskIds.length} responsibilities."),
    ));
  }

  /// Mirrors `TasksTab._invalidateAfterTaskChange`: any mutation here moves a
  /// task off a card, onto a card, or out of the ACTIVE set entirely, all of
  /// which the Balance and Role View tabs derive their numbers from.
  void _invalidate() {
    ref.invalidate(wpTasksProvider);
    ref.invalidate(wpPersonLoadsProvider);
    ref.invalidate(wpAllTaskComputedProvider);
    ref.invalidate(ownerComputedProvider);
    ref.invalidate(roleScorecardListProvider);
  }
}
