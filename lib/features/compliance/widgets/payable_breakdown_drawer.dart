import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme.dart';
import '../../../app/tokens.dart';
import '../../../data/models/hiring_entity.dart';
import '../../../data/models/statutory_payable.dart';
import '../providers.dart';

/// Per-employee detail for one (brand × month × agency) row, opened from a
/// row tap. Pulls from `statutory_payable_breakdown_v` — the same view the
/// XLSX export uses, so on-screen and exported figures can never drift.
class PayableBreakdownDrawer extends ConsumerWidget {
  final StatutoryPayable payable;
  final HiringEntity? brand;
  const PayableBreakdownDrawer({
    super.key,
    required this.payable,
    required this.brand,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = StatutoryPaymentsQuery(
      hiringEntityId: payable.hiringEntityId,
      periodYear: payable.periodYear,
      periodMonth: payable.periodMonth,
      agency: payable.agency,
    );
    final breakdownAsync = ref.watch(statutoryBreakdownProvider(query));

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, controller) => Padding(
        padding: const EdgeInsets.all(LuxiumSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    payable.agency.fullLabel,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            Text(
              '${brand?.name ?? payable.hiringEntityId} • ${_periodLabel(payable)}',
              style: TextStyle(color: LuxiumColors.of(context).soft),
            ),
            const SizedBox(height: LuxiumSpacing.md),
            Expanded(
              child: breakdownAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Error: $e',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
                data: (rows) =>
                    _BreakdownTable(rows: rows, scrollController: controller),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BreakdownTable extends ConsumerStatefulWidget {
  final List<StatutoryPayableBreakdownRow> rows;
  final ScrollController scrollController;
  const _BreakdownTable({required this.rows, required this.scrollController});

  @override
  ConsumerState<_BreakdownTable> createState() => _BreakdownTableState();
}

class _BreakdownTableState extends ConsumerState<_BreakdownTable> {
  Map<String, _EmpInfo>? _employees;

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    final ids = widget.rows.map((r) => r.employeeId).toSet().toList();
    if (ids.isEmpty) {
      setState(() => _employees = const {});
      return;
    }
    final client = Supabase.instance.client;
    final raw = await client
        .from('employees')
        .select('id, employee_number, first_name, middle_name, last_name')
        .inFilter('id', ids);
    final byId = <String, _EmpInfo>{
      for (final r in (raw as List<dynamic>).cast<Map<String, dynamic>>())
        r['id'] as String: _EmpInfo.fromRow(r),
    };
    if (mounted) setState(() => _employees = byId);
  }

  @override
  Widget build(BuildContext context) {
    final emps = _employees;
    if (emps == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.rows.isEmpty) {
      return const Center(child: Text('No employees in this row.'));
    }

    final fmt = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    final sorted = [...widget.rows]..sort((a, b) {
        final ea = emps[a.employeeId]?.lastName ?? '';
        final eb = emps[b.employeeId]?.lastName ?? '';
        return ea.compareTo(eb);
      });

    Decimal totalEe = Decimal.zero;
    Decimal totalEr = Decimal.zero;
    Decimal totalSum = Decimal.zero;
    for (final r in sorted) {
      totalEe += r.eeShare;
      totalEr += r.erShare;
      totalSum += r.totalAmount;
    }

    return SingleChildScrollView(
      controller: widget.scrollController,
      child: DataTable(
        columnSpacing: 12,
        columns: const [
          DataColumn(label: Text('Last')),
          DataColumn(label: Text('First')),
          DataColumn(label: Text('MI')),
          DataColumn(label: Text('Employee #')),
          DataColumn(label: Text('EE Share'), numeric: true),
          DataColumn(label: Text('ER Share'), numeric: true),
          DataColumn(label: Text('Total'), numeric: true),
        ],
        rows: [
          for (final r in sorted)
            DataRow(cells: [
              DataCell(Text(emps[r.employeeId]?.lastName ?? '—')),
              DataCell(Text(emps[r.employeeId]?.firstName ?? '—')),
              DataCell(Text(_mi(emps[r.employeeId]?.middleName))),
              DataCell(Text(emps[r.employeeId]?.employeeNumber ?? '—',
                  style: AppTheme.mono(context))),
              DataCell(Text(fmt.format(r.eeShare.toDouble()),
                  style: AppTheme.mono(context))),
              DataCell(Text(fmt.format(r.erShare.toDouble()),
                  style: AppTheme.mono(context))),
              DataCell(Text(fmt.format(r.totalAmount.toDouble()),
                  style:
                      AppTheme.mono(context, fontWeight: FontWeight.w600))),
            ]),
          DataRow(
            color: WidgetStateProperty.all(
              LuxiumColors.of(context).muted.withValues(alpha: 0.4),
            ),
            cells: [
              const DataCell(Text('TOTAL', style: TextStyle(fontWeight: FontWeight.w700))),
              const DataCell(Text('')),
              const DataCell(Text('')),
              const DataCell(Text('')),
              DataCell(Text(fmt.format(totalEe.toDouble()),
                  style: AppTheme.mono(context, fontWeight: FontWeight.w700))),
              DataCell(Text(fmt.format(totalEr.toDouble()),
                  style: AppTheme.mono(context, fontWeight: FontWeight.w700))),
              DataCell(Text(fmt.format(totalSum.toDouble()),
                  style: AppTheme.mono(context, fontWeight: FontWeight.w700))),
            ],
          ),
        ],
      ),
    );
  }

  String _mi(String? middleName) {
    if (middleName == null || middleName.trim().isEmpty) return '';
    return middleName.trim()[0].toUpperCase();
  }
}

class _EmpInfo {
  final String employeeNumber;
  final String firstName;
  final String? middleName;
  final String lastName;
  const _EmpInfo({
    required this.employeeNumber,
    required this.firstName,
    this.middleName,
    required this.lastName,
  });

  factory _EmpInfo.fromRow(Map<String, dynamic> r) => _EmpInfo(
        employeeNumber: r['employee_number'] as String? ?? '',
        firstName: r['first_name'] as String? ?? '',
        middleName: r['middle_name'] as String?,
        lastName: r['last_name'] as String? ?? '',
      );
}

String _periodLabel(StatutoryPayable p) {
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  return '${months[p.periodMonth - 1]} ${p.periodYear}';
}
