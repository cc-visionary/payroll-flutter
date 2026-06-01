import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/workflows/seeders.dart';

void main() {
  test('seedSeparationWorkflow with 3 docs produces instance + 3 DOCUMENT_GENERATION steps', () {
    final seed = seedSeparationWorkflow(
      companyId: 'c1',
      employeeId: 'e1',
      employeeFullName: 'Maria Santos',
      documentTypes: const ['QUITCLAIM', 'COE', 'NTE'],
      eventId: 'ev1',
      docIdByType: const {
        'QUITCLAIM': 'd1',
        'COE': 'd2',
        'NTE': 'd3',
      },
      initiatedById: 'u1',
    );
    expect(seed.instance.workflowType, 'SEPARATION');
    expect(seed.instance.title, 'Separation — Maria Santos');
    expect(seed.instance.context['event_id'], 'ev1');
    expect(seed.steps.length, 3);
    expect(seed.steps[0].stepIndex, 0);
    expect(seed.steps[0].stepType, 'DOCUMENT_GENERATION');
    expect(seed.steps[0].name, contains('Quitclaim'));
    expect(seed.steps[0].generatedDocumentId, 'd1');
    expect(seed.steps[0].inputData?['template_id'], 'quitclaim');
    expect(seed.steps[2].generatedDocumentId, 'd3');
  });

  test('seedSeparationWorkflow with empty doc list produces 0 steps', () {
    final seed = seedSeparationWorkflow(
      companyId: 'c1',
      employeeId: 'e1',
      employeeFullName: 'Maria Santos',
      documentTypes: const [],
      eventId: 'ev1',
      docIdByType: const {},
      initiatedById: 'u1',
    );
    expect(seed.steps, isEmpty);
  });
}
