import '../../data/models/workforce_planning.dart';
import '../../data/repositories/role_scorecard_repository.dart' show KpiAssignee;
import 'capacity_math.dart';

class BalanceRow {
  final String employeeId;
  final String name;
  final String? roleTitle;
  final int tasksOwned;
  final double capacityHours;
  final double hoursScaled;
  final double loadScaled;
  final LoadStatus status;
  final int kpiCount;
  const BalanceRow({
    required this.employeeId,
    required this.name,
    required this.roleTitle,
    required this.tasksOwned,
    required this.capacityHours,
    required this.hoursScaled,
    required this.loadScaled,
    required this.status,
    required this.kpiCount,
  });
}

/// employeeId -> number of distinct KPIs they are tracked on.
Map<String, int> kpiCountByEmployee(Map<String, List<KpiAssignee>> assignedByKpi) {
  final out = <String, int>{};
  for (final assignees in assignedByKpi.values) {
    for (final a in assignees) {
      out[a.employeeId] = (out[a.employeeId] ?? 0) + 1;
    }
  }
  return out;
}

/// Joins per-person aggregates to display info and projects load at [multiplier].
/// Sorted by scaled load descending (most-loaded first). Missing employee record
/// falls back to the id as name and a null role.
List<BalanceRow> buildBalanceRows({
  required List<WpPersonLoad> loads,
  required Map<String, ({String name, String? title})> employeeById,
  required Map<String, int> kpiCounts,
  required double multiplier,
}) {
  final rows = <BalanceRow>[];
  for (final l in loads) {
    final emp = employeeById[l.employeeId];
    final hours = projectedHours(l.hoursFixed, l.hoursGrowingBase, multiplier);
    final frac = loadFraction(hours, l.capacityHours);
    rows.add(BalanceRow(
      employeeId: l.employeeId,
      name: emp?.name ?? l.employeeId,
      roleTitle: emp?.title,
      tasksOwned: l.tasksOwned,
      capacityHours: l.capacityHours,
      hoursScaled: hours,
      loadScaled: frac,
      status: loadStatus(frac),
      kpiCount: kpiCounts[l.employeeId] ?? 0,
    ));
  }
  rows.sort((a, b) => b.loadScaled.compareTo(a.loadScaled));
  return rows;
}
