import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money.dart';
import '../../../data/models/role_scorecard.dart';
import '../../../data/repositories/role_rate_change_repository.dart';
import '../../auth/profile_provider.dart';
import '../../payroll/engine/role_rate.dart';

/// Records an effective-dated change to a role's default base rate (e.g. a
/// wage order moving 695 → 755). Returns the new rate on success.
///
/// Only employees paid the role default on the effective date are repriced;
/// anyone with their own compensation record keeps it. Days before the
/// effective date keep the old rate (see `roleRateAsOf`).
Future<Decimal?> showUpdateBaseRateDialog(
  BuildContext context,
  RoleScorecard card,
) => showDialog<Decimal>(
  context: context,
  builder: (_) => _UpdateBaseRateDialog(card: card),
);

class _UpdateBaseRateDialog extends ConsumerStatefulWidget {
  const _UpdateBaseRateDialog({required this.card});
  final RoleScorecard card;

  @override
  ConsumerState<_UpdateBaseRateDialog> createState() =>
      _UpdateBaseRateDialogState();
}

class _UpdateBaseRateDialogState extends ConsumerState<_UpdateBaseRateDialog> {
  final _formKey = GlobalKey<FormState>();
  final _rate = TextEditingController();
  final _reason = TextEditingController();
  late DateTime _effectiveDate;
  Future<List<({String id, String name})>>? _holders;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _effectiveDate = DateTime(now.year, now.month, now.day);
    _loadHolders();
  }

  void _loadHolders() {
    _holders = ref
        .read(roleRateChangeRepositoryProvider)
        .roleDefaultHolders(scorecardId: widget.card.id, asOf: _effectiveDate);
  }

  @override
  void dispose() {
    _rate.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final actorId = ref.read(userProfileProvider).asData?.value?.userId;
    if (actorId == null) {
      setState(() => _error = 'Could not resolve your user — sign in again.');
      return;
    }
    final newRate = Decimal.parse(_rate.text.trim());
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = ref.read(roleRateChangeRepositoryProvider);
      // The rate in force the day BEFORE the effective date — not simply
      // base_salary, which already holds any later future-dated rate.
      final history = await repo.listByScorecard(widget.card.id);
      final prev = roleRateAsOf(
        history,
        _effectiveDate.subtract(const Duration(days: 1)),
        widget.card.baseSalary,
      );
      await repo.record(
            companyId: widget.card.companyId,
            scorecardId: widget.card.id,
            effectiveDate: _effectiveDate,
            prevBaseSalary: prev,
            newBaseSalary: newRate,
            reason: _reason.text.trim(),
            initiatedById: actorId,
          );
      if (mounted) Navigator.of(context).pop(newRate);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.card.baseSalary;
    final unit = switch (widget.card.wageType) {
      'DAILY' => ' / day',
      'HOURLY' => ' / hour',
      _ => ' / month',
    };
    return AlertDialog(
      title: const Text('Update base rate'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Current rate: '
                '${current == null ? '—' : Money.fmtPhp(current)}$unit',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _rate,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'New base rate *',
                  suffixText: unit.trim(),
                  border: const OutlineInputBorder(),
                ),
                validator: (v) {
                  final parsed = Decimal.tryParse((v ?? '').trim());
                  if (parsed == null || parsed <= Decimal.zero) {
                    return 'Enter a rate above zero';
                  }
                  if (parsed == current) return 'Same as the current rate';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Effective date',
                  border: OutlineInputBorder(),
                ),
                child: InkWell(
                  onTap: () async {
                    final p = await showDatePicker(
                      context: context,
                      initialDate: _effectiveDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (p != null) {
                      setState(() {
                        _effectiveDate = p;
                        _loadHolders();
                      });
                    }
                  },
                  child: Text(
                    _effectiveDate.toIso8601String().substring(0, 10),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _reason,
                decoration: const InputDecoration(
                  labelText: 'Reason *',
                  hintText: 'e.g. Wage Order NCR-26',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              FutureBuilder<List<({String id, String name})>>(
                future: _holders,
                builder: (context, snap) {
                  final style = Theme.of(context).textTheme.bodySmall;
                  if (snap.connectionState != ConnectionState.done) {
                    return Text('Checking who is affected…', style: style);
                  }
                  if (snap.hasError) {
                    return Text('Could not load employees: ${snap.error}',
                        style: style);
                  }
                  final holders = snap.data ?? const [];
                  return Text(
                    holders.isEmpty
                        ? 'No active employee is on the role default rate. '
                              'Employees with their own pay keep it.'
                        : 'Moves to the new rate from this date: '
                              '${holders.map((h) => h.name).join(', ')}. '
                              'Employees with their own pay keep it. Days '
                              'before the effective date keep the old rate, '
                              'and new documents use the new rate.',
                    style: style,
                  );
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Update rate'),
        ),
      ],
    );
  }
}
