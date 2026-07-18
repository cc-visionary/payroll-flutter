import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/breakpoints.dart';
import '../../app/shell.dart';
import '../../data/models/kpi.dart';
import '../../data/repositories/role_scorecard_repository.dart';
import '../auth/profile_provider.dart';
import 'kpi_form_dialog.dart';

const String _kUncategorized = 'Uncategorized';

/// HR-facing screen for managing the shared KPI library (`kpis` table) that
/// role cards pick from. Groups KPIs by category, with a "New KPI" action and
/// per-row edit/deactivate. Mirrors `ResponsibilityCardsScreen` for the
/// page-level layout and `RolesSettingsScreen`'s `_RoleForm` pattern for the
/// dialog-driven create/edit/delete flow. Reachable only by HR/Admin — see
/// the `/kpi-library` redirect guard in `app/router.dart`.
class KpiLibraryScreen extends ConsumerWidget {
  const KpiLibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(kpiLibraryProvider);
    final assignedAsync = ref.watch(kpiAssignedEmployeesProvider);
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
          final grouped = _groupByCategory(kpis);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final category in grouped.keys) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: Text(
                    category,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                for (final kpi in grouped[category]!)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _KpiTile(
                      kpi: kpi,
                      assignedAsync: assignedAsync,
                      onEdit: companyId == null
                          ? null
                          : () =>
                              _openForm(context, ref, companyId, existing: kpi),
                      onDeactivate: () => _confirmDeactivate(context, ref, kpi),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  /// Groups [kpis] by `category` (blank/null → "Uncategorized"), sorted
  /// alphabetically with "Uncategorized" always last.
  static Map<String, List<Kpi>> _groupByCategory(List<Kpi> kpis) {
    final grouped = <String, List<Kpi>>{};
    for (final k in kpis) {
      final cat = k.category?.trim().isNotEmpty == true
          ? k.category!.trim()
          : _kUncategorized;
      (grouped[cat] ??= []).add(k);
    }
    final categories = grouped.keys.toList()
      ..sort((a, b) {
        if (a == _kUncategorized) return 1;
        if (b == _kUncategorized) return -1;
        return a.compareTo(b);
      });
    return {for (final c in categories) c: grouped[c]!};
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
      await ref.read(roleScorecardRepositoryProvider).saveLibraryKpi(
        id: existing?.id,
        companyId: companyId,
        name: result.name,
        category: result.category,
        description: result.description,
        measurementUnit: result.measurementUnit,
      );
    } catch (e) {
      if (!context.mounted) return;
      final duplicate = e.toString().contains('23505') ||
          e.toString().toLowerCase().contains('duplicate');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(duplicate
              ? 'A KPI with that name already exists.'
              : 'Could not save KPI: $e'),
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
            style:
                FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not deactivate KPI: $e')),
      );
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      kpi.name,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    if (kpi.measurementUnit != null &&
                        kpi.measurementUnit!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Chip(
                        label: Text(kpi.measurementUnit!,
                            style: const TextStyle(fontSize: 11)),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ],
                  ],
                ),
                if (kpi.description != null && kpi.description!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      kpi.description!,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _buildAssigneeLine(context),
                ),
              ],
            ),
          ),
          if (onEdit != null)
            TextButton(onPressed: onEdit, child: const Text('Edit')),
          TextButton(
            onPressed: onDeactivate,
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Deactivate'),
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
          return Text('Not currently tracked by anyone', style: mutedStyle);
        }
        final names = assignees.map((a) => a.name).join(', ');
        return Text(
          'Assigned (${assignees.length}): $names',
          style: mutedStyle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
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
