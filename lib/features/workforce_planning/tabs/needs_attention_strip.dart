import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/status_colors.dart';
import '../../../data/repositories/role_scorecard_repository.dart';
import '../accountability_chart_screen.dart' show areasBySeat;
import '../needs_attention.dart';
import '../seat_tree.dart' show seatBoxes;
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
    final kpiAssignedByKpi = ref
        .watch(kpiAssignedEmployeesProvider)
        .asData
        ?.value;
    // Read defensively — this signal must never block first paint on the
    // strip's other, already-required providers. Safe here because an empty
    // assignment map yields ZERO misallocated responsibilities.
    final assignmentsByTask =
        ref.watch(wpAssignmentsByTaskProvider).asData?.value ?? const {};
    // Deliberately NOT given the same empty-map default. `asData` is null
    // while this FutureProvider re-resolves (every invalidation) and forever
    // if it throws, and empty maps here would read as "every ACTIVE holder in
    // the company has no KPI set" — the maximum, not zero. Passed through as
    // null so buildNeedsAttention skips the signal until it really knows.
    final kpiAssignmentMaps = ref
        .watch(wpKpiAssignmentMapsProvider)
        .asData
        ?.value;

    if (loads == null ||
        tasks == null ||
        employees == null ||
        cards == null ||
        kpis == null ||
        kpiAssignedByKpi == null) {
      return const SizedBox.shrink();
    }

    // Same derivation the Accountability Chart itself uses for a box's roles
    // (`areasBySeat()` in accountability_chart_screen.dart — authored areas
    // from wp_tasks, not the card's shared-appended `responsibilities`; see
    // that function's doc comment for why) and for what counts as an open
    // seat (`seatBoxes`' no-ACTIVE-holder rule) — so a chip's count matches
    // what the chart shows one click away.
    final areas = areasBySeat(tasks);
    final areaCountBySeat = {
      for (final entry in areas.entries) entry.key: entry.value.length,
    };
    final boxes = seatBoxes(
      seats: cards,
      employees: employees,
      areasBySeat: areas,
    );
    final holderCountBySeat = <String, int>{};
    for (final box in boxes) {
      holderCountBySeat[box.seatId] =
          (holderCountBySeat[box.seatId] ?? 0) + (box.isOpen ? 0 : 1);
    }

    final items = buildNeedsAttention(
      loads: loads,
      tasks: tasks,
      employees: employees,
      cards: cards,
      kpis: kpis,
      kpiAssignedByKpi: kpiAssignedByKpi,
      assignmentsByTask: assignmentsByTask,
      roleKpiIdsByCard: kpiAssignmentMaps?.roleKpiIdsByCard,
      assignedKpiIdsByEmployee: kpiAssignmentMaps?.assignedKpiIdsByEmployee,
      areaCountBySeat: areaCountBySeat,
      holderCountBySeat: holderCountBySeat,
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
