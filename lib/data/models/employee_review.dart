class EmployeeReview {
  final String id;
  final String reviewCycleId;
  final String employeeId;
  final String employeeNameSnapshot;
  final String responsibilityCardId;
  final int responsibilityCardVersion;
  final String directManagerId;
  final String reviewType;
  final DateTime reviewPeriodStart;
  final DateTime reviewPeriodEnd;
  final String status;
  final List<Map<String, dynamic>> responsibilitySnapshot;
  final double? overallRating;
  final String? overallOutcome;
  final String? finalizedBy;
  final DateTime? finalizedAt;
  final DateTime? discussionDate;
  final String? discussionNotes;
  final DateTime? discussionCompletedAt;
  final DateTime? reopenedAt;
  final String? reopenReason;
  final DateTime createdAt;
  final DateTime updatedAt;

  const EmployeeReview({
    required this.id,
    required this.reviewCycleId,
    required this.employeeId,
    required this.employeeNameSnapshot,
    required this.responsibilityCardId,
    required this.responsibilityCardVersion,
    required this.directManagerId,
    required this.reviewType,
    required this.reviewPeriodStart,
    required this.reviewPeriodEnd,
    required this.status,
    required this.responsibilitySnapshot,
    this.overallRating,
    this.overallOutcome,
    this.finalizedBy,
    this.finalizedAt,
    this.discussionDate,
    this.discussionNotes,
    this.discussionCompletedAt,
    this.reopenedAt,
    this.reopenReason,
    required this.createdAt,
    required this.updatedAt,
  });

  factory EmployeeReview.fromRow(Map<String, dynamic> row) {
    DateTime date(Object value) => DateTime.parse(value as String);
    DateTime? optionalDate(Object? value) =>
        value == null ? null : DateTime.parse(value as String);
    final rawResponsibilities = row['responsibility_snapshot'];
    return EmployeeReview(
      id: row['id'] as String,
      reviewCycleId: row['review_cycle_id'] as String,
      employeeId: row['employee_id'] as String,
      employeeNameSnapshot: row['employee_name_snapshot'] as String,
      responsibilityCardId: row['responsibility_card_id'] as String,
      responsibilityCardVersion: (row['responsibility_card_version'] as num)
          .toInt(),
      directManagerId: row['direct_manager_id'] as String,
      reviewType: row['review_type'] as String,
      reviewPeriodStart: date(row['review_period_start']),
      reviewPeriodEnd: date(row['review_period_end']),
      status: row['status'] as String,
      responsibilitySnapshot: rawResponsibilities is List
          ? rawResponsibilities
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
          : const [],
      overallRating: (row['overall_rating'] as num?)?.toDouble(),
      overallOutcome: row['overall_outcome'] as String?,
      finalizedBy: row['finalized_by'] as String?,
      finalizedAt: optionalDate(row['finalized_at']),
      discussionDate: optionalDate(row['discussion_date']),
      discussionNotes: row['discussion_notes'] as String?,
      discussionCompletedAt: optionalDate(row['discussion_completed_at']),
      reopenedAt: optionalDate(row['reopened_at']),
      reopenReason: row['reopen_reason'] as String?,
      createdAt: date(row['created_at']),
      updatedAt: date(row['updated_at']),
    );
  }
}
