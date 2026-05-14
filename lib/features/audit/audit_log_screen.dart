import 'dart:convert';

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
                        DataCell(Text(_entityDisplay(r))),
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

/// Builds the Entity column label. For known entity types we extract a
/// compact identifier from new_values (falling back to old_values for
/// DELETEs). For unknown types we fall back to the original
/// `<type> <id-prefix>` form so this stays a non-breaking change.
///
/// The audit_logs.description column already carries the rich human-
/// readable summary (name, amount, status, etc.) — the Entity column
/// is intentionally a compact secondary identifier.
String _entityDisplay(Map<String, dynamic> row) {
  final type = row['entity_type'] as String? ?? '';
  final id = row['entity_id'] as String? ?? '';
  final idShort = id.length >= 8 ? id.substring(0, 8) : id;
  final json = _asMap(row['new_values']) ?? _asMap(row['old_values']);
  if (type == 'employees') {
    if (json != null) {
      final first = (json['first_name'] as String? ?? '').trim();
      final middle = (json['middle_name'] as String? ?? '').trim();
      final last = (json['last_name'] as String? ?? '').trim();
      final number = (json['employee_number'] as String? ?? '').trim();
      final name = [first, middle, last].where((s) => s.isNotEmpty).join(' ');
      if (name.isNotEmpty) {
        if (number.isNotEmpty) return '$type · $name ($number)';
        return '$type · $name';
      }
    }
  } else if (type == 'payroll_runs') {
    final status = (json?['status'] as String? ?? '').trim();
    if (status.isNotEmpty) return '$type · $status';
  } else if (type == 'payslips') {
    final number = (json?['payslip_number'] as String? ?? '').trim();
    if (number.isNotEmpty) return '$type · $number';
  } else if (type == 'manual_adjustment_lines') {
    final category = (json?['category'] as String? ?? '').trim();
    final amount = json?['amount'];
    if (category.isNotEmpty && amount != null) {
      return '$type · $category · ₱$amount';
    }
    if (category.isNotEmpty) return '$type · $category';
  }
  return '$type $idShort';
}

/// JSONB columns usually come back as `Map<String, dynamic>` from the
/// supabase-dart client, but defensively handle a String payload too.
Map<String, dynamic>? _asMap(dynamic value) {
  if (value == null) return null;
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  if (value is String && value.isNotEmpty) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }
  return null;
}
