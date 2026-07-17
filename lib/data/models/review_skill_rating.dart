class ReviewSkillRating {
  final String id;
  final String reviewId;
  final int snapshotOrder;
  final String skillName;
  final String? skillDescription;
  final String skillCategory;
  final int? managerRating;
  final String? employeeComment;
  final String? managerComment;
  final bool developmentNeeded;

  const ReviewSkillRating({
    required this.id,
    required this.reviewId,
    required this.snapshotOrder,
    required this.skillName,
    this.skillDescription,
    required this.skillCategory,
    this.managerRating,
    this.employeeComment,
    this.managerComment,
    required this.developmentNeeded,
  });

  factory ReviewSkillRating.fromRow(Map<String, dynamic> row) =>
      ReviewSkillRating(
        id: row['id'] as String,
        reviewId: row['review_id'] as String,
        snapshotOrder: (row['snapshot_order'] as num).toInt(),
        skillName: row['skill_name'] as String,
        skillDescription: row['skill_description'] as String?,
        skillCategory: row['skill_category'] as String,
        managerRating: (row['manager_rating'] as num?)?.toInt(),
        employeeComment: row['employee_comment'] as String?,
        managerComment: row['manager_comment'] as String?,
        developmentNeeded: row['development_needed'] as bool? ?? false,
      );
}
