import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../widgets/responsive_table.dart';
import '../balance_rows.dart';
import '../capacity_math.dart';
import '../wp_providers.dart';

class BalanceTab extends ConsumerWidget {
  const BalanceTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loadsAsync = ref.watch(wpPersonLoadsProvider);
    final empsAsync = ref.watch(wpActiveEmployeesProvider);
    final kpiAsync = ref.watch(wpKpiCountByEmployeeProvider);
    final multiplier = ref.watch(wpGrowthMultiplierProvider);

    if (loadsAsync.isLoading || empsAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final err = loadsAsync.error ?? empsAsync.error;
    if (err != null) {
      return Center(child: Text('Error: $err', style: const TextStyle(color: Colors.red)));
    }
    final employeeById = {
      for (final e in empsAsync.asData!.value)
        e.id: (name: '${e.firstName} ${e.lastName}', title: e.jobTitle),
    };
    final rows = buildBalanceRows(
      loads: loadsAsync.asData!.value,
      employeeById: employeeById,
      kpiCounts: kpiAsync.asData?.value ?? const {},
      multiplier: multiplier,
    );
    if (rows.isEmpty) {
      return const Center(child: Text('No active people to show.'));
    }
    final showProjected = multiplier != 1.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: ResponsiveTable(
        child: DataTable(
          columns: [
            const DataColumn(label: Text('Person')),
            const DataColumn(label: Text('Role')),
            const DataColumn(label: Text('Tasks'), numeric: true),
            const DataColumn(label: Text('Hours/mo'), numeric: true),
            const DataColumn(label: Text('Capacity'), numeric: true),
            DataColumn(label: Text(showProjected ? 'Load (proj.)' : 'Load'), numeric: true),
            const DataColumn(label: Text('Status')),
            const DataColumn(label: Text('KPIs'), numeric: true),
          ],
          rows: [
            for (final r in rows)
              DataRow(cells: [
                DataCell(Text(r.name)),
                DataCell(Text(r.roleTitle ?? '—')),
                DataCell(Text('${r.tasksOwned}', style: AppTheme.mono(context))),
                DataCell(Text(r.hoursScaled.toStringAsFixed(1), style: AppTheme.mono(context))),
                DataCell(Text(r.capacityHours.toStringAsFixed(0), style: AppTheme.mono(context))),
                DataCell(Text('${(r.loadScaled * 100).round()}%', style: AppTheme.mono(context))),
                DataCell(_LoadChip(status: r.status)),
                DataCell(Text('${r.kpiCount}', style: AppTheme.mono(context))),
              ]),
          ],
        ),
      ),
    );
  }
}

/// Tinted status chip (no border) per PRODUCT.md.
class _LoadChip extends StatelessWidget {
  final LoadStatus status;
  const _LoadChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (String label, MaterialColor base) = switch (status) {
      LoadStatus.over => ('Over', Colors.red),
      LoadStatus.ok => ('OK', Colors.green),
      LoadStatus.under => ('Under', Colors.orange),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: base.withValues(alpha: dark ? 0.22 : 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: dark ? base.shade200 : base.shade700)),
    );
  }
}
