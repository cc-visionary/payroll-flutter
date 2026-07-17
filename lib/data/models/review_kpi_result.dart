class ReviewKpiResult {
  final String id;
  final String reviewId;
  final int snapshotOrder;
  final String kpiName;
  final String? description;
  final String? measurementUnit;
  final String? targetValue;
  final String? checkFrequency;
  final String? actualValue;
  final bool isQualitative;
  final String? resultStatus;
  final int? managerRating;
  final String? managerComment;
  final String source;

  const ReviewKpiResult({
    required this.id,
    required this.reviewId,
    required this.snapshotOrder,
    required this.kpiName,
    this.description,
    this.measurementUnit,
    this.targetValue,
    this.checkFrequency,
    this.actualValue,
    required this.isQualitative,
    this.resultStatus,
    this.managerRating,
    this.managerComment,
    required this.source,
  });

  factory ReviewKpiResult.fromRow(Map<String, dynamic> row) => ReviewKpiResult(
    id: row['id'] as String,
    reviewId: row['review_id'] as String,
    snapshotOrder: (row['snapshot_order'] as num).toInt(),
    kpiName: row['kpi_name'] as String,
    description: row['description'] as String?,
    measurementUnit: row['measurement_unit'] as String?,
    targetValue: row['target_value'] as String?,
    checkFrequency: row['check_frequency'] as String?,
    actualValue: row['actual_value'] as String?,
    isQualitative: row['is_qualitative'] as bool? ?? false,
    resultStatus: row['result_status'] as String?,
    managerRating: (row['manager_rating'] as num?)?.toInt(),
    managerComment: row['manager_comment'] as String?,
    source: row['source'] as String? ?? 'MANUAL',
  );
}
