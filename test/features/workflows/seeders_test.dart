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

  test('seedPenaltyWorkflow produces a generate step then a signature approval', () {
    final seed = seedPenaltyWorkflow(
      companyId: 'c1',
      employeeId: 'e1',
      employeeFullName: 'Gylian Gangawan',
      penaltyId: 'p1',
      employeeDocumentId: 'd1',
      initiatedById: 'u1',
    );
    expect(seed.instance.workflowType, 'REPAYMENT_AGREEMENT');
    expect(seed.instance.title, 'Penalty Repayment — Gylian Gangawan');
    expect(seed.instance.context['penalty_id'], 'p1');
    expect(seed.steps.length, 2);
    expect(seed.steps[0].stepType, 'DOCUMENT_GENERATION');
    expect(seed.steps[0].inputData?['template_id'], 'penalty_agreement');
    // The penalty id must ride on the step: _generateNow reads it from
    // input_data to render THIS penalty rather than the newest active one.
    expect(seed.steps[0].inputData?['penalty_id'], 'p1');
    expect(seed.steps[0].generatedDocumentId, 'd1');
    expect(seed.steps[1].stepIndex, 1);
    expect(seed.steps[1].stepType, 'APPROVAL');
  });

  test('seedHiringWorkflow produces 4 default STATUS_UPDATE onboarding steps', () {
    final seed = seedHiringWorkflow(
      companyId: 'c1',
      employeeId: 'e1',
      employeeFullName: 'Juan Cruz',
      applicantId: 'a1',
      initiatedById: 'u1',
    );
    expect(seed.instance.workflowType, 'HIRING');
    expect(seed.instance.title, 'Hiring — Juan Cruz');
    expect(seed.instance.context['applicant_id'], 'a1');
    expect(seed.steps.length, 4);
    expect(seed.steps[0].stepType, 'STATUS_UPDATE');
    expect(seed.steps[0].name, contains('IT account'));
    expect(seed.steps[3].name, contains('30-day'));
    for (var i = 0; i < seed.steps.length; i++) {
      expect(seed.steps[i].stepIndex, i);
    }
  });
}
