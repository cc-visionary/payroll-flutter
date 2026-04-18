import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/profile_provider.dart';
import '../../data/repositories/company_settings_repository.dart';
import '../../widgets/syncing_dialog.dart';
import '../../widgets/responsive_table.dart';
import '../../app/status_colors.dart';
import '../leave/leave_format.dart';
import 'lark_repository.dart';

class LarkSettingsScreen extends ConsumerStatefulWidget {
  const LarkSettingsScreen({super.key});
  @override
  ConsumerState<LarkSettingsScreen> createState() => _State();
}

class _State extends ConsumerState<LarkSettingsScreen> {
  bool? _connOk;
  String? _connDetail;
  bool _pinging = false;
  // Default range: Jan 1 of the current year → today. Lark rejects future
  // dates on most endpoints (1220001), so the end defaults to today, not
  // year-end. Users can still pick a future `to` via the date picker if
  // they really want (edge functions clamp to today before calling Lark).
  DateTime _from = DateTime(DateTime.now().year, 1, 1);
  DateTime _to = DateTime.now();
  RealtimeChannel? _benefitChannel;

  @override
  void initState() {
    super.initState();
    // Live-refresh benefit tables when rows are inserted/updated server-side
    _benefitChannel = Supabase.instance.client
        .channel('lark-benefits')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'cash_advances',
          callback: (_) => ref.invalidate(_benefitTableProvider),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'reimbursements',
          callback: (_) => ref.invalidate(_benefitTableProvider),
        )
        .subscribe();
  }

  @override
  void dispose() {
    _benefitChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _ping() async {
    setState(() => _pinging = true);
    try {
      final r = await ref.read(larkRepositoryProvider).ping();
      setState(() { _connOk = r.ok; _connDetail = r.detail; });
    } finally {
      if (mounted) setState(() => _pinging = false);
    }
  }

  Future<void> _run(Future<LarkSyncResult> Function() fn, String label) async {
    try {
      final res = await runWithSyncingDialog(context, label, fn);
      if (!mounted) return;
      final note = res.note ?? '${res.created} created, ${res.updated} updated${res.errors.isNotEmpty ? " — ${res.errors.length} error(s)" : ""}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label: $note')));
      ref.invalidate(syncHistoryProvider);
      ref.invalidate(_attendanceProvider);
      ref.invalidate(_leavesProvider);
      ref.invalidate(_otProvider);
      ref.invalidate(_benefitTableProvider);
      ref.invalidate(_employeeLinkStatsProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).asData?.value;
    if (profile == null) return const Center(child: CircularProgressIndicator());
    final repo = ref.read(larkRepositoryProvider);
    final cid = profile.companyId;

    final flags = ref.watch(attendanceSourceFlagsProvider).asData?.value ??
        const AttendanceSourceFlags(manualCsvEnabled: true, larkEnabled: true);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Integrations', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        const Text('Enable the integrations you need — both can be on.', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 16),

        _AttendanceSourceCard(flags: flags),
        const SizedBox(height: 16),

        // Everything below this point is Lark-specific. Gate on the Lark
        // toggle so admins who only use Manual CSV don't see sync UI that
        // would fail or confuse them.
        if (flags.larkEnabled) ...[
          _card('Connection Status', [
            Row(children: [
              FilledButton(onPressed: _pinging ? null : _ping, child: _pinging ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Test Connection')),
              const SizedBox(width: 12),
              if (_connOk != null)
                Expanded(child: Row(children: [
                  Icon(_connOk! ? Icons.check_circle : Icons.error, color: _connOk! ? Colors.green : Colors.red, size: 18),
                  const SizedBox(width: 6),
                  Expanded(child: Text(_connOk!
                      ? 'Connected${_connDetail != null ? " (token: $_connDetail)" : ""}'
                      : 'Unable to connect: ${_connDetail ?? "unknown"}',
                      overflow: TextOverflow.ellipsis, maxLines: 2)),
                ])),
            ]),
            const SizedBox(height: 4),
            const Text('Credentials are configured via Edge Function secrets (LARK_APP_ID, LARK_APP_SECRET)', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ]),
          const SizedBox(height: 16),

          _EmployeeLinkCard(companyId: cid, onSync: () => _run(() => repo.syncEmployees(cid), 'Employees')),
          const SizedBox(height: 16),

          _rangeCard(),
          const SizedBox(height: 16),

          _SyncCard(
            title: 'Synced Attendance',
            subtitle: 'Last 50 Lark-imported attendance records',
            onSync: () => _run(() => repo.syncAttendance(cid, from: _from, to: _to), 'Attendance'),
            child: const _AttendanceTable(),
          ),
          const SizedBox(height: 16),

          _SyncCard(
            title: 'Synced Leaves',
            subtitle: 'Last 20 Lark-synced leave requests',
            onSync: () => _run(() => repo.syncLeaves(cid, from: _from, to: _to), 'Leaves'),
            child: const _LeavesTable(),
          ),
          const SizedBox(height: 16),

          _SyncCard(
            title: 'Synced Approved OT',
            subtitle: 'Last 15 Lark-synced OT approvals',
            onSync: () => _run(() => repo.syncOvertime(cid, from: _from, to: _to), 'OT'),
            child: const _OtTable(),
          ),
          const SizedBox(height: 16),

          _SyncCard(
            title: 'Synced Cash Advances',
            subtitle: 'Last 10 Lark-synced cash-advance approvals',
            onSync: () => _run(() => repo.syncCashAdvances(cid, from: _from, to: _to), 'Cash advances'),
            child: const _BenefitTable(table: 'cash_advances'),
          ),
          const SizedBox(height: 16),

          _SyncCard(
            title: 'Synced Reimbursements',
            subtitle: 'Last 10 Lark-synced reimbursement approvals',
            onSync: () => _run(() => repo.syncReimbursements(cid, from: _from, to: _to), 'Reimbursements'),
            child: const _BenefitTable(table: 'reimbursements'),
          ),
          const SizedBox(height: 16),

          const _SyncHistoryCard(),
        ],
      ]),
    );
  }

  Widget _card(String title, List<Widget> children) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            ...children,
          ]),
        ),
      );

  Widget _rangeCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Sync range:', style: TextStyle(fontWeight: FontWeight.w600)),
              _dateBtn('From', _from, (d) => setState(() => _from = d)),
              _dateBtn('To', _to, (d) => setState(() => _to = d)),
              const Text('Applied to attendance / leaves / OT / cash-advances / reimbursements',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ),
      );

  Widget _dateBtn(String label, DateTime d, void Function(DateTime) set) => OutlinedButton.icon(
        icon: const Icon(Icons.calendar_today, size: 16),
        label: Text('$label: ${d.toIso8601String().substring(0, 10)}'),
        onPressed: () async {
          final p = await showDatePicker(
            context: context,
            initialDate: d,
            firstDate: DateTime(2020),
            lastDate: DateTime(2100),
          );
          if (p != null) set(p);
        },
      );
}

// -----------------------------------------------------------------------------

class _SyncCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onSync;
  final Widget child;
  const _SyncCard({
    required this.title,
    required this.subtitle,
    required this.onSync,
    required this.child,
  });
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ])),
              FilledButton.icon(onPressed: onSync, icon: const Icon(Icons.sync, size: 16), label: const Text('Sync from Lark')),
            ]),
            const SizedBox(height: 12),
            child,
          ]),
        ),
      );
}

// Employees linked card ------------------------------------------------------

final _employeeLinkStatsProvider = FutureProvider<({int linked, int total, List<Map<String, dynamic>> rows})>((ref) async {
  final rows = await Supabase.instance.client
      .from('employees')
      .select('id, employee_number, first_name, last_name, lark_user_id')
      .isFilter('deleted_at', null)
      .order('employee_number');
  final list = rows.cast<Map<String, dynamic>>().toList();
  final linked = list.where((r) => r['lark_user_id'] != null).length;
  return (linked: linked, total: list.length, rows: list);
});

class _EmployeeLinkCard extends ConsumerWidget {
  final String companyId;
  final VoidCallback onSync;
  const _EmployeeLinkCard({required this.companyId, required this.onSync});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_employeeLinkStatsProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Employee Lark User IDs', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              async.when(
                loading: () => const Text('Loading…', style: TextStyle(color: Colors.grey, fontSize: 12)),
                error: (_, __) => const SizedBox.shrink(),
                data: (s) => Text('${s.linked} of ${s.total} employees linked', style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ),
            ])),
            FilledButton.icon(
              onPressed: () { onSync(); ref.invalidate(_employeeLinkStatsProvider); },
              icon: const Icon(Icons.sync, size: 16),
              label: const Text('Sync All from Lark'),
            ),
          ]),
          const SizedBox(height: 4),
          const Text('Matches each employee\'s Employee Number with Lark\'s employee_no field to link Lark User IDs. Used for payslip approval routing.',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 12),
          async.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => Text('Error: $e', style: const TextStyle(color: Colors.red)),
            data: (s) => ResponsiveTable(
          fullWidth: true,
              child: DataTable(
                columnSpacing: 24,
                columns: const [
                  DataColumn(label: Text('Employee No')),
                  DataColumn(label: Text('Name')),
                  DataColumn(label: Text('Lark User ID')),
                  DataColumn(label: Text('Status')),
                ],
                rows: s.rows.map((r) => DataRow(cells: [
                  DataCell(Text(r['employee_number'] as String, style: const TextStyle(fontFamily: 'monospace'))),
                  DataCell(Text('${r['first_name']} ${r['last_name']}')),
                  DataCell(Text((r['lark_user_id'] as String?) ?? '—', style: const TextStyle(fontFamily: 'monospace'))),
                  DataCell(r['lark_user_id'] != null
                      ? const StatusChip(label: 'Linked', tone: StatusTone.success)
                      : const Chip(label: Text('—'), visualDensity: VisualDensity.compact)),
                ])).toList(),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// Sync history ---------------------------------------------------------------

class _SyncHistoryCard extends ConsumerWidget {
  const _SyncHistoryCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(syncHistoryProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Sync History', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
            IconButton(onPressed: () => ref.invalidate(syncHistoryProvider), icon: const Icon(Icons.refresh, size: 18)),
          ]),
          const SizedBox(height: 12),
          async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e', style: const TextStyle(color: Colors.red)),
            data: (rows) => rows.isEmpty ? const Text('No syncs yet.') : ResponsiveTable(
          fullWidth: true,
              child: DataTable(
                columnSpacing: 24,
                columns: const [
                  DataColumn(label: Text('Type')),
                  DataColumn(label: Text('Date Range')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Total')),
                  DataColumn(label: Text('Created')),
                  DataColumn(label: Text('Updated')),
                  DataColumn(label: Text('Errors')),
                  DataColumn(label: Text('When')),
                ],
                rows: rows.map((r) {
                  final hasErrors = r.errorDetails.isNotEmpty;
                  void show() => _showSyncErrors(context, r);
                  return DataRow(
                    cells: [
                      DataCell(Text(r.syncType, style: const TextStyle(fontFamily: 'monospace'))),
                      DataCell(Text(r.dateFrom != null ? '${r.dateFrom} to ${r.dateTo}' : '—')),
                      DataCell(_statusChip(r.status)),
                      DataCell(Text('${r.total}')),
                      DataCell(Text('${r.created}', style: TextStyle(color: r.created > 0 ? Colors.green : null))),
                      DataCell(Text('${r.updated}', style: TextStyle(color: r.updated > 0 ? Colors.orange : null))),
                      DataCell(
                        hasErrors
                            ? InkWell(
                                onTap: show,
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Text('${r.errors}', style: const TextStyle(color: Colors.red, decoration: TextDecoration.underline)),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.info_outline, size: 14, color: Colors.red),
                                ]),
                              )
                            : Text(r.errors > 0 ? '${r.errors}' : '—', style: TextStyle(color: r.errors > 0 ? Colors.red : null)),
                      ),
                      DataCell(Text(DateFormat('M/d/yy, h:mm a').format(r.startedAt.toLocal()))),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

void _showSyncErrors(BuildContext context, SyncLogRow r) {
  showDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (dialogCtx) => AlertDialog(
      title: Text('${r.syncType} sync errors (${r.errorDetails.length})'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: r.errorDetails.isEmpty
            ? const Text('No detail recorded.')
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final e in r.errorDetails)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: SelectableText('• $e', style: const TextStyle(fontSize: 13)),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          // Pop the dialog itself, not whatever GoRouter route is below it.
          onPressed: () => Navigator.of(dialogCtx, rootNavigator: true).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

Widget _statusChip(String s) {
  final tone = switch (s) {
    'COMPLETED' => StatusTone.success,
    'PARTIAL' => StatusTone.warning,
    'FAILED' => StatusTone.danger,
    _ => StatusTone.neutral,
  };
  return StatusChip(label: s, tone: tone);
}

/// Cash-advance / reimbursement status. Local PENDING means "approved by Lark,
/// awaiting payroll deduction/payout" — show APPROVED so Lark's truth surfaces.
/// Once it moves to DEDUCTED/PAID/CANCELLED, that's the local lifecycle and wins.
Widget _benefitStatusChip({required String localStatus, required String? larkStatus}) {
  String label = localStatus;
  StatusTone tone;
  if (localStatus == 'PENDING' && larkStatus == 'APPROVED') {
    label = 'APPROVED';
    tone = StatusTone.success;
  } else {
    tone = toneForStatusString(localStatus);
  }
  return StatusChip(label: label, tone: tone);
}

// Attendance / Leaves / OT / benefit tables ---------------------------------

final _attendanceProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final rows = await Supabase.instance.client
      .from('attendance_day_records')
      .select('id, attendance_date, actual_time_in, actual_time_out, attendance_status, employees!inner(employee_number, first_name, last_name)')
      .eq('source_type', 'LARK_IMPORT')
      .order('attendance_date', ascending: false)
      .limit(50);
  return rows.cast<Map<String, dynamic>>().toList();
});

class _AttendanceTable extends ConsumerWidget {
  const _AttendanceTable();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_attendanceProvider);
    return async.when(
      loading: () => const SizedBox(height: 60, child: Center(child: CircularProgressIndicator())),
      error: (e, _) => Text('Error: $e', style: const TextStyle(color: Colors.red)),
      data: (rows) => rows.isEmpty ? const Text('No attendance yet.') : ResponsiveTable(
          fullWidth: true,
        child: DataTable(
          columnSpacing: 24,
          columns: const [
            DataColumn(label: Text('Employee')),
            DataColumn(label: Text('Date')),
            DataColumn(label: Text('Time In')),
            DataColumn(label: Text('Time Out')),
            DataColumn(label: Text('Status')),
          ],
          rows: rows.map((r) {
            final emp = r['employees'] as Map<String, dynamic>? ?? const {};
            final status = '${r['attendance_status']}';
            return DataRow(cells: [
              DataCell(Text('${emp['employee_number']} ${emp['first_name']} ${emp['last_name']}', style: const TextStyle(fontSize: 12))),
              DataCell(Text((r['attendance_date'] as String).substring(0, 10))),
              DataCell(Text(_time(r['actual_time_in']))),
              DataCell(Text(_time(r['actual_time_out']))),
              DataCell(StatusChip(label: status, tone: toneForStatusString(status))),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}

String _time(Object? iso) {
  if (iso == null) return '—';
  try {
    return DateFormat('hh:mm a').format(DateTime.parse(iso as String).toLocal());
  } catch (_) { return '—'; }
}

final _leavesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final rows = await Supabase.instance.client
      .from('leave_requests')
      .select('id, start_date, end_date, leave_days, lark_leave_unit, lark_leave_duration, status, reason, employees!inner(employee_number, first_name, last_name), leave_types(name, code)')
      .order('start_date', ascending: false)
      .limit(20);
  return rows.cast<Map<String, dynamic>>().toList();
});

class _LeavesTable extends ConsumerWidget {
  const _LeavesTable();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_leavesProvider);
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => Text('Error: $e', style: const TextStyle(color: Colors.red)),
      data: (rows) => rows.isEmpty ? const Text('No leaves yet.') : ResponsiveTable(
          fullWidth: true,
        child: DataTable(
          columnSpacing: 24,
          columns: const [
            DataColumn(label: Text('Employee')),
            DataColumn(label: Text('Type')),
            DataColumn(label: Text('Range')),
            DataColumn(label: Text('Duration')),
            DataColumn(label: Text('Status')),
          ],
          rows: rows.map((r) {
            final emp = r['employees'] as Map<String, dynamic>? ?? const {};
            final lt = r['leave_types'] as Map<String, dynamic>? ?? const {};
            final status = '${r['status']}';
            final durationLabel = formatLeaveDurationUnit(
              larkUnit: r['lark_leave_unit'],
              larkDuration: r['lark_leave_duration'],
              leaveDays: r['leave_days'],
            );
            return DataRow(cells: [
              DataCell(Text('${emp['employee_number']} ${emp['first_name']}', style: const TextStyle(fontSize: 12))),
              DataCell(Text('${lt['name'] ?? '—'}')),
              DataCell(Text('${r['start_date']} → ${r['end_date']}')),
              DataCell(Text(durationLabel)),
              DataCell(StatusChip(label: status, tone: toneForStatusString(status))),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}

final _otProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final rows = await Supabase.instance.client
      .from('attendance_day_records')
      .select('id, attendance_date, actual_time_in, actual_time_out, approved_ot_minutes, early_in_approved, late_out_approved, employees!inner(employee_number, first_name, last_name)')
      .gt('approved_ot_minutes', 0)
      .order('attendance_date', ascending: false)
      .limit(15);
  return rows.cast<Map<String, dynamic>>().toList();
});

class _OtTable extends ConsumerWidget {
  const _OtTable();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_otProvider);
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => Text('Error: $e', style: const TextStyle(color: Colors.red)),
      data: (rows) => rows.isEmpty ? const Text('No OT yet.') : ResponsiveTable(
          fullWidth: true,
        child: DataTable(
          columnSpacing: 24,
          columns: const [
            DataColumn(label: Text('Employee')),
            DataColumn(label: Text('Date')),
            DataColumn(label: Text('OT Min')),
            DataColumn(label: Text('Flags')),
          ],
          rows: rows.map((r) {
            final emp = r['employees'] as Map<String, dynamic>? ?? const {};
            return DataRow(cells: [
              DataCell(Text('${emp['employee_number']} ${emp['first_name']}', style: const TextStyle(fontSize: 12))),
              DataCell(Text((r['attendance_date'] as String).substring(0, 10))),
              DataCell(Text('${r['approved_ot_minutes'] ?? 0}')),
              DataCell(Row(children: [
                if (r['early_in_approved'] == true) const Chip(label: Text('Early In'), visualDensity: VisualDensity.compact),
                if (r['late_out_approved'] == true) const Chip(label: Text('Late Out'), visualDensity: VisualDensity.compact),
              ])),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}

final _benefitTableProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, table) async {
  final rows = await Supabase.instance.client
      .from(table)
      .select('id, amount, reason, status, lark_approval_status, synced_at, '
              'employees!inner(employee_number, first_name, last_name)'
              '${table == "reimbursements" ? ", reimbursement_type, transaction_date" : ""}')
      .not('lark_instance_code', 'is', null)
      .order('synced_at', ascending: false)
      .limit(10);
  return rows.cast<Map<String, dynamic>>().toList();
});

class _BenefitTable extends ConsumerWidget {
  final String table;
  const _BenefitTable({required this.table});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_benefitTableProvider(table));
    final isReim = table == 'reimbursements';
    return async.when(
      loading: () => const SizedBox(height: 40, child: Center(child: CircularProgressIndicator())),
      error: (e, _) => Text('Error: $e', style: const TextStyle(color: Colors.red)),
      data: (rows) {
        if (rows.isEmpty) return Text('No $table yet.');
        return ResponsiveTable(
          fullWidth: true,
          child: DataTable(
            columnSpacing: 24,
            columns: [
              const DataColumn(label: Text('Employee')),
              const DataColumn(label: Text('Amount')),
              if (isReim) const DataColumn(label: Text('Type')),
              const DataColumn(label: Text('Reason')),
              if (isReim) const DataColumn(label: Text('Date')),
              const DataColumn(label: Text('Status')),
            ],
            rows: rows.map((r) {
              final emp = r['employees'] as Map<String, dynamic>? ?? const {};
              return DataRow(cells: [
                DataCell(Text('${emp['employee_number']} ${emp['first_name']}', style: const TextStyle(fontSize: 12))),
                DataCell(Text('₱${r['amount']}')),
                if (isReim) DataCell(Text('${r['reimbursement_type'] ?? '—'}')),
                DataCell(SizedBox(width: 200, child: Text('${r['reason'] ?? '—'}', overflow: TextOverflow.ellipsis))),
                if (isReim) DataCell(Text('${r['transaction_date'] ?? '—'}')),
                DataCell(_benefitStatusChip(
                  localStatus: '${r['status']}',
                  larkStatus: r['lark_approval_status'] as String?,
                )),
              ]);
            }).toList(),
          ),
        );
      },
    );
  }
}

class _AttendanceSourceCard extends ConsumerStatefulWidget {
  final AttendanceSourceFlags flags;
  const _AttendanceSourceCard({required this.flags});
  @override
  ConsumerState<_AttendanceSourceCard> createState() =>
      _AttendanceSourceCardState();
}

class _AttendanceSourceCardState
    extends ConsumerState<_AttendanceSourceCard> {
  bool _saving = false;

  Future<void> _set(AttendanceSourceFlags next) async {
    if (_saving) return;
    // At least one must stay on — otherwise Attendance has no data path.
    if (!next.manualCsvEnabled && !next.larkEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('At least one attendance source must be enabled.')));
      return;
    }
    final profile = ref.read(userProfileProvider).asData?.value;
    if (profile == null) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(companySettingsRepositoryProvider)
          .setAttendanceSourceFlags(profile.companyId, next);
      ref.invalidate(attendanceSourceFlagsProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update integrations: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.flags;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text('Attendance Source',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              if (_saving) ...[
                const SizedBox(width: 12),
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ]),
            const SizedBox(height: 4),
            const Text(
              'Enable one or both. Manual Import unlocks the "Import CSV" '
              'button on the Attendance screen; Lark unlocks all Lark sync '
              'cards below.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: f.larkEnabled,
              onChanged: _saving
                  ? null
                  : (v) => _set(f.copyWith(larkEnabled: v ?? false)),
              title: const Text('Lark'),
              subtitle: const Text(
                  'Pull attendance, leaves, OT, cash advances, and reimbursements from Lark. Shows the Lark sync cards below.'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: f.manualCsvEnabled,
              onChanged: _saving
                  ? null
                  : (v) => _set(f.copyWith(manualCsvEnabled: v ?? false)),
              title: const Text('Manual Import'),
              subtitle: const Text(
                  'Allow CSV uploads from the Attendance screen for any day.'),
            ),
          ],
        ),
      ),
    );
  }
}
