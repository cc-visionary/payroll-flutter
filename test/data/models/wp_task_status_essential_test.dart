import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';

void main() {
  test('fromRow reads criticality, is_essential and status with defaults', () {
    final t = WpTask.fromRow({
      'id': 't1', 'company_id': 'c', 'name': 'Pack',
      'criticality': 'HIGH', 'is_essential': true, 'status': 'ACTIVE',
    });
    expect(t.criticality, 'HIGH');
    expect(t.isEssential, isTrue);
    expect(t.status, 'ACTIVE');

    final bare = WpTask.fromRow({'id': 't2', 'company_id': 'c', 'name': 'x'});
    expect(bare.criticality, isNull);
    expect(bare.isEssential, isTrue, reason: 'default is essential');
    expect(bare.status, 'ACTIVE', reason: 'default is active');
  });

  test('toUpsert writes the three columns', () {
    const t = WpTask(
      id: 't1', companyId: 'c', name: 'Pack',
      criticality: 'CRITICAL', isEssential: true, status: 'ARCHIVED');
    final m = t.toUpsert('c');
    expect(m['criticality'], 'CRITICAL');
    expect(m['is_essential'], true);
    expect(m['status'], 'ARCHIVED');
  });

  test('toUpsert forces is_essential false when the task is an expectation', () {
    const t = WpTask(
      id: 't1', companyId: 'c', name: 'Grow',
      isExpectation: true, isEssential: true);
    expect(t.toUpsert('c')['is_essential'], false,
        reason: 'an expectation is by definition non-essential');
  });

  test('copyWithSort preserves the three columns', () {
    const t = WpTask(
      id: 't1', companyId: 'c', name: 'Pack',
      criticality: 'MEDIUM', isEssential: false, status: 'ARCHIVED');
    final moved = t.copyWithSort(areaSort: 3, taskSort: 4);
    expect(moved.criticality, 'MEDIUM');
    expect(moved.isEssential, isFalse);
    expect(moved.status, 'ARCHIVED');
  });
}
