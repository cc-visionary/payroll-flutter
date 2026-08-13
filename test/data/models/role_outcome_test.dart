import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/role_outcome.dart';

void main() {
  test('round-trips a row', () {
    final o = RoleOutcome.fromRow({
      'id': 'o1',
      'company_id': 'c1',
      'role_scorecard_id': 'r1',
      'responsibility_area': 'Order Fulfillment',
      'text': 'Customers receive the correct product',
      'sort_order': 2,
    });
    expect(o.responsibilityArea, 'Order Fulfillment');
    expect(o.text, 'Customers receive the correct product');
    expect(o.sortOrder, 2);

    final payload = o.toUpsertPayload();
    expect(payload['responsibility_area'], 'Order Fulfillment');
    expect(payload['sort_order'], 2);
    expect(payload['role_scorecard_id'], 'r1');
  });

  test('sort_order defaults to zero when absent', () {
    final o = RoleOutcome.fromRow({
      'id': 'o1',
      'company_id': 'c1',
      'role_scorecard_id': 'r1',
      'responsibility_area': 'Returns',
      'text': 'Refunds land within SLA',
    });
    expect(o.sortOrder, 0);
  });
}
