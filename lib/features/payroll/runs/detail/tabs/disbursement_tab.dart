import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/money.dart';
import '../../../../../data/repositories/payroll_repository.dart';
import '../../../constants.dart';
import '../disbursement_export.dart';
import '../providers.dart';

class PayrollDisbursementTab extends ConsumerStatefulWidget {
  final String runId;
  final String runStatus;
  const PayrollDisbursementTab({
    super.key,
    required this.runId,
    required this.runStatus,
  });

  @override
  ConsumerState<PayrollDisbursementTab> createState() =>
      _PayrollDisbursementTabState();

  // Static helpers kept on the widget class so existing call sites in
  // _GroupCard / _GroupRow (outside the state class) keep working.
  static Decimal dec(Object? v) => _decFn(v);
  static String fullName(Map<String, dynamic>? emp) => _fullNameFn(emp);
}

class _PayrollDisbursementTabState
    extends ConsumerState<PayrollDisbursementTab> {
  // Guard against re-running auto-assign on every rebuild / provider refresh.
  bool _didAutoAssign = false;
  bool _autoAssignInFlight = false;

  String get runId => widget.runId;
  String get runStatus => widget.runStatus;

  /// Walk the payslip rows once per mount. For any row with no
  /// `payment_source_account`, pick a best-fit source using
  /// [resolveAutoPaymentSource] (company → bank → CASH fallback) and persist
  /// it. Only runs while the run is in REVIEW — released/approved rows stay
  /// frozen. Updates happen in parallel; we invalidate the provider once when
  /// done so the UI reflects the new assignments.
  Future<void> _autoAssignIfNeeded(List<Map<String, dynamic>> rows) async {
    if (_didAutoAssign || _autoAssignInFlight) return;
    if (runStatus != 'REVIEW') {
      _didAutoAssign = true;
      return;
    }
    final pending = rows.where((r) {
      final src = r['payment_source_account'] as String?;
      return src == null || src.isEmpty;
    }).toList();
    if (pending.isEmpty) {
      _didAutoAssign = true;
      return;
    }
    _autoAssignInFlight = true;
    final repo = ref.read(payrollRepositoryProvider);
    final writes = <Future<void>>[];
    for (final r in pending) {
      final payslipId = r['id'] as String?;
      if (payslipId == null) continue;
      final emp = r['employees'] as Map<String, dynamic>?;
      final entity = emp?['hiring_entities'] as Map<String, dynamic>?;
      final entityCode = entity?['code'] as String?;
      final bankCodes = _employeeBankCodes(emp);
      final picked = resolveAutoPaymentSource(
        hiringEntityCode: entityCode,
        employeeBankCodes: bankCodes,
      );
      if (picked == null) continue;
      writes.add(repo.updatePayslipDisbursement(
        payslipId,
        sourceAccount: picked,
      ));
    }
    if (writes.isEmpty) {
      _didAutoAssign = true;
      _autoAssignInFlight = false;
      return;
    }
    try {
      await Future.wait(writes);
    } catch (_) {
      // Swallow individual failures — the "No Source" group will still show
      // anything we couldn't assign, and the user can pick manually.
    }
    if (!mounted) return;
    _didAutoAssign = true;
    _autoAssignInFlight = false;
    ref.invalidate(payslipListForRunProvider(runId));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(payslipListForRunProvider(runId));
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
        // Fire-and-forget — the helper guards itself against re-running.
        if (!_didAutoAssign) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _autoAssignIfNeeded(rows);
          });
        }
        final groups = _groupBySource(rows);
        final totalNet = rows.fold<Decimal>(
          Decimal.zero,
          (s, r) => s + _dec(r['net_pay']),
        );
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            _HeaderCard(
              groupCount: groups.length,
              employeeCount: rows.length,
              totalNet: totalNet,
              onExportAll: () => _exportAll(context, groups),
            ),
            const SizedBox(height: 12),
            for (final g in groups) ...[
              _GroupCard(
                runId: runId,
                runStatus: runStatus,
                group: g,
              ),
              const SizedBox(height: 12),
            ],
            if (groups.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'No payslips computed yet',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  List<_Group> _groupBySource(List<Map<String, dynamic>> rows) {
    final map = <String, _Group>{};
    for (final r in rows) {
      final source = r['payment_source_account'] as String?;
      final key = source ?? '__none__';
      final label = paymentSourceLabel(source);
      final group = map.putIfAbsent(
        key,
        () => _Group(key: key, label: label, items: [], total: Decimal.zero),
      );
      group.items.add(r);
      group.total += _dec(r['net_pay']);
    }
    final out = map.values.toList();
    out.sort((a, b) => a.label.compareTo(b.label));
    return out;
  }

  Future<void> _exportAll(BuildContext context, List<_Group> groups) async {
    if (groups.isEmpty) return;
    // Period dates come from the run detail provider; the Summary tab already
    // watches this, so it's in cache by the time the user hits Export All.
    final detail =
        ref.read(payrollRunDetailProvider(runId)).asData?.value;
    final exports = groups
        .map((g) => DisbursementGroupExport(
              sourceAccountName: exportSourceAccountName(
                g.key == '__none__' ? null : g.key,
              ),
              items: g.items.map(_toExportRow).toList(),
            ))
        .toList();
    try {
      final path = await exportDisbursementAllXlsx(
        groups: exports,
        periodStart: detail?.payPeriodStart,
        periodEnd: detail?.payPeriodEnd,
      );
      if (!context.mounted) return;
      if (path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved: $path')),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }

  DisbursementExportRow _toExportRow(Map<String, dynamic> r) {
    final source = r['payment_source_account'] as String?;
    return DisbursementExportRow.fromPayslipRow(
      r,
      source: source,
      resolveAccount: _resolveAccount,
    );
  }

  // Local shorthand for the file-level helper so existing in-class calls
  // (`_dec(...)`) keep compiling after the move to ConsumerStatefulWidget.
  Decimal _dec(Object? v) => _decFn(v);
}

Decimal _decFn(Object? v) => Decimal.parse((v ?? '0').toString());

String _fullNameFn(Map<String, dynamic>? emp) {
  if (emp == null) return '';
  return [emp['first_name'], emp['middle_name'], emp['last_name']]
      .where((s) => s != null && (s as String).isNotEmpty)
      .join(' ');
}

/// Pull the distinct bank_codes off the employee's registered bank accounts.
/// Used to filter the source dropdown so the disbursement only lists sources
/// where the employee actually holds an account at that bank.
Set<String> _employeeBankCodes(Map<String, dynamic>? emp) {
  final accts = (emp?['employee_bank_accounts'] as List<dynamic>?) ?? const [];
  final codes = <String>{};
  for (final a in accts.cast<Map<String, dynamic>>()) {
    final deletedAt = a['deleted_at'];
    if (deletedAt != null) continue;
    final code = a['bank_code'] as String?;
    if (code != null && code.isNotEmpty) codes.add(code);
  }
  return codes;
}

(String?, String?) _resolveAccount(
    Map<String, dynamic> row, String? source) {
  if (source == null || source == 'CASH') return (null, null);
  final bank = paymentSourceBankCode(source);
  if (bank == null) return (null, null);
  final emp = row['employees'] as Map<String, dynamic>?;
  final accts = (emp?['employee_bank_accounts'] as List<dynamic>?) ?? const [];
  // Prefer the employee's primary account at the matching bank; fall back to
  // any non-deleted account at that bank. Deleted accounts are ignored.
  Map<String, dynamic>? primary;
  Map<String, dynamic>? any;
  for (final a in accts.cast<Map<String, dynamic>>()) {
    if (a['deleted_at'] != null) continue;
    if ((a['bank_code'] as String?) != bank) continue;
    any ??= a;
    if (a['is_primary'] == true) {
      primary = a;
      break;
    }
  }
  final match = primary ?? any;
  if (match == null) return (null, null);
  return (
    match['account_number'] as String?,
    match['account_name'] as String?,
  );
}

class _Group {
  final String key;
  final String label;
  final List<Map<String, dynamic>> items;
  Decimal total;
  _Group({
    required this.key,
    required this.label,
    required this.items,
    required this.total,
  });
}

class _HeaderCard extends StatelessWidget {
  final int groupCount;
  final int employeeCount;
  final Decimal totalNet;
  final VoidCallback onExportAll;
  const _HeaderCard({
    required this.groupCount,
    required this.employeeCount,
    required this.totalNet,
    required this.onExportAll,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Disbursement List',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$groupCount group${groupCount == 1 ? '' : 's'} · '
                  '$employeeCount employee${employeeCount == 1 ? '' : 's'} · '
                  '${Money.fmtPhp(totalNet)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (employeeCount > 0)
            OutlinedButton.icon(
              onPressed: onExportAll,
              icon: const Icon(Icons.download_outlined, size: 16),
              label: const Text('Export All'),
            ),
        ],
      ),
    );
  }
}

class _GroupCard extends ConsumerWidget {
  final String runId;
  final String runStatus;
  final _Group group;
  const _GroupCard({
    required this.runId,
    required this.runStatus,
    required this.group,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isNoSource = group.key == '__none__';
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isNoSource ? 'No Source Account' : group.label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isNoSource ? const Color(0xFFDC2626) : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${group.items.length} employee${group.items.length == 1 ? '' : 's'} · ${Money.fmtPhp(group.total)}',
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _copy(context),
                  icon: const Icon(Icons.copy_outlined, size: 14),
                  label: const Text('Copy'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _exportGroup(context, ref),
                  icon: const Icon(Icons.download_outlined, size: 14),
                  label: const Text('Export'),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor),
          _GroupHeader(),
          Divider(height: 1, color: Theme.of(context).dividerColor),
          for (final r in group.items) ...[
            _GroupRow(
              runId: runId,
              runStatus: runStatus,
              row: r,
              onSourceChanged: (newSource) async {
                // Legacy-constant dropdown still in use during the FK
                // transition: write both the legacy string AND the new uuid
                // (null for now — resolved once the dropdown pulls from the
                // hiring_entity_bank_accounts table).
                await ref
                    .read(payrollRepositoryProvider)
                    .updatePayslipDisbursement(
                      r['id'] as String,
                      sourceAccount: newSource,
                      paySourceAccountId: null,
                    );
                ref.invalidate(payslipListForRunProvider(runId));
              },
            ),
            Divider(height: 1, color: Theme.of(context).dividerColor),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Subtotal (${group.items.length})',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  group.total.toString(),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    final export = _toExport();
    final tsv = buildGroupTsv(export);
    await Clipboard.setData(ClipboardData(text: tsv));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copied group as TSV.')),
      );
    }
  }

  Future<void> _exportGroup(BuildContext context, WidgetRef ref) async {
    final export = _toExport();
    final detail = ref.read(payrollRunDetailProvider(runId)).asData?.value;
    try {
      final path = await exportDisbursementGroupXlsx(
        group: export,
        periodStart: detail?.payPeriodStart,
        periodEnd: detail?.payPeriodEnd,
      );
      if (!context.mounted) return;
      if (path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved: $path')),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }

  /// Convert the raw payslip rows inside this group into the typed export
  /// structure, reusing `_resolveAccount` so the exported account matches
  /// exactly what's rendered in the table.
  DisbursementGroupExport _toExport() {
    return DisbursementGroupExport(
      sourceAccountName: exportSourceAccountName(
        group.key == '__none__' ? null : group.key,
      ),
      items: group.items.map((r) {
        final source = r['payment_source_account'] as String?;
        return DisbursementExportRow.fromPayslipRow(
          r,
          source: source,
          resolveAccount: _resolveAccount,
        );
      }).toList(),
    );
  }
}

class _GroupHeader extends StatelessWidget {
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
          Expanded(flex: 3, child: Text('EMPLOYEE', style: style)),
          Expanded(flex: 3, child: Text('COMPANY', style: style)),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text('NET PAY', style: style),
            ),
          ),
          Expanded(flex: 3, child: Text('SOURCE ACCOUNT', style: style)),
          Expanded(flex: 3, child: Text('ACCOUNT NUMBER', style: style)),
          Expanded(flex: 3, child: Text('ACCOUNT NAME', style: style)),
        ],
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  final String runId;
  final String runStatus;
  final Map<String, dynamic> row;
  final ValueChanged<String> onSourceChanged;
  const _GroupRow({
    required this.runId,
    required this.runStatus,
    required this.row,
    required this.onSourceChanged,
  });

  @override
  Widget build(BuildContext context) {
    final emp = row['employees'] as Map<String, dynamic>?;
    final name = PayrollDisbursementTab.fullName(emp);
    final number = emp?['employee_number'] as String? ?? '—';
    final entity =
        (emp?['hiring_entities'] as Map<String, dynamic>?)?['name'] as String?;
    final net = PayrollDisbursementTab.dec(row['net_pay']);
    final source = row['payment_source_account'] as String?;
    final (acctNum, acctName) = _resolveAccount(row, source);
    final isCash = source == 'CASH';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
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
            child: Text(entity ?? '—', style: const TextStyle(fontSize: 13)),
          ),
          Expanded(
            flex: 2,
            child: Text(
              net.toStringAsFixed(3),
              textAlign: TextAlign.right,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
          Expanded(
            flex: 3,
            child: runStatus == 'REVIEW'
                ? _SourceDropdown(
                    value: source,
                    onChanged: onSourceChanged,
                    employeeBankCodes: _employeeBankCodes(emp),
                    hiringEntityCode: (emp?['hiring_entities']
                        as Map<String, dynamic>?)?['code'] as String?,
                  )
                : Text(
                    paymentSourceLabel(source),
                    style: const TextStyle(fontSize: 13),
                  ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              isCash ? '-' : (acctNum ?? '-'),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              isCash ? '-' : (acctName ?? '-'),
              style: const TextStyle(fontSize: 13),
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
}

class _SourceDropdown extends StatelessWidget {
  final String? value;
  final ValueChanged<String> onChanged;
  // Bank codes belonging to the employee's registered accounts. Only sources
  // whose `bankCode` matches one of these (or is null = CASH) are shown, so
  // HR can't accidentally route a payment to a bank the employee doesn't
  // have an account in. If empty, show everything (the payroll compute may
  // have run before the employee added any bank accounts).
  final Set<String> employeeBankCodes;
  // Employee's hiring entity code (e.g. LUXIUM, GAMECOVE). When set, the
  // dropdown hides sources tagged for a different entity so disbursement
  // can't route across companies.
  final String? hiringEntityCode;
  const _SourceDropdown({
    required this.value,
    required this.onChanged,
    required this.employeeBankCodes,
    required this.hiringEntityCode,
  });

  @override
  Widget build(BuildContext context) {
    final hasFilter = employeeBankCodes.isNotEmpty;
    // Company scope — shared sources (hiringEntityCode == null) always pass.
    Iterable<PaymentSource> scoped = paymentSourceAccounts.where((p) =>
        p.hiringEntityCode == null || p.hiringEntityCode == hiringEntityCode);
    final eligible = hasFilter
        ? scoped
            .where((p) => p.bankCode == null || employeeBankCodes.contains(p.bankCode))
            .toList()
        : scoped.toList();
    // Ensure the currently-selected value is always in the list, even if it
    // no longer matches the filter — so we don't flash a null value.
    final ensureCurrent = value != null &&
        !eligible.any((p) => p.value == value);
    return DropdownButton<String>(
      value: value,
      isDense: true,
      underline: const SizedBox.shrink(),
      hint: const Text('No source', style: TextStyle(fontSize: 13)),
      onChanged: (v) => v == null ? null : onChanged(v),
      items: [
        for (final p in eligible)
          DropdownMenuItem(
            value: p.value,
            child: Text(p.label, style: const TextStyle(fontSize: 13)),
          ),
        if (ensureCurrent)
          DropdownMenuItem(
            value: value,
            child: Text(
              '${paymentSourceLabel(value)} (no matching account)',
              style: const TextStyle(fontSize: 13, color: Colors.red),
            ),
          ),
      ],
    );
  }
}
