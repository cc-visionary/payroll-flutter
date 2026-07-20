import '../../data/models/role_scorecard.dart';

/// Rebuilds a card's ordered responsibility tree from its wp_tasks rows.
/// Areas order by their smallest `area_sort` (ties by name); tasks by `task_sort`.
/// Rows with no area or no name are not card responsibilities and are skipped.
List<ResponsibilityArea> responsibilitiesFromTaskRows(List<Map<String, dynamic>> rows) {
  final areaSort = <String, int>{};
  final byArea = <String, List<({int sort, String name})>>{};
  for (final r in rows) {
    final area = (r['responsibility_area'] as String?)?.trim() ?? '';
    final name = (r['name'] as String?)?.trim() ?? '';
    if (area.isEmpty || name.isEmpty) continue;
    final aSort = (r['area_sort'] as num?)?.toInt() ?? 0;
    final tSort = (r['task_sort'] as num?)?.toInt() ?? 0;
    final prev = areaSort[area];
    areaSort[area] = prev == null || aSort < prev ? aSort : prev;
    (byArea[area] ??= []).add((sort: tSort, name: name));
  }
  final areas = byArea.keys.toList()
    ..sort((a, b) {
      final c = areaSort[a]!.compareTo(areaSort[b]!);
      return c != 0 ? c : a.compareTo(b);
    });
  return [
    for (final a in areas)
      ResponsibilityArea(
        area: a,
        tasks: (byArea[a]!..sort((x, y) => x.sort.compareTo(y.sort)))
            .map((e) => e.name)
            .toList(),
      ),
  ];
}

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
