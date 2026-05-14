import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/templates/non_reg_template.dart';

void main() {
  test('template metadata', () {
    const t = NonRegTemplate();
    expect(t.id, 'non_reg');
    expect(t.name, 'Notice of Non-Regularization');
    expect(t.version, 1);
  });

  test('emptyInputs has today as dateIssued and empty findings', () {
    const t = NonRegTemplate();
    final i = t.emptyInputs();
    expect(i.findings, isEmpty);
    expect(i.employeeId, isEmpty);
    expect(i.companyId, isEmpty);
  });
}
