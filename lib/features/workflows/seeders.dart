import '../../data/repositories/workflow_repository.dart';

/// Pure output of a seeder: an instance + its steps. Used by kickoff
/// handlers (separation, hiring) to assemble inputs before calling
/// `workflowRepository.insertWithSteps`.
class WorkflowSeed {
  final WorkflowInstanceInput instance;
  final List<WorkflowStepInput> steps;
  const WorkflowSeed({required this.instance, required this.steps});
}

/// Map from `employee_documents.document_type` enum value to the
/// `template_registry.dart` template id.
const _templateIdByDocType = <String, String>{
  'QUITCLAIM': 'quitclaim',
  'COE': 'coe',
  'NTE': 'nte',
  'NON_REG': 'non_reg',
  'EMPLOYMENT_CONTRACT': 'employment_contract',
  'NDA': 'nda',
  'LIABILITY_WAIVER': 'liability_waiver',
  'PENALTY_AGREEMENT': 'penalty_agreement',
};

/// Human-readable label for a document type.
const _docLabel = <String, String>{
  'QUITCLAIM': 'Quitclaim',
  'COE': 'Certificate of Employment',
  'NTE': 'Notice to Explain',
  'NON_REG': 'Notice of Non-Regularization',
  'EMPLOYMENT_CONTRACT': 'Employment Contract',
  'NDA': 'Non-Disclosure Agreement',
  'LIABILITY_WAIVER': 'Liability Waiver',
  'PENALTY_AGREEMENT': 'Penalty Repayment Agreement',
};

/// Build a SEPARATION workflow: one DOCUMENT_GENERATION step per selected
/// document type. Each step's `input_data` carries the template id + the id
/// of the DRAFT `employee_documents` row that's already been inserted by
/// the separation confirmation handler.
WorkflowSeed seedSeparationWorkflow({
  required String companyId,
  required String employeeId,
  required String employeeFullName,
  required List<String> documentTypes,
  required String eventId,
  required Map<String, String> docIdByType,
  required String initiatedById,
}) {
  final steps = <WorkflowStepInput>[];
  for (var i = 0; i < documentTypes.length; i++) {
    final type = documentTypes[i];
    final templateId = _templateIdByDocType[type] ?? type.toLowerCase();
    final label = _docLabel[type] ?? type;
    steps.add(
      WorkflowStepInput(
        stepIndex: i,
        stepType: 'DOCUMENT_GENERATION',
        name: 'Generate $label',
        description: 'Render the $label PDF and mark this step complete.',
        inputData: {
          'template_id': templateId,
          'employee_document_id': docIdByType[type],
        },
        generatedDocumentId: docIdByType[type],
      ),
    );
  }
  return WorkflowSeed(
    instance: WorkflowInstanceInput(
      companyId: companyId,
      employeeId: employeeId,
      workflowType: 'SEPARATION',
      title: 'Separation — $employeeFullName',
      context: {'event_id': eventId},
      initiatedById: initiatedById,
    ),
    steps: steps,
  );
}

/// Documents every new hire must have: generated first, never optional.
const kRequiredHireDocumentTypes = <String>['EMPLOYMENT_CONTRACT', 'NDA'];

/// Onboarding documents HR may add; each becomes an optional step.
const kOptionalHireDocumentTypes = <String>['LIABILITY_WAIVER'];

/// Onboarding checklist items HR may add; each is an optional STATUS_UPDATE
/// step HR marks complete by hand.
const kOnboardingTasks = <String>[
  'IT account & email setup',
  'Equipment provisioning (laptop, peripherals)',
  'Day-1 orientation completed',
  '30-day check-in completed',
];

/// Title for a hire document's DRAFT `employee_documents` row.
String hireDocTitle(String type) => _docLabel[type] ?? type;

/// Whether a step was seeded as optional (`input_data.optional`). Optional
/// steps are skippable like any other; the flag only tells HR they may be.
bool isOptionalStep(Map<String, dynamic>? inputData) =>
    inputData?['optional'] == true;

/// Build a HIRING workflow: the required contract + NDA, then whichever
/// optional documents and checklist tasks HR picked, each flagged optional.
///
/// Document steps link to DRAFT `employee_documents` rows the caller has
/// already inserted ([docIdByType]), exactly like [seedSeparationWorkflow],
/// so "Generate now" fills that row instead of minting a second one.
WorkflowSeed seedHiringWorkflow({
  required String companyId,
  required String employeeId,
  required String employeeFullName,
  String? applicantId,
  required Map<String, String> docIdByType,
  List<String> optionalDocumentTypes = const [],
  List<String> optionalTasks = const [],
  required String initiatedById,
}) {
  final steps = <WorkflowStepInput>[];
  void addDoc(String type, {required bool optional}) {
    final label = _docLabel[type] ?? type;
    steps.add(
      WorkflowStepInput(
        stepIndex: steps.length,
        stepType: 'DOCUMENT_GENERATION',
        name: 'Generate $label',
        description: optional
            ? 'Optional — skip if this hire does not need it.'
            : 'Render the $label PDF and mark this step complete.',
        inputData: {
          'template_id': _templateIdByDocType[type] ?? type.toLowerCase(),
          'employee_document_id': docIdByType[type],
          if (optional) 'optional': true,
        },
        generatedDocumentId: docIdByType[type],
      ),
    );
  }

  for (final type in kRequiredHireDocumentTypes) {
    addDoc(type, optional: false);
  }
  for (final type in optionalDocumentTypes) {
    addDoc(type, optional: true);
  }
  for (final task in optionalTasks) {
    steps.add(
      WorkflowStepInput(
        stepIndex: steps.length,
        stepType: 'STATUS_UPDATE',
        name: task,
        description: 'Optional — skip if this hire does not need it.',
        inputData: const {'optional': true},
      ),
    );
  }
  return WorkflowSeed(
    instance: WorkflowInstanceInput(
      companyId: companyId,
      employeeId: employeeId,
      workflowType: 'HIRING',
      title: 'Hiring — $employeeFullName',
      context: {'applicant_id': ?applicantId},
      initiatedById: initiatedById,
    ),
    steps: steps,
  );
}

/// Build a REPAYMENT_AGREEMENT workflow for a recorded penalty: generate the
/// repayment agreement, then track the employee's signed copy coming back.
///
/// The penalty row and its installments are written before this seed is built
/// (same ordering as the compensation-change chain) — the workflow documents
/// and tracks a deduction that already exists, it doesn't create one.
///
/// Step 1 is a manual APPROVAL by design: no workflow in this app is wired to
/// Lark approvals, so HR marks it when the signed agreement is physically back.
WorkflowSeed seedPenaltyWorkflow({
  required String companyId,
  required String employeeId,
  required String employeeFullName,
  required String penaltyId,
  required String employeeDocumentId,
  required String initiatedById,
}) {
  return WorkflowSeed(
    instance: WorkflowInstanceInput(
      companyId: companyId,
      employeeId: employeeId,
      workflowType: 'REPAYMENT_AGREEMENT',
      title: 'Penalty Repayment — $employeeFullName',
      context: {'penalty_id': penaltyId},
      initiatedById: initiatedById,
    ),
    steps: [
      WorkflowStepInput(
        stepIndex: 0,
        stepType: 'DOCUMENT_GENERATION',
        name: 'Generate Penalty Repayment Agreement',
        description:
            'Render the agreement with the installment schedule and mark this '
            'step complete.',
        inputData: {
          'template_id': 'penalty_agreement',
          'penalty_id': penaltyId,
          'employee_document_id': employeeDocumentId,
        },
        generatedDocumentId: employeeDocumentId,
      ),
      WorkflowStepInput(
        stepIndex: 1,
        stepType: 'APPROVAL',
        name: 'Employee signed the agreement',
        description:
            'Approve once the employee has signed and returned the agreement. '
            'Deductions run on the schedule regardless; this records consent.',
      ),
    ],
  );
}

/// employee_documents.document_type for a compensation change notice.
/// Pay-only changes file as SALARY_ADJUSTMENT; role changes file distinctly.
String compensationDocumentType(String changeType) => switch (changeType) {
  'PROMOTION' => 'PROMOTION',
  'LATERAL_TRANSFER' => 'LATERAL_TRANSFER',
  'DEMOTION' => 'DEMOTION',
  _ => 'SALARY_ADJUSTMENT', // SALARY_INCREASE | SALARY_DECREASE
};

String compensationDocTitle(String changeType) => switch (changeType) {
  'PROMOTION' => 'Notice of Promotion',
  'LATERAL_TRANSFER' => 'Notice of Lateral Transfer',
  'DEMOTION' => 'Notice of Change in Role',
  _ => 'Notice of Salary Adjustment',
};

/// Build a SALARY_CHANGE (pay-only) or ROLE_CHANGE (role moved) workflow with a
/// single DOCUMENT_GENERATION step wired to the pre-inserted DRAFT notice row.
WorkflowSeed seedCompensationChangeWorkflow({
  required String companyId,
  required String employeeId,
  required String employeeFullName,
  required String changeType,
  required String employeeDocumentId,
  required String initiatedById,
}) {
  final isRole =
      changeType == 'PROMOTION' ||
      changeType == 'LATERAL_TRANSFER' ||
      changeType == 'DEMOTION';
  final label = compensationDocTitle(changeType);
  return WorkflowSeed(
    instance: WorkflowInstanceInput(
      companyId: companyId,
      employeeId: employeeId,
      workflowType: isRole ? 'ROLE_CHANGE' : 'SALARY_CHANGE',
      title: '$label — $employeeFullName',
      context: {'change_type': changeType},
      initiatedById: initiatedById,
    ),
    steps: [
      WorkflowStepInput(
        stepIndex: 0,
        stepType: 'DOCUMENT_GENERATION',
        name: 'Generate $label',
        description: 'Render the $label PDF and mark this step complete.',
        inputData: {
          'template_id': 'salary_adjustment',
          'change_type': changeType,
          'employee_document_id': employeeDocumentId,
        },
        generatedDocumentId: employeeDocumentId,
      ),
    ],
  );
}
