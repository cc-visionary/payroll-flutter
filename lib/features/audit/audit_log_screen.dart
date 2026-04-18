import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/breakpoints.dart';
import '../../app/shell.dart';

final _auditLogsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final rows = await Supabase.instance.client
      .from('audit_logs')
      .select()
      .order('created_at', ascending: false)
      .limit(500) as List<dynamic>;
  return rows.cast<Map<String, dynamic>>();
});

class AuditLogScreen extends ConsumerWidget {
  const AuditLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_auditLogsProvider);
    return Scaffold(
      drawer: isMobile(context) ? const AppDrawer() : null,
      appBar: AppBar(
        title: const Text('Audit Log'),
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(_auditLogsProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
          data: (rows) => rows.isEmpty
              ? const Center(child: Text('No audit entries.'))
              : Card(
                  child: DataTable2(
                    columnSpacing: 16,
                    horizontalMargin: 16,
                    minWidth: 900,
                    columns: const [
                      DataColumn2(label: Text('When'), size: ColumnSize.S),
                      DataColumn2(label: Text('User'), size: ColumnSize.M),
                      DataColumn2(label: Text('Action'), size: ColumnSize.S),
                      DataColumn2(label: Text('Entity'), size: ColumnSize.M),
                      DataColumn2(label: Text('Description'), size: ColumnSize.L),
                    ],
                    rows: rows.map((r) {
                      final when = DateTime.parse(r['created_at'] as String).toLocal();
                      return DataRow2(cells: [
                        DataCell(Text(when.toString().substring(0, 19))),
                        DataCell(Text(r['user_email'] as String? ?? '—')),
                        DataCell(Text(r['action'] as String)),
                        DataCell(Text('${r['entity_type']} ${(r['entity_id'] as String? ?? '').substring(0, 8)}')),
                        DataCell(Text(r['description'] as String? ?? '')),
                      ]);
                    }).toList(),
                  ),
                ),
        ),
      ),
    );
  }
}
