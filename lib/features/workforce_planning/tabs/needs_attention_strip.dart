import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/status_colors.dart';
import '../../../data/repositories/role_scorecard_repository.dart';
import '../needs_attention.dart';
import '../wp_providers.dart';
import 'tab_intro.dart';

/// Hub tabs live in the same DefaultTabController (Balance 0, Roles 1,
/// Structure 2, Tasks 3, Unassigned 4). KPI library is a separate route.
void _go(BuildContext context, AttentionTarget target) {
  const tabIndex = {
    AttentionTarget.roles: 1,
    AttentionTarget.tasks: 3,
    AttentionTarget.unassigned: 4,
  };
  final idx = tabIndex[target];
  if (idx != null) {
    DefaultTabController.of(context).animateTo(idx);
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

/// Derived gaps in the current plan, surfaced at the top of the Balance tab —
/// over-capacity people, unowned or uncosted work, unstaffed critical roles,
/// KPIs measuring nobody. Each row deep-links to the tab/route that fixes it.
///
/// Self-contained: watches its own providers and disappears entirely
/// (`SizedBox.shrink()`) while loading or once there is nothing to flag, so
/// it never costs a spinner or a layout jump on the tab it sits above.
class NeedsAttentionStrip extends ConsumerWidget {
  const NeedsAttentionStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loads = ref.watch(wpPersonLoadsProvider).asData?.value;
    final tasks = ref.watch(wpTasksProvider).asData?.value;
    final employees = ref.watch(wpActiveEmployeesProvider).asData?.value;
    final cards = ref.watch(roleScorecardListProvider).asData?.value;
    final kpis = ref.watch(kpiLibraryProvider).asData?.value;
    final kpiAssignedByKpi = ref.watch(kpiAssignedEmployeesProvider).asData?.value;

    if (loads == null ||
        tasks == null ||
        employees == null ||
        cards == null ||
        kpis == null ||
        kpiAssignedByKpi == null) {
      return const SizedBox.shrink();
    }

    final items = buildNeedsAttention(
      loads: loads,
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
                        for (final item in items.where((i) => i.category == category))
                          if (item.target == AttentionTarget.balance)
                            StatusChip(
                              label: item.label,
                              tone: item.severity == AttentionSeverity.high
                                  ? StatusTone.danger
                                  : StatusTone.warning,
                            )
                          else
                            InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => _go(context, item.target),
                              child: StatusChip(
                                label: item.label,
                                tone: item.severity == AttentionSeverity.high
                                    ? StatusTone.danger
                                    : StatusTone.warning,
                              ),
                            ),
                      ],
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
