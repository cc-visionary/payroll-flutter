import 'org_tree.dart';

/// Error for a reporting drag (make [movingId] report to [newParentId]), or null
/// when valid. Guards self-parenting and cycles. A drop on the current manager is
/// a harmless idempotent write and returns null.
String? reportingDropError({
  required String movingId,
  required String newParentId,
  required List<({String id, String? parentId})> people,
}) {
  if (movingId == newParentId) return "A person can't report to themselves.";
  if (wouldCreateCycle(movingId: movingId, newParentId: newParentId, people: people)) {
    return 'That would create a reporting loop.';
  }
  return null;
}
