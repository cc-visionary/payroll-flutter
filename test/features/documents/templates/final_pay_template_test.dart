import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/templates/final_pay_template.dart';

void main() {
  test('FinalPayTemplate exposes correct id + name', () {
    const t = FinalPayTemplate();
    expect(t.id, 'final_pay');
    expect(t.name, contains('Final Pay'));
    expect(t.supportsBulk, isFalse);
  });
}
