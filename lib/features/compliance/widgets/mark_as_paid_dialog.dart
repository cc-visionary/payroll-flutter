import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/tokens.dart';
import '../../../data/models/hiring_entity.dart';
import '../../../data/models/statutory_payable.dart';
import '../../../data/repositories/statutory_payables_repository.dart';
import '../../auth/profile_provider.dart';
import '../providers.dart';

/// Capture a new statutory_payments row. Defaults `amount_paid` to the full
/// amount due so the common case (full PRN payment) is one click. The
/// `paid_by_id` is taken automatically from the current user.
class MarkAsPaidDialog extends ConsumerStatefulWidget {
  final StatutoryPayable payable;
  final HiringEntity? brand;
  const MarkAsPaidDialog({super.key, required this.payable, required this.brand});

  @override
  ConsumerState<MarkAsPaidDialog> createState() => _MarkAsPaidDialogState();
}

class _MarkAsPaidDialogState extends ConsumerState<MarkAsPaidDialog> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _paidOn = DateTime.now();
  late final TextEditingController _amountCtl = TextEditingController(
    text: widget.payable.amountDue.toString(),
  );
  final TextEditingController _refCtl = TextEditingController();
  final TextEditingController _notesCtl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _amountCtl.dispose();
    _refCtl.dispose();
    _notesCtl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paidOn,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _paidOn = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = Decimal.tryParse(_amountCtl.text.trim());
    if (amount == null) return;

    setState(() => _saving = true);
    try {
      final repo = ref.read(statutoryPayablesRepositoryProvider);
      final profile = await ref.read(userProfileProvider.future);
      await repo.insertPayment(
        hiringEntityId: widget.payable.hiringEntityId,
        periodYear: widget.payable.periodYear,
        periodMonth: widget.payable.periodMonth,
        agency: widget.payable.agency,
        paidOn: _paidOn,
        referenceNo: _refCtl.text.trim().isEmpty ? null : _refCtl.text.trim(),
        amountPaid: amount,
        paidById: profile?.userId,
        notes: _notesCtl.text.trim().isEmpty ? null : _notesCtl.text.trim(),
      );
      ref.invalidate(compliancePaidSummariesProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Payment recorded for ${widget.payable.agency.shortLabel}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save payment: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = widget.brand;
    final period = _periodLabel(widget.payable);
    final due = NumberFormat.currency(symbol: '₱', decimalDigits: 2)
        .format(widget.payable.amountDue.toDouble());

    return AlertDialog(
      title: Text('Mark ${widget.payable.agency.shortLabel} as paid'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${brand?.name ?? widget.payable.hiringEntityId} • $period',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Amount due: $due',
                  style: TextStyle(color: LuxiumColors.of(context).soft),
                ),
                const SizedBox(height: LuxiumSpacing.md),
                InkWell(
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Paid on',
                      border: OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: Icon(Icons.event, size: 16),
                    ),
                    child: Text(DateFormat('MMM d, y').format(_paidOn)),
                  ),
                ),
                const SizedBox(height: LuxiumSpacing.md),
                TextFormField(
                  controller: _amountCtl,
                  decoration: const InputDecoration(
                    labelText: 'Amount paid (₱)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  validator: (v) {
                    final d = Decimal.tryParse((v ?? '').trim());
                    if (d == null) return 'Enter a valid number';
                    if (d <= Decimal.zero) return 'Must be greater than zero';
                    return null;
                  },
                ),
                const SizedBox(height: LuxiumSpacing.md),
                TextFormField(
                  controller: _refCtl,
                  decoration: const InputDecoration(
                    labelText: 'Reference No. (optional)',
                    helperText: 'PRN, OR number, transaction ID, etc.',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: LuxiumSpacing.md),
                TextFormField(
                  controller: _notesCtl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Record payment'),
        ),
      ],
    );
  }
}

String _periodLabel(StatutoryPayable p) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[p.periodMonth - 1]} ${p.periodYear}';
}
