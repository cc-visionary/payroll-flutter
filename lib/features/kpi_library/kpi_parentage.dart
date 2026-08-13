import '../workforce_planning/org_tree.dart';

const _rank = {'PERSONAL': 0, 'DEPARTMENT': 1, 'COMPANY': 2};

/// Error for parenting [kpiId] under [newParentId], or null when valid.
///
/// Two rules, and they fail for different reasons. The level rule is about
/// meaning: a cascade only cascades upward, so a department measure serving
/// another department measure says nothing. Both sides of that comparison
/// must resolve to a known level — an unrecognised level (on either the KPI
/// being moved or the proposed parent) means the data isn't in a state this
/// rule can reason about, and the honest answer is to refuse the edit, not to
/// guess by treating the unknown as the lowest level.
///
/// The cycle rule guards pre-existing data, not future edits: because ranks
/// are strictly increasing (PERSONAL 0 < DEPARTMENT 1 < COMPANY 2) and every
/// accepted parent must be strictly higher, no sequence of edits that all pass
/// the level rule can ever create a new cycle. But `parent_kpi_id` shipped
/// with no database-level constraint of its own — no check, no trigger — so a
/// loop can already exist in data written before this function existed.
/// [wouldCreateCycle] is safe to run against such data anyway: it carries a
/// visited set (see `descendantsOf` in `org_tree.dart`), so it terminates
/// even on a cyclic graph. A naive walk up the tree that didn't track visited
/// nodes would be the thing that hangs.
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
  final mine = _rank[levelOf(kpiId)];
  final theirs = _rank[levelOf(newParentId)];
  if (mine == null || theirs == null) {
    return "A KPI's level isn't recognised, so parentage can't be checked.";
  }
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
