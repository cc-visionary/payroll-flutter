/// Plain-Dart model mirroring the `skill_ratings` table.
///
/// `skill_name` is a snapshot of the employee's `RoleScorecard.kpis[i].name`
/// at check-in creation time. This is intentional — historical reviews must
/// not drift when KPIs are later edited on the scorecard.
class SkillRating {
  final String id;
  final String checkInId;
  final String skillCategory;
  final String skillName;
  final int? selfRating; // 1-5
  final int? managerRating; // 1-5
  final String? comments;
  final String? developmentPlan;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SkillRating({
    required this.id,
    required this.checkInId,
    required this.skillCategory,
    required this.skillName,
    this.selfRating,
    this.managerRating,
    this.comments,
    this.developmentPlan,
    required this.createdAt,
    required this.updatedAt,
  });
}

extension SkillRatingFromRow on SkillRating {
  static SkillRating fromRow(Map<String, dynamic> r) {
    DateTime dt(Object v) => DateTime.parse(v as String);
    return SkillRating(
      id: r['id'] as String,
      checkInId: r['check_in_id'] as String,
      skillCategory: r['skill_category'] as String,
      skillName: r['skill_name'] as String,
      selfRating: (r['self_rating'] as num?)?.toInt(),
      managerRating: (r['manager_rating'] as num?)?.toInt(),
      comments: r['comments'] as String?,
      developmentPlan: r['development_plan'] as String?,
      createdAt: dt(r['created_at']),
      updatedAt: dt(r['updated_at']),
    );
  }
}
