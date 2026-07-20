/// One editable responsibility line. [id] is the wp_tasks row id when it already
/// exists — that's what makes a rename an UPDATE instead of delete+insert (which
/// would discard the row's cadence/minutes/owner).
class RespDraft {
  final String? id;
  String name;
  RespDraft({this.id, required this.name});
}

/// Diffs the edited tree against the card's existing responsibility rows.
({List<Map<String, dynamic>> inserts, List<Map<String, dynamic>> updates, List<String> deleteIds})
    diffResponsibilities({
  required List<({String area, List<RespDraft> tasks})> draft,
  required List<Map<String, dynamic>> existingRows,
  required String cardId,
  required String companyId,
}) {
  final inserts = <Map<String, dynamic>>[];
  final updates = <Map<String, dynamic>>[];
  final kept = <String>{};
  for (var ai = 0; ai < draft.length; ai++) {
    final area = draft[ai].area.trim();
    if (area.isEmpty) continue;
    final tasks = draft[ai].tasks;
    for (var ti = 0; ti < tasks.length; ti++) {
      final name = tasks[ti].name.trim();
      if (name.isEmpty) continue;
      final id = tasks[ti].id;
      if (id == null) {
        inserts.add({
          'company_id': companyId,
          'role_scorecard_id': cardId,
          'responsibility_area': area,
          'name': name,
          'area_sort': ai,
          'task_sort': ti,
          'times_source': 'manual',
          'minutes_source': 'manual',
        });
      } else {
        kept.add(id);
        updates.add({
          'id': id,
          'responsibility_area': area,
          'name': name,
          'area_sort': ai,
          'task_sort': ti,
        });
      }
    }
  }
  final deleteIds = [
    for (final r in existingRows)
      if (r['id'] is String && !kept.contains(r['id'] as String)) r['id'] as String,
  ];
  return (inserts: inserts, updates: updates, deleteIds: deleteIds);
}
