import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/money.dart';
import '../../../../../data/models/payroll_run.dart';
import '../../../../../widgets/syncing_dialog.dart';
import '../../../../auth/profile_provider.dart';
import '../../compute/compute_service.dart';
import '../providers.dart';
import '../run_roster.dart';
import '../run_roster_service.dart';
import '../widgets/add_employees_dialog.dart';

class PayrollPayslipsTab extends ConsumerStatefulWidget {
  final PayrollRun run;
  const PayrollPayslipsTab({super.key, required this.run});

  String get runId => run.id;
  String get runStatus => run.status;

  @override
  ConsumerState<PayrollPayslipsTab> createState() => _PayrollPayslipsTabState();
}

class _PayrollPayslipsTabState extends ConsumerState<PayrollPayslipsTab> {
  String _search = '';

  /// Whether the run's employee roster can still be edited here: an unreleased
  /// run, and a user allowed to run payroll. RELEASED and CANCELLED runs are
  /// final — [PayrollRosterService] refuses them too, this just hides the UI.
  bool get _canEditRoster {
    final canRun =
        ref.watch(userProfileProvider).asData?.value?.canRunPayroll ?? false;
    return canRun &&
        (widget.runStatus == 'DRAFT' || widget.runStatus == 'REVIEW');
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(payslipListForRunProvider(widget.runId));
    final canEdit = _canEditRoster;
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
        final filtered = _search.isEmpty
            ? rows
            : rows.where((r) {
                final emp = r['employees'] as Map<String, dynamic>?;
                final name = _fullName(emp).toLowerCase();
                final num =
                    (emp?['employee_number'] as String?)?.toLowerCase() ?? '';
                final q = _search.toLowerCase();
                return name.contains(q) || num.contains(q);
              }).toList();
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
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                              hintText: 'Search employees...',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (v) => setState(() => _search = v),
                          ),
                        ),
                        if (canEdit) ...[
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            onPressed: _addEmployees,
                            icon: const Icon(Icons.person_add_alt, size: 16),
                            label: const Text('Add Employee'),
                          ),
                        ],
                      ],
                    ),
                  ),
                  _Header(
                    showLark: widget.runStatus == 'RELEASED',
                    showRowMenu: canEdit,
                  ),
                  Divider(height: 1, color: Theme.of(context).dividerColor),
                  if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                          _search.isEmpty
                              ? 'No payslips computed yet'
                              : 'No employees found',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  else
                    for (final r in filtered) ...[
                      _PayslipRow(
                        runId: widget.runId,
                        row: r,
                        showLark: widget.runStatus == 'RELEASED',
                        onRemove: canEdit ? () => _confirmRemove(r) : null,
                      ),
                      Divider(height: 1, color: Theme.of(context).dividerColor),
                    ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// Drop one employee from the run. No recompute — removing somebody cannot
  /// change anybody else's pay, so the service just deletes their payslip and
  /// re-sums the run's totals.
  Future<void> _confirmRemove(Map<String, dynamic> row) async {
    final emp = row['employees'] as Map<String, dynamic>?;
    final name = _fullName(emp);
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Remove from payroll run?'),
            content: Text(
              '$name will be dropped from this run and their payslip deleted. '
              "The run's totals update immediately, and later recomputes will "
              'not bring them back. You can add them again with "Add '
              'Employee".',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                ),
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Remove'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(payrollRosterServiceProvider)
          .removeEmployeeFromRun(
            run: widget.run,
            employeeId: row['employee_id'] as String,
          );
      await refreshRunDetail(ref, widget.runId);
      messenger.showSnackBar(
        SnackBar(content: Text('Removed $name from this run.')),
      );
    } on RosterEditException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Remove failed: $e')));
    }
  }

  /// Add employees to the run, then recompute — the compute pass is what
  /// actually generates their payslips. Lark-locked payslips already in the
  /// run survive it untouched (see [PayrollComputeService]).
  Future<void> _addEmployees() async {
    final ids = await showDialog<List<String>>(
      context: context,
      builder: (_) => AddEmployeesDialog(run: widget.run),
    );
    if (ids == null || ids.isEmpty || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(payrollRosterServiceProvider);
    final compute = ref.read(payrollComputeServiceProvider);
    try {
      await service.addEmployeesToRun(run: widget.run, employeeIds: ids);
      if (!mounted) return;
      final outcome = await runWithSyncingDialog(
        context,
        'Computing payslips',
        () => compute.computeRun(widget.runId),
      );
      await refreshRunDetail(ref, widget.runId);
      if (!mounted) return;
      final skipped = outcome.warnings.length + outcome.errors.length;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Added ${ids.length} employee${ids.length == 1 ? '' : 's'}.'
            '${skipped > 0 ? ' $skipped could not be computed.' : ''}',
          ),
        ),
      );
    } on RosterEditException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Add failed: $e')));
    }
  }

  static String _fullName(Map<String, dynamic>? emp) {
    if (emp == null) return '';
    return [
      emp['first_name'],
      emp['middle_name'],
      emp['last_name'],
    ].where((s) => s != null && (s as String).isNotEmpty).join(' ');
  }
}

class _Header extends StatelessWidget {
  final bool showLark;

  /// Mirrors the rows' overflow menu so the ACTIONS column keeps the same
  /// width in the header as in the body — the menu needs a full tap target,
  /// which does not fit alongside "View" in a single flex unit.
  final bool showRowMenu;
  const _Header({required this.showLark, required this.showRowMenu});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    final style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: color,
      letterSpacing: 0.4,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('EMPLOYEE', style: style)),
          Expanded(flex: 2, child: Text('DEPARTMENT', style: style)),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text('GROSS PAY', style: style),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text('DEDUCTIONS', style: style),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text('NET PAY', style: style),
            ),
          ),
          if (showLark)
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.center,
                child: Text('LARK STATUS', style: style),
              ),
            ),
          Expanded(
            flex: showRowMenu ? 2 : 1,
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

class _PayslipRow extends StatelessWidget {
  final String runId;
  final Map<String, dynamic> row;
  final bool showLark;

  /// Null when the run's roster can't be edited — hides the overflow menu.
  final VoidCallback? onRemove;
  const _PayslipRow({
    required this.runId,
    required this.row,
    required this.showLark,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final emp = row['employees'] as Map<String, dynamic>?;
    final directDept =
        (emp?['departments'] as Map<String, dynamic>?)?['name'] as String?;
    final scorecardDept =
        ((emp?['role_scorecards'] as Map<String, dynamic>?)?['departments']
                as Map<String, dynamic>?)?['name']
            as String?;
    final dept = (directDept != null && directDept.isNotEmpty)
        ? directDept
        : scorecardDept;
    final fullName = _PayrollPayslipsTabState._fullName(emp);
    final empNumber = emp?['employee_number'] as String? ?? '—';
    final gross = _dec(row['gross_pay']);
    final deductions = _dec(row['total_deductions']);
    final net = _dec(row['net_pay']);
    final larkStatus = row['lark_approval_status'] as String?;

    return InkWell(
      onTap: () =>
          context.push('/payroll/$runId/payslip/${row['id'] as String}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _lastFirst(fullName),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    empNumber,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(dept ?? '—', style: const TextStyle(fontSize: 13)),
            ),
            Expanded(
              flex: 2,
              child: Text(
                Money.fmtPhp(gross),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                '-${Money.fmtPhp(deductions)}',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 13, color: Color(0xFFDC2626)),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                Money.fmtPhp(net),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (showLark)
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.center,
                  child: _LarkStatusPill(status: larkStatus),
                ),
              ),
            Expanded(
              flex: onRemove == null ? 1 : 2,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => context.push(
                      '/payroll/$runId/payslip/${row['id'] as String}',
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF2563EB),
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(40, 24),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('View'),
                  ),
                  if (onRemove != null)
                    PopupMenuButton<String>(
                      tooltip: 'More actions',
                      icon: const Icon(Icons.more_vert, size: 18),
                      padding: EdgeInsets.zero,
                      splashRadius: 16,
                      constraints: const BoxConstraints(minWidth: 180),
                      onSelected: (v) {
                        if (v == 'remove') onRemove!();
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem<String>(
                          value: 'remove',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              Icons.person_remove_outlined,
                              size: 18,
                              color: Color(0xFFDC2626),
                            ),
                            title: Text(
                              'Remove from run',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFFDC2626),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
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

  static Decimal _dec(Object? v) => Decimal.parse((v ?? '0').toString());
}

class _LarkStatusPill extends StatelessWidget {
  final String? status;
  const _LarkStatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    if (status == null) {
      return Text(
        'Not sent',
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    final (label, bg, fg) = switch (status) {
      'APPROVED' => (
        'Acknowledged',
        const Color(0xFFDCFCE7),
        const Color(0xFF166534),
      ),
      'PENDING' => (
        'Pending',
        const Color(0xFFFEF3C7),
        const Color(0xFF92400E),
      ),
      'REJECTED' => (
        'Rejected',
        const Color(0xFFFEE2E2),
        const Color(0xFF991B1B),
      ),
      'CANCELED' => (
        'Recalled',
        const Color(0xFFF3F4F6),
        const Color(0xFF4B5563),
      ),
      'DELETED' => (
        'Deleted',
        const Color(0xFFF3F4F6),
        const Color(0xFF4B5563),
      ),
      _ => (status!, const Color(0xFFF3F4F6), const Color(0xFF4B5563)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}
