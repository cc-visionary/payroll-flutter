import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/breakpoints.dart';
import '../../../app/shell.dart';
import '../../../core/money.dart';
import '../../../data/models/payroll_run.dart';
import '../../../data/repositories/payroll_repository.dart';
import '../../auth/profile_provider.dart';
import 'new/new_run_dialog.dart';

class PayrollRunsScreen extends ConsumerWidget {
  const PayrollRunsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(payrollRunsProvider);
    final profile = ref.watch(userProfileProvider).asData?.value;
    final canRun = profile?.canRunPayroll ?? false;

    return Scaffold(
      drawer: isMobile(context) ? const AppDrawer() : null,
      appBar: AppBar(
        title: const Text('Payroll Runs'),
        actions: [
          if (canRun)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: FilledButton.icon(
                onPressed: () => showNewPayrollRunDialog(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('New run'),
              ),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
          data: (rows) => rows.isEmpty
              ? const Center(child: Text('No payroll runs yet.'))
              : Card(child: _RunsTable(runs: rows, canRun: canRun)),
        ),
      ),
    );
  }
}

class _RunsTable extends ConsumerWidget {
  final List<PayrollRun> runs;
  final bool canRun;
  const _RunsTable({required this.runs, required this.canRun});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DataTable2(
      columnSpacing: 16,
      horizontalMargin: 16,
      minWidth: 1000,
      columns: const [
        DataColumn2(label: Text('Pay Date'), size: ColumnSize.S),
        DataColumn2(label: Text('Status'), size: ColumnSize.S),
        DataColumn2(label: Text('Employees'), size: ColumnSize.S, numeric: true),
        DataColumn2(label: Text('Gross'), size: ColumnSize.M, numeric: true),
        DataColumn2(label: Text('Deductions'), size: ColumnSize.M, numeric: true),
        DataColumn2(label: Text('Net'), size: ColumnSize.M, numeric: true),
        DataColumn2(label: Text('Actions'), size: ColumnSize.L),
      ],
      rows: runs
          .map((r) => DataRow2(
                onTap: () => context.push('/payroll/${r.id}'),
                cells: [
                  DataCell(Text(r.payDate?.toIso8601String().substring(0, 10) ?? '—')),
                  DataCell(_RunStatusChip(status: r.status)),
                  DataCell(Text(r.employeeCount.toString())),
                  DataCell(Text(Money.fmtPhp(r.totalGrossPay))),
                  DataCell(Text(Money.fmtPhp(r.totalDeductions))),
                  DataCell(Text(Money.fmtPhp(r.totalNetPay))),
                  DataCell(canRun
                      ? _RunActions(run: r)
                      : Text(r.status == 'RELEASED' ? 'Released' : '—',
                          style: Theme.of(context).textTheme.bodySmall)),
                ],
              ))
          .toList(),
    );
  }
}

class _RunStatusChip extends StatelessWidget {
  final String status;
  const _RunStatusChip({required this.status});

  Color _color(BuildContext c) {
    switch (status) {
      case 'RELEASED':
        return Colors.green;
      case 'REVIEW':
        return Colors.orange;
      case 'CANCELLED':
        return Colors.red;
      case 'COMPUTING':
        return Colors.blue;
      default:
        return Theme.of(c).disabledColor;
    }
  }

  @override
  Widget build(BuildContext c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color(c).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(status,
          style: TextStyle(fontSize: 11, color: _color(c), fontWeight: FontWeight.w600)),
    );
  }
}

Future<void> _confirmAndDelete(
  BuildContext context,
  WidgetRef ref,
  PayrollRun run,
) async {
  final dateLabel = run.createdAt.toIso8601String().substring(0, 10);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete cancelled run?'),
      content: Text(
        'Permanently delete the cancelled payroll run from $dateLabel? '
        'This also removes any payslips that were generated. This cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
          ),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(payrollRepositoryProvider).deleteRun(run.id);
    ref.invalidate(payrollRunsProvider);
    if (context.mounted) {
      messenger.showSnackBar(const SnackBar(content: Text('Run deleted.')));
    }
  } catch (e) {
    if (context.mounted) {
      messenger.showSnackBar(SnackBar(
        content: Text('Delete failed: ${e.toString().replaceAll('Exception: ', '')}'),
        duration: const Duration(seconds: 6),
      ));
    }
  }
}

class _RunActions extends ConsumerWidget {
  final PayrollRun run;
  const _RunActions({required this.run});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countsAsync = ref.watch(payslipApprovalCountsProvider(run.id));
    final repo = ref.read(payrollRepositoryProvider);

    if (run.status != 'REVIEW') {
      // DRAFT → Start review (move to REVIEW)
      if (run.status == 'DRAFT') {
        return OutlinedButton(
          onPressed: () async {
            await repo.updateStatus(run.id, 'REVIEW');
            ref.invalidate(payrollRunsProvider);
          },
          child: const Text('Start review'),
        );
      }
      // CANCELLED → allow permanent delete (confirm first)
      if (run.status == 'CANCELLED') {
        return TextButton.icon(
          onPressed: () => _confirmAndDelete(context, ref, run),
          icon: Icon(Icons.delete_outline,
              size: 16, color: Theme.of(context).colorScheme.error),
          label: Text('Delete',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        );
      }
      return const SizedBox.shrink();
    }

    // REVIEW state — iterative workflow.
    return countsAsync.when(
      loading: () => const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      error: (e, _) => Text('Err: $e', style: const TextStyle(color: Colors.red, fontSize: 11)),
      data: (counts) {
        final draft = counts['DRAFT_IN_REVIEW'] ?? 0;
        final pending = counts['PENDING_APPROVAL'] ?? 0;
        final approved = counts['APPROVED'] ?? 0;
        final total = draft + pending + approved + (counts['REJECTED'] ?? 0) + (counts['RECALLED'] ?? 0);
        final allApproved = total > 0 && approved == total;

        return Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('$approved/$total approved',
                style: Theme.of(context).textTheme.bodySmall),
            if (draft > 0)
              OutlinedButton(
                onPressed: () async {
                  await repo.sendPayslipApprovals(run.id);
                  ref.invalidate(payslipApprovalCountsProvider(run.id));
                },
                child: Text('Send ($draft)'),
              ),
            if (pending > 0)
              OutlinedButton(
                onPressed: () {
                  ref.invalidate(payslipApprovalCountsProvider(run.id));
                },
                child: Text('Refresh ($pending)'),
              ),
            if (pending > 0)
              TextButton(
                onPressed: () async {
                  await repo.recallPayslipApprovals(run.id);
                  ref.invalidate(payslipApprovalCountsProvider(run.id));
                },
                child: const Text('Unsend'),
              ),
            FilledButton(
              onPressed: allApproved
                  ? () async {
                      await repo.updateStatus(run.id, 'RELEASED');
                      ref.invalidate(payrollRunsProvider);
                    }
                  : null,
              child: const Text('Release'),
            ),
          ],
        );
      },
    );
  }
}
