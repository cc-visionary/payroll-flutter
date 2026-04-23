import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/tokens.dart';
import '../../../data/models/statutory_payable.dart';
import '../../../data/models/hiring_entity.dart';
import '../providers.dart';

/// Top-of-screen filter row: period (single month or custom range), brand
/// multi-select, agency multi-select. Stays a single Wrap so it reflows
/// gracefully on narrow viewports without forcing a separate mobile layout.
class PayablesFilterBar extends ConsumerWidget {
  const PayablesFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(compliancePeriodProvider);
    final brandsAsync = ref.watch(complianceBrandsProvider);
    final brandFilter = ref.watch(complianceBrandFilterProvider);
    final agencyFilter = ref.watch(complianceAgencyFilterProvider);

    final brandLabel = _summariseBrandFilter(
      brandFilter,
      brandsAsync.asData?.value ?? const [],
    );

    return Wrap(
      spacing: LuxiumSpacing.md,
      runSpacing: LuxiumSpacing.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _PeriodControl(period: period),
        _BrandPickerButton(
          label: brandLabel,
          selectedCount: brandFilter.length,
          brands: brandsAsync.asData?.value ?? const [],
        ),
        _AgencyChipsRow(selected: agencyFilter),
        if (brandFilter.isNotEmpty || agencyFilter.isNotEmpty)
          TextButton.icon(
            onPressed: () {
              ref.read(complianceBrandFilterProvider.notifier).clear();
              ref.read(complianceAgencyFilterProvider.notifier).clear();
            },
            icon: const Icon(Icons.clear, size: 16),
            label: const Text('Clear filters'),
          ),
      ],
    );
  }

  String _summariseBrandFilter(Set<String> ids, List<HiringEntity> brands) {
    if (ids.isEmpty) return 'All brands';
    if (ids.length == 1) {
      final match = brands.where((b) => b.id == ids.first).firstOrNull;
      return match?.name ?? '1 brand';
    }
    return '${ids.length} brands';
  }
}

class _PeriodControl extends ConsumerWidget {
  final CompliancePeriod period;
  const _PeriodControl({required this.period});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SegmentedButton<PeriodMode>(
          segments: const [
            ButtonSegment(
              value: PeriodMode.singleMonth,
              label: Text('Month'),
              icon: Icon(Icons.event, size: 16),
            ),
            ButtonSegment(
              value: PeriodMode.customRange,
              label: Text('Range'),
              icon: Icon(Icons.date_range, size: 16),
            ),
          ],
          selected: {period.mode},
          onSelectionChanged: (s) async {
            final mode = s.first;
            if (mode == PeriodMode.singleMonth) {
              ref
                  .read(compliancePeriodProvider.notifier)
                  .setSingleMonth(period.year, period.month);
            } else {
              await _pickRange(context, ref);
            }
          },
        ),
        const SizedBox(width: LuxiumSpacing.sm),
        OutlinedButton.icon(
          icon: const Icon(Icons.edit_calendar_outlined, size: 16),
          label: Text(period.label()),
          onPressed: () => period.mode == PeriodMode.singleMonth
              ? _pickMonth(context, ref)
              : _pickRange(context, ref),
        ),
      ],
    );
  }

  Future<void> _pickMonth(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(period.year, period.month, 1),
      firstDate: DateTime(now.year - 5, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: 'Pick remittance month',
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null) {
      ref
          .read(compliancePeriodProvider.notifier)
          .setSingleMonth(picked.year, picked.month);
    }
  }

  Future<void> _pickRange(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange:
          DateTimeRange(start: period.rangeStart, end: period.rangeEnd),
      firstDate: DateTime(now.year - 5, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: 'Remittance period',
      saveText: 'Use range',
      fieldStartLabelText: 'From',
      fieldEndLabelText: 'To',
    );
    if (picked != null) {
      ref
          .read(compliancePeriodProvider.notifier)
          .setRange(picked.start, picked.end);
    }
  }
}

class _BrandPickerButton extends ConsumerWidget {
  final String label;
  final int selectedCount;
  final List<HiringEntity> brands;
  const _BrandPickerButton({
    required this.label,
    required this.selectedCount,
    required this.brands,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.business_outlined, size: 16),
      label: Text(label),
      onPressed: () async {
        final updated = await showDialog<Set<String>>(
          context: context,
          builder: (_) => _BrandMultiSelectDialog(
            brands: brands,
            initial: ref.read(complianceBrandFilterProvider),
          ),
        );
        if (updated != null) {
          ref
              .read(complianceBrandFilterProvider.notifier)
              .setAll(updated);
        }
      },
    );
  }
}

class _BrandMultiSelectDialog extends StatefulWidget {
  final List<HiringEntity> brands;
  final Set<String> initial;
  const _BrandMultiSelectDialog({
    required this.brands,
    required this.initial,
  });

  @override
  State<_BrandMultiSelectDialog> createState() =>
      _BrandMultiSelectDialogState();
}

class _BrandMultiSelectDialogState extends State<_BrandMultiSelectDialog> {
  late final Set<String> _selected = Set<String>.from(widget.initial);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Filter by brand'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final b in widget.brands)
                CheckboxListTile(
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _selected.contains(b.id),
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selected.add(b.id);
                      } else {
                        _selected.remove(b.id);
                      }
                    });
                  },
                  title: Text(b.name),
                  subtitle: Text(b.code),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(_selected.clear),
          child: const Text('Clear'),
        ),
        const Spacer(),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selected),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _AgencyChipsRow extends ConsumerWidget {
  final Set<StatutoryAgency> selected;
  const _AgencyChipsRow({required this.selected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: LuxiumSpacing.xs,
      children: [
        for (final a in StatutoryAgency.values)
          FilterChip(
            label: Text(a.shortLabel),
            selected: selected.contains(a),
            onSelected: (_) =>
                ref.read(complianceAgencyFilterProvider.notifier).toggle(a),
          ),
      ],
    );
  }
}

extension _IterableFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
