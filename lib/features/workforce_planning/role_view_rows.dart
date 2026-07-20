import '../../data/models/workforce_planning.dart';

class RoleTaskRow {
  final String name;
  final String? nodeName;
  final String? cadence;
  final String? skillTier;
  final String? risk;
  final double hoursScaled;

  /// True when this task reaches the person through their role card rather than
  /// an explicit owner — its hours are this person's SHARE (see [buildRoleTaskRows]).
  final bool derived;
  const RoleTaskRow({
    required this.name,
    required this.nodeName,
    required this.cadence,
    required this.skillTier,
    required this.risk,
    required this.hoursScaled,
    this.derived = false,
  });
}

/// Builds display rows for one person's owned tasks, projecting hours at
/// [multiplier] (only driver-bound growing tasks scale). Tasks with no computed
/// row (shouldn't happen for owned tasks) fall back to 0 hours.
/// [holderCountByTaskId] divides a task's hours when it is shared — a task
/// derived from a role card held by N people gives each holder 1/N, mirroring
/// `wp_person_load`'s split. Absent entries mean "wholly this person's" (1).
/// [derivedTaskIds] marks which rows arrived via the role card rather than an
/// explicit owner, so the UI can label them.
List<RoleTaskRow> buildRoleTaskRows({
  required List<WpTask> ownerTasks,
  required Map<String, WpTaskComputed> computedById,
  required Map<String, String> nodeNameById,
  required double multiplier,
  Map<String, int> holderCountByTaskId = const {},
  Set<String> derivedTaskIds = const {},
}) {
  final rows = <RoleTaskRow>[];
  for (final t in ownerTasks) {
    final c = computedById[t.id];
    final base = c?.hoursPerMonthBase ?? 0;
    final growing = c?.isGrowing ?? false;
    final holders = holderCountByTaskId[t.id] ?? 1;
    final divisor = holders < 1 ? 1 : holders;
    final hours = (growing ? base * multiplier : base) / divisor;
    rows.add(RoleTaskRow(
      name: t.name,
      nodeName: t.nodeId == null ? null : nodeNameById[t.nodeId],
      cadence: t.cadence,
      skillTier: t.skillTier,
      risk: t.risk,
      hoursScaled: hours,
      derived: derivedTaskIds.contains(t.id),
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
