/// Plain-Dart model mirroring the `check_in_goals` table.
/// One goal row per check-in (cascade-delete with parent check-in).
class CheckInGoal {
  final String id;
  final String checkInId;
  final String goalType;     // enum: PERFORMANCE|LEARNING|PROJECT|BEHAVIORAL
  final String title;
  final String? description;
  final DateTime? targetDate;
  final int progress;        // 0-100
  final String status;       // enum: NOT_STARTED|IN_PROGRESS|COMPLETED|PARTIALLY_MET|NOT_MET|DEFERRED
  final String? selfAssessment;
  final String? managerAssessment;
  final int? rating;         // 1-5
  final bool carryForward;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CheckInGoal({
    required this.id,
    required this.checkInId,
    required this.goalType,
    required this.title,
    this.description,
    this.targetDate,
    required this.progress,
    required this.status,
    this.selfAssessment,
    this.managerAssessment,
    this.rating,
    required this.carryForward,
    required this.createdAt,
    required this.updatedAt,
  });
}

extension CheckInGoalFromRow on CheckInGoal {
  static CheckInGoal fromRow(Map<String, dynamic> r) {
    DateTime? dt(Object? v) => v == null ? null : DateTime.parse(v as String);
    return CheckInGoal(
      id: r['id'] as String,
      checkInId: r['check_in_id'] as String,
      goalType: r['goal_type'] as String,
      title: r['title'] as String,
      description: r['description'] as String?,
      targetDate: dt(r['target_date']),
      progress: (r['progress'] as num).toInt(),
      status: r['status'] as String,
      selfAssessment: r['self_assessment'] as String?,
      managerAssessment: r['manager_assessment'] as String?,
      rating: (r['rating'] as num?)?.toInt(),
      carryForward: r['carry_forward'] as bool,
      createdAt: dt(r['created_at'])!,
      updatedAt: dt(r['updated_at'])!,
    );
  }
}
