import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/status_colors.dart';
import '../../../data/repositories/role_scorecard_repository.dart';
import '../needs_attention.dart';
import '../role_load.dart';
import '../wp_providers.dart';
import 'tab_intro.dart';

/// Hub tabs live in the same DefaultTabController (Roles 0, Organization 1,
/// All tasks 2). KPI library is a separate route. The strip itself renders
/// only on the Roles tab, so [AttentionTarget.roles] has no link: its chips
/// are plain (see [NeedsAttentionStrip]).
void _go(BuildContext context, AttentionTarget target) {
  if (target == AttentionTarget.tasks) {
    DefaultTabController.of(context).animateTo(2);
  } else if (target == AttentionTarget.kpiLibrary) {
    context.push('/kpi-library');
  }
}

String _categoryLabel(AttentionCategory c) => switch (c) {
  AttentionCategory.people => 'People',
  AttentionCategory.process => 'Process',
  AttentionCategory.structure => 'Structure',
  AttentionCategory.tools => 'Tools',
};

/// Derived gaps in the current plan, surfaced at the top of the Roles tab —
/// over-capacity roles, tasks with no role or flagged for a check, uncosted
/// work, unstaffed critical roles, KPIs measuring nobody. A chip whose fix is
/// elsewhere (All tasks, KPI library) deep-links there; a chip whose fix is on
/// the Roles tab — where the strip already sits — is a plain chip.
///
/// Self-contained: watches its own providers and disappears entirely
/// (`SizedBox.shrink()`) while loading or once there is nothing to flag, so
/// it never costs a spinner or a layout jump on the tab it sits above.
class NeedsAttentionStrip extends ConsumerWidget {
  const NeedsAttentionStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loads = ref.watch(wpPersonLoadsProvider).asData?.value;
    final computed = ref.watch(wpAllTaskComputedProvider).asData?.value;
    final configAsync = ref.watch(wpConfigProvider);
    final multiplier = ref.watch(wpGrowthMultiplierProvider);
    final tasks = ref.watch(wpTasksProvider).asData?.value;
    final employees = ref.watch(wpActiveEmployeesProvider).asData?.value;
    final cards = ref.watch(roleScorecardListProvider).asData?.value;
    final kpis = ref.watch(kpiLibraryProvider).asData?.value;
    final kpiAssignedByKpi = ref
        .watch(kpiAssignedEmployeesProvider)
        .asData
        ?.value;

    if (loads == null ||
        computed == null ||
        !configAsync.hasValue ||
        tasks == null ||
        employees == null ||
        cards == null ||
        kpis == null ||
        kpiAssignedByKpi == null) {
      return const SizedBox.shrink();
    }

    // Built exactly as the Roles board builds its cards, so a chip's count
    // matches what a manager sees after clicking through.
    final roleLoads = buildRoleLoads(
      roles: cards.where((c) => c.isActive).toList(),
      employees: employees,
      tasks: tasks,
      hoursByTaskId: {
        for (final c in computed) c.taskId: taskHours(c, multiplier),
      },
      capacityByEmployee: {
        for (final l in loads) l.employeeId: l.capacityHours,
      },
      defaultCapacity: configAsync.value?.defaultCapacityHours ?? 160,
    );

    final items = buildNeedsAttention(
      roleLoads: roleLoads,
      tasks: tasks,
      employees: employees,
      cards: cards,
      kpis: kpis,
      kpiAssignedByKpi: kpiAssignedByKpi,
    );
    if (items.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TabIntro(
            purpose: 'Needs attention',
            details: const [WpGlossary.needsAttention],
          ),
          const SizedBox(height: 8),
          for (final category in AttentionCategory.values)
            if (items.any((i) => i.category == category))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _categoryLabel(category),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final item in items.where(
                          (i) => i.category == category,
                        ))
                          _chip(context, item),
                      ],
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, AttentionItem item) {
    final chip = StatusChip(
      label: item.label,
      tone: item.severity == AttentionSeverity.high
          ? StatusTone.danger
          : StatusTone.warning,
    );
    if (item.target == AttentionTarget.roles) return chip;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _go(context, item.target),
      child: chip,
    );
  }
}
