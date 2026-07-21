import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/tasks_paging.dart';

RoleScorecard _card(String id, String title) => RoleScorecard(
      id: id, companyId: 'c', jobTitle: title, missionStatement: '',
      responsibilities: const [], kpis: const [], wageType: 'MONTHLY',
      workHoursPerDay: 8, workDaysPerWeek: 'MON_FRI', isActive: true,
      effectiveDate: DateTime(2026, 1, 1),
    );

WpTask _t(String id, {String? card, String? area, String? ext}) => WpTask(
      id: id, companyId: 'c', name: id, roleScorecardId: card,
      responsibilityArea: area, externalRef: ext,
    );

void main() {
  group('pageOfTasks', () {
    final ten = [for (var i = 0; i < 10; i++) _t('t$i')];

    test('first page reports 1-4 of 10', () {
      final p = pageOfTasks(ten, 0, 4);
      expect(p.tasks.map((t) => t.id), ['t0', 't1', 't2', 't3']);
      expect(p.firstIndex, 1);
      expect(p.lastIndex, 4);
      expect(p.total, 10);
      expect(p.pageCount, 3);
      expect(p.hasPrev, isFalse);
      expect(p.hasNext, isTrue);
    });

    test('last page is short and reports its real bounds', () {
      final p = pageOfTasks(ten, 2, 4);
      expect(p.tasks.map((t) => t.id), ['t8', 't9']);
      expect(p.firstIndex, 9);
      expect(p.lastIndex, 10);
      expect(p.hasNext, isFalse);
    });

    test('an out-of-range page clamps instead of going blank', () {
      final p = pageOfTasks(ten, 99, 4);
      expect(p.page, 2, reason: 'deleting rows must not strand the user');
      expect(p.tasks, isNotEmpty);
    });

    test('a negative page clamps to the first', () {
      expect(pageOfTasks(ten, -5, 4).page, 0);
    });

    test('empty input is one empty page, not zero pages', () {
      final p = pageOfTasks(const [], 0, 25);
      expect(p.tasks, isEmpty);
      expect(p.pageCount, 1);
      expect(p.total, 0);
      expect(p.firstIndex, 0);
      expect(p.lastIndex, 0);
      expect(p.hasPrev, isFalse);
      expect(p.hasNext, isFalse);
    });

    test('an exact multiple does not add a trailing empty page', () {
      expect(pageOfTasks(ten, 0, 5).pageCount, 2);
    });

    test('page size larger than the list is a single page', () {
      final p = pageOfTasks(ten, 0, 500);
      expect(p.pageCount, 1);
      expect(p.tasks, hasLength(10));
    });

    test('a non-positive page size is rejected, not silently corrected', () {
      expect(() => pageOfTasks(ten, 0, 0), throwsArgumentError);
    });
  });

  group('scopes', () {
    final cards = [_card('rs1', 'Ops'), _card('rs2', 'HR')];
    final tasks = [
      _t('a1', card: 'rs1', area: 'A'),
      _t('a2', card: 'rs1', area: 'A'),
      _t('b1', card: 'rs2', area: 'B'),
      _t('leg', ext: 'T1'),
      _t('orphan'),
    ];

    test('lists All, each card, then the buckets with counts', () {
      final s = buildScopes(tasks, cards);
      expect(s.first.key, TaskScope.allKey);
      expect(s.first.count, 5);
      expect(s.map((x) => x.label),
          containsAll(['Ops', 'HR', 'From capacity model', 'Unattributed']));
      expect(s.firstWhere((x) => x.label == 'Ops').count, 2);
    });

    test('empty buckets are omitted — an empty option is a dead end', () {
      final s = buildScopes([_t('a1', card: 'rs1', area: 'A')], cards);
      expect(s.map((x) => x.label), isNot(contains('From capacity model')));
      expect(s.map((x) => x.label), isNot(contains('Unattributed')));
      expect(s.map((x) => x.label), isNot(contains('HR')),
          reason: 'a card with no tasks has nothing to show');
    });

    test('scoping to a card returns only its tasks', () {
      expect(tasksInScope(tasks, cards, 'rs1').map((t) => t.id), ['a1', 'a2']);
    });

    test('legacy and unattributed scopes are distinct', () {
      expect(tasksInScope(tasks, cards, TaskScope.legacyKey).map((t) => t.id), ['leg']);
      expect(tasksInScope(tasks, cards, TaskScope.unattributedKey).map((t) => t.id),
          ['orphan']);
    });

    test('all-scope covers every task exactly once', () {
      final all = tasksInScope(tasks, cards, TaskScope.allKey);
      expect(all, hasLength(tasks.length));
      expect(all.map((t) => t.id).toSet(), tasks.map((t) => t.id).toSet());
    });

    test('paging over the all-scope never drops or duplicates a row', () {
      final all = tasksInScope(tasks, cards, TaskScope.allKey);
      final seen = <String>[];
      for (var p = 0; p < pageOfTasks(all, 0, 2).pageCount; p++) {
        seen.addAll(pageOfTasks(all, p, 2).tasks.map((t) => t.id));
      }
      expect(seen, hasLength(5));
      expect(seen.toSet(), hasLength(5));
    });
  });
}
