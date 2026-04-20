import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/breakpoints.dart';
import '../../../../data/repositories/payroll_repository.dart';
import '../../../../widgets/syncing_dialog.dart';
import '../../../auth/profile_provider.dart';
import '../compute/compute_service.dart';
import '../../payslips/payslip_pdf_context.dart';
import 'providers.dart';
import 'tabs/approvals_tab.dart';
import 'tabs/disbursement_tab.dart';
import 'tabs/payslips_tab.dart';
import 'tabs/summary_tab.dart';
import 'widgets/distribute_13th_dialog.dart';
import 'widgets/status_timeline.dart';

/// Payroll run detail — Summary / Payslips / Disbursement / Approvals tabs.
/// Matches the payrollos run detail layout.
class PayrollRunDetailScreen extends ConsumerStatefulWidget {
  final String runId;
  const PayrollRunDetailScreen({super.key, required this.runId});

  @override
  ConsumerState<PayrollRunDetailScreen> createState() =>
      _PayrollRunDetailScreenState();
}

class _PayrollRunDetailScreenState
    extends ConsumerState<PayrollRunDetailScreen> {
  RealtimeChannel? _channel;

  String get runId => widget.runId;

  @override
  void initState() {
    super.initState();
    // Live-refresh this run's detail + payslip list whenever rows change
    // server-side. Filters by `payroll_run_id=eq.<runId>` so we only get
    // notifications about THIS run — not every run in the system. One
    // channel per run; one Realtime message ≡ one targeted invalidate.
    _channel = Supabase.instance.client
        .channel('payroll-run-$runId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'payslips',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'payroll_run_id',
            value: runId,
          ),
          callback: (_) => _invalidateAll(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'payroll_runs',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: runId,
          ),
          callback: (_) => _invalidateAll(),
        )
        .subscribe();
  }

  void _invalidateAll() {
    if (!mounted) return;
    ref.invalidate(payrollRunDetailProvider(runId));
    ref.invalidate(payslipListForRunProvider(runId));
    ref.invalidate(payslipApprovalCountsProvider(runId));
    ref.invalidate(larkApprovalCountsProvider(runId));
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(payrollRunDetailProvider(runId));
    return Scaffold(
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Error: $e', style: const TextStyle(color: Colors.red)),
          ),
        ),
        data: (detail) {
          if (detail == null) {
            return const Center(child: Text('Payroll run not found.'));
          }
          final showApprovals =
              detail.run.status == 'REVIEW' || detail.run.status == 'RELEASED';
          final tabCount = showApprovals ? 4 : 3;
          final hPad = isMobile(context) ? 16.0 : 24.0;
          return DefaultTabController(
            length: tabCount,
            child: NestedScrollView(
              headerSliverBuilder: (context, _) => [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 0),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Header(detail: detail),
                        const SizedBox(height: 16),
                        PayrollStatusTimeline(
                          status: detail.run.status,
                          createdAt: detail.run.createdAt,
                          approvedAt: detail.run.approvedAt,
                          releasedAt: detail.run.releasedAt,
                        ),
                        const SizedBox(height: 16),
                        _ActionBar(detail: detail),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabBarDelegate(
                    child: Container(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      padding: EdgeInsets.symmetric(horizontal: hPad),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TabBar(
                            isScrollable: true,
                            tabAlignment: TabAlignment.start,
                            indicatorSize: TabBarIndicatorSize.label,
                            labelStyle: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                            unselectedLabelStyle:
                                const TextStyle(fontSize: 14),
                            tabs: [
                              const Tab(text: 'Summary'),
                              Tab(text: 'Payslips (${detail.payslipCount})'),
                              const Tab(text: 'Disbursement'),
                              if (showApprovals) const Tab(text: 'Approvals'),
                            ],
                          ),
                          const Divider(height: 1),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              body: Padding(
                padding: EdgeInsets.symmetric(horizontal: hPad),
                child: TabBarView(
                  children: [
                    PayrollSummaryTab(detail: detail),
                    PayrollPayslipsTab(
                      runId: runId,
                      runStatus: detail.run.status,
                    ),
                    PayrollDisbursementTab(
                      runId: runId,
                      runStatus: detail.run.status,
                    ),
                    if (showApprovals) PayrollApprovalsTab(runId: runId),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Pins the TabBar below the scrollable header in the NestedScrollView.
class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  _TabBarDelegate({required this.child});
  static const double _h = 49;
  @override
  double get minExtent => _h;
  @override
  double get maxExtent => _h;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      SizedBox(height: _h, child: child);
  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) =>
      oldDelegate.child != child;
}

// ---------------------------------------------------------------------------
// Header: back link, code, dates, status chip.
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  final PayrollRunDetail detail;
  const _Header({required this.detail});

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = _statusPill(detail.run.status);
    final code = detail.payPeriodCode;
    final start = detail.payPeriodStart;
    final end = detail.payPeriodEnd;
    final payDate = detail.payDate;
    final range = '${_fmtDate(start)} - ${_fmtDate(end)}';
    final mobile = isMobile(context);

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            InkWell(
              onTap: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/payroll');
                }
              },
              child: Text(
                'Payroll Runs',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const Text('  /  ',
                style: TextStyle(color: Color(0xFF9CA3AF))),
            Flexible(
              child: Text(
                code,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          code,
          style: TextStyle(
            fontSize: mobile ? 18 : 22,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '$range | Pay Date: ${_fmtDate(payDate)}',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
    final statusPill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );

    if (mobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          titleBlock,
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerLeft, child: statusPill),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: titleBlock),
        statusPill,
      ],
    );
  }

  static (String, Color, Color) _statusPill(String status) {
    switch (status) {
      case 'DRAFT':
        return ('Draft', const Color(0xFFF3F4F6), const Color(0xFF4B5563));
      case 'COMPUTING':
        return ('Computing...', const Color(0xFFDBEAFE), const Color(0xFF1E40AF));
      case 'REVIEW':
        return ('In Review', const Color(0xFFFEF3C7), const Color(0xFF92400E));
      case 'RELEASED':
        return ('Released', const Color(0xFFF3E8FF), const Color(0xFF6B21A8));
      case 'CANCELLED':
        return ('Cancelled', const Color(0xFFFEE2E2), const Color(0xFF991B1B));
      default:
        return (status, const Color(0xFFF3F4F6), const Color(0xFF4B5563));
    }
  }

  static String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}

// ---------------------------------------------------------------------------
// Action bar: Compute / Recompute / Release / Cancel / Export / Lark buttons.
// Visibility matches payrollos; actions are stubbed where the compute pipeline
// isn't wired yet.
// ---------------------------------------------------------------------------

class _ActionBar extends ConsumerWidget {
  final PayrollRunDetail detail;
  const _ActionBar({required this.detail});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).asData?.value;
    final canRun = profile?.canRunPayroll ?? false;
    if (!canRun) return const SizedBox.shrink();
    final status = detail.run.status;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        if (status == 'DRAFT')
          FilledButton.icon(
            onPressed: () => _compute(context, ref),
            icon: const Icon(Icons.play_arrow, size: 16),
            label: const Text('Compute Payroll'),
          ),
        if (status == 'REVIEW') ...[
          OutlinedButton.icon(
            onPressed: () => _compute(context, ref, isRecompute: true),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Recompute'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
            ),
            onPressed: () => _confirmRelease(context, ref),
            child: const Text('Release'),
          ),
        ],
        if (status == 'DRAFT' || status == 'REVIEW')
          OutlinedButton(
            onPressed: () => _confirmCancel(context, ref),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFDC2626),
              side: const BorderSide(color: Color(0xFFFCA5A5)),
            ),
            child: const Text('Cancel Run'),
          ),
        if (status == 'REVIEW' || status == 'RELEASED')
          OutlinedButton.icon(
            onPressed: () => _stub(context, 'Export Payslips'),
            icon: const Icon(Icons.file_download_outlined, size: 16),
            label: const Text('Export Payslips'),
          ),
        if (status == 'REVIEW' || status == 'RELEASED')
          _SendLarkApprovalsButton(runId: detail.run.id),
        if (status == 'REVIEW')
          PopupMenuButton<String>(
            tooltip: 'More actions',
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'distribute_13th') {
                showDialog<bool>(
                  context: context,
                  builder: (_) => Distribute13thDialog(runId: detail.run.id),
                );
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem<String>(
                value: 'distribute_13th',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.card_giftcard_outlined, size: 20),
                  title: Text('Distribute 13th Month'),
                  subtitle: Text(
                    "Attach a 13th-month line to this run's payslips",
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  void _stub(BuildContext context, String action) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$action — coming soon.')),
    );
  }

  Future<void> _compute(
    BuildContext context,
    WidgetRef ref, {
    bool isRecompute = false,
  }) async {
    if (isRecompute) {
      final ok = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('Recompute payroll?'),
              content: const Text(
                'This deletes the current payslips for this run and computes '
                'fresh ones from attendance, adjustments, and approvals. '
                'Approval statuses already sent to Lark will be cleared.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('Recompute'),
                ),
              ],
            ),
          ) ??
          false;
      if (!ok || !context.mounted) return;
    }
    final service = ref.read(payrollComputeServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    final runId = detail.run.id;
    try {
      final outcome = await runWithSyncingDialog(
        context,
        isRecompute ? 'Recomputing payroll' : 'Computing payroll',
        () => service.computeRun(runId),
      );
      // Force-refresh every provider the detail screen reads so the current
      // tab (Summary/Payslips/Disbursement/Approvals) updates in place —
      // without this the totals stay stale until the user switches tabs.
      // `refresh().future` awaits the re-fetch so we don't flash the snackbar
      // before fresh data lands.
      await Future.wait([
        ref.refresh(payrollRunDetailProvider(runId).future),
        ref.refresh(payslipListForRunProvider(runId).future),
        ref.refresh(payslipApprovalCountsProvider(runId).future),
        ref.refresh(larkApprovalCountsProvider(runId).future),
      ]);
      ref.invalidate(payrollRunsProvider);
      if (!context.mounted) return;
      if (outcome.errors.isEmpty && outcome.warnings.isEmpty) {
        messenger.showSnackBar(SnackBar(
          content: Text('Computed ${outcome.employeeCount} payslip(s).'),
        ));
      } else {
        final msg = StringBuffer()
          ..write('Computed ${outcome.employeeCount} payslip(s).');
        if (outcome.warnings.isNotEmpty) {
          msg.write(' ${outcome.warnings.length} skipped.');
        }
        if (outcome.errors.isNotEmpty) {
          msg.write(' ${outcome.errors.length} error(s).');
        }
        messenger.showSnackBar(SnackBar(
          content: Text(msg.toString()),
          action: SnackBarAction(
            label: 'Details',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Compute details'),
                content: SingleChildScrollView(
                  child: Text(
                    [
                      if (outcome.warnings.isNotEmpty) ...[
                        'Skipped employees:',
                        ...outcome.warnings,
                        '',
                      ],
                      if (outcome.errors.isNotEmpty) ...[
                        'Errors:',
                        ...outcome.errors,
                      ],
                    ].join('\n'),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ),
        ));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Compute failed: $e'),
      ));
    }
  }

  Future<void> _confirmRelease(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Release payroll?'),
            content: const Text(
              'Releasing locks attendance for this period, marks cash advances '
              'and reimbursements as deducted, and finalizes payslips. This '
              'cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                ),
                child: const Text('Release'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final runId = detail.run.id;
    try {
      await runWithSyncingDialog(
        context,
        'Releasing payroll',
        () => ref.read(payrollRepositoryProvider).releaseRun(runId),
      );
      ref.invalidate(payrollRunDetailProvider(runId));
      ref.invalidate(payslipListForRunProvider(runId));
      ref.invalidate(payrollRunsProvider);
      if (context.mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Payroll released.')),
        );
      }
    } catch (err) {
      messenger.showSnackBar(SnackBar(content: Text('Release failed: $err')));
    }
  }

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Cancel payroll run?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'The run will be marked CANCELLED. It will no longer be '
                  'computed or released.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'Reason (optional)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  maxLines: 2,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Keep'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                ),
                child: const Text('Cancel Run'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !context.mounted) return;
    await ref.read(payrollRepositoryProvider).cancelRun(
          detail.run.id,
          reason: controller.text.trim().isEmpty ? null : controller.text.trim(),
        );
    ref.invalidate(payrollRunDetailProvider(detail.run.id));
    ref.invalidate(payrollRunsProvider);
    if (context.mounted) context.go('/payroll');
  }
}

/// Button that dispatches unsent payslips in a run to Lark for approval.
///
/// Label + enabled state reflect the current approval_status counts:
///   - `DRAFT_IN_REVIEW` rows are the only ones the edge function will
///     actually dispatch, so we key both the label and the disabled state off
///     that bucket. This matches `send-payslip-approvals/index.ts`, which
///     filters `.eq('approval_status', 'DRAFT_IN_REVIEW')`.
///   - "Send" when nothing's been sent yet; "Send Remaining (n)" when some
///     were already sent; disabled once all payslips have moved past
///     DRAFT_IN_REVIEW.
class _SendLarkApprovalsButton extends ConsumerWidget {
  final String runId;
  const _SendLarkApprovalsButton({required this.runId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countsAsync = ref.watch(payslipApprovalCountsProvider(runId));
    final counts = countsAsync.asData?.value ?? const <String, int>{};
    // DRAFT_IN_REVIEW = never sent; RECALLED = previously sent, pulled back.
    // Both are eligible to dispatch — the edge function filters on both.
    final unsent =
        (counts['DRAFT_IN_REVIEW'] ?? 0) + (counts['RECALLED'] ?? 0);
    final alreadyTouched = counts.entries.fold<int>(
      0,
      (s, e) => (e.key == 'DRAFT_IN_REVIEW' || e.key == 'RECALLED')
          ? s
          : s + e.value,
    );

    // `alreadyTouched` kept as a marker for "partial progress" phrasing, but
    // the primary label now always states the exact count being sent so the
    // action is unambiguous ("Send All Lark Approvals (9)" vs
    // "Send Remaining Lark Approvals (3)").
    final String label;
    if (unsent == 0) {
      label = 'Send All Lark Approvals (0)';
    } else if (alreadyTouched == 0) {
      label = 'Send All Lark Approvals ($unsent)';
    } else {
      label = 'Send Remaining Lark Approvals ($unsent)';
    }

    return OutlinedButton.icon(
      onPressed: unsent == 0
          ? null
          : () async {
              final ok = await _confirm(context, unsent: unsent);
              if (!ok || !context.mounted) return;
              final messenger = ScaffoldMessenger.of(context);
              try {
                // Lark's approval template has a required PDF attachment
                // widget, so we build every payslip's PDF up-front and
                // pass them as base64 so the edge function can upload to
                // Lark before creating each approval instance.
                final rows = await ref
                    .read(payrollRepositoryProvider)
                    .payslipListForRun(runId);
                final ids = <String>[
                  for (final r in rows)
                    if (r['approval_status'] == 'DRAFT_IN_REVIEW' ||
                        r['approval_status'] == 'RECALLED')
                      r['id'] as String,
                ];
                messenger.showSnackBar(SnackBar(
                  content: Text(
                      'Generating ${ids.length} payslip PDF${ids.length == 1 ? '' : 's'}…'),
                  duration: const Duration(seconds: 3),
                ));
                final pdfs =
                    await buildPayslipPdfsBase64ForIds(ref, ids);
                final res = await ref
                    .read(payrollRepositoryProvider)
                    .sendPayslipApprovals(
                      runId,
                      payslipIds: ids,
                      pdfsByPayslipId: pdfs,
                    );
                ref.invalidate(payslipListForRunProvider(runId));
                ref.invalidate(payrollRunDetailProvider(runId));
                ref.invalidate(payslipApprovalCountsProvider(runId));
                ref.invalidate(larkApprovalCountsProvider(runId));
                final sent = (res['sent'] as num?)?.toInt() ?? 0;
                final failed = (res['failed'] as num?)?.toInt() ?? 0;
                final errs = (res['errors'] as List?) ?? const [];
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
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF2563EB),
        side: const BorderSide(color: Color(0xFF93C5FD)),
      ),
      icon: const Icon(Icons.send, size: 16),
      label: Text(label),
    );
  }

  Future<bool> _confirm(BuildContext context, {required int unsent}) async {
    final plural = unsent == 1 ? '' : 's';
    final result = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Send Lark approvals?'),
        content: Text(
          'This will dispatch $unsent payslip approval request$plural to '
          "Lark. Each recipient will be notified in their Lark inbox and "
          "can't be un-sent silently — a Recall is required to cancel.\n\n"
          'Make sure the run totals are correct before continuing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text('Send ($unsent)'),
          ),
        ],
      ),
    );
    return result == true;
  }
}
