/// Plain-Dart model mirroring the `performance_check_ins` table.
/// One row per employee per period. Constraint: unique (period_id, employee_id).
class PerformanceCheckIn {
  final String id;
  final String periodId;
  final String employeeId;
  final String? reviewerId;
  final String status;       // enum: DRAFT|SUBMITTED|UNDER_REVIEW|COMPLETED|SKIPPED
  final int? overallRating;  // 1-5
  final String? overallComments;
  final String? accomplishments;
  final String? challenges;
  final String? learnings;
  final String? supportNeeded;
  final String? managerFeedback;
  final String? strengths;
  final String? areasForImprovement;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PerformanceCheckIn({
    required this.id,
    required this.periodId,
    required this.employeeId,
    this.reviewerId,
    required this.status,
    this.overallRating,
    this.overallComments,
    this.accomplishments,
    this.challenges,
    this.learnings,
    this.supportNeeded,
    this.managerFeedback,
    this.strengths,
    this.areasForImprovement,
    this.submittedAt,
    this.reviewedAt,
    required this.createdAt,
    required this.updatedAt,
  });
}

extension PerformanceCheckInFromRow on PerformanceCheckIn {
  static PerformanceCheckIn fromRow(Map<String, dynamic> r) {
    DateTime? dt(Object? v) => v == null ? null : DateTime.parse(v as String);
    return PerformanceCheckIn(
      id: r['id'] as String,
      periodId: r['period_id'] as String,
      employeeId: r['employee_id'] as String,
      reviewerId: r['reviewer_id'] as String?,
      status: r['status'] as String,
      overallRating: (r['overall_rating'] as num?)?.toInt(),
      overallComments: r['overall_comments'] as String?,
      accomplishments: r['accomplishments'] as String?,
      challenges: r['challenges'] as String?,
      learnings: r['learnings'] as String?,
      supportNeeded: r['support_needed'] as String?,
      managerFeedback: r['manager_feedback'] as String?,
      strengths: r['strengths'] as String?,
      areasForImprovement: r['areas_for_improvement'] as String?,
      submittedAt: dt(r['submitted_at']),
      reviewedAt: dt(r['reviewed_at']),
      createdAt: dt(r['created_at'])!,
      updatedAt: dt(r['updated_at'])!,
    );
  }
}
