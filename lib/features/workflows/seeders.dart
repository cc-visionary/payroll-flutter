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
    steps.add(WorkflowStepInput(
      stepIndex: i,
      stepType: 'DOCUMENT_GENERATION',
      name: 'Generate $label',
      description: 'Render the $label PDF and mark this step complete.',
      inputData: {
        'template_id': templateId,
        'employee_document_id': docIdByType[type],
      },
      generatedDocumentId: docIdByType[type],
    ));
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
