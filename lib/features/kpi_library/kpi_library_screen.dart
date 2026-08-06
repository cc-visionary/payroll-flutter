import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/breakpoints.dart';
import '../../app/shell.dart';
import '../../data/models/kpi.dart';
import '../../data/models/department.dart';
import '../../data/repositories/department_repository.dart';
import '../../data/repositories/role_scorecard_repository.dart';
import '../../app/status_colors.dart';
import '../auth/profile_provider.dart';
import 'kpi_form_dialog.dart';
import 'kpi_rows.dart';

/// HR-facing screen for managing the shared KPI library (`kpis` table) that
/// role cards pick from. Groups KPIs by category, with a "New KPI" action and
/// per-row edit/deactivate. Mirrors `ResponsibilityCardsScreen` for the
/// page-level layout and `RolesSettingsScreen`'s `_RoleForm` pattern for the
/// dialog-driven create/edit/delete flow. Reachable only by HR/Admin — see
/// the `/kpi-library` redirect guard in `app/router.dart`.
class KpiLibraryScreen extends ConsumerStatefulWidget {
  const KpiLibraryScreen({super.key});

  @override
  ConsumerState<KpiLibraryScreen> createState() => _KpiLibraryScreenState();
}

class _KpiLibraryScreenState extends ConsumerState<KpiLibraryScreen> {
  KpiFilter _filter = const KpiFilter();
  final _searchCtl = TextEditingController();

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(kpiLibraryProvider);
    final assignedAsync = ref.watch(kpiAssignedEmployeesProvider);
    final deptNames = <String, String>{
      for (final d
          in ref.watch(departmentListProvider).asData?.value ??
              const <Department>[])
        d.id: d.name,
    };
    final companyId = ref.watch(userProfileProvider).asData?.value?.companyId;
    final mobile = isMobile(context);

    return Scaffold(
      drawer: mobile ? const AppDrawer() : null,
      appBar: AppBar(
        title: const Text('KPI Library'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: mobile
                ? IconButton(
                    tooltip: 'New KPI',
                    onPressed: companyId == null
                        ? null
                        : () => _openForm(context, ref, companyId),
                    icon: const Icon(Icons.add),
                  )
                : FilledButton.icon(
                    onPressed: companyId == null
                        ? null
                        : () => _openForm(context, ref, companyId),
                    icon: const Icon(Icons.add),
                    label: const Text('New KPI'),
                  ),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Error: $e', style: const TextStyle(color: Colors.red)),
        ),
        data: (kpis) {
          if (kpis.isEmpty) {
            return const Center(child: Text('No KPIs yet. Click "New KPI".'));
          }
          final assigned =
              assignedAsync.asData?.value ??
              const <String, List<KpiAssignee>>{};
          final stats = kpiLibraryStats(
            kpis,
            assigned,
            departmentNameById: deptNames,
          );
          final shown = applyKpiFilter(
            kpis,
            _filter,
            assigned,
            departmentNameById: deptNames,
          );
          // Department first, then category: a KPI is a departmental measure
          // before it is a personal one, and the department is who answers for
          // the number.
          final grouped = groupKpisByDepartment(shown, deptNames);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _statsBar(context, stats),
              const SizedBox(height: 12),
              _filterBar(context, kpis, stats, shown.length, deptNames),
              const SizedBox(height: 8),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: Text(
                      'No KPI matches these filters.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              for (final dept in grouped.keys) ...[
                _departmentHeader(context, dept, grouped[dept]!, assigned),
                for (final category in grouped[dept]!.keys) ...[
                  _categoryHeader(
                    context,
                    category,
                    grouped[dept]![category]!,
                    assigned,
                  ),
                  for (final kpi in grouped[dept]![category]!)
                    _KpiTile(
                      kpi: kpi,
                      assignedAsync: assignedAsync,
                      onEdit: companyId == null
                          ? null
                          : () => _openForm(
                              context,
                              ref,
                              companyId,
                              existing: kpi,
                            ),
                      onDeactivate: () => _confirmDeactivate(context, ref, kpi),
                    ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 8),
              ],
            ],
          );
        },
      ),
    );
  }

  /// What shape the library is in, before the list of rows. A library is
  /// judged by coverage — how much of it actually measures somebody — and that
  /// cannot be seen by scrolling 58 cards.
  Widget _statsBar(BuildContext context, KpiLibraryStats s) {
    final cs = Theme.of(context).colorScheme;
    Widget stat(String value, String label, {Color? tone}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: tone,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
      ],
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 40,
        runSpacing: 12,
        children: [
          stat('${s.active}', 'active KPIs'),
          stat('${s.departments}', 'departments'),
          stat('${s.categories}', 'categories'),
          stat(
            '${s.assigned}',
            'tracked on someone',
            tone: StatusPalette.of(context, StatusTone.success).foreground,
          ),
          if (s.unassigned > 0)
            stat(
              '${s.unassigned}',
              'measuring nobody',
              tone: StatusPalette.of(context, StatusTone.warning).foreground,
            ),
          if (s.uncategorized > 0)
            stat(
              '${s.uncategorized}',
              'uncategorised',
              tone: StatusPalette.of(context, StatusTone.warning).foreground,
            ),
          if (s.noDepartment > 0)
            stat(
              '${s.noDepartment}',
              'no department',
              tone: StatusPalette.of(context, StatusTone.warning).foreground,
            ),
          stat('${s.peopleTracked}', 'people tracked'),
        ],
      ),
    );
  }

  Widget _filterBar(
    BuildContext context,
    List<Kpi> all,
    KpiLibraryStats s,
    int shownCount,
    Map<String, String> deptNames,
  ) {
    final cs = Theme.of(context).colorScheme;
    void set(KpiFilter f) => setState(() => _filter = f);
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 260,
          child: TextField(
            controller: _searchCtl,
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Search name or measurement',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => set(
              KpiFilter(
                query: v,
                department: _filter.department,
                category: _filter.category,
                assignment: _filter.assignment,
                showInactive: _filter.showInactive,
              ),
            ),
          ),
        ),
        DropdownButton<String?>(
          value: _filter.department,
          hint: const Text('All departments'),
          underline: const SizedBox.shrink(),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('All departments'),
            ),
            for (final d in kpiDepartments(all, deptNames))
              DropdownMenuItem<String?>(value: d, child: Text(d)),
          ],
          onChanged: (v) => set(
            KpiFilter(
              query: _filter.query,
              department: v,
              category: _filter.category,
              assignment: _filter.assignment,
              showInactive: _filter.showInactive,
            ),
          ),
        ),
        DropdownButton<String?>(
          value: _filter.category,
          hint: const Text('All categories'),
          underline: const SizedBox.shrink(),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('All categories'),
            ),
            for (final c in kpiCategories(all))
              DropdownMenuItem<String?>(value: c, child: Text(c)),
          ],
          onChanged: (v) => set(
            KpiFilter(
              query: _filter.query,
              department: _filter.department,
              category: v,
              assignment: _filter.assignment,
              showInactive: _filter.showInactive,
            ),
          ),
        ),
        DropdownButton<bool?>(
          value: _filter.assignment,
          hint: const Text('Assigned or not'),
          underline: const SizedBox.shrink(),
          items: [
            const DropdownMenuItem<bool?>(
              value: null,
              child: Text('Assigned or not'),
            ),
            DropdownMenuItem<bool?>(
              value: true,
              child: Text('Tracked on someone (${s.assigned})'),
            ),
            DropdownMenuItem<bool?>(
              value: false,
              child: Text('Measuring nobody (${s.unassigned})'),
            ),
          ],
          onChanged: (v) => set(
            KpiFilter(
              query: _filter.query,
              department: _filter.department,
              category: _filter.category,
              assignment: v,
              showInactive: _filter.showInactive,
            ),
          ),
        ),
        FilterChip(
          label: const Text('Include deactivated'),
          selected: _filter.showInactive,
          onSelected: (v) => set(
            KpiFilter(
              query: _filter.query,
              department: _filter.department,
              category: _filter.category,
              assignment: _filter.assignment,
              showInactive: v,
            ),
          ),
        ),
        if (!_filter.isEmpty) ...[
          Text(
            '$shownCount shown',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          TextButton.icon(
            onPressed: () {
              _searchCtl.clear();
              set(const KpiFilter());
            },
            icon: const Icon(Icons.filter_alt_off, size: 16),
            label: const Text('Clear'),
          ),
        ],
      ],
    );
  }

  /// The primary grouping. A department owns its measures, so it owns the gap
  /// when some of them track nobody.
  Widget _departmentHeader(
    BuildContext context,
    String dept,
    Map<String, List<Kpi>> byCategory,
    Map<String, List<KpiAssignee>> assigned,
  ) {
    final cs = Theme.of(context).colorScheme;
    final all = [for (final v in byCategory.values) ...v];
    final tracked = all.where((k) => kpiIsAssigned(k, assigned)).length;
    final gap = all.length - tracked;
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Row(
        children: [
          Text(
            dept,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 10),
          Text(
            '${all.length} KPIs · ${byCategory.length} categories',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          if (gap > 0) ...[
            const SizedBox(width: 8),
            Text(
              '$gap measuring nobody',
              style: TextStyle(
                fontSize: 12,
                color: StatusPalette.of(context, StatusTone.warning).foreground,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _categoryHeader(
    BuildContext context,
    String category,
    List<Kpi> kpis,
    Map<String, List<KpiAssignee>> assigned,
  ) {
    final cs = Theme.of(context).colorScheme;
    final tracked = kpis.where((k) => kpiIsAssigned(k, assigned)).length;
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 6, bottom: 4),
      child: Row(
        children: [
          Text(
            category,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Text(
            '${kpis.length} · $tracked tracked',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref,
    String companyId, {
    Kpi? existing,
  }) async {
    final result = await showDialog<Kpi>(
      context: context,
      builder: (_) => KpiFormDialog(existing: existing),
    );
    if (result == null) return;
    try {
      await ref
          .read(roleScorecardRepositoryProvider)
          .saveLibraryKpi(
            id: existing?.id,
            companyId: companyId,
            name: result.name,
            category: result.category,
            description: result.description,
            measurementUnit: result.measurementUnit,
          );
    } catch (e) {
      if (!context.mounted) return;
      final duplicate =
          e.toString().contains('23505') ||
          e.toString().toLowerCase().contains('duplicate');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            duplicate
                ? 'A KPI with that name already exists.'
                : 'Could not save KPI: $e',
          ),
        ),
      );
      return;
    }
    ref.invalidate(kpiLibraryProvider);
  }

  Future<void> _confirmDeactivate(
    BuildContext context,
    WidgetRef ref,
    Kpi kpi,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Deactivate KPI?'),
        content: Text(
          'Remove "${kpi.name}" from the library? Role cards that already '
          'reference it keep their history, but it will no longer be '
          'selectable for new links.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(c).colorScheme.error,
            ),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(roleScorecardRepositoryProvider).deactivateKpi(kpi.id);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not deactivate KPI: $e')));
      return;
    }
    ref.invalidate(kpiLibraryProvider);
  }
}

class _KpiTile extends StatelessWidget {
  final Kpi kpi;
  final AsyncValue<Map<String, List<KpiAssignee>>> assignedAsync;
  final VoidCallback? onEdit;
  final VoidCallback onDeactivate;
  const _KpiTile({
    required this.kpi,
    required this.assignedAsync,
    required this.onEdit,
    required this.onDeactivate,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final measure = kpi.measurementUnit?.trim() ?? '';
    final desc = kpi.description?.trim() ?? '';
    // The measurement IS the description for most of these, so showing both
    // printed the same sentence twice per row and tripled the row height for
    // nothing. The measurement wins — it says how the number is computed — and
    // a description only appears when it genuinely adds something.
    final extraDesc =
        desc.isNotEmpty && desc.toLowerCase() != measure.toLowerCase()
        ? desc
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: kpi.isActive ? null : cs.surfaceContainerHighest,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 230,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  kpi.name,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (!kpi.isActive)
                  Text(
                    'Deactivated',
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  measure.isEmpty ? 'No measurement defined' : measure,
                  style: TextStyle(
                    fontSize: 12,
                    color: measure.isEmpty
                        ? StatusPalette.of(
                            context,
                            StatusTone.warning,
                          ).foreground
                        : cs.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (extraDesc.isNotEmpty)
                  Text(
                    extraDesc,
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(width: 210, child: _buildAssigneeLine(context)),
          const SizedBox(width: 8),
          if (onEdit != null)
            IconButton(
              tooltip: 'Edit',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.edit_outlined, size: 17),
              onPressed: onEdit,
            ),
          IconButton(
            tooltip: 'Deactivate',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove_circle_outline, size: 17),
            color: StatusPalette.of(context, StatusTone.danger).foreground,
            onPressed: onDeactivate,
          ),
        ],
      ),
    );
  }

  /// The muted "who's tracking this" subtitle. Loading renders a subtle
  /// spinner (not a blocking state); errors render nothing so a failure in
  /// this side provider never disrupts the rest of the KPI row.
  Widget _buildAssigneeLine(BuildContext context) {
    final mutedStyle = TextStyle(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontSize: 12,
    );
    return assignedAsync.when(
      data: (map) {
        final assignees = map[kpi.id] ?? const <KpiAssignee>[];
        if (assignees.isEmpty) {
          // Called out rather than muted: a KPI nobody is tracked on is
          // measuring nothing, which is the main thing this page should
          // surface about its own contents.
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_off_outlined,
                size: 13,
                color: StatusPalette.of(context, StatusTone.warning).foreground,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  'Measuring nobody',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: StatusPalette.of(
                      context,
                      StatusTone.warning,
                    ).foreground,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
        }
        final names = assignees.map((a) => a.name).join(', ');
        return Tooltip(
          message: names,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people_outline, size: 13, color: mutedStyle.color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  '${assignees.length} · $names',
                  style: mutedStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
      loading: () => SizedBox(
        height: 12,
        width: 12,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}
