/// Plain-Dart model mirroring the `workflow_instances` table from
/// supabase/migrations/20260414000013_workflows.sql.
///
/// One row = one HR process per employee (a SEPARATION case, a HIRING case,
/// etc.). FK to `employees`; the workflow never duplicates employee data.
class WorkflowInstance {
  final String id;
  final String companyId;
  final String employeeId;
  final String
  workflowType; // enum: HIRING|REGULARIZATION|SALARY_CHANGE|ROLE_CHANGE|DISCIPLINARY|SEPARATION|REPAYMENT_AGREEMENT
  final String status; // enum: DRAFT|IN_PROGRESS|COMPLETED|CANCELLED
  final String title;
  final Map<String, dynamic> context;
  final Map<String, dynamic>? result;
  final String initiatedById;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final String? cancelReason;
  final DateTime createdAt;
  final DateTime updatedAt;

  const WorkflowInstance({
    required this.id,
    required this.companyId,
    required this.employeeId,
    required this.workflowType,
    required this.status,
    required this.title,
    required this.context,
    this.result,
    required this.initiatedById,
    this.completedAt,
    this.cancelledAt,
    this.cancelReason,
    required this.createdAt,
    required this.updatedAt,
  });
}

extension WorkflowInstanceFromRow on WorkflowInstance {
  static WorkflowInstance fromRow(Map<String, dynamic> r) {
    DateTime? dt(Object? v) => v == null ? null : DateTime.parse(v as String);
    return WorkflowInstance(
      id: r['id'] as String,
      companyId: r['company_id'] as String,
      employeeId: r['employee_id'] as String,
      workflowType: r['workflow_type'] as String,
      status: r['status'] as String,
      title: r['title'] as String,
      context: (r['context'] as Map<String, dynamic>?) ?? const {},
      result: r['result'] as Map<String, dynamic>?,
      initiatedById: r['initiated_by_id'] as String,
      completedAt: dt(r['completed_at']),
      cancelledAt: dt(r['cancelled_at']),
      cancelReason: r['cancel_reason'] as String?,
      createdAt: dt(r['created_at'])!,
      updatedAt: dt(r['updated_at'])!,
    );
  }
}
