import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/assignable_pool.dart';

WpTask _t(String id, {String? roleScorecardId}) => WpTask(
    id: id, companyId: 'c', name: 'Task $id', roleScorecardId: roleScorecardId);

WpTaskAssignment _a(String id, String taskId, {String? roleScorecardId}) =>
    WpTaskAssignment(
        id: id, companyId: 'c', taskId: taskId, roleScorecardId: roleScorecardId);

void main() {
  group('tasksOnCard', () {
    test(
        'includes a task AUTHORED on the card and one SHARED via an '
        'assignment row, excludes an unrelated task', () {
      final allTasks = [
        _t('authored', roleScorecardId: 'card-1'), // authored here
        _t('shared-task', roleScorecardId: 'card-2'), // owned elsewhere, shared in
        _t('unrelated', roleScorecardId: 'card-3'), // owned elsewhere, not shared
      ];
      final allAssignments = [
        _a('asn-1', 'shared-task', roleScorecardId: 'card-1'),
        // An assignment targeting a DIFFERENT card must not leak in.
        _a('asn-2', 'unrelated', roleScorecardId: 'card-3'),
      ];

      final result = tasksOnCard(
          cardId: 'card-1', allTasks: allTasks, allAssignments: allAssignments);

      expect(result, {'authored', 'shared-task'});
      expect(result.contains('unrelated'), isFalse);
    });

    test('cardId == null returns an empty set', () {
      final allTasks = [_t('a', roleScorecardId: 'card-1')];
      final allAssignments = [_a('asn-1', 'a', roleScorecardId: 'card-1')];

      final result =
          tasksOnCard(cardId: null, allTasks: allTasks, allAssignments: allAssignments);

      expect(result, isEmpty);
    });

    test('empty inputs return an empty set', () {
      final result = tasksOnCard(cardId: 'card-1', allTasks: const [], allAssignments: const []);
      expect(result, isEmpty);
    });
  });
}
