import '../workforce_planning/org_tree.dart';

const _rank = {'PERSONAL': 0, 'DEPARTMENT': 1, 'COMPANY': 2};

/// Error for parenting [kpiId] under [newParentId], or null when valid.
///
/// Two rules, and they fail for different reasons. The level rule is about
/// meaning: a cascade only cascades upward, so a department measure serving
/// another department measure says nothing.
///
/// The cycle check guards against pre-existing data corruption. Because ranks
/// are strictly increasing (PERSONAL 0 < DEPARTMENT 1 < COMPANY 2) and every
/// accepted parent must be strictly higher, no sequence of edits that all pass
/// the level rule can ever create a new cycle. However, `parent_kpi_id` shipped
/// without a guard, so a loop could exist in the database before this check
/// was deployed. Walking up the tree without this guard would hang on such data.
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
