class ManagerReview {
  final String id;
  final String reviewId;
  final String? overallFeedback;
  final String? performanceConcerns;
  final String? supportManagerWillProvide;
  final String? readinessForAdditionalDuties;
  final List<Map<String, dynamic>> strengths;
  final List<Map<String, dynamic>> developmentAreas;
  final String? recommendedOutcome;
  final DateTime? submittedAt;

  const ManagerReview({
    required this.id,
    required this.reviewId,
    this.overallFeedback,
    this.performanceConcerns,
    this.supportManagerWillProvide,
    this.readinessForAdditionalDuties,
    required this.strengths,
    required this.developmentAreas,
    this.recommendedOutcome,
    this.submittedAt,
  });

  factory ManagerReview.fromRow(Map<String, dynamic> row) => ManagerReview(
    id: row['id'] as String,
    reviewId: row['review_id'] as String,
    overallFeedback: row['overall_feedback'] as String?,
    performanceConcerns: row['performance_concerns'] as String?,
    supportManagerWillProvide: row['support_manager_will_provide'] as String?,
    readinessForAdditionalDuties:
        row['readiness_for_additional_duties'] as String?,
    strengths: _list(row['strengths']),
    developmentAreas: _list(row['development_areas']),
    recommendedOutcome: row['recommended_outcome'] as String?,
    submittedAt: row['submitted_at'] == null
        ? null
        : DateTime.parse(row['submitted_at'] as String),
  );
}

List<Map<String, dynamic>> _list(Object? value) => value is List
    ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
    : const [];
