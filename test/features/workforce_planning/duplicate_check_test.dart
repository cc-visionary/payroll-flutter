import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/duplicate_check.dart';

WpTask _t(String id, String name, {String status = 'ACTIVE', bool exp = false}) =>
    WpTask(id: id, companyId: 'c', name: name, status: status, isExpectation: exp);

void main() {
  final all = [
    _t('1', 'Pack, label, check and dispatch online orders'),
    _t('2', 'Reconcile bank statements'),
    _t('3', 'Old packing flow', status: 'ARCHIVED'),
    _t('4', 'Participate in training', exp: true),
  ];

  test('finds a near-duplicate above the threshold, best first', () {
    final m = findSimilarAccountabilities(typed: 'Pack and dispatch online orders', all: all);
    expect(m, isNotEmpty);
    expect(m.first.task.id, '1');
  });

  test('ignores archived and expectation rows', () {
    expect(findSimilarAccountabilities(typed: 'Old packing flow', all: all)
        .any((m) => m.task.id == '3'), isFalse);
    expect(findSimilarAccountabilities(typed: 'Participate in training', all: all)
        .any((m) => m.task.id == '4'), isFalse);
  });

  test('returns nothing for unrelated or too-short input', () {
    expect(findSimilarAccountabilities(typed: 'Design social ads', all: all), isEmpty);
    expect(findSimilarAccountabilities(typed: 'ab', all: all), isEmpty);
    expect(findSimilarAccountabilities(typed: '   ', all: all), isEmpty);
  });

  test('excludeId keeps a row from matching itself', () {
    final m = findSimilarAccountabilities(
        typed: 'Reconcile bank statements', all: all, excludeId: '2');
    expect(m.any((x) => x.task.id == '2'), isFalse);
  });

  test('respects the limit', () {
    final many = [for (var i = 0; i < 10; i++) _t('$i', 'Pack orders daily $i')];
    expect(findSimilarAccountabilities(typed: 'Pack orders daily', all: many, limit: 3).length, 3);
  });
}
