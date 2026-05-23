import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/templates/nda_template.dart';

void main() {
  test('template metadata', () {
    const t = NdaTemplate();
    expect(t.id, 'nda');
    expect(t.name, 'Confidentiality & Non-Disclosure Agreement');
    expect(t.version, 1);
  });

  test('emptyInputs sensible defaults', () {
    const t = NdaTemplate();
    final i = t.emptyInputs();
    expect(i.employeeId, isEmpty);
    expect(i.companyId, isEmpty);
    expect(i.employeePosition, isEmpty);
    expect(i.effectiveDate, isNull);
    expect(i.authorizedSignatoryRole, 'Authorized Signatory');
  });

  test('build returns a non-empty block tree', () {
    const t = NdaTemplate();
    expect(t.build(t.emptyInputs()), isNotEmpty);
  });
}
