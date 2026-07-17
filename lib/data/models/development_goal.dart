class DevelopmentGoal {
  final String id;
  final String employeeId;
  final String? sourceReviewId;
  final String goalType;
  final String title;
  final String? description;
  final String? baseline;
  final String target;
  final DateTime startDate;
  final DateTime dueDate;
  final String ownerId;
  final String managerId;
  final String? trainerId;
  final int progress;
  final String status;
  final String? evidenceRequired;

  const DevelopmentGoal({
    required this.id,
    required this.employeeId,
    this.sourceReviewId,
    required this.goalType,
    required this.title,
    this.description,
    this.baseline,
    required this.target,
    required this.startDate,
    required this.dueDate,
    required this.ownerId,
    required this.managerId,
    this.trainerId,
    required this.progress,
    required this.status,
    this.evidenceRequired,
  });

  factory DevelopmentGoal.fromRow(Map<String, dynamic> row) => DevelopmentGoal(
    id: row['id'] as String,
    employeeId: row['employee_id'] as String,
    sourceReviewId: row['source_review_id'] as String?,
    goalType: row['goal_type'] as String,
    title: row['title'] as String,
    description: row['description'] as String?,
    baseline: row['baseline'] as String?,
    target: row['target'] as String,
    startDate: DateTime.parse(row['start_date'] as String),
    dueDate: DateTime.parse(row['due_date'] as String),
    ownerId: row['owner_id'] as String,
    managerId: row['manager_id'] as String,
    trainerId: row['trainer_id'] as String?,
    progress: (row['progress'] as num?)?.toInt() ?? 0,
    status: row['status'] as String? ?? 'NOT_STARTED',
    evidenceRequired: row['evidence_required'] as String?,
  );
}
