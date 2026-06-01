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
