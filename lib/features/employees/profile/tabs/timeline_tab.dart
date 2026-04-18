import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/money.dart';
import '../../../../data/models/employee.dart';
import '../../../auth/profile_provider.dart';
import '../../../lark/lark_repository.dart';
import '../../../../widgets/syncing_dialog.dart';
import '../providers.dart';
import '../widgets/info_card.dart';

class TimelineTab extends ConsumerStatefulWidget {
  final Employee employee;
  const TimelineTab({super.key, required this.employee});

  @override
  ConsumerState<TimelineTab> createState() => _TimelineTabState();
}

enum _Filter {
  all,
  events,
  payslips,
  documents,
  cashAdvances,
  reimbursements,
  penalties,
}

class _TimelineTabState extends ConsumerState<TimelineTab> {
  _Filter _filter = _Filter.all;

  bool _matches(TimelineEntry e) {
    switch (_filter) {
      case _Filter.all:
        return true;
      case _Filter.events:
        return e.kind == TimelineKind.event || e.kind == TimelineKind.leave;
      case _Filter.payslips:
        return e.kind == TimelineKind.payslip;
      case _Filter.documents:
        return e.kind == TimelineKind.document;
      case _Filter.cashAdvances:
        return e.kind == TimelineKind.cashAdvance;
      case _Filter.reimbursements:
        return e.kind == TimelineKind.reimbursement;
      case _Filter.penalties:
        return e.kind == TimelineKind.penalty;
    }
  }

  Future<void> _syncFromLark(BuildContext context) async {
    final profile = ref.read(userProfileProvider).asData?.value;
    final companyId = profile?.companyId;
    if (companyId == null || companyId.isEmpty) return;
    final lark = ref.read(larkRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final results = await runWithSyncingDialog(
        context,
        'Lark approvals for ${widget.employee.fullName}',
        () async {
          final res = await Future.wait([
            lark.syncLeaves(companyId),
            lark.syncCashAdvances(companyId),
            lark.syncReimbursements(companyId),
          ]);
          return res;
        },
      );
      final totalCreated = results.fold<int>(0, (s, r) => s + r.created);
      final totalUpdated = results.fold<int>(0, (s, r) => s + r.updated);
      messenger.showSnackBar(SnackBar(
        content: Text(
          'Synced — leaves, cash advances, reimbursements · '
          'created $totalCreated, updated $totalUpdated.',
        ),
      ));
      ref.invalidate(timelineProvider(widget.employee.id));
      ref.invalidate(financialsByEmployeeProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Sync failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(timelineProvider(widget.employee.id));

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _FilterChip(
                    label: 'All',
                    selected: _filter == _Filter.all,
                    onTap: () => setState(() => _filter = _Filter.all),
                  ),
                  _FilterChip(
                    label: 'Events',
                    selected: _filter == _Filter.events,
                    onTap: () => setState(() => _filter = _Filter.events),
                  ),
                  _FilterChip(
                    label: 'Payslips',
                    selected: _filter == _Filter.payslips,
                    onTap: () => setState(() => _filter = _Filter.payslips),
                  ),
                  _FilterChip(
                    label: 'Documents',
                    selected: _filter == _Filter.documents,
                    onTap: () => setState(() => _filter = _Filter.documents),
                  ),
                  _FilterChip(
                    label: 'Cash Advances',
                    selected: _filter == _Filter.cashAdvances,
                    onTap: () =>
                        setState(() => _filter = _Filter.cashAdvances),
                  ),
                  _FilterChip(
                    label: 'Reimbursements',
                    selected: _filter == _Filter.reimbursements,
                    onTap: () =>
                        setState(() => _filter = _Filter.reimbursements),
                  ),
                  _FilterChip(
                    label: 'Penalties',
                    selected: _filter == _Filter.penalties,
                    onTap: () => setState(() => _filter = _Filter.penalties),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _syncFromLark(context),
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
          data: (entries) {
            final filtered = entries.where(_matches).toList();
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                    child: Row(
                      children: [
                        const Text(
                          'Timeline',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '(${filtered.length} entries)',
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: Theme.of(context).dividerColor),
                  if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'No timeline entries.',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  else
                    for (final e in filtered) _TimelineRow(entry: e),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final TimelineEntry entry;
  const _TimelineRow({required this.entry});

  Color _dot(TimelineKind kind) {
    return switch (kind) {
      TimelineKind.payslip => const Color(0xFF16A34A),
      TimelineKind.leave => const Color(0xFF2563EB),
      TimelineKind.event => const Color(0xFFA855F7),
      TimelineKind.penalty => const Color(0xFFDC2626),
      TimelineKind.cashAdvance => const Color(0xFFF59E0B),
      TimelineKind.reimbursement => const Color(0xFF0891B2),
      TimelineKind.document => const Color(0xFF6366F1),
    };
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = _fmtDate(entry.date);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 12),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: _dot(entry.kind),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        entry.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusChip(
                      label: entry.status.replaceAll('_', ' '),
                      tone: toneForStatus(entry.status),
                    ),
                    if (entry.subtitle != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        entry.subtitle!,
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  dateLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (entry.dateRange != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      entry.dateRange!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (entry.amountText != null)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                Money.fmtPhp(Decimal.parse(entry.amountText!)),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _fmtDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}
