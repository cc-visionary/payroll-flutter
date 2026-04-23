import 'package:data_table_2/data_table_2.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/status_colors.dart';
import '../../../app/theme.dart';
import '../../../app/tokens.dart';
import '../../../data/models/hiring_entity.dart';
import '../../../data/models/statutory_payable.dart';
import '../providers.dart';
import 'mark_as_paid_dialog.dart';
import 'payable_breakdown_drawer.dart';
import 'view_payments_dialog.dart';

/// Main table — one row per (brand × month × agency). Built atop the
/// existing data_table_2 widget for consistency with the payroll-runs
/// disbursement table; the parent screen wraps it in a [Card].
class PayablesTable extends ConsumerWidget {
  const PayablesTable({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rowsAsync = ref.watch(complianceTableRowsProvider);
    final brandsAsync = ref.watch(complianceBrandsProvider);
    final period = ref.watch(compliancePeriodProvider);

    return rowsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(LuxiumSpacing.lg),
          child: Text('Error loading payables: $e',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return _EmptyState(periodLabel: period.label());
        }
        final brandsById = <String, HiringEntity>{
          for (final b in brandsAsync.asData?.value ?? const []) b.id: b,
        };
        final sorted = [...rows]..sort((a, b) {
            final ay = a.payable.periodYear * 100 + a.payable.periodMonth;
            final by = b.payable.periodYear * 100 + b.payable.periodMonth;
            if (ay != by) return by.compareTo(ay); // newest period first
            final an = brandsById[a.payable.hiringEntityId]?.name ?? '';
            final bn = brandsById[b.payable.hiringEntityId]?.name ?? '';
            final brandCmp = an.compareTo(bn);
            if (brandCmp != 0) return brandCmp;
            return a.payable.agency.index.compareTo(b.payable.agency.index);
          });

        return DataTable2(
          columnSpacing: 16,
          horizontalMargin: 16,
          minWidth: 1200,
          columns: const [
            DataColumn2(label: Text('Brand'), size: ColumnSize.M),
            DataColumn2(label: Text('Period'), size: ColumnSize.S),
            DataColumn2(label: Text('Agency'), size: ColumnSize.M),
            DataColumn2(
              label: Text('Employees'),
              size: ColumnSize.S,
              numeric: true,
            ),
            DataColumn2(
              label: Text('Amount Due'),
              size: ColumnSize.M,
              numeric: true,
            ),
            DataColumn2(label: Text('Status'), size: ColumnSize.S),
            DataColumn2(label: Text('Last Paid'), size: ColumnSize.S),
            DataColumn2(
              label: Text('Amount Paid'),
              size: ColumnSize.M,
              numeric: true,
            ),
            DataColumn2(
              label: Text('Variance'),
              size: ColumnSize.S,
              numeric: true,
            ),
            DataColumn2(label: Text(''), size: ColumnSize.M),
          ],
          rows: [
            for (final row in sorted)
              _buildRow(context, ref, row, brandsById),
          ],
        );
      },
    );
  }

  DataRow2 _buildRow(
    BuildContext context,
    WidgetRef ref,
    CompliancePayableRow row,
    Map<String, HiringEntity> brandsById,
  ) {
    final brand = brandsById[row.payable.hiringEntityId];
    final paid = row.paid?.amountPaid ?? Decimal.zero;
    final variance = paid - row.payable.amountDue;
    final status = classifyPayable(row.payable.amountDue, paid);

    return DataRow2(
      onTap: () => _openBreakdown(context, row, brand),
      cells: [
        DataCell(Text(brand?.name ?? row.payable.hiringEntityId)),
        DataCell(Text(_periodLabel(row.payable))),
        DataCell(Text(row.payable.agency.fullLabel)),
        DataCell(Text('${row.payable.employeeCount}')),
        DataCell(_money(context, row.payable.amountDue)),
        DataCell(_StatusChip(status: status)),
        DataCell(Text(row.paid?.lastPaidOn == null
            ? '—'
            : DateFormat('MMM d, y').format(row.paid!.lastPaidOn!))),
        DataCell(_money(context, paid)),
        DataCell(_varianceCell(context, variance)),
        DataCell(_RowActions(row: row, brand: brand)),
      ],
    );
  }

  String _periodLabel(StatutoryPayable payable) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[payable.periodMonth - 1]} ${payable.periodYear}';
  }

  Widget _money(BuildContext context, Decimal v) {
    final s = NumberFormat.currency(symbol: '₱', decimalDigits: 2)
        .format(v.toDouble());
    return Text(s, style: AppTheme.mono(context));
  }

  Widget _varianceCell(BuildContext context, Decimal v) {
    final isZero = v.abs() < Decimal.parse('0.01');
    final text = isZero
        ? '—'
        : NumberFormat.currency(symbol: '₱', decimalDigits: 2)
            .format(v.toDouble());
    final color = isZero
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : (v < Decimal.zero
            ? StatusPalette.of(context, StatusTone.warning).foreground
            : StatusPalette.of(context, StatusTone.info).foreground);
    return Text(
      text,
      style: AppTheme.mono(context, color: color),
    );
  }

  void _openBreakdown(
    BuildContext context,
    CompliancePayableRow row,
    HiringEntity? brand,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PayableBreakdownDrawer(
        payable: row.payable,
        brand: brand,
      ),
    );
  }
}

class _RowActions extends ConsumerWidget {
  final CompliancePayableRow row;
  final HiringEntity? brand;
  const _RowActions({required this.row, required this.brand});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paid = row.paid?.amountPaid ?? Decimal.zero;
    final hasPayments = paid > Decimal.zero;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton.icon(
          icon: const Icon(Icons.payments_outlined, size: 16),
          label: const Text('Mark Paid'),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => MarkAsPaidDialog(payable: row.payable, brand: brand),
          ),
        ),
        if (hasPayments) ...[
          const SizedBox(width: 4),
          TextButton.icon(
            icon: const Icon(Icons.list_alt_outlined, size: 16),
            label: const Text('View'),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => ViewPaymentsDialog(
                payable: row.payable,
                brand: brand,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final PayableStatus status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final tone = switch (status) {
      PayableStatus.unpaid => StatusTone.neutral,
      PayableStatus.partial => StatusTone.warning,
      PayableStatus.paid => StatusTone.success,
      PayableStatus.overpaid => StatusTone.info,
    };
    return StatusChip(label: status.label, tone: tone);
  }
}

class _EmptyState extends StatelessWidget {
  final String periodLabel;
  const _EmptyState({required this.periodLabel});

  @override
  Widget build(BuildContext context) {
    final p = LuxiumColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(LuxiumSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined, size: 48, color: p.soft),
            const SizedBox(height: LuxiumSpacing.md),
            Text(
              'No statutory payables for $periodLabel.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: LuxiumSpacing.xs),
            Text(
              'Try a different period or release a payroll run.',
              style: TextStyle(color: p.soft),
            ),
          ],
        ),
      ),
    );
  }
}
