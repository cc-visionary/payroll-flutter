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

  test('finds the spec\'s motivating duplicate: a manager retyping '
      '"Pack and dispatch orders" against the longer, more specific '
      '"Pack, label, check and dispatch online orders" (score 0.571)', () {
    final m = findSimilarAccountabilities(typed: 'Pack and dispatch orders', all: all);
    expect(m, isNotEmpty);
    expect(m.first.task.id, '1');
  });

  test('ignores archived and expectation rows', () {
    expect(findSimilarAccountabilities(typed: 'Old packing flow', all: all)
        .any((m) => m.task.id == '3'), isFalse);
    expect(findSimilarAccountabilities(typed: 'Participate in training', all: all)
        .any((m) => m.task.id == '4'), isFalse);
  });

  test('unrelated names sharing no words score 0 and do not match', () {
    expect(findSimilarAccountabilities(typed: 'Design social ads', all: all), isEmpty);
    expect(findSimilarAccountabilities(typed: 'Reconcile bank statements', all: all)
        .any((m) => m.task.id == '1'), isFalse);
    final adsVsBank = [_t('a', 'Design social ads'), _t('b', 'Reconcile bank statements')];
    expect(findSimilarAccountabilities(typed: 'Design social ads', all: adsVsBank)
        .any((m) => m.task.id == 'b'), isFalse);
  });

  test('returns nothing for too-short input', () {
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
