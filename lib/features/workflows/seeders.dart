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
  'NDA': 'NDA',
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

/// Build a HIRING workflow with 4 default onboarding steps. Each step is a
/// STATUS_UPDATE that HR manually marks complete as the onboarding work
/// happens. Schema supports per-step assignment via `assigned_to_id` — v1
/// leaves it null (implicitly assigned to whoever initiated the workflow).
WorkflowSeed seedHiringWorkflow({
  required String companyId,
  required String employeeId,
  required String employeeFullName,
  required String applicantId,
  required String initiatedById,
}) {
  const onboardingSteps = <String>[
    'IT account & email setup',
    'Equipment provisioning (laptop, peripherals)',
    'Day-1 orientation completed',
    '30-day check-in completed',
  ];
  final steps = <WorkflowStepInput>[
    for (var i = 0; i < onboardingSteps.length; i++)
      WorkflowStepInput(
        stepIndex: i,
        stepType: 'STATUS_UPDATE',
        name: onboardingSteps[i],
      ),
  ];
  return WorkflowSeed(
    instance: WorkflowInstanceInput(
      companyId: companyId,
      employeeId: employeeId,
      workflowType: 'HIRING',
      title: 'Hiring — $employeeFullName',
      context: {'applicant_id': applicantId},
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
