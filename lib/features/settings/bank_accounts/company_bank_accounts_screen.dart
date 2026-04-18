import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/hiring_entity.dart';
import '../../../data/models/hiring_entity_bank_account.dart';
import '../../../data/repositories/hiring_entity_bank_account_repository.dart';
import '../../../data/repositories/hiring_entity_repository.dart';

/// Admin settings screen for managing the company's own bank/GCash/Cash
/// accounts (payroll disbursement sources). One section per hiring entity —
/// GameCove and Luxium keep separate banks.
class CompanyBankAccountsScreen extends ConsumerWidget {
  const CompanyBankAccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entitiesAsync = ref.watch(hiringEntityListProvider);
    final accountsAsync = ref.watch(companyBankAccountsProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Company Bank Accounts',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          const Text(
            'Payroll disbursement sources for each hiring entity. Admins add '
            'the bank / GCash / cash accounts payroll disburses FROM; employees '
            'then pick from this list when setting their default pay source.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: entitiesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                  child: Text('Error: $e',
                      style: const TextStyle(color: Colors.red))),
              data: (entities) => accountsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                    child: Text('Error: $e',
                        style: const TextStyle(color: Colors.red))),
                data: (accounts) {
                  final byEntity =
                      <String, List<HiringEntityBankAccount>>{};
                  for (final a in accounts) {
                    byEntity.putIfAbsent(a.hiringEntityId, () => []).add(a);
                  }
                  return ListView(
                    children: [
                      for (final e in entities)
                        _EntitySection(
                          entity: e,
                          accounts: byEntity[e.id] ?? const [],
                          onChanged: () {
                            ref.invalidate(companyBankAccountsProvider);
                            ref.invalidate(
                                hiringEntityBankAccountsProvider(e.id));
                          },
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EntitySection extends ConsumerWidget {
  final HiringEntity entity;
  final List<HiringEntityBankAccount> accounts;
  final VoidCallback onChanged;
  const _EntitySection({
    required this.entity,
    required this.accounts,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(entity.name,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(entity.code,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace')),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _openAccountDialog(context, ref, null),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add account'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (accounts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No accounts yet. Click "Add account".',
                    style: TextStyle(color: Colors.grey)),
              )
            else
              ...accounts.map((a) => _AccountRow(
                    account: a,
                    onTogglePrimary: () async {
                      final repo = ref.read(
                          hiringEntityBankAccountRepositoryProvider);
                      await repo.setPrimary(
                          hiringEntityId: entity.id, accountId: a.id);
                      onChanged();
                    },
                    onEdit: () => _openAccountDialog(context, ref, a),
                    onDelete: () => _confirmDelete(context, ref, a),
                  )),
          ],
        ),
      ),
    );
  }

  Future<void> _openAccountDialog(
    BuildContext context,
    WidgetRef ref,
    HiringEntityBankAccount? existing,
  ) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _CompanyBankAccountDialog(
        hiringEntityId: entity.id,
        existing: existing,
      ),
    );
    if (changed == true) onChanged();
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    HiringEntityBankAccount a,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete bank account?'),
        content: Text(
            'Remove "${a.accountName} · ${a.bankCode}"? This cannot be undone. '
            'Existing payslips that reference this account keep their link for '
            'audit purposes.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(c).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(hiringEntityBankAccountRepositoryProvider).delete(a.id);
    onChanged();
  }
}

class _AccountRow extends StatelessWidget {
  final HiringEntityBankAccount account;
  final VoidCallback onTogglePrimary;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _AccountRow({
    required this.account,
    required this.onTogglePrimary,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          IconButton(
            tooltip: account.isPrimary ? 'Primary' : 'Set as primary',
            icon: Icon(
              account.isPrimary ? Icons.star : Icons.star_border,
              color: account.isPrimary ? const Color(0xFFF59E0B) : null,
            ),
            onPressed: account.isPrimary ? null : onTogglePrimary,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${account.bankName} · ${account.accountNumber}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '${account.accountName}'
                  '${account.accountType == null ? '' : ' · ${account.accountType}'}'
                  '${account.isActive ? '' : ' · inactive'}',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: onEdit,
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline,
                size: 18, color: Colors.redAccent),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _CompanyBankAccountDialog extends ConsumerStatefulWidget {
  final String hiringEntityId;
  final HiringEntityBankAccount? existing;
  const _CompanyBankAccountDialog({
    required this.hiringEntityId,
    required this.existing,
  });

  @override
  ConsumerState<_CompanyBankAccountDialog> createState() =>
      _CompanyBankAccountDialogState();
}

class _CompanyBankAccountDialogState
    extends ConsumerState<_CompanyBankAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _bankCode = TextEditingController();
  final _bankName = TextEditingController();
  final _number = TextEditingController();
  final _name = TextEditingController();
  String? _accountType;
  bool _isPrimary = false;
  bool _isActive = true;
  bool _saving = false;
  String? _error;

  static const _accountTypes = <String>[
    'SAVINGS',
    'CHECKING',
    'EWALLET',
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _bankCode.text = e.bankCode;
      _bankName.text = e.bankName;
      _number.text = e.accountNumber;
      _name.text = e.accountName;
      _accountType = e.accountType;
      _isPrimary = e.isPrimary;
      _isActive = e.isActive;
    }
  }

  @override
  void dispose() {
    _bankCode.dispose();
    _bankName.dispose();
    _number.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = ref.read(hiringEntityBankAccountRepositoryProvider);
      final saved = await repo.upsert(
        id: widget.existing?.id,
        hiringEntityId: widget.hiringEntityId,
        bankCode: _bankCode.text.trim().toUpperCase(),
        bankName: _bankName.text.trim(),
        accountNumber: _number.text.trim(),
        accountName: _name.text.trim(),
        accountType: _accountType,
        isPrimary: _isPrimary,
        isActive: _isActive,
      );
      if (_isPrimary) {
        await repo.setPrimary(
          hiringEntityId: widget.hiringEntityId,
          accountId: saved.id,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null
          ? 'Add company bank account'
          : 'Edit company bank account'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _bankCode,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Bank code *',
                    border: OutlineInputBorder(),
                    helperText: 'e.g. MBTC, BDO, BPI, GCASH, CASH',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _bankName,
                  decoration: const InputDecoration(
                    labelText: 'Bank name *',
                    border: OutlineInputBorder(),
                    helperText: 'Display label, e.g. "Metrobank"',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _number,
                  decoration: const InputDecoration(
                    labelText: 'Account number *',
                    border: OutlineInputBorder(),
                    helperText: 'Use "—" for cash / placeholder',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Account name *',
                    border: OutlineInputBorder(),
                    helperText: 'e.g. "Luxium Trading Inc." or "Chris (GCash)"',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: _accountType,
                  decoration: const InputDecoration(
                    labelText: 'Account type',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('— None —')),
                    ..._accountTypes.map((t) => DropdownMenuItem<String?>(
                          value: t,
                          child: Text(t),
                        )),
                  ],
                  onChanged: (v) => setState(() => _accountType = v),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Primary account for this entity'),
                  value: _isPrimary,
                  onChanged: (v) =>
                      setState(() => _isPrimary = v ?? false),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Active (selectable for new payslips)'),
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v ?? true),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
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
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}
