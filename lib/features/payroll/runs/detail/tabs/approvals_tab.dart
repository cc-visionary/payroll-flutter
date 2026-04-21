import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../data/repositories/payroll_repository.dart';
import '../../../payslips/payslip_pdf_context.dart';
import '../providers.dart';

/// Resolves an employee's department name with fallback: direct
/// `employees.departments.name` first, then the department attached to
/// their role scorecard (`role_scorecards.departments.name`). Returns null
/// if both are missing. EMP005-009 sit at the scorecard level, which is
/// why the direct lookup alone showed "—".
String? _deptFor(Map<String, dynamic>? emp) {
  final direct =
      (emp?['departments'] as Map<String, dynamic>?)?['name'] as String?;
  if (direct != null && direct.trim().isNotEmpty) return direct;
  final scorecard = emp?['role_scorecards'] as Map<String, dynamic>?;
  final scDept = (scorecard?['departments'] as Map<String, dynamic>?)
      ?['name'] as String?;
  if (scDept != null && scDept.trim().isNotEmpty) return scDept;
  return null;
}

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

        // Bucket selected rows by eligibility so we can size the two action
        // buttons independently. A row is "sendable" if it's DRAFT_IN_REVIEW
        // (never dispatched) OR RECALLED (previously sent, then recalled —
        // the edge function reissues the approval and overwrites the old
        // instance_code). "Syncable" means the row still has a Lark
        // instance_code we can poll for status.
        final hasSelection = _selectedIds.isNotEmpty;
        int sendableAll = 0, sendableSelected = 0;
        int syncableAll = 0, syncableSelected = 0;
        for (final r in rows) {
          final id = r['id'] as String;
          final approvalStatus = r['approval_status'] as String?;
          final instanceCode = r['lark_approval_instance_code'] as String?;
          final isSendable = approvalStatus == 'DRAFT_IN_REVIEW' ||
              approvalStatus == 'RECALLED';
          final isSyncable = instanceCode != null &&
              instanceCode.isNotEmpty &&
              approvalStatus != 'RECALLED';
          if (isSendable) sendableAll++;
          if (isSyncable) syncableAll++;
          if (_selectedIds.contains(id)) {
            if (isSendable) sendableSelected++;
            if (isSyncable) syncableSelected++;
          }
        }
        final sendCount = hasSelection ? sendableSelected : sendableAll;
        final syncCount = hasSelection ? syncableSelected : syncableAll;

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
                    hasSelection: hasSelection,
                    sendCount: sendCount,
                    syncCount: syncCount,
                    onSync: syncCount == 0
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final ids = hasSelection
                                ? _syncableSelectedIds(rows)
                                : null;
                            try {
                              final res = await ref
                                  .read(payrollRepositoryProvider)
                                  .syncPayslipApprovals(
                                    widget.runId,
                                    payslipIds: ids,
                                  );
                              ref.invalidate(
                                  payslipListForRunProvider(widget.runId));
                              ref.invalidate(
                                  larkApprovalCountsProvider(widget.runId));
                              final synced =
                                  (res['synced'] as num?)?.toInt() ?? 0;
                              final failed =
                                  (res['failed'] as num?)?.toInt() ?? 0;
                              final errs =
                                  (res['errors'] as List?) ?? const [];
                              if (!context.mounted) return;
                              messenger.showSnackBar(SnackBar(
                                content: Text(failed == 0
                                    ? 'Synced $synced status${synced == 1 ? '' : 'es'} from Lark.'
                                    : 'Synced $synced, $failed failed'
                                        '${errs.isNotEmpty ? ": ${(errs.first as Map)['error']}" : ''}.'),
                              ));
                            } catch (e) {
                              if (!context.mounted) return;
                              messenger.showSnackBar(SnackBar(
                                backgroundColor: Colors.red.shade600,
                                content: Text('Sync failed: $e'),
                              ));
                            }
                          },
                    onSend: sendCount == 0
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.of(context);
                            // Dispatch set: explicit selection wins; fall
                            // back to every DRAFT_IN_REVIEW row in the run
                            // when nothing's ticked.
                            final ids = hasSelection
                                ? _sendableSelectedIds(rows)
                                : _allSendableIds(rows);
                            messenger.showSnackBar(SnackBar(
                              content: Text(
                                  'Generating ${ids.length} payslip PDF${ids.length == 1 ? '' : 's'}…'),
                              duration: const Duration(seconds: 3),
                            ));
                            try {
                              final pdfs =
                                  await buildPayslipPdfsBase64ForIds(ref, ids);
                              final res = await ref
                                  .read(payrollRepositoryProvider)
                                  .sendPayslipApprovals(
                                    widget.runId,
                                    payslipIds: ids,
                                    pdfsByPayslipId: pdfs,
                                  );
                              ref.invalidate(
                                  payslipListForRunProvider(widget.runId));
                              ref.invalidate(
                                  larkApprovalCountsProvider(widget.runId));
                              ref.invalidate(
                                  payslipApprovalCountsProvider(widget.runId));
                              final sent =
                                  (res['sent'] as num?)?.toInt() ?? 0;
                              final failed =
                                  (res['failed'] as num?)?.toInt() ?? 0;
                              final errs =
                                  (res['errors'] as List?) ?? const [];
                              if (!context.mounted) return;
                              messenger.hideCurrentSnackBar();
                              messenger.showSnackBar(SnackBar(
                                content: Text(failed == 0
                                    ? 'Sent $sent Lark approval${sent == 1 ? '' : 's'}.'
                                    : 'Sent $sent, $failed failed'
                                        '${errs.isNotEmpty ? ": ${(errs.first as Map)['error']}" : ''}.'),
                              ));
                            } catch (e) {
                              if (!context.mounted) return;
                              messenger.hideCurrentSnackBar();
                              messenger.showSnackBar(SnackBar(
                                backgroundColor: Colors.red.shade600,
                                content: Text('Send failed: $e'),
                              ));
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
                          final messenger = ScaffoldMessenger.of(context);
                          final payslipId = r['id'] as String;
                          // Verb choice follows the row's current state —
                          // APPROVED → Revoke, everything else → Recall.
                          // The edge function treats them identically;
                          // only the snackbar phrasing changes.
                          final verb = r['approval_status'] == 'APPROVED'
                              ? 'Revoke'
                              : 'Recall';
                          final verbed =
                              verb == 'Revoke' ? 'Revoked' : 'Recalled';
                          try {
                            final res = await ref
                                .read(payrollRepositoryProvider)
                                .recallPayslipApprovals(
                                  widget.runId,
                                  payslipIds: [payslipId],
                                );
                            ref.invalidate(
                                payslipListForRunProvider(widget.runId));
                            ref.invalidate(
                                larkApprovalCountsProvider(widget.runId));
                            ref.invalidate(payslipApprovalCountsProvider(
                                widget.runId));
                            final recalled =
                                (res['recalled'] as num?)?.toInt() ?? 0;
                            final failed =
                                (res['failed'] as num?)?.toInt() ?? 0;
                            final errs =
                                (res['errors'] as List?) ?? const [];
                            if (!context.mounted) return;
                            messenger.showSnackBar(SnackBar(
                              content: Text(failed == 0
                                  ? '$verbed $recalled approval${recalled == 1 ? '' : 's'}.'
                                  : '$verbed $recalled, $failed failed'
                                      '${errs.isNotEmpty ? ": ${(errs.first as Map)['error']}" : ''}.'),
                            ));
                          } catch (e) {
                            if (!context.mounted) return;
                            messenger.showSnackBar(SnackBar(
                              backgroundColor: Colors.red.shade600,
                              content: Text('$verb failed: $e'),
                            ));
                          }
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

  static bool _isSendable(Map<String, dynamic> r) {
    final s = r['approval_status'];
    return s == 'DRAFT_IN_REVIEW' || s == 'RECALLED';
  }

  List<String> _sendableSelectedIds(List<Map<String, dynamic>> rows) {
    final out = <String>[];
    for (final r in rows) {
      final id = r['id'] as String;
      if (!_selectedIds.contains(id)) continue;
      if (_isSendable(r)) out.add(id);
    }
    return out;
  }

  List<String> _allSendableIds(List<Map<String, dynamic>> rows) {
    final out = <String>[];
    for (final r in rows) {
      if (_isSendable(r)) out.add(r['id'] as String);
    }
    return out;
  }

  List<String> _syncableSelectedIds(List<Map<String, dynamic>> rows) {
    final out = <String>[];
    for (final r in rows) {
      final id = r['id'] as String;
      if (!_selectedIds.contains(id)) continue;
      final code = r['lark_approval_instance_code'] as String?;
      // Skip RECALLED rows — their Lark instance is already CANCELED, so
      // there's nothing live to poll.
      if (r['approval_status'] == 'RECALLED') continue;
      if (code != null && code.isNotEmpty) out.add(id);
    }
    return out;
  }

  _Counts _tally(List<Map<String, dynamic>> rows) {
    // Drive counts off our local state machine (`approval_status`) rather
    // than `lark_approval_status`, so RECALLED rows are still counted as
    // "was sent" — recall nulls the Lark-side status but we don't want to
    // pretend they were never dispatched. `lark_approval_sent_at` is the
    // physical receipt; `approval_status` is the current bucket.
    int sent = 0, approved = 0, pending = 0, rejected = 0;
    for (final r in rows) {
      final wasSent = r['lark_approval_sent_at'] != null;
      if (wasSent) sent++;
      switch (r['approval_status']) {
        case 'APPROVED':
          approved++;
          break;
        case 'PENDING_APPROVAL':
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
  // Button labels flip between "All" and "Selected" scopes based on whether
  // the user has ticked any row. The edge functions themselves filter by
  // eligibility (DRAFT_IN_REVIEW for send, has instance_code for sync), so
  // the counts here only need to reflect how many rows will actually be
  // dispatched — already-sent rows don't inflate the Send count, etc.
  final bool hasSelection;
  final int sendCount;
  final int syncCount;
  final VoidCallback? onSync;
  final VoidCallback? onSend;
  const _HeaderBar({
    required this.sent,
    required this.total,
    required this.approved,
    required this.pending,
    required this.hasSelection,
    required this.sendCount,
    required this.syncCount,
    required this.onSync,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final syncLabel = hasSelection
        ? 'Sync Selected ($syncCount)'
        : 'Sync All ($syncCount)';
    final sendLabel = hasSelection
        ? 'Send Selected ($sendCount)'
        : 'Send All ($sendCount)';

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
            label: Text(syncLabel),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: onSend,
            icon: const Icon(Icons.send, size: 14),
            label: Text(sendLabel),
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
    // Falls back to role_scorecards.departments.name when the employee has
    // no direct department_id (department is carried by the role card).
    final dept = _deptFor(emp);
    final sentAt = row['lark_approval_sent_at'] as String?;
    final status = row['lark_approval_status'] as String?;
    // `approval_status` (our local state machine) drives the row action —
    // not `lark_approval_status`. PENDING_APPROVAL → "Recall" (cancels an
    // in-flight approval). APPROVED → "Revoke" (cancels a completed
    // approval; Lark requires "Allow post-approval cancellation" to be
    // enabled on the template). Both call the same edge function.
    final approvalStatus = row['approval_status'] as String?;
    final canRecallOrRevoke = approvalStatus == 'PENDING_APPROVAL' ||
        approvalStatus == 'APPROVED';
    final actionLabel =
        approvalStatus == 'APPROVED' ? 'Revoke' : 'Recall';

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
            child: _StatusPill(
              approvalStatus: approvalStatus,
              larkStatus: status,
            ),
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
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => _ApprovalDetailDialog(row: row),
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
                  onPressed: canRecallOrRevoke ? onRecall : null,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(40, 24),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(actionLabel),
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
  // Our local state machine (`approval_status`) is the source of truth;
  // the Lark-side status is a fallback for transient cases where our row
  // hasn't been updated yet. We null out `lark_approval_status` on recall
  // (so the compute service knows the payslip is editable again) — without
  // falling back to `approval_status`, the RECALLED row would render as
  // "Not sent" which misrepresents history.
  final String? approvalStatus;
  final String? larkStatus;
  const _StatusPill({
    required this.approvalStatus,
    required this.larkStatus,
  });

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = _labelFor(approvalStatus, larkStatus);
    if (bg == null || fg == null) {
      return Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
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

  /// Returns `(label, bg, fg)`. A null bg/fg signals "render as plain
  /// text, no pill" — used for the neutral "Not sent" state.
  (String, Color?, Color?) _labelFor(String? approval, String? lark) {
    switch (approval) {
      case 'APPROVED':
        return ('Acknowledged', const Color(0xFFDCFCE7), const Color(0xFF166534));
      case 'PENDING_APPROVAL':
        return ('Pending', const Color(0xFFFEF3C7), const Color(0xFF92400E));
      case 'REJECTED':
        return ('Rejected', const Color(0xFFFEE2E2), const Color(0xFF991B1B));
      case 'RECALLED':
        return ('Recalled', const Color(0xFFF3F4F6), const Color(0xFF4B5563));
      case 'DRAFT_IN_REVIEW':
        return ('Not sent', null, null);
    }
    // Defensive fallback: if `approval_status` is somehow unset, use the
    // Lark-side status. Shouldn't happen in practice (column is NOT NULL
    // with a default) but cheap to preserve.
    switch (lark) {
      case 'APPROVED':
        return ('Acknowledged', const Color(0xFFDCFCE7), const Color(0xFF166534));
      case 'PENDING':
        return ('Pending', const Color(0xFFFEF3C7), const Color(0xFF92400E));
      case 'REJECTED':
        return ('Rejected', const Color(0xFFFEE2E2), const Color(0xFF991B1B));
      case 'CANCELED':
        return ('Recalled', const Color(0xFFF3F4F6), const Color(0xFF4B5563));
    }
    return ('Not sent', null, null);
  }
}

// ---------------------------------------------------------------------------
// Approval detail dialog — tapped from "View" in the actions cell. Shows
// which payslip PDF was sent to Lark plus the approval metadata (status,
// sent-at, Lark instance code). "Open PDF" navigates to the existing
// payslip preview route so the user can inspect / re-download what Lark
// received.
// ---------------------------------------------------------------------------

class _ApprovalDetailDialog extends StatelessWidget {
  final Map<String, dynamic> row;
  const _ApprovalDetailDialog({required this.row});

  @override
  Widget build(BuildContext context) {
    final emp = row['employees'] as Map<String, dynamic>?;
    final name = [emp?['first_name'], emp?['middle_name'], emp?['last_name']]
        .where((s) => s != null && (s as String).isNotEmpty)
        .join(' ');
    final number = emp?['employee_number'] as String? ?? '—';
    final dept = _deptFor(emp);
    final payslipId = row['id'] as String?;
    final payslipNumber = row['payslip_number'] as String?;
    final status = row['lark_approval_status'] as String?;
    final sentAtRaw = row['lark_approval_sent_at'] as String?;
    final instanceCode = row['lark_approval_instance_code'] as String?;

    final pdfFilename = payslipNumber != null
        ? 'Payslip-$payslipNumber.pdf'
        : payslipId != null
            ? 'Payslip-${payslipId.substring(0, 8)}.pdf'
            : 'Payslip.pdf';

    DateTime? sentAt;
    if (sentAtRaw != null) sentAt = DateTime.tryParse(sentAtRaw)?.toLocal();

    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final pillColors = _statusPillColors(status);
    final canOpenPdf = payslipId != null;

    return AlertDialog(
      title: Text('Payslip Acknowledgement — ${_ApprovalRow._lastFirst(name)}'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetailRow(
              label: 'Employee',
              value: '${_ApprovalRow._lastFirst(name)} · $number',
            ),
            if (dept != null && dept.isNotEmpty)
              _DetailRow(label: 'Department', value: dept),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 12),
            // The PDF card is the focal point of the dialog — matches the
            // "Payslip PDF" row in the Lark approval detail page.
            Text('Payslip PDF sent',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: muted)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.picture_as_pdf_outlined,
                        size: 16, color: Color(0xFFB91C1C)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(pdfFilename,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'GeistMono')),
                        if (payslipNumber != null)
                          Text(payslipNumber,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: muted,
                                  fontFamily: 'GeistMono')),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: canOpenPdf ? 'Open PDF' : 'Payslip ID missing',
                    icon: const Icon(Icons.open_in_new, size: 18),
                    // Always route to the PDF preview (`/payslips/:id`).
                    // `/payroll/:runId/payslip/:payslipId` is the
                    // breakdown screen (tabs for calculation, attendance,
                    // adjustments) — useful, but not what "Open PDF"
                    // implies. The PDF preview shows the exact file that
                    // was uploaded to Lark.
                    onPressed: canOpenPdf
                        ? () {
                            Navigator.of(context).pop();
                            context.push('/payslips/$payslipId');
                          }
                        : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _DetailRow(
              label: 'Status',
              valueWidget: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: pillColors.bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  pillColors.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: pillColors.fg,
                  ),
                ),
              ),
            ),
            if (sentAt != null)
              _DetailRow(label: 'Sent at', value: _fmtFullDateTime(sentAt)),
            if (instanceCode != null && instanceCode.isNotEmpty)
              _DetailRow(
                label: 'Lark ref',
                value: instanceCode,
                mono: true,
                onCopy: () {
                  Clipboard.setData(ClipboardData(text: instanceCode));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Lark instance code copied.'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        if (canOpenPdf)
          FilledButton.icon(
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
            label: const Text('Open payslip PDF'),
            // See the IconButton above — we route to `/payslips/:id` (the
            // actual PDF preview) rather than the breakdown screen so the
            // label matches the behaviour.
            onPressed: () {
              Navigator.of(context).pop();
              context.push('/payslips/$payslipId');
            },
          ),
      ],
    );
  }

  static ({String label, Color bg, Color fg}) _statusPillColors(
      String? status) {
    switch (status) {
      case 'PENDING':
        return (
          label: 'Pending',
          bg: const Color(0xFFFEF3C7),
          fg: const Color(0xFF92400E)
        );
      case 'APPROVED':
        return (
          label: 'Approved',
          bg: const Color(0xFFD1FADF),
          fg: const Color(0xFF12B76A)
        );
      case 'REJECTED':
        return (
          label: 'Rejected',
          bg: const Color(0xFFFEE2E2),
          fg: const Color(0xFFB91C1C)
        );
      case 'CANCELED':
      case 'CANCELLED':
      case 'RECALLED':
        return (
          label: 'Recalled',
          bg: const Color(0xFFF3F4F6),
          fg: const Color(0xFF4B5563)
        );
      default:
        return (
          label: 'Not sent',
          bg: const Color(0xFFF3F4F6),
          fg: const Color(0xFF6B7280)
        );
    }
  }

  static String _fmtFullDateTime(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    final suffix = d.hour >= 12 ? 'PM' : 'AM';
    return '${months[d.month - 1]} ${d.day}, ${d.year} · $h:$m $suffix';
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String? value;
  final Widget? valueWidget;
  final bool mono;
  final VoidCallback? onCopy;
  const _DetailRow({
    required this.label,
    this.value,
    this.valueWidget,
    this.mono = false,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ),
          Expanded(
            child: valueWidget ??
                Text(
                  value ?? '—',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    fontFamily: mono ? 'GeistMono' : null,
                  ),
                ),
          ),
          if (onCopy != null)
            IconButton(
              tooltip: 'Copy',
              icon: const Icon(Icons.copy_outlined, size: 16),
              onPressed: onCopy,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}
