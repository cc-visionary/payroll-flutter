import 'kpi_goal.dart';

/// The three levels a KPI result can be computed at.
enum KpiScope { personal, department, company }

/// A period's verdict on one KPI.
///
/// [noData] is NOT a soft failure — it means the engine could not form a
/// judgement, and it must never render as red. Red means data existed and the
/// target was missed. Conflating them trains people to ignore red.
enum KpiStatus { onTrack, offTrack, noData }

const kpiScopeCodes = {
  KpiScope.personal: 'PERSONAL',
  KpiScope.department: 'DEPARTMENT',
  KpiScope.company: 'COMPANY',
};

const kpiStatusCodes = {
  KpiStatus.onTrack: 'ON_TRACK',
  KpiStatus.offTrack: 'OFF_TRACK',
  KpiStatus.noData: 'NO_DATA',
};

/// Shared with `kpi_input.dart` — `kpi_exceptions`/`kpi_readings` reuse the
/// same `scope` vocabulary and CHECK constraint as `kpi_results`.
KpiScope kpiScopeFromCode(String? code) => switch (code) {
  'PERSONAL' => KpiScope.personal,
  'DEPARTMENT' => KpiScope.department,
  'COMPANY' => KpiScope.company,
  // scope is NOT NULL with a CHECK constraint in kpi_results (and mirrored
  // in kpi_readings), so a real row can never carry anything else. Throwing
  // loudly here beats guessing a scope for a row whose actual scope is
  // unknown.
  _ => throw ArgumentError('unrecognized kpi_results.scope: $code'),
};

KpiStatus _kpiStatusFromCode(String? code) => switch (code) {
  'ON_TRACK' => KpiStatus.onTrack,
  'OFF_TRACK' => KpiStatus.offTrack,
  // Same fail-toward-absence rule the status column itself encodes: an
  // unrecognized code is treated as "no judgement", never as a silent
  // ON_TRACK/OFF_TRACK guess.
  _ => KpiStatus.noData,
};

/// Whether a result's inputs came from a fully wired source, or from one that
/// could not be read this period (an integration outage, a channel not yet
/// connected). Distinct from [KpiStatus.noData]: a KPI can have no goal set
/// and still be [SourceCompleteness.complete], or have a goal, a value, and
/// still be [SourceCompleteness.missingSource] because only part of its data
/// arrived.
enum SourceCompleteness { complete, missingSource }

const sourceCompletenessCodes = {
  SourceCompleteness.complete: 'COMPLETE',
  SourceCompleteness.missingSource: 'MISSING_SOURCE',
};

SourceCompleteness _sourceCompletenessFromCode(String? code) => switch (code) {
  'COMPLETE' => SourceCompleteness.complete,
  // Mirrors the column's own `default 'COMPLETE'` for a genuinely absent
  // key (an older select list, a hand-built test row) — but anything present
  // and unrecognized fails toward the pessimistic reading rather than the
  // reassuring one.
  null => SourceCompleteness.complete,
  _ => SourceCompleteness.missingSource,
};

/// Postgres numerics can arrive as int, double or String depending on the
/// driver — normalize all three without forcing a widening to double, so an
/// integer count round-trips as an integer.
num? _num(Object? v) => switch (v) {
  null => null,
  num n => n,
  String s => num.tryParse(s),
  _ => null,
};

/// One period's verdict on one KPI at one scope.
/// Mirrors `kpi_results` (supabase/migrations/20260814000004_kpi_results.sql).
///
/// Results are DERIVED, never hand-entered — every column is reproducible
/// from raw inputs plus the KPI's definition. A manual reading lives in
/// `kpi_readings` instead; anything written by hand into this table would be
/// destroyed by the next recompute, or would force the recompute to guess
/// which rows are safe to overwrite.
class KpiResult {
  /// Null for a freshly-computed result that has not been written yet — the
  /// repository discovers the real id (if one already exists for this key)
  /// by reading the period first, never by trusting this field on write.
  final String? id;
  final String companyId;
  final String kpiId;
  final String period;
  final KpiScope scope;
  final String? employeeId;
  final String? departmentId;
  final num? numerator;
  final num? denominator;
  final num? value;
  final num? targetSnapshot;
  final num? targetMaxSnapshot;
  final GoalDirection? direction;
  final KpiStatus status;
  final SourceCompleteness sourceCompleteness;

  const KpiResult({
    this.id,
    required this.companyId,
    required this.kpiId,
    required this.period,
    required this.scope,
    this.employeeId,
    this.departmentId,
    this.numerator,
    this.denominator,
    this.value,
    this.targetSnapshot,
    this.targetMaxSnapshot,
    this.direction,
    required this.status,
    this.sourceCompleteness = SourceCompleteness.complete,
  });

  factory KpiResult.fromRow(Map<String, dynamic> r) => KpiResult(
    id: r['id'] as String?,
    companyId: r['company_id'] as String,
    kpiId: r['kpi_id'] as String,
    period: r['period'] as String,
    scope: kpiScopeFromCode(r['scope'] as String?),
    employeeId: r['employee_id'] as String?,
    departmentId: r['department_id'] as String?,
    numerator: _num(r['numerator']),
    denominator: _num(r['denominator']),
    value: _num(r['value']),
    targetSnapshot: _num(r['target_snapshot']),
    targetMaxSnapshot: _num(r['target_max_snapshot']),
    direction: goalDirectionFromCode(r['direction_snapshot'] as String?),
    status: _kpiStatusFromCode(r['status'] as String?),
    sourceCompleteness: _sourceCompletenessFromCode(
      r['source_completeness'] as String?,
    ),
  );

  /// Every writable column, including explicit nulls. A NO_DATA row's null
  /// numerator/value must stay null in this map, not silently drop out of
  /// it — an omitted key and an explicit null look identical to callers that
  /// only check `containsKey`, but PostgREST treats a dropped key as "leave
  /// the existing value alone" on an update, which would let a stale nonzero
  /// reading survive under a fresh NO_DATA verdict.
  Map<String, dynamic> toUpsertPayload() => {
    'id': id,
    'company_id': companyId,
    'kpi_id': kpiId,
    'period': period,
    'scope': kpiScopeCodes[scope],
    'employee_id': employeeId,
    'department_id': departmentId,
    'numerator': numerator,
    'denominator': denominator,
    'value': value,
    'target_snapshot': targetSnapshot,
    'target_max_snapshot': targetMaxSnapshot,
    'direction_snapshot': direction == null
        ? null
        : goalDirectionCode(direction!),
    'status': kpiStatusCodes[status],
    'source_completeness': sourceCompletenessCodes[sourceCompleteness],
  };
}
