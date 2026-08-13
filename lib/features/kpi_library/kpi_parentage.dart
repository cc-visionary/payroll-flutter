import '../workforce_planning/org_tree.dart';

const _rank = {'PERSONAL': 0, 'DEPARTMENT': 1, 'COMPANY': 2};

/// Error for parenting [kpiId] under [newParentId], or null when valid.
///
/// Two rules, and they fail for different reasons. The level rule is about
/// meaning: a cascade only cascades upward, so a department measure serving
/// another department measure says nothing. The cycle rule is about
/// termination: `parent_kpi_id` is a self-reference and a loop would hang any
/// walk up the tree.
///
/// [wouldCreateCycle] is reused verbatim from `org_tree.dart` — it is generic
/// over `({String id, String? parentId})` and has nothing to do with people.
String? kpiParentError({
  required String kpiId,
  required String newParentId,
  required List<({String id, String? parentId})> kpis,
  required String Function(String id) levelOf,
}) {
  if (kpiId == newParentId) return "A KPI can't serve itself.";
  final mine = _rank[levelOf(kpiId)] ?? 0;
  final theirs = _rank[levelOf(newParentId)] ?? 0;
  if (theirs <= mine) return 'A KPI can only serve a higher level.';
  if (wouldCreateCycle(
    movingId: kpiId,
    newParentId: newParentId,
    people: kpis,
  )) {
    return 'That would create a loop.';
  }
  return null;
}
