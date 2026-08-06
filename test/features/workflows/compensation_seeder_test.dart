import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/workflows/seeders.dart';

void main() {
  test('compensationDocumentType maps every change type', () {
    expect(compensationDocumentType('SALARY_INCREASE'), 'SALARY_ADJUSTMENT');
    expect(compensationDocumentType('SALARY_DECREASE'), 'SALARY_ADJUSTMENT');
    expect(compensationDocumentType('PROMOTION'), 'PROMOTION');
    expect(compensationDocumentType('LATERAL_TRANSFER'), 'LATERAL_TRANSFER');
    expect(compensationDocumentType('DEMOTION'), 'DEMOTION');
  });

  test('role changes seed a ROLE_CHANGE workflow', () {
    final seed = seedCompensationChangeWorkflow(
      companyId: 'CO1',
      employeeId: 'E1',
      employeeFullName: 'Jane Cruz',
      changeType: 'PROMOTION',
      employeeDocumentId: 'DOC1',
      initiatedById: 'U1',
    );
    expect(seed.instance.workflowType, 'ROLE_CHANGE');
    expect(seed.steps.single.stepType, 'DOCUMENT_GENERATION');
    expect(seed.steps.single.inputData!['template_id'], 'salary_adjustment');
    expect(seed.steps.single.inputData!['change_type'], 'PROMOTION');
    expect(seed.steps.single.generatedDocumentId, 'DOC1');
  });

  test('pay-only changes seed a SALARY_CHANGE workflow', () {
    final seed = seedCompensationChangeWorkflow(
      companyId: 'CO1',
      employeeId: 'E1',
      employeeFullName: 'Jane Cruz',
      changeType: 'SALARY_INCREASE',
      employeeDocumentId: 'DOC1',
      initiatedById: 'U1',
    );
    expect(seed.instance.workflowType, 'SALARY_CHANGE');
  });
}
