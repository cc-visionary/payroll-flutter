class SelfReviewRequest {
  final String id;
  final String reviewId;
  final String reviewCycleId;
  final String employeeId;
  final int formVersion;
  final String status;
  final String? formLink;
  final String? larkMessageId;
  final DateTime? sentAt;
  final int attemptCount;
  final String? errorMessage;

  const SelfReviewRequest({
    required this.id,
    required this.reviewId,
    required this.reviewCycleId,
    required this.employeeId,
    required this.formVersion,
    required this.status,
    this.formLink,
    this.larkMessageId,
    this.sentAt,
    required this.attemptCount,
    this.errorMessage,
  });

  factory SelfReviewRequest.fromRow(Map<String, dynamic> row) =>
      SelfReviewRequest(
        id: row['id'] as String,
        reviewId: row['review_id'] as String,
        reviewCycleId: row['review_cycle_id'] as String,
        employeeId: row['employee_id'] as String,
        formVersion: (row['form_version'] as num).toInt(),
        status: row['status'] as String,
        formLink: row['form_link'] as String?,
        larkMessageId: row['lark_message_id'] as String?,
        sentAt: row['sent_at'] == null
            ? null
            : DateTime.parse(row['sent_at'] as String),
        attemptCount: (row['attempt_count'] as num?)?.toInt() ?? 0,
        errorMessage: row['error_message'] as String?,
      );
}
