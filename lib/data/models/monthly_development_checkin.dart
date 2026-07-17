class MonthlyGoalUpdate {
  final String id;
  final String goalId;
  final int progress;
  final String goalStatus;
  final String? progressNote;

  const MonthlyGoalUpdate({
    required this.id,
    required this.goalId,
    required this.progress,
    required this.goalStatus,
    this.progressNote,
  });

  factory MonthlyGoalUpdate.fromRow(Map<String, dynamic> row) =>
      MonthlyGoalUpdate(
        id: row['id'] as String,
        goalId: row['goal_id'] as String,
        progress: (row['progress'] as num).toInt(),
        goalStatus: row['goal_status'] as String,
        progressNote: row['progress_note'] as String?,
      );
}

class MonthlyDevelopmentCheckin {
  final String id;
  final String employeeId;
  final String managerId;
  final String sourceReviewId;
  final DateTime checkinDate;
  final String? whatWentWell;
  final String? needsAttention;
  final String? supportNeeded;
  final String agreedNextAction;
  final String actionOwnerId;
  final DateTime actionDueDate;
  final String generalStatus;
  final DateTime completedAt;
  final List<MonthlyGoalUpdate> goalUpdates;

  const MonthlyDevelopmentCheckin({
    required this.id,
    required this.employeeId,
    required this.managerId,
    required this.sourceReviewId,
    required this.checkinDate,
    this.whatWentWell,
    this.needsAttention,
    this.supportNeeded,
    required this.agreedNextAction,
    required this.actionOwnerId,
    required this.actionDueDate,
    required this.generalStatus,
    required this.completedAt,
    required this.goalUpdates,
  });

  factory MonthlyDevelopmentCheckin.fromRow(Map<String, dynamic> row) {
    final updates = row['monthly_checkin_goal_updates'];
    return MonthlyDevelopmentCheckin(
      id: row['id'] as String,
      employeeId: row['employee_id'] as String,
      managerId: row['manager_id'] as String,
      sourceReviewId: row['source_review_id'] as String,
      checkinDate: DateTime.parse(row['checkin_date'] as String),
      whatWentWell: row['what_went_well'] as String?,
      needsAttention: row['needs_attention'] as String?,
      supportNeeded: row['support_needed'] as String?,
      agreedNextAction: row['agreed_next_action'] as String,
      actionOwnerId: row['action_owner_id'] as String,
      actionDueDate: DateTime.parse(row['action_due_date'] as String),
      generalStatus: row['general_status'] as String,
      completedAt: DateTime.parse(row['completed_at'] as String),
      goalUpdates: updates is List
          ? updates
                .whereType<Map>()
                .map(
                  (item) => MonthlyGoalUpdate.fromRow(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList()
          : const [],
    );
  }
}
