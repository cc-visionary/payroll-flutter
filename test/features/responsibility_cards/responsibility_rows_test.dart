import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
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

  group('linking an existing task onto a card', () {
    test('an update carries role_scorecard_id so the row actually joins', () {
      // A task from the unlinked pool has role_scorecard_id = null. Without
      // setting it the row would take the area and name but never join the
      // card, and the link would appear to vanish on the next load.
      final d = diffResponsibilities(
        draft: [(area: 'Setup', tasks: [RespDraft(id: 'legacy-1', name: 'SD card flashing')])],
        existingRows: const [],
        cardId: 'rs1',
        companyId: 'c',
      );
      expect(d.inserts, isEmpty, reason: 'it exists already — adopt, do not duplicate');
      expect(d.updates.single['id'], 'legacy-1');
      expect(d.updates.single['role_scorecard_id'], 'rs1');
      expect(d.updates.single['responsibility_area'], 'Setup');
    });

    test('adopting does not delete rows already on the card', () {
      final d = diffResponsibilities(
        draft: [
          (area: 'Setup', tasks: [
            RespDraft(id: 'own-1', name: 'Existing responsibility'),
            RespDraft(id: 'legacy-1', name: 'Adopted'),
          ])
        ],
        existingRows: const [
          {'id': 'own-1', 'responsibility_area': 'Setup', 'name': 'Existing responsibility'},
        ],
        cardId: 'rs1',
        companyId: 'c',
      );
      expect(d.deleteIds, isEmpty);
      expect(d.updates.map((u) => u['id']), ['own-1', 'legacy-1']);
      expect(d.updates.map((u) => u['task_sort']), [0, 1],
          reason: 'the adopted row lands after the existing one');
    });
  });
}
