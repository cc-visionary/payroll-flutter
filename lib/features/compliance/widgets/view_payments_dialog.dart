import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/status_colors.dart';
import '../../../app/theme.dart';
import '../../../app/tokens.dart';
import '../../../data/models/hiring_entity.dart';
import '../../../data/models/statutory_payable.dart';
import '../../../data/models/statutory_payment.dart';
import '../../../data/repositories/statutory_payables_repository.dart';
import '../../auth/profile_provider.dart';
import '../providers.dart';

/// All ledger rows (active + voided) for a single (brand × period × agency).
/// Lets HR audit and act on individual payments — Edit replaces a row by
/// inserting a corrected entry + voiding the prior; Void prompts for the
/// reason and stamps `voided_at + voided_by + void_reason`.
class ViewPaymentsDialog extends ConsumerWidget {
  final StatutoryPayable payable;
  final HiringEntity? brand;
  const ViewPaymentsDialog({
    super.key,
    required this.payable,
    required this.brand,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = StatutoryPaymentsQuery(
      hiringEntityId: payable.hiringEntityId,
      periodYear: payable.periodYear,
      periodMonth: payable.periodMonth,
      agency: payable.agency,
    );
    final paymentsAsync = ref.watch(statutoryPaymentsProvider(query));

    return AlertDialog(
      title: Text('Payments — ${payable.agency.shortLabel}'),
      content: SizedBox(
        width: 600,
        child: paymentsAsync.when(
          loading: () => const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('Error: $e',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          data: (payments) {
            if (payments.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(LuxiumSpacing.lg),
                child: Text('No payments recorded yet.'),
              );
            }
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${brand?.name ?? payable.hiringEntityId} • ${_periodLabel(payable)}',
                    style: TextStyle(color: LuxiumColors.of(context).soft),
                  ),
                  const SizedBox(height: LuxiumSpacing.md),
                  for (final p in payments) ...[
                    _PaymentTile(payment: p, query: query),
                    const Divider(height: 1),
                  ],
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _PaymentTile extends ConsumerWidget {
  final StatutoryPayment payment;
  final StatutoryPaymentsQuery query;
  const _PaymentTile({required this.payment, required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final money = NumberFormat.currency(symbol: '₱', decimalDigits: 2)
        .format(payment.amountPaid.toDouble());
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: LuxiumSpacing.sm,
        vertical: 4,
      ),
      title: Row(
        children: [
          Text(money, style: AppTheme.mono(context, fontWeight: FontWeight.w600)),
          const SizedBox(width: LuxiumSpacing.sm),
          if (payment.isVoided)
            const StatusChip(label: 'Voided', tone: StatusTone.danger),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Paid ${DateFormat('MMM d, y').format(payment.paidOn)}'
            '${payment.referenceNo != null ? " • Ref: ${payment.referenceNo}" : ""}',
            style: const TextStyle(fontSize: 12),
          ),
          if (payment.notes != null && payment.notes!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(payment.notes!,
                  style: const TextStyle(fontSize: 12)),
            ),
          if (payment.isVoided && payment.voidReason != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Void reason: ${payment.voidReason}',
                style: TextStyle(
                  fontSize: 12,
                  color: StatusPalette.of(context, StatusTone.danger).foreground,
                ),
              ),
            ),
        ],
      ),
      trailing: payment.isVoided
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Void',
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () => _confirmVoid(context, ref),
                ),
              ],
            ),
    );
  }

  Future<void> _confirmVoid(BuildContext context, WidgetRef ref) async {
    final reasonCtl = TextEditingController();
    final reason = await showDialog<String?>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Void payment?'),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: reasonCtl,
            decoration: const InputDecoration(
              labelText: 'Reason',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            maxLines: 2,
            autofocus: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final r = reasonCtl.text.trim();
              if (r.isEmpty) return;
              Navigator.of(context).pop(r);
            },
            child: const Text('Void'),
          ),
        ],
      ),
    );
    if (reason == null) return;
    final repo = ref.read(statutoryPayablesRepositoryProvider);
    final profile = await ref.read(userProfileProvider.future);
    await repo.voidPayment(
      paymentId: payment.id,
      voidReason: reason,
      voidedById: profile?.userId,
    );
    ref.invalidate(statutoryPaymentsProvider(query));
    ref.invalidate(compliancePaidSummariesProvider);
  }
}

String _periodLabel(StatutoryPayable p) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[p.periodMonth - 1]} ${p.periodYear}';
}
