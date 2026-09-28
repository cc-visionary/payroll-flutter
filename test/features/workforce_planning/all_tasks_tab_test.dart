import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/tabs/all_tasks_tab.dart';

void main() {
  const tasks = [
    WpTask(id: 'a', companyId: 'c', name: 'Pack Shopee orders', roleScorecardId: 'bh'),
    WpTask(id: 'b', companyId: 'c', name: 'Reply to chats'),
    WpTask(id: 'c', companyId: 'c', name: 'Legacy row', externalRef: 'X'),
    WpTask(id: 'd', companyId: 'c', name: 'Split thing', roleScorecardId: 'om', allocationReviewNote: 'was: x'),
    WpTask(id: 'e', companyId: 'c', name: 'Old', roleScorecardId: 'bh', status: 'ARCHIVED'),
  ];

  test('default hides archived and legacy reference rows', () {
    expect(filterTasks(tasks).map((t) => t.id), ['a', 'b', 'd']);
  });
  test('search is case-insensitive on name', () {
    expect(filterTasks(tasks, query: 'shopee').map((t) => t.id), ['a']);
  });
  test('no role / flagged / by role', () {
    expect(filterTasks(tasks, filter: AllTasksFilter.noRole).map((t) => t.id), ['b']);
    expect(filterTasks(tasks, filter: AllTasksFilter.flagged).map((t) => t.id), ['d']);
    expect(filterTasks(tasks, filter: AllTasksFilter.role, roleId: 'bh').map((t) => t.id), ['a']);
  });
}
