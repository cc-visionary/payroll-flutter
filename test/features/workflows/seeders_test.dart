import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/workflows/seeders.dart';

void main() {
  test(
    'seedSeparationWorkflow with 3 docs produces instance + 3 DOCUMENT_GENERATION steps',
    () {
      final seed = seedSeparationWorkflow(
        companyId: 'c1',
        employeeId: 'e1',
        employeeFullName: 'Maria Santos',
        documentTypes: const ['QUITCLAIM', 'COE', 'NTE'],
        eventId: 'ev1',
        docIdByType: const {'QUITCLAIM': 'd1', 'COE': 'd2', 'NTE': 'd3'},
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
    },
  );

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

  test(
    'seedPenaltyWorkflow produces a generate step then a signature approval',
    () {
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
    },
  );

  group('seedHiringWorkflow', () {
    WorkflowSeed seed({
      List<String> optionalDocs = const [],
      String? applicantId,
    }) => seedHiringWorkflow(
      companyId: 'c1',
      employeeId: 'e1',
      employeeFullName: 'Juan Cruz',
      applicantId: applicantId,
      docIdByType: const {
        'EMPLOYMENT_CONTRACT': 'd-contract',
        'NDA': 'd-nda',
        'LIABILITY_WAIVER': 'd-waiver',
      },
      optionalDocumentTypes: optionalDocs,
      initiatedById: 'u1',
    );

    test('always starts with the contract then the NDA, both required', () {
      final s = seed();
      expect(s.instance.workflowType, 'HIRING');
      expect(s.instance.title, 'Hiring — Juan Cruz');
      expect(s.steps.map((x) => x.stepType), [
        'DOCUMENT_GENERATION',
        'DOCUMENT_GENERATION',
      ]);
      expect(s.steps[0].inputData?['template_id'], 'employment_contract');
      expect(s.steps[0].generatedDocumentId, 'd-contract');
      expect(s.steps[1].inputData?['template_id'], 'nda');
      expect(s.steps[1].generatedDocumentId, 'd-nda');
      for (final step in s.steps) {
        expect(isOptionalStep(step.inputData), isFalse);
      }
    });

    test('optional documents follow the required ones, flagged optional', () {
      final s = seed(optionalDocs: ['LIABILITY_WAIVER']);
      expect(s.steps.length, 3);
      expect(s.steps[2].inputData?['template_id'], 'liability_waiver');
      expect(s.steps[2].generatedDocumentId, 'd-waiver');
      for (var i = 0; i < s.steps.length; i++) {
        expect(s.steps[i].stepIndex, i);
        expect(isOptionalStep(s.steps[i].inputData), i >= 2);
      }
    });

    test('context records the Lark onboarding checklist was sent', () {
      final c = seed().instance.context;
      expect(c['onboarding_checklist_sent'], isTrue);
      expect(
        c['onboarding_checklist_template_url'],
        kLarkOnboardingChecklistTemplateUrl,
      );
    });

    test('applicant id is carried only when the hire came from one', () {
      expect(seed(applicantId: 'a1').instance.context['applicant_id'], 'a1');
      expect(seed().instance.context.containsKey('applicant_id'), isFalse);
    });
  });
}
