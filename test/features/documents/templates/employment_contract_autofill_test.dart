import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/templates/employment_contract_template.dart';

void main() {
  test('template metadata', () {
    const t = EmploymentContractTemplate();
    expect(t.id, 'employment_contract');
    expect(t.name, 'Employment Contract');
    expect(t.version, 1);
  });

  test('emptyInputs sensible defaults', () {
    const t = EmploymentContractTemplate();
    final i = t.emptyInputs();
    expect(i.employeeId, isEmpty);
    expect(i.workHoursPerDay, 8);
    expect(i.workDaysPerWeek, 'Monday to Saturday');
    expect(i.nonCompeteMonths, 24);
    expect(i.representativeRole, 'People Manager');
    expect(i.responsibilities, isEmpty);
  });

  test('build returns empty until implemented', () {
    const t = EmploymentContractTemplate();
    expect(t.build(t.emptyInputs()), isEmpty);
  });
}
