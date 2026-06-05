class JobListing {
  final String id;
  final String companyId;
  final String hiringEntityId;
  final String roleScorecardId;
  final String title;
  final int targetHeadcount;
  final String status; // 'OPEN' | 'PAUSED' | 'CLOSED'
  final String? notes;
  final DateTime createdAt;
  final String? createdById;
  final DateTime? closedAt;
  final DateTime? deletedAt;

  const JobListing({
    required this.id,
    required this.companyId,
    required this.hiringEntityId,
    required this.roleScorecardId,
    required this.title,
    required this.targetHeadcount,
    required this.status,
    this.notes,
    required this.createdAt,
    this.createdById,
    this.closedAt,
    this.deletedAt,
  });

  factory JobListing.fromRow(Map<String, dynamic> r) => JobListing(
    id: r['id'] as String,
    companyId: r['company_id'] as String,
    hiringEntityId: r['hiring_entity_id'] as String,
    roleScorecardId: r['role_scorecard_id'] as String,
    title: r['title'] as String,
    targetHeadcount: r['target_headcount'] as int,
    status: r['status'] as String,
    notes: r['notes'] as String?,
    createdAt: DateTime.parse(r['created_at'] as String),
    createdById: r['created_by_id'] as String?,
    closedAt: r['closed_at'] == null
        ? null
        : DateTime.parse(r['closed_at'] as String),
    deletedAt: r['deleted_at'] == null
        ? null
        : DateTime.parse(r['deleted_at'] as String),
  );

  Map<String, dynamic> toUpsertPayload() => {
    'id': id,
    'company_id': companyId,
    'hiring_entity_id': hiringEntityId,
    'role_scorecard_id': roleScorecardId,
    'title': title,
    'target_headcount': targetHeadcount,
    'status': status,
    'notes': notes,
    if (closedAt != null) 'closed_at': closedAt!.toIso8601String(),
    if (deletedAt != null) 'deleted_at': deletedAt!.toIso8601String(),
  };

  JobListing copyWith({
    String? id,
    String? companyId,
    String? hiringEntityId,
    String? roleScorecardId,
    String? title,
    int? targetHeadcount,
    String? status,
    Object? notes = _undef,
    DateTime? createdAt,
    Object? createdById = _undef,
    Object? closedAt = _undef,
    Object? deletedAt = _undef,
  }) => JobListing(
    id: id ?? this.id,
    companyId: companyId ?? this.companyId,
    hiringEntityId: hiringEntityId ?? this.hiringEntityId,
    roleScorecardId: roleScorecardId ?? this.roleScorecardId,
    title: title ?? this.title,
    targetHeadcount: targetHeadcount ?? this.targetHeadcount,
    status: status ?? this.status,
    notes: identical(notes, _undef) ? this.notes : notes as String?,
    createdAt: createdAt ?? this.createdAt,
    createdById: identical(createdById, _undef)
        ? this.createdById
        : createdById as String?,
    closedAt: identical(closedAt, _undef)
        ? this.closedAt
        : closedAt as DateTime?,
    deletedAt: identical(deletedAt, _undef)
        ? this.deletedAt
        : deletedAt as DateTime?,
  );
}

const _undef = Object();
