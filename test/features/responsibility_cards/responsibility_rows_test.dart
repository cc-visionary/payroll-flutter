import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/responsibility_cards/responsibility_rows.dart';

void main() {
  test('responsibilitiesFromTaskRows groups + orders by sort, not name', () {
    final rows = <Map<String, dynamic>>[
      {'name': 'Zebra task', 'responsibility_area': 'Alpha', 'area_sort': 0, 'task_sort': 0},
      {'name': 'Apple task', 'responsibility_area': 'Alpha', 'area_sort': 0, 'task_sort': 1},
      {'name': 'Only', 'responsibility_area': 'Beta', 'area_sort': 1, 'task_sort': 0},
      {'name': 'unlinked', 'responsibility_area': null, 'area_sort': 0, 'task_sort': 0},
    ];
    final out = responsibilitiesFromTaskRows(rows);
    expect(out.map((a) => a.area).toList(), ['Alpha', 'Beta']); // area_sort order
    expect(out.first.tasks, ['Zebra task', 'Apple task']);      // task_sort, NOT alphabetical
    expect(out.length, 2);                                       // blank-area row skipped
  });

  test('diffResponsibilities updates renames by id (preserves costing) and assigns sorts', () {
    final existing = <Map<String, dynamic>>[
      {'id': 't1', 'name': 'Old name', 'responsibility_area': 'Alpha'},
      {'id': 't2', 'name': 'Gone', 'responsibility_area': 'Alpha'},
    ];
    final d = diffResponsibilities(
      draft: [
        (area: 'Alpha', tasks: [RespDraft(id: 't1', name: 'New name'), RespDraft(id: null, name: 'Fresh')]),
      ],
      existingRows: existing,
      cardId: 'c1',
      companyId: 'co',
    );
    expect(d.updates.single['id'], 't1');
    expect(d.updates.single['name'], 'New name');   // rename = UPDATE, keeps hours
    expect(d.updates.single['task_sort'], 0);
    expect(d.inserts.single['name'], 'Fresh');
    expect(d.inserts.single['task_sort'], 1);
    expect(d.inserts.single['role_scorecard_id'], 'c1');
    expect(d.deleteIds, ['t2']);
  });
}
