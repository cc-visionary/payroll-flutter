import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/money.dart';
import '../../../../../data/repositories/payroll_repository.dart';
import '../providers.dart';

/// Modal that lists every employee on a run with their current 13th-month
/// accrual basis and projected payout, lets HR tick rows, and dispatches
/// [PayrollRepository.distributeThirteenthMonth] on confirm.
///
/// Pops with `true` when at least one employee was paid out.
class Distribute13thDialog extends ConsumerStatefulWidget {
  final String runId;
  const Distribute13thDialog({super.key, required this.runId});

  @override
  ConsumerState<Distribute13thDialog> createState() =>
      _Distribute13thDialogState();
}

class _Distribute13thDialogState extends ConsumerState<Distribute13thDialog> {
  List<_Row>? _rows;
  String? _loadError;
  bool _saving = false;
  String? _saveError;
  final Set<String> _ticked = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(payrollRepositoryProvider);
      final raw = await repo.payslipListForRun(widget.runId);
      final employeeIds = <String>[];
      final empById = <String, Map<String, dynamic>>{};
      final payslipIdByEmp = <String, String>{};
      final alreadyByEmp = <String, bool>{};
      for (final r in raw) {
        final emp = r['employees'] as Map<String, dynamic>?;
        if (emp == null) continue;
        final empId = emp['id'] as String;
        employeeIds.add(empId);
        empById[empId] = emp;
        payslipIdByEmp[empId] = r['id'] as String;
        final lines = (r['payslip_lines'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>() ??
            const <Map<String, dynamic>>[];
        alreadyByEmp[empId] = lines.any(
            (l) => (l['category'] as String?) == 'THIRTEENTH_MONTH_PAY');
      }

      // Live compute: (Σ basic − Σ late) ÷ 12 per employee, scoped to
      // RELEASED payslips + this run since their last distribution.
      final live = await repo.thirteenthMonthPayoutsForRun(
        widget.runId,
        employeeIds,
      );

      final rows = <_Row>[];
      for (final empId in employeeIds) {
        final emp = empById[empId]!;
        final l = live[empId] ?? LiveThirteenthMonth.zero();
        rows.add(_Row(
          employeeId: empId,
          employeeNumber: (emp['employee_number'] as String?) ?? '—',
          name: _nameFor(emp),
          basis: l.netBasic,
          payout: l.payout,
          totalBasic: l.totalBasic,
          totalLate: l.totalLate,
          alreadyDistributed: alreadyByEmp[empId] ?? false,
          payslipId: payslipIdByEmp[empId] ?? '',
        ));
      }
      rows.sort((a, b) => a.employeeNumber.compareTo(b.employeeNumber));
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _ticked
          ..clear()
          ..addAll(rows.where((r) => r.eligible).map((r) => r.employeeId));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e.toString());
    }
  }

  static String _nameFor(Map<String, dynamic> emp) {
    final last = (emp['last_name'] as String?) ?? '';
    final first = (emp['first_name'] as String?) ?? '';
    return last.isEmpty ? first : '$last, $first';
  }

  Future<void> _confirm() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final repo = ref.read(payrollRepositoryProvider);
      final res = await repo.distributeThirteenthMonth(
        runId: widget.runId,
        employeeIds: _ticked.toList(),
      );
      if (!mounted) return;
      ref.invalidate(payrollRunDetailProvider(widget.runId));
      ref.invalidate(payslipListForRunProvider(widget.runId));
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger.showSnackBar(SnackBar(
        content: Text(
          'Distributed 13th month to ${res.employeesDistributed} '
          'employee${res.employeesDistributed == 1 ? "" : "s"}. '
          'Total ${Money.fmtPhp(res.totalPayout)}.'
          '${res.errors.isEmpty ? "" : " ${res.errors.length} skipped."}',
        ),
        duration: const Duration(seconds: 4),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final totalPayout = rows == null
        ? Decimal.zero
        : rows
            .where((r) => _ticked.contains(r.employeeId))
            .fold<Decimal>(Decimal.zero, (s, r) => s + r.payout);

    return AlertDialog(
      title: const Text('Distribute 13th Month'),
      content: SizedBox(
        width: 560,
        child: _loadError != null
            ? Text('Error: $_loadError',
                style: const TextStyle(color: Colors.red))
            : rows == null
                ? const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Adds a "13th Month Pay" line to each selected '
                        "employee's payslip on this run. Payout is "
                        'live-computed from released payslips plus this '
                        'run: (Σ Basic Pay − Σ Late/UT) ÷ 12, scoped '
                        "since the employee's last distribution.",
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Heads up: recomputing this run after distribution '
                        'will wipe the new line — finalize adjustments first.',
                        style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 360),
                        child: Scrollbar(
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: rows.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final r = rows[i];
                              final ticked = _ticked.contains(r.employeeId);
                              return CheckboxListTile(
                                dense: true,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                value: ticked,
                                onChanged: r.eligible
                                    ? (v) => setState(() {
                                          if (v == true) {
                                            _ticked.add(r.employeeId);
                                          } else {
                                            _ticked.remove(r.employeeId);
                                          }
                                        })
                                    : null,
                                title: Text(
                                  '${r.name}  ·  ${r.employeeNumber}',
                                  style: const TextStyle(fontSize: 13),
                                ),
                                subtitle: Text(
                                  r.alreadyDistributed
                                      ? 'Already distributed on this run'
                                      : r.basis <= Decimal.zero
                                          ? 'Not eligible — no net basic earned'
                                          : 'Basic ${Money.fmtPhp(r.totalBasic)} − Late ${Money.fmtPhp(r.totalLate)} = ${Money.fmtPhp(r.basis)} ÷ 12 → ${Money.fmtPhp(r.payout)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: r.eligible
                                        ? Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant
                                        : Theme.of(context).disabledColor,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            'Total to distribute: ',
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                          Text(
                            Money.fmtPhp(totalPayout),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'GeistMono',
                            ),
                          ),
                        ],
                      ),
                      if (_saveError != null) ...[
                        const SizedBox(height: 8),
                        Text(_saveError!,
                            style: const TextStyle(color: Colors.red)),
                      ],
                    ],
                  ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_saving || _ticked.isEmpty) ? null : _confirm,
          child: _saving
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('Distribute (${_ticked.length})'),
        ),
      ],
    );
  }
}

class _Row {
  final String employeeId;
  final String employeeNumber;
  final String name;
  final Decimal basis;
  final Decimal payout;
  final Decimal totalBasic;
  final Decimal totalLate;
  final bool alreadyDistributed;
  final String payslipId;
  _Row({
    required this.employeeId,
    required this.employeeNumber,
    required this.name,
    required this.basis,
    required this.payout,
    required this.totalBasic,
    required this.totalLate,
    required this.alreadyDistributed,
    required this.payslipId,
  });
  bool get eligible => !alreadyDistributed && basis > Decimal.zero;
}
