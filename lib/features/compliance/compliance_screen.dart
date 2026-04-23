import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/breakpoints.dart';
import '../../app/shell.dart';
import '../../app/status_colors.dart';
import '../../app/tokens.dart';
import '../../data/repositories/statutory_payables_repository.dart';
import 'payables_export.dart';
import 'providers.dart';
import 'widgets/payables_filter_bar.dart';
import 'widgets/payables_table.dart';

/// Statutory Payables Ledger — replaces the prior Compliance coming-soon.
///
/// Layout:
///   [filter bar — period / brand / agency / export]
///   [unassigned-employees warning, when relevant]
///   [main table — one row per (brand × month × agency)]
///
/// State lives in `providers.dart`; this screen is mostly composition.
class ComplianceScreen extends ConsumerWidget {
  const ComplianceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mobile = isMobile(context);
    return Scaffold(
      appBar: mobile
          ? AppBar(title: const Text('Compliance'))
          : null,
      drawer: mobile ? const AppDrawer() : null,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(LuxiumSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!mobile)
                Padding(
                  padding: const EdgeInsets.only(bottom: LuxiumSpacing.md),
                  child: Text(
                    'Statutory Payables',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
              const _ToolbarRow(),
              const SizedBox(height: LuxiumSpacing.md),
              const _UnassignedWarning(),
              const SizedBox(height: LuxiumSpacing.md),
              const Expanded(
                child: Card(child: PayablesTable()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolbarRow extends ConsumerWidget {
  const _ToolbarRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Expanded(child: PayablesFilterBar()),
        const SizedBox(width: LuxiumSpacing.sm),
        IconButton(
          tooltip: 'Refresh — re-fetch payables and payments from the database. '
              'Use after editing an employee\'s statutory employer of record.',
          icon: const Icon(Icons.refresh, size: 20),
          onPressed: () {
            ref.invalidate(compliancePayablesProvider);
            ref.invalidate(compliancePaidSummariesProvider);
            ref.invalidate(complianceUnassignedCountProvider);
            ref.invalidate(pendingStatutoryPayablesCountProvider);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Refreshed.'),
                duration: Duration(seconds: 1),
              ),
            );
          },
        ),
        const SizedBox(width: LuxiumSpacing.sm),
        _ExportMenu(),
      ],
    );
  }
}

class _ExportMenu extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brandFilter = ref.watch(complianceBrandFilterProvider);
    final selectedSingleBrand = brandFilter.length == 1;

    return MenuAnchor(
      builder: (context, controller, _) => FilledButton.icon(
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.file_download_outlined, size: 18),
        label: const Text('Export'),
      ),
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.dashboard_outlined),
          onPressed: () => _runExport(context, ref, singleBrand: false),
          child: const Text('Export current view (multi-sheet)'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.business_outlined),
          onPressed: selectedSingleBrand
              ? () => _runExport(context, ref, singleBrand: true)
              : null,
          child: const Text('Export selected brand only'),
        ),
      ],
    );
  }

  Future<void> _runExport(
    BuildContext context,
    WidgetRef ref, {
    required bool singleBrand,
  }) async {
    final repo = ref.read(statutoryPayablesRepositoryProvider);
    final period = ref.read(compliancePeriodProvider);
    final brandFilter = ref.read(complianceBrandFilterProvider);
    final agencyFilter = ref.read(complianceAgencyFilterProvider);
    final brandsAsync = ref.read(complianceBrandsProvider);
    final brands = brandsAsync.asData?.value ?? const [];
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;

    final effectiveBrandFilter = singleBrand && brandFilter.length == 1
        ? brandFilter
        : brandFilter;

    try {
      final sheets = await buildBrandSheetsFromCurrentFilter(
        client: Supabase.instance.client,
        repo: repo,
        period: period,
        brandFilter: effectiveBrandFilter,
        agencyFilter: agencyFilter,
        brands: brands,
      );
      if (sheets.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Nothing to export for the current filter.')),
        );
        return;
      }
      final path = await exportPayablesXlsx(
        sheets: sheets,
        periodLabel: period.label(),
        isCustomRange: period.mode == PeriodMode.customRange,
      );
      if (path != null) {
        messenger.showSnackBar(SnackBar(content: Text('Saved: $path')));
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: errorColor,
        ),
      );
    }
  }
}

class _UnassignedWarning extends ConsumerWidget {
  const _UnassignedWarning();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countAsync = ref.watch(complianceUnassignedCountProvider);
    final count = countAsync.asData?.value ?? 0;
    if (count == 0) return const SizedBox.shrink();
    final warn = StatusPalette.of(context, StatusTone.warning);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LuxiumSpacing.md,
        vertical: LuxiumSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: warn.background,
        borderRadius: BorderRadius.circular(LuxiumRadius.lg),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_outlined, size: 18, color: warn.foreground),
          const SizedBox(width: LuxiumSpacing.sm),
          Expanded(
            child: Text(
              '$count active employee${count == 1 ? "" : "s"} have no '
              'hiring entity set — their statutory contributions are excluded '
              'from this ledger.',
              style: TextStyle(color: warn.foreground),
            ),
          ),
        ],
      ),
    );
  }
}
