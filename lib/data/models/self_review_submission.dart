class SelfReviewSubmission {
  final String id;
  final String reviewId;
  final String employeeId;
  final int versionNumber;
  final int formVersion;
  final String? externalSubmissionId;
  final String? accomplishments;
  final String? challenges;
  final String? learnings;
  final String? desiredDevelopmentArea;
  final String? supportNeeded;
  final String? additionalComments;
  final List<Map<String, dynamic>> attachments;
  final DateTime submittedAt;
  final bool isActive;
  final String? supersededById;

  const SelfReviewSubmission({
    required this.id,
    required this.reviewId,
    required this.employeeId,
    required this.versionNumber,
    required this.formVersion,
    this.externalSubmissionId,
    this.accomplishments,
    this.challenges,
    this.learnings,
    this.desiredDevelopmentArea,
    this.supportNeeded,
    this.additionalComments,
    required this.attachments,
    required this.submittedAt,
    required this.isActive,
    this.supersededById,
  });

  factory SelfReviewSubmission.fromRow(Map<String, dynamic> row) {
    final rawAttachments = row['attachments'];
    return SelfReviewSubmission(
      id: row['id'] as String,
      reviewId: row['review_id'] as String,
      employeeId: row['employee_id'] as String,
      versionNumber: (row['version_number'] as num).toInt(),
      formVersion: (row['form_version'] as num).toInt(),
      externalSubmissionId: row['external_submission_id'] as String?,
      accomplishments: row['accomplishments'] as String?,
      challenges: row['challenges'] as String?,
      learnings: row['learnings'] as String?,
      desiredDevelopmentArea: row['desired_development_area'] as String?,
      supportNeeded: row['support_needed'] as String?,
      additionalComments: row['additional_comments'] as String?,
      attachments: rawAttachments is List
          ? rawAttachments
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
          : const [],
      submittedAt: DateTime.parse(row['submitted_at'] as String),
      isActive: row['is_active'] as bool? ?? false,
      supersededById: row['superseded_by_id'] as String?,
    );
  }
}
