import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../auth/profile_provider.dart';
import '../providers.dart';

/// Add-penalty dialog. Creates a `penalties` row plus N `penalty_installments`
/// rows (one per installment). Once saved, the compute service picks the
/// installments up in the first pay period whose `period_end >=
/// effective_date`, per the effective-date filter in
/// `_loadActivePenaltyInstallments`.
///
/// Pass [existing] to edit a penalty in-place. Edit is only safe when the
/// penalty has zero deducted installments — the caller must enforce that
/// guard. On edit we replace the installments wholesale (safe under the
/// "no installment has been deducted" precondition).
///
/// Returns true when the penalty was saved.
Future<bool?> showAddPenaltyDialog({
  required BuildContext context,
  required String employeeId,
  Map<String, dynamic>? existing,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _AddPenaltyDialog(
      employeeId: employeeId,
      existing: existing,
    ),
  );
}

class _AddPenaltyDialog extends ConsumerStatefulWidget {
  final String employeeId;
  final Map<String, dynamic>? existing;
  const _AddPenaltyDialog({required this.employeeId, this.existing});

  @override
  ConsumerState<_AddPenaltyDialog> createState() => _AddPenaltyDialogState();
}

class _AddPenaltyDialogState extends ConsumerState<_AddPenaltyDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _description;
  late final TextEditingController _totalAmount;
  late final TextEditingController _installments;
  late final TextEditingController _remarks;
  late DateTime _effectiveDate;
  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _description = TextEditingController(
      text: (e?['custom_description'] as String?) ?? '',
    );
    _totalAmount = TextEditingController(
      text: e == null ? '' : (e['total_amount']?.toString() ?? ''),
    );
    _installments = TextEditingController(
      text: e == null ? '1' : (e['installment_count']?.toString() ?? '1'),
    );
    _remarks = TextEditingController(
      text: (e?['remarks'] as String?) ?? '',
    );
    final effectiveStr = e?['effective_date'] as String?;
    _effectiveDate = effectiveStr != null
        ? DateTime.parse(effectiveStr)
        : DateTime.now();
  }

  @override
  void dispose() {
    _description.dispose();
    _totalAmount.dispose();
    _installments.dispose();
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _effectiveDate,
      firstDate: DateTime(_effectiveDate.year - 2),
      lastDate: DateTime(_effectiveDate.year + 2),
    );
    if (picked != null) setState(() => _effectiveDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final profile = ref.read(userProfileProvider).asData?.value;
    if (profile == null) {
      setState(() => _error = 'Not signed in.');
      return;
    }
    final total = Decimal.tryParse(_totalAmount.text.trim());
    final count = int.tryParse(_installments.text.trim()) ?? 1;
    if (total == null || total <= Decimal.zero || count < 1) {
      setState(() => _error = 'Invalid amount or installment count.');
      return;
    }

    // Split the total across N installments, 2dp rounding. The last slot
    // absorbs any rounding remainder so sum(installments) == total exactly.
    final perInstallment = (total / Decimal.fromInt(count))
        .toDecimal(scaleOnInfinitePrecision: 2);
    final amounts = List<Decimal>.generate(count, (_) => perInstallment);
    final residual = total - amounts.fold(Decimal.zero, (s, a) => s + a);
    amounts[amounts.length - 1] = amounts.last + residual;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      final effectiveIso =
          _effectiveDate.toIso8601String().substring(0, 10);
      final fields = <String, dynamic>{
        'custom_description': _description.text.trim(),
        'total_amount': total.toString(),
        'installment_count': count,
        'installment_amount': perInstallment.toString(),
        'effective_date': effectiveIso,
        'remarks':
            _remarks.text.trim().isEmpty ? null : _remarks.text.trim(),
      };

      String penaltyId;
      if (_isEditing) {
        // Edit mode: update the penalty row and replace its installments.
        // Safe only because the caller guarantees no installment has been
        // deducted yet (see eligibility check in financials_tab _Row).
        //
        // A REVIEW-status payroll run may already hold a payslip_line that
        // references the old installment via `penalty_installment_id`. The
        // FK on that column is `NO ACTION` (see migration
        // `20260414000010_benefits.sql:108`), so a raw DELETE on installments
        // would fail. Null the FK on any referencing lines first — the lines
        // themselves survive (so payslip totals don't shift mid-edit) and
        // get regenerated with correct installment refs on the next
        // Recompute, which the caller's snackbar prompts the user to run.
        penaltyId = widget.existing!['id'] as String;
        final oldInstallments = await client
            .from('penalty_installments')
            .select('id')
            .eq('penalty_id', penaltyId);
        final oldInstallmentIds = (oldInstallments as List)
            .map((r) => (r as Map)['id'] as String)
            .toList();
        await client
            .from('penalties')
            .update(fields)
            .eq('id', penaltyId);
        if (oldInstallmentIds.isNotEmpty) {
          await client
              .from('payslip_lines')
              .update({'penalty_installment_id': null})
              .inFilter('penalty_installment_id', oldInstallmentIds);
        }
        await client
            .from('penalty_installments')
            .delete()
            .eq('penalty_id', penaltyId);
      } else {
        final inserted = await client
            .from('penalties')
            .insert({
              ...fields,
              'employee_id': widget.employeeId,
              'status': 'ACTIVE',
              'created_by_id': profile.userId,
            })
            .select('id')
            .single();
        penaltyId = inserted['id'] as String;
      }

      await client.from('penalty_installments').insert([
        for (var i = 0; i < count; i++)
          {
            'penalty_id': penaltyId,
            'installment_number': i + 1,
            'amount': amounts[i].toString(),
            'is_deducted': false,
          },
      ]);
      ref.invalidate(financialsByEmployeeProvider);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Save failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = _effectiveDate.toIso8601String().substring(0, 10);
    return AlertDialog(
      title: Text(_isEditing ? 'Edit Penalty' : 'Add Penalty'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _description,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'e.g. Equipment damage, Policy violation',
                ),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Required' : null,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _totalAmount,
                      decoration: const InputDecoration(
                        labelText: 'Total amount (PHP)',
                        hintText: '0.00',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (v) {
                        final d = Decimal.tryParse((v ?? '').trim());
                        if (d == null || d <= Decimal.zero) {
                          return 'Must be > 0';
                        }
                        return null;
                      },
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 120,
                    child: TextFormField(
                      controller: _installments,
                      decoration: const InputDecoration(
                        labelText: 'Installments',
                        hintText: '1',
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        final n = int.tryParse((v ?? '').trim());
                        if (n == null || n < 1) return '≥ 1';
                        return null;
                      },
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Effective date',
                ),
                child: Row(
                  children: [
                    Expanded(child: Text(dateStr)),
                    TextButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today, size: 14),
                      label: const Text('Pick'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4),
                child: Text(
                  'The penalty starts deducting in the pay period that '
                  'contains this date.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _remarks,
                decoration: const InputDecoration(
                  labelText: 'Remarks (optional)',
                ),
                minLines: 1,
                maxLines: 3,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
