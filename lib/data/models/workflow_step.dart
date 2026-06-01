/// Plain-Dart model mirroring the `workflow_steps` table from
/// supabase/migrations/20260414000013_workflows.sql.
class WorkflowStep {
  final String id;
  final String workflowInstanceId;
  final int stepIndex;
  final String stepType;        // enum: DATA_ENTRY|APPROVAL|DOCUMENT_GENERATION|STATUS_UPDATE|REVIEW
  final String name;
  final String? description;
  final String status;          // enum: PENDING|IN_PROGRESS|COMPLETED|SKIPPED|REJECTED
  final String? assignedToId;
  final Map<String, dynamic>? inputData;
  final Map<String, dynamic>? outputData;
  final String? completedById;
  final DateTime? completedAt;
  final String? remarks;
  final String? generatedDocumentId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const WorkflowStep({
    required this.id,
    required this.workflowInstanceId,
    required this.stepIndex,
    required this.stepType,
    required this.name,
    this.description,
    required this.status,
    this.assignedToId,
    this.inputData,
    this.outputData,
    this.completedById,
    this.completedAt,
    this.remarks,
    this.generatedDocumentId,
    required this.createdAt,
    required this.updatedAt,
  });
}

extension WorkflowStepFromRow on WorkflowStep {
  static WorkflowStep fromRow(Map<String, dynamic> r) {
    DateTime? dt(Object? v) => v == null ? null : DateTime.parse(v as String);
    return WorkflowStep(
      id: r['id'] as String,
      workflowInstanceId: r['workflow_instance_id'] as String,
      stepIndex: (r['step_index'] as num).toInt(),
      stepType: r['step_type'] as String,
      name: r['name'] as String,
      description: r['description'] as String?,
      status: r['status'] as String,
      assignedToId: r['assigned_to_id'] as String?,
      inputData: r['input_data'] as Map<String, dynamic>?,
      outputData: r['output_data'] as Map<String, dynamic>?,
      completedById: r['completed_by_id'] as String?,
      completedAt: dt(r['completed_at']),
      remarks: r['remarks'] as String?,
      generatedDocumentId: r['generated_document_id'] as String?,
      createdAt: dt(r['created_at'])!,
      updatedAt: dt(r['updated_at'])!,
    );
  }
}
