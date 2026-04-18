import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/money.dart';
import '../providers.dart';

class PayrollPayslipsTab extends ConsumerStatefulWidget {
  final String runId;
  final String runStatus;
  const PayrollPayslipsTab({
    super.key,
    required this.runId,
    required this.runStatus,
  });

  @override
  ConsumerState<PayrollPayslipsTab> createState() => _PayrollPayslipsTabState();
}

class _PayrollPayslipsTabState extends ConsumerState<PayrollPayslipsTab> {
  String _search = '';

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
        final filtered = _search.isEmpty
            ? rows
            : rows.where((r) {
                final emp = r['employees'] as Map<String, dynamic>?;
                final name = _fullName(emp).toLowerCase();
                final num = (emp?['employee_number'] as String?)?.toLowerCase() ??
                    '';
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
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search employees...',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => setState(() => _search = v),
                    ),
                  ),
                  _Header(showLark: widget.runStatus == 'RELEASED'),
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
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
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

  static String _fullName(Map<String, dynamic>? emp) {
    if (emp == null) return '';
    return [emp['first_name'], emp['middle_name'], emp['last_name']]
        .where((s) => s != null && (s as String).isNotEmpty)
        .join(' ');
  }
}

class _Header extends StatelessWidget {
  final bool showLark;
  const _Header({required this.showLark});

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
            child:
                Align(alignment: Alignment.centerRight, child: Text('GROSS PAY', style: style)),
          ),
          Expanded(
            flex: 2,
            child:
                Align(alignment: Alignment.centerRight, child: Text('DEDUCTIONS', style: style)),
          ),
          Expanded(
            flex: 2,
            child: Align(alignment: Alignment.centerRight, child: Text('NET PAY', style: style)),
          ),
          if (showLark)
            Expanded(
              flex: 2,
              child:
                  Align(alignment: Alignment.center, child: Text('LARK STATUS', style: style)),
            ),
          Expanded(
            flex: 1,
            child: Align(alignment: Alignment.centerRight, child: Text('ACTIONS', style: style)),
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
  const _PayslipRow({
    required this.runId,
    required this.row,
    required this.showLark,
  });

  @override
  Widget build(BuildContext context) {
    final emp = row['employees'] as Map<String, dynamic>?;
    final directDept =
        (emp?['departments'] as Map<String, dynamic>?)?['name'] as String?;
    final scorecardDept = ((emp?['role_scorecards'] as Map<String, dynamic>?)
            ?['departments'] as Map<String, dynamic>?)?['name'] as String?;
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
              child: Text(
                dept ?? '—',
                style: const TextStyle(fontSize: 13),
              ),
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
              flex: 1,
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => context.push(
                      '/payroll/$runId/payslip/${row['id'] as String}'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF2563EB),
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(40, 24),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('View'),
                ),
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
      'APPROVED' => ('Acknowledged', const Color(0xFFDCFCE7), const Color(0xFF166534)),
      'PENDING' => ('Pending', const Color(0xFFFEF3C7), const Color(0xFF92400E)),
      'REJECTED' => ('Rejected', const Color(0xFFFEE2E2), const Color(0xFF991B1B)),
      'CANCELED' => ('Recalled', const Color(0xFFF3F4F6), const Color(0xFF4B5563)),
      'DELETED' => ('Deleted', const Color(0xFFF3F4F6), const Color(0xFF4B5563)),
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
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}
