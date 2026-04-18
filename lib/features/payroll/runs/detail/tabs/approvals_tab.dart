import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../data/repositories/payroll_repository.dart';
import '../providers.dart';

class PayrollApprovalsTab extends ConsumerStatefulWidget {
  final String runId;
  const PayrollApprovalsTab({super.key, required this.runId});

  @override
  ConsumerState<PayrollApprovalsTab> createState() =>
      _PayrollApprovalsTabState();
}

class _PayrollApprovalsTabState extends ConsumerState<PayrollApprovalsTab> {
  final Set<String> _selectedIds = {};

  void _toggleRow(String id, bool? value) {
    setState(() {
      if (value == true) {
        _selectedIds.add(id);
      } else {
        _selectedIds.remove(id);
      }
    });
  }

  void _toggleAll(List<Map<String, dynamic>> rows, bool? value) {
    setState(() {
      if (value == true) {
        _selectedIds
          ..clear()
          ..addAll(rows.map((r) => r['id'] as String));
      } else {
        _selectedIds.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(payslipListForRunProvider(widget.runId));
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Error: $e', style: const TextStyle(color: Colors.red)),
      ),
      data: (rows) {
        // Drop selections for rows that no longer exist (e.g. after refresh).
        final existingIds = rows.map((r) => r['id'] as String).toSet();
        _selectedIds.retainWhere(existingIds.contains);

        final counts = _tally(rows);
        final allSelected =
            rows.isNotEmpty && _selectedIds.length == rows.length;
        final someSelected =
            _selectedIds.isNotEmpty && _selectedIds.length < rows.length;
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _HeaderBar(
                    sent: counts.sent,
                    total: counts.total,
                    approved: counts.approved,
                    pending: counts.pending,
                    onSync: () async {
                      ref.invalidate(payslipListForRunProvider(widget.runId));
                      ref.invalidate(larkApprovalCountsProvider(widget.runId));
                    },
                    onResend: () async {
                      await ref
                          .read(payrollRepositoryProvider)
                          .sendPayslipApprovals(widget.runId);
                      ref.invalidate(payslipListForRunProvider(widget.runId));
                      ref.invalidate(larkApprovalCountsProvider(widget.runId));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content:
                                  Text('Approvals sent to Lark.')),
                        );
                      }
                    },
                  ),
                  Divider(height: 1, color: Theme.of(context).dividerColor),
                  _TableHeader(
                    allSelected: allSelected,
                    someSelected: someSelected,
                    onToggleAll: rows.isEmpty
                        ? null
                        : (v) => _toggleAll(rows, v),
                  ),
                  Divider(height: 1, color: Theme.of(context).dividerColor),
                  if (rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                          'No payslips yet',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  else
                    for (final r in rows) ...[
                      _ApprovalRow(
                        row: r,
                        selected: _selectedIds.contains(r['id'] as String),
                        onSelectedChanged: (v) =>
                            _toggleRow(r['id'] as String, v),
                        onRecall: () async {
                          // Individual recall isn't surfaced by the repo yet,
                          // so fall back to the run-wide recall which is
                          // what payrollos uses when explicit recall fails.
                          await ref
                              .read(payrollRepositoryProvider)
                              .recallPayslipApprovals(widget.runId);
                          ref.invalidate(
                              payslipListForRunProvider(widget.runId));
                        },
                      ),
                      Divider(
                          height: 1,
                          color: Theme.of(context).dividerColor),
                    ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  _Counts _tally(List<Map<String, dynamic>> rows) {
    int sent = 0, approved = 0, pending = 0, rejected = 0;
    for (final r in rows) {
      final s = r['lark_approval_status'] as String?;
      if (s == null) continue;
      sent++;
      switch (s) {
        case 'APPROVED':
          approved++;
          break;
        case 'PENDING':
          pending++;
          break;
        case 'REJECTED':
          rejected++;
          break;
      }
    }
    return _Counts(
      total: rows.length,
      sent: sent,
      approved: approved,
      pending: pending,
      rejected: rejected,
    );
  }
}

class _Counts {
  final int total;
  final int sent;
  final int approved;
  final int pending;
  final int rejected;
  const _Counts({
    required this.total,
    required this.sent,
    required this.approved,
    required this.pending,
    required this.rejected,
  });
}

class _HeaderBar extends StatelessWidget {
  final int sent;
  final int total;
  final int approved;
  final int pending;
  final VoidCallback onSync;
  final VoidCallback onResend;
  const _HeaderBar({
    required this.sent,
    required this.total,
    required this.approved,
    required this.pending,
    required this.onSync,
    required this.onResend,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const Text(
            'Lark Payslip Approvals',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 12),
          Text(
            '$sent/$total sent',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$approved acknowledged',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF16A34A),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$pending pending',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFFEA580C),
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: onSync,
            icon: const Icon(Icons.sync, size: 14),
            label: const Text('Sync Statuses'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: onResend,
            icon: const Icon(Icons.send, size: 14),
            label: const Text('Resend'),
          ),
        ],
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  final bool allSelected;
  final bool someSelected;
  final ValueChanged<bool?>? onToggleAll;
  const _TableHeader({
    this.allSelected = false,
    this.someSelected = false,
    this.onToggleAll,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      letterSpacing: 0.4,
    );
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Checkbox(
              tristate: true,
              value: allSelected ? true : (someSelected ? null : false),
              onChanged: onToggleAll,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          Expanded(flex: 3, child: Text('EMPLOYEE', style: style)),
          Expanded(flex: 3, child: Text('DEPARTMENT', style: style)),
          Expanded(flex: 2, child: Text('STATUS', style: style)),
          Expanded(flex: 3, child: Text('SENT AT', style: style)),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text('ACTIONS', style: style),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApprovalRow extends StatelessWidget {
  final Map<String, dynamic> row;
  final bool selected;
  final ValueChanged<bool?> onSelectedChanged;
  final VoidCallback onRecall;
  const _ApprovalRow({
    required this.row,
    required this.selected,
    required this.onSelectedChanged,
    required this.onRecall,
  });

  @override
  Widget build(BuildContext context) {
    final emp = row['employees'] as Map<String, dynamic>?;
    final name = [emp?['first_name'], emp?['middle_name'], emp?['last_name']]
        .where((s) => s != null && (s as String).isNotEmpty)
        .join(' ');
    final number = emp?['employee_number'] as String? ?? '—';
    final dept =
        (emp?['departments'] as Map<String, dynamic>?)?['name'] as String?;
    final sentAt = row['lark_approval_sent_at'] as String?;
    final status = row['lark_approval_status'] as String?;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Checkbox(
              value: selected,
              onChanged: onSelectedChanged,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _lastFirst(name),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  number,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(dept ?? '—', style: const TextStyle(fontSize: 13)),
          ),
          Expanded(
            flex: 2,
            child: _StatusPill(status: status),
          ),
          Expanded(
            flex: 3,
            child: Text(
              sentAt == null ? '—' : _fmtDateTime(DateTime.parse(sentAt)),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Approval detail view — coming soon.'),
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF2563EB),
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(40, 24),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('View'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: status == null ? null : onRecall,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(40, 24),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Recall'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _lastFirst(String full) {
    final parts = full.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return full;
    final last = parts.last;
    final rest = parts.sublist(0, parts.length - 1).join(' ');
    return '$last, $rest';
  }

  static String _fmtDateTime(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final local = d.toLocal();
    final h = local.hour;
    final period = h >= 12 ? 'PM' : 'AM';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final m = local.minute.toString().padLeft(2, '0');
    return '${months[local.month - 1]} ${local.day}, ${local.year}, $h12:$m $period';
  }
}

class _StatusPill extends StatelessWidget {
  final String? status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    if (status == null) {
      return Text(
        'Not sent',
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    final (label, bg, fg) = switch (status) {
      'APPROVED' => ('Acknowledged', const Color(0xFFDCFCE7), const Color(0xFF166534)),
      'PENDING' => ('Pending', const Color(0xFFFEF3C7), const Color(0xFF92400E)),
      'REJECTED' => ('Rejected', const Color(0xFFFEE2E2), const Color(0xFF991B1B)),
      'CANCELED' => ('Recalled', const Color(0xFFF3F4F6), const Color(0xFF4B5563)),
      _ => (status!, const Color(0xFFF3F4F6), const Color(0xFF4B5563)),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: fg,
          ),
        ),
      ),
    );
  }
}
