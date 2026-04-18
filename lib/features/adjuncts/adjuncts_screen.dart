import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/breakpoints.dart';
import '../../app/shell.dart';
import '../../core/money.dart';
import '../auth/profile_provider.dart';

/// Combined screen for Penalties, Cash Advances, Reimbursements — three tabs.
class AdjunctsScreen extends ConsumerWidget {
  const AdjunctsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        drawer: isMobile(context) ? const AppDrawer() : null,
        appBar: AppBar(
          title: const Text('Payroll Adjuncts'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Penalties'),
            Tab(text: 'Cash Advances'),
            Tab(text: 'Reimbursements'),
          ]),
        ),
        body: const TabBarView(children: [
          _List(table: 'penalties', amountKey: 'total_amount', statusKey: 'status'),
          _List(table: 'cash_advances', amountKey: 'amount', statusKey: 'status'),
          _List(table: 'reimbursements', amountKey: 'amount', statusKey: 'status'),
        ]),
      ),
    );
  }
}

final _listProvider =
    FutureProvider.family<List<Map<String, dynamic>>, _ListKey>((ref, k) async {
  final profile = ref.watch(userProfileProvider).asData?.value;
  final employeeId = (profile?.isHrOrAdmin ?? false) ? null : profile?.employeeId;
  var q = Supabase.instance.client.from(k.table).select();
  if (employeeId != null) q = q.eq('employee_id', employeeId);
  final rows = await q.order('created_at', ascending: false).limit(200) as List<dynamic>;
  return rows.cast<Map<String, dynamic>>();
});

class _ListKey {
  final String table;
  const _ListKey(this.table);
  @override
  bool operator ==(Object o) => o is _ListKey && o.table == table;
  @override
  int get hashCode => table.hashCode;
}

class _List extends ConsumerWidget {
  final String table;
  final String amountKey;
  final String statusKey;
  const _List({required this.table, required this.amountKey, required this.statusKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_listProvider(_ListKey(table)));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
      data: (rows) => rows.isEmpty
          ? const Center(child: Text('Nothing here yet.'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              itemBuilder: (c, i) {
                final r = rows[i];
                final amount = r[amountKey] == null
                    ? '—'
                    : Money.fmtPhp(Decimal.parse(r[amountKey].toString()));
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(_title(r)),
                    subtitle: Text(_subtitle(r)),
                    trailing: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(amount, style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Chip(
                          label: Text(r[statusKey] as String? ?? '—'),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  String _title(Map<String, dynamic> r) {
    if (table == 'penalties') {
      return r['custom_description'] as String? ?? 'Penalty';
    }
    return r['reason'] as String? ?? (r['reimbursement_type'] as String? ?? table.toUpperCase());
  }

  String _subtitle(Map<String, dynamic> r) {
    final created = DateTime.parse(r['created_at'] as String).toLocal();
    return created.toString().substring(0, 16);
  }
}

