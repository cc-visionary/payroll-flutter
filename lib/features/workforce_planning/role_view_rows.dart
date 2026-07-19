import '../../data/models/workforce_planning.dart';

class RoleTaskRow {
  final String name;
  final String? nodeName;
  final String? cadence;
  final String? skillTier;
  final String? risk;
  final double hoursScaled;
  const RoleTaskRow({
    required this.name,
    required this.nodeName,
    required this.cadence,
    required this.skillTier,
    required this.risk,
    required this.hoursScaled,
  });
}

/// Builds display rows for one person's owned tasks, projecting hours at
/// [multiplier] (only driver-bound growing tasks scale). Tasks with no computed
/// row (shouldn't happen for owned tasks) fall back to 0 hours.
List<RoleTaskRow> buildRoleTaskRows({
  required List<WpTask> ownerTasks,
  required Map<String, WpTaskComputed> computedById,
  required Map<String, String> nodeNameById,
  required double multiplier,
}) {
  final rows = <RoleTaskRow>[];
  for (final t in ownerTasks) {
    final c = computedById[t.id];
    final base = c?.hoursPerMonthBase ?? 0;
    final growing = c?.isGrowing ?? false;
    final hours = growing ? base * multiplier : base;
    rows.add(RoleTaskRow(
      name: t.name,
      nodeName: t.nodeId == null ? null : nodeNameById[t.nodeId],
      cadence: t.cadence,
      skillTier: t.skillTier,
      risk: t.risk,
      hoursScaled: hours,
    ));
  }
  return rows;
}

/// Sum of scaled hours by skill tier; null tier grouped under 'Untiered'.
Map<String, double> hoursByTier(List<RoleTaskRow> rows) {
  final out = <String, double>{};
  for (final r in rows) {
    final key = r.skillTier ?? 'Untiered';
    out[key] = (out[key] ?? 0) + r.hoursScaled;
  }
  return out;
}
