import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/money.dart';
import '../../../../data/models/employee.dart';
import '../../../auth/profile_provider.dart';
import '../providers.dart';
import '../widgets/info_card.dart';
import 'add_penalty_dialog.dart';

class FinancialsTab extends ConsumerStatefulWidget {
  final Employee employee;
  const FinancialsTab({super.key, required this.employee});

  @override
  ConsumerState<FinancialsTab> createState() => _FinancialsTabState();
}

class _FinancialsTabState extends ConsumerState<FinancialsTab> {
  FinancialKind _kind = FinancialKind.penalties;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).asData?.value;
    final canManage = profile?.canManageEmployees ?? false;
    final async = ref.watch(financialsByEmployeeProvider(
      FinancialsQuery(employeeId: widget.employee.id, kind: _kind),
    ));

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        Row(
          children: [
            _SubTabChip(
              label: 'Penalties',
              selected: _kind == FinancialKind.penalties,
              onTap: () => setState(() => _kind = FinancialKind.penalties),
            ),
            const SizedBox(width: 8),
            _SubTabChip(
              label: 'Cash Advances',
              selected: _kind == FinancialKind.cashAdvances,
              onTap: () => setState(() => _kind = FinancialKind.cashAdvances),
            ),
            const SizedBox(width: 8),
            _SubTabChip(
              label: 'Reimbursements',
              selected: _kind == FinancialKind.reimbursements,
              onTap: () =>
                  setState(() => _kind = FinancialKind.reimbursements),
            ),
            const Spacer(),
            if (canManage)
              OutlinedButton.icon(
                onPressed: () => _showComingSoon(context, 'Sync from Lark'),
                icon: const Icon(Icons.cloud_sync_outlined, size: 16),
                label: const Text('Sync from Lark'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Error: $e', style: const TextStyle(color: Colors.red)),
          ),
          data: (rows) {
            final summary = _Summary.from(_kind, rows);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SummaryRow(kind: _kind, summary: summary),
                const SizedBox(height: 12),
                if (canManage)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton(
                      onPressed: () => _onAdd(context),
                      child: Text('Add ${_kindLabel(_kind)}'),
                    ),
                  ),
                const SizedBox(height: 16),
                _List(
                  kind: _kind,
                  rows: rows,
                  onEdit: _kind == FinancialKind.penalties
                      ? (row) => _onEditPenalty(context, row)
                      : null,
                  onDelete: _kind == FinancialKind.penalties
                      ? (row) => _onDeletePenalty(context, row)
                      : null,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

String _kindLabel(FinancialKind k) => switch (k) {
      FinancialKind.penalties => 'Penalty',
      FinancialKind.cashAdvances => 'Cash Advance',
      FinancialKind.reimbursements => 'Reimbursement',
    };

void _showComingSoon(BuildContext context, String action) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('$action — coming soon.')),
  );
}

extension on _FinancialsTabState {
  Future<void> _onAdd(BuildContext context) async {
    switch (_kind) {
      case FinancialKind.penalties:
        final created = await showAddPenaltyDialog(
          context: context,
          employeeId: widget.employee.id,
        );
        if (created == true && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Penalty recorded.')),
          );
        }
        break;
      case FinancialKind.cashAdvances:
      case FinancialKind.reimbursements:
        // Cash advances + reimbursements originate in Lark approvals — they
        // flow in via Sync from Lark rather than being manually created
        // here. Keep the placeholder until we have a manual-entry use case.
        _showComingSoon(context, 'Add ${_kindLabel(_kind)}');
        break;
    }
  }

  Future<void> _onEditPenalty(
      BuildContext context, Map<String, dynamic> row) async {
    final saved = await showAddPenaltyDialog(
      context: context,
      employeeId: widget.employee.id,
      existing: row,
    );
    if (saved == true && context.mounted) {
      // Any in-review payroll run that computed a line for this penalty
      // now points at an orphaned installment reference (the dialog nulls
      // it on save — see add_penalty_dialog.dart). Prompt the user to
      // recompute so the line regenerates against the new installments.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Penalty updated. Recompute any in-review payroll run to apply.',
          ),
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _onDeletePenalty(
      BuildContext context, Map<String, dynamic> row) async {
    final description =
        (row['custom_description'] as String?)?.trim().isNotEmpty == true
            ? row['custom_description'] as String
            : 'this penalty';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete penalty?'),
        content: Text(
          'Delete "$description"? This also removes any scheduled '
          'installments. The penalty can only be deleted while no '
          'installment has been withdrawn from a payroll run.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await Supabase.instance.client
          .from('penalties')
          .delete()
          .eq('id', row['id'] as String);
      ref.invalidate(financialsByEmployeeProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Penalty deleted.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }
}

class _SubTabChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SubTabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF111827) : Colors.transparent,
          border: Border.all(
            color: selected
                ? const Color(0xFF111827)
                : Theme.of(context).dividerColor,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : null,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _Summary {
  final int active;
  final int completed;
  final Decimal remaining;
  const _Summary({
    required this.active,
    required this.completed,
    required this.remaining,
  });

  factory _Summary.from(FinancialKind kind, List<Map<String, dynamic>> rows) {
    int active = 0, completed = 0;
    var remaining = Decimal.zero;
    for (final r in rows) {
      final status = (r['status'] as String?)?.toUpperCase() ?? '';
      if (status == 'COMPLETED' || status == 'PAID') {
        completed++;
      } else if (status == 'ACTIVE' || status == 'PENDING') {
        active++;
        switch (kind) {
          case FinancialKind.penalties:
            final total = _dec(r['total_amount']);
            final paid = _dec(r['total_deducted']);
            remaining += total - paid;
            break;
          case FinancialKind.cashAdvances:
            final amount = _dec(r['amount']);
            if (r['is_deducted'] != true) remaining += amount;
            break;
          case FinancialKind.reimbursements:
            final amount = _dec(r['amount']);
            if (r['is_paid'] != true) remaining += amount;
            break;
        }
      }
    }
    return _Summary(
      active: active,
      completed: completed,
      remaining: remaining,
    );
  }

  static Decimal _dec(Object? v) {
    if (v == null) return Decimal.zero;
    return Decimal.parse(v.toString());
  }
}

class _SummaryRow extends StatelessWidget {
  final FinancialKind kind;
  final _Summary summary;
  const _SummaryRow({required this.kind, required this.summary});

  @override
  Widget build(BuildContext context) {
    final activeLabel = switch (kind) {
      FinancialKind.penalties => 'ACTIVE PENALTIES',
      FinancialKind.cashAdvances => 'ACTIVE ADVANCES',
      FinancialKind.reimbursements => 'ACTIVE REIMBURSEMENTS',
    };
    final remainingLabel = switch (kind) {
      FinancialKind.penalties => 'REMAINING BALANCE',
      FinancialKind.cashAdvances => 'OUTSTANDING',
      FinancialKind.reimbursements => 'PENDING PAYOUT',
    };
    return LayoutBuilder(builder: (ctx, c) {
      final cols = c.maxWidth >= 700 ? 3 : 1;
      final spacing = 12.0;
      final w = (c.maxWidth - spacing * (cols - 1)) / cols;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          SizedBox(
              width: w,
              child: InfoCard(
                label: activeLabel,
                value: summary.active.toString(),
              )),
          SizedBox(
              width: w,
              child: InfoCard(
                label: remainingLabel,
                value: 'PHP ${Money.fmtPhp(summary.remaining).replaceAll('₱', '')}',
              )),
          SizedBox(
              width: w,
              child: InfoCard(
                label: 'COMPLETED',
                value: summary.completed.toString(),
              )),
        ],
      );
    });
  }
}

// ---------------------------------------------------------------------------

class _List extends StatelessWidget {
  final FinancialKind kind;
  final List<Map<String, dynamic>> rows;
  final void Function(Map<String, dynamic> row)? onEdit;
  final void Function(Map<String, dynamic> row)? onDelete;
  const _List({
    required this.kind,
    required this.rows,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            'No ${_kindLabel(kind).toLowerCase()}s recorded for this employee.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _Row(
              kind: kind,
              row: r,
              onEdit: onEdit,
              onDelete: onDelete,
            ),
          ),
      ],
    );
  }
}

enum _RowAction { edit, delete }

class _Row extends StatelessWidget {
  final FinancialKind kind;
  final Map<String, dynamic> row;
  final void Function(Map<String, dynamic> row)? onEdit;
  final void Function(Map<String, dynamic> row)? onDelete;
  const _Row({
    required this.kind,
    required this.row,
    this.onEdit,
    this.onDelete,
  });

  /// Penalty row is mutable only when the parent is not CANCELLED and *no*
  /// installment has been deducted yet. Once any payroll run has withdrawn
  /// even one installment, the row is frozen — editing the amount or date
  /// after that would silently desync the historical payslip.
  ///
  /// Derives from the installments array (authoritative) rather than
  /// `penalties.total_deducted` so the gate is correct even when the
  /// total-sync trigger hasn't been deployed.
  bool get _canMutate {
    if (kind != FinancialKind.penalties) return false;
    final rawStatus = (row['status'] as String?)?.toUpperCase();
    if (rawStatus == 'CANCELLED') return false;
    final installments = (row['penalty_installments'] as List<dynamic>?)
        ?.whereType<Map<String, dynamic>>();
    if (installments != null) {
      return !installments.any((i) => i['is_deducted'] == true);
    }
    // No installments embedded — fall back to the stored total.
    final deducted = row['total_deducted'];
    if (deducted == null) return true;
    return Decimal.parse(deducted.toString()) == Decimal.zero;
  }

  @override
  Widget build(BuildContext context) {
    if (kind == FinancialKind.penalties) return _buildPenaltyCard(context);
    return _buildGenericCard(context);
  }

  /// Penalty layout: title + status, installment progress, progress bar,
  /// and a footer row with Remaining / Effective / Note (when present).
  ///
  /// All totals + status derive from the embedded `penalty_installments`
  /// array (authoritative — set to `is_deducted=true` at run release time
  /// in `PayrollRepository.releaseRun` step 4). The `penalties.total_deducted`
  /// column is kept in sync by trigger `_penalty_installments_totals`
  /// (migration `20260418000008`), but computing locally from the children
  /// keeps the UI correct even when the trigger hasn't been deployed yet
  /// or the parent row lags behind for any reason.
  Widget _buildPenaltyCard(BuildContext context) {
    final total = _dec(row['total_amount']);
    final installments = (row['penalty_installments'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        const <Map<String, dynamic>>[];
    final installmentCount =
        installments.isNotEmpty
            ? installments.length
            : (row['installment_count'] as num?)?.toInt() ?? 0;
    final paidInstallments =
        installments.where((i) => i['is_deducted'] == true).toList();
    final paidCount = paidInstallments.length;
    final remainingCount =
        (installmentCount - paidCount).clamp(0, installmentCount);
    final deducted = paidInstallments.fold<Decimal>(
      Decimal.zero,
      (s, i) => s + _dec(i['amount']),
    );
    final remaining = total - deducted;
    final progress = total == Decimal.zero
        ? 0.0
        : (deducted / total).toDouble().clamp(0.0, 1.0);
    // Derive status from installment completion instead of the DB column —
    // avoids showing ACTIVE when all installments are actually paid but
    // the trigger-maintained `penalties.status` hasn't caught up.
    final rawStatus = (row['status'] as String?)?.toUpperCase() ?? '';
    final String status;
    if (rawStatus == 'CANCELLED') {
      status = 'CANCELLED';
    } else if (installmentCount > 0 && paidCount >= installmentCount) {
      status = 'COMPLETED';
    } else {
      status = 'ACTIVE';
    }
    final effectiveIso = row['effective_date'] as String?;
    final remarks = (row['remarks'] as String?)?.trim();
    final canMutate = _canMutate && (onEdit != null || onDelete != null);

    final subtle = Theme.of(context).colorScheme.onSurfaceVariant;
    final bodyStyle = TextStyle(fontSize: 12, color: subtle);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title row: description + status chip + actions menu.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _title(),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    StatusChip(label: status, tone: toneForStatus(status)),
                  ],
                ),
              ),
              if (canMutate) _actionsMenu(),
            ],
          ),
          const SizedBox(height: 8),
          // Installment summary line.
          Text(
            '${Money.fmtPhp(total)} total · '
            '$installmentCount installment${installmentCount == 1 ? '' : 's'} '
            '($paidCount paid, $remainingCount remaining)',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          // Progress bar.
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(
                      progress >= 1.0
                          ? const Color(0xFF16A34A) // completed green
                          : Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(progress * 100).round()}%',
                style: bodyStyle,
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Footer: Remaining / Effective / Note.
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              Text('Remaining: ${Money.fmtPhp(remaining)}', style: bodyStyle),
              if (effectiveIso != null)
                Text('Effective: ${_fmtDate(effectiveIso)}', style: bodyStyle),
              if (remarks != null && remarks.isNotEmpty)
                Text('Note: $remarks', style: bodyStyle),
              Text('Created: ${_created()}', style: bodyStyle),
            ],
          ),
        ],
      ),
    );
  }

  /// Fallback layout for Cash Advance / Reimbursement rows.
  Widget _buildGenericCard(BuildContext context) {
    final amount = row[kind.amountKey];
    final amountText = amount == null
        ? '—'
        : Money.fmtPhp(Decimal.parse(amount.toString()));
    final status = (row['status'] as String?) ?? '—';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title(),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Created: ${_created()}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amountText,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              StatusChip(label: status, tone: toneForStatus(status)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionsMenu() {
    return PopupMenuButton<_RowAction>(
      tooltip: 'More actions',
      icon: const Icon(Icons.more_vert, size: 18),
      onSelected: (action) {
        switch (action) {
          case _RowAction.edit:
            onEdit?.call(row);
            break;
          case _RowAction.delete:
            onDelete?.call(row);
            break;
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: _RowAction.edit,
          child: ListTile(
            leading: Icon(Icons.edit_outlined, size: 18),
            title: Text('Edit'),
            dense: true,
          ),
        ),
        PopupMenuItem(
          value: _RowAction.delete,
          child: ListTile(
            leading: Icon(Icons.delete_outline, size: 18, color: Colors.red),
            title: Text('Delete', style: TextStyle(color: Colors.red)),
            dense: true,
          ),
        ),
      ],
    );
  }

  static Decimal _dec(Object? v) {
    if (v == null) return Decimal.zero;
    return Decimal.parse(v.toString());
  }

  static String _fmtDate(String iso) {
    // ISO date like 2026-02-02 → "Feb 2, 2026". Keep defensive against
    // datetime strings (substring(0,10)).
    try {
      final d = DateTime.parse(iso.substring(0, 10));
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      return '${months[d.month - 1]} ${d.day}, ${d.year}';
    } catch (_) {
      return iso.substring(0, 10);
    }
  }

  String _created() {
    final created = row['created_at'] as String?;
    if (created == null) return '—';
    return _fmtDate(created);
  }

  String _title() {
    if (kind == FinancialKind.penalties) {
      return (row['custom_description'] as String?) ?? 'Penalty';
    }
    if (kind == FinancialKind.reimbursements) {
      return (row['reason'] as String?) ??
          (row['reimbursement_type'] as String?) ??
          'Reimbursement';
    }
    return (row['reason'] as String?) ?? 'Cash Advance';
  }
}
