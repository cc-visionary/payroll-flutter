class ReviewCycle {
  final String id;
  final String companyId;
  final String name;
  final String reviewType;
  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime selfReviewDueDate;
  final DateTime managerReviewDueDate;
  final DateTime? finalizationDueDate;
  final String status;
  final String larkFormTemplateId;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ReviewCycle({
    required this.id,
    required this.companyId,
    required this.name,
    required this.reviewType,
    required this.periodStart,
    required this.periodEnd,
    required this.selfReviewDueDate,
    required this.managerReviewDueDate,
    this.finalizationDueDate,
    required this.status,
    required this.larkFormTemplateId,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ReviewCycle.fromRow(Map<String, dynamic> row) {
    DateTime date(Object value) => DateTime.parse(value as String);
    DateTime? optionalDate(Object? value) =>
        value == null ? null : DateTime.parse(value as String);
    return ReviewCycle(
      id: row['id'] as String,
      companyId: row['company_id'] as String,
      name: row['name'] as String,
      reviewType: row['review_type'] as String,
      periodStart: date(row['period_start']),
      periodEnd: date(row['period_end']),
      selfReviewDueDate: date(row['self_review_due_date']),
      managerReviewDueDate: date(row['manager_review_due_date']),
      finalizationDueDate: optionalDate(row['finalization_due_date']),
      status: row['status'] as String,
      larkFormTemplateId: row['lark_form_template_id'] as String,
      createdBy: row['created_by'] as String,
      createdAt: date(row['created_at']),
      updatedAt: date(row['updated_at']),
    );
  }
}
