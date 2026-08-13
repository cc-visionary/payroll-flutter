/// A desired outcome, scoped to a role AND one of its accountability areas —
/// what should be TRUE if the area's work is done well ("customers receive
/// the correct product"), sitting between the area's responsibilities and
/// the KPI that proves it. See role_outcomes (20260814000002).
///
/// [responsibilityArea] is a plain string match against
/// `wp_tasks.responsibility_area`, NOT a foreign key: accountability areas
/// are not rows in this schema, they are the grouping string `areasByRole()`
/// (lib/features/workforce_planning/role_structure.dart) derives from the
/// role's tasks. Nothing enforces that link at the database level, so
/// renaming an area does not rename or move the outcomes filed under its old
/// name — they are orphaned (still stored, no longer matched by the new
/// name) until something re-files them by hand.
class RoleOutcome {
  final String id;
  final String companyId;
  final String roleScorecardId;
  final String responsibilityArea;
  final String text;
  final int sortOrder;

  const RoleOutcome({
    required this.id,
    required this.companyId,
    required this.roleScorecardId,
    required this.responsibilityArea,
    required this.text,
    this.sortOrder = 0,
  });

  factory RoleOutcome.fromRow(Map<String, dynamic> r) => RoleOutcome(
    id: r['id'] as String,
    companyId: r['company_id'] as String,
    roleScorecardId: r['role_scorecard_id'] as String,
    responsibilityArea: r['responsibility_area'] as String,
    text: r['text'] as String,
    sortOrder: r['sort_order'] as int? ?? 0,
  );

  Map<String, dynamic> toUpsertPayload() => {
    'id': id,
    'company_id': companyId,
    'role_scorecard_id': roleScorecardId,
    'responsibility_area': responsibilityArea,
    'text': text,
    'sort_order': sortOrder,
  };
}
