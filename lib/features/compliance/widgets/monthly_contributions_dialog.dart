import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/status_colors.dart';
import '../../../app/tokens.dart';
import '../../../data/repositories/audit_repository.dart';
import '../../../data/repositories/statutory_payables_repository.dart';
import '../monthly_contributions_export.dart';
import '../providers.dart';

/// Month + brand picker for the Monthly Contributions Report (the
/// per-employee declared-salary XLSX sent to the benefits accountant).
///
/// Defaults to the previous calendar month — the common case is closing
/// out last month's remittance after both cutoffs have been released.
/// Shows a warning when the selected month has fewer than 2 released
/// payroll runs, since the report would then be missing a cutoff.
class MonthlyContributionsDialog extends ConsumerStatefulWidget {
  const MonthlyContributionsDialog({super.key});

  @override
  ConsumerState<MonthlyContributionsDialog> createState() =>
      _MonthlyContributionsDialogState();
}

class _MonthlyContributionsDialogState
    extends ConsumerState<MonthlyContributionsDialog> {
  static const _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  late int _year;
  late int _month;
  final Set<String> _brandIds = <String>{};
  bool _exporting = false;
  int? _releasedRunCount; // null = loading

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final prev = DateTime(now.year, now.month - 1, 1);
    _year = prev.year;
    _month = prev.month;
    _loadRunCount();
  }

  Future<void> _loadRunCount() async {
    setState(() => _releasedRunCount = null);
    final year = _year;
    final month = _month;
    try {
      final count = await releasedRunCountForMonth(
        Supabase.instance.client,
        year,
        month,
      );
      // Selection may have moved on while this fetch was in flight.
      if (!mounted || year != _year || month != _month) return;
      setState(() => _releasedRunCount = count);
    } catch (_) {
      // Warning is best-effort; export itself surfaces real errors.
      if (!mounted || year != _year || month != _month) return;
      setState(() => _releasedRunCount = -1);
    }
  }

  Future<void> _export() async {
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    final navigator = Navigator.of(context);
    final audit = ref.read(auditRepositoryProvider);
    final label = monthlyContributionsMonthLabel(_year, _month);
    setState(() => _exporting = true);
    try {
      final sheets = await buildMonthlyContributionsSheets(
        client: Supabase.instance.client,
        repo: ref.read(statutoryPayablesRepositoryProvider),
        year: _year,
        month: _month,
        brandFilter: _brandIds,
        brands: ref.read(complianceBrandsProvider).asData?.value ?? const [],
      );
      if (sheets.isEmpty) {
        messenger.showSnackBar(
          SnackBar(content: Text('No released contributions for $label.')),
        );
        return;
      }
      final path = await exportMonthlyContributionsXlsx(
        sheets: sheets,
        year: _year,
        month: _month,
      );
      if (path == null) return; // user cancelled the save dialog
      final recordCount = sheets.fold<int>(0, (n, s) => n + s.rows.length);
      final fileName = path.replaceAll('\\', '/').split('/').last;
      audit.logExport(
        description:
            'Monthly contributions export: $fileName · $label · $recordCount employees',
        entityType: 'statutory_payables',
        metadata: {
          'file_name': fileName,
          'period': label,
          'record_count': recordCount,
          'brands': [for (final s in sheets) s.brand.name],
          'report': 'monthly_contributions',
        },
      );
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Saved: $path')));
        navigator.pop();
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: errorColor,
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final years = [for (var y = now.year; y >= now.year - 3; y--) y];
    final brands =
        ref.watch(complianceBrandsProvider).asData?.value ?? const [];
    final runCount = _releasedRunCount;

    return AlertDialog(
      title: const Text('Monthly Contributions Report'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Per-employee declared salary + the month\'s SSS, PhilHealth, '
              'Pag-IBIG and W/H tax deductions, for the benefits accountant.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: LuxiumSpacing.md),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _month,
                    decoration: const InputDecoration(labelText: 'Month'),
                    items: [
                      for (var m = 1; m <= 12; m++)
                        DropdownMenuItem(
                          value: m,
                          child: Text(_monthNames[m - 1]),
                        ),
                    ],
                    onChanged: _exporting
                        ? null
                        : (v) {
                            if (v == null) return;
                            setState(() => _month = v);
                            _loadRunCount();
                          },
                  ),
                ),
                const SizedBox(width: LuxiumSpacing.sm),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: years.contains(_year) ? _year : years.first,
                    decoration: const InputDecoration(labelText: 'Year'),
                    items: [
                      for (final y in years)
                        DropdownMenuItem(value: y, child: Text('$y')),
                    ],
                    onChanged: _exporting
                        ? null
                        : (v) {
                            if (v == null) return;
                            setState(() => _year = v);
                            _loadRunCount();
                          },
                  ),
                ),
              ],
            ),
            const SizedBox(height: LuxiumSpacing.md),
            Text('Brands', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: LuxiumSpacing.xs),
            Wrap(
              spacing: LuxiumSpacing.xs,
              runSpacing: LuxiumSpacing.xs,
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: _brandIds.isEmpty,
                  onSelected: _exporting
                      ? null
                      : (_) => setState(() => _brandIds.clear()),
                ),
                for (final b in brands)
                  FilterChip(
                    label: Text(b.name),
                    selected: _brandIds.contains(b.id),
                    onSelected: _exporting
                        ? null
                        : (_) => setState(() {
                            if (!_brandIds.remove(b.id)) {
                              _brandIds.add(b.id);
                            }
                          }),
                  ),
              ],
            ),
            if (runCount != null && runCount >= 0 && runCount < 2) ...[
              const SizedBox(height: LuxiumSpacing.md),
              Builder(
                builder: (context) {
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
                        Icon(
                          Icons.warning_amber_outlined,
                          size: 18,
                          color: warn.foreground,
                        ),
                        const SizedBox(width: LuxiumSpacing.sm),
                        Expanded(
                          child: Text(
                            runCount == 0
                                ? 'No released payroll runs found for '
                                      '${monthlyContributionsMonthLabel(_year, _month)} '
                                      '— the report will be empty.'
                                : 'Only 1 released cutoff found for '
                                      '${monthlyContributionsMonthLabel(_year, _month)} '
                                      '— the report may be missing half the month.',
                            style: TextStyle(color: warn.foreground),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _exporting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _exporting ? null : _export,
          icon: _exporting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.file_download_outlined, size: 18),
          label: const Text('Export'),
        ),
      ],
    );
  }
}
