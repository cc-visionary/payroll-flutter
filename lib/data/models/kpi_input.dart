import 'kpi_result.dart';

/// Where a manually-reported row came from. Recorded on every row from day
/// one — even while only one surface exists to write it — because provenance
/// cannot be retrofitted onto rows already collected. A future Lark sync
/// would be another caller of [KpiResultRepository]'s record methods, using
/// `LARK` here and `externalRef` for idempotency.
enum ReportedVia { app, lark }

const reportedViaCodes = {ReportedVia.app: 'APP', ReportedVia.lark: 'LARK'};

ReportedVia _reportedViaFromCode(String? code) => switch (code) {
  'LARK' => ReportedVia.lark,
  // 'APP' and anything else (an older row, a hand-built test) default to the
  // in-app surface — the only one that exists today.
  _ => ReportedVia.app,
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

DateTime _date(Object? v) => switch (v) {
  DateTime d => d,
  String s => DateTime.parse(s),
  _ => throw ArgumentError('expected a date, got $v'),
};

DateTime? _dateOrNull(Object? v) => v == null ? null : _date(v);

String _dateOnly(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// One occurrence of a confirmable exception — a purchasing error, a
/// confirmed fulfillment error, a piece of technical rework. Mirrors
/// `kpi_exceptions` (supabase/migrations/20260814000005_kpi_inputs.sql).
///
/// Deliberately not the same shape as [KpiReading]: an exception is a single
/// countable event with a date it happened on, a period reading is a number
/// someone counted for a whole period. Merging them behind a `kind` column
/// would force every consumer to branch on which fields are meaningful.
class KpiException {
  /// Null for a not-yet-written exception — the repository assigns a real id
  /// on insert.
  final String? id;
  final String companyId;
  final String kpiId;
  final String? employeeId;
  final String? departmentId;

  /// The day the exception HAPPENED, not the day it was recorded or
  /// confirmed. [confirmedCountFor] buckets by this field so a late
  /// confirmation still lands in the month the error occurred.
  final DateTime occurredOn;
  final num quantity;
  final String? note;
  final String? reportedBy;
  final ReportedVia reportedVia;

  /// A Lark record id (or similar) used to make a re-sync idempotent via the
  /// `unique (kpi_id, external_ref)` index. Null for anything entered
  /// directly in the app.
  final String? externalRef;

  /// Null until an HR/admin confirms the report actually happened.
  /// [confirmedCountFor] only counts rows where this is non-null — an
  /// unconfirmed claim must never move a KPI.
  final DateTime? confirmedAt;
  final String? confirmedBy;

  const KpiException({
    this.id,
    required this.companyId,
    required this.kpiId,
    this.employeeId,
    this.departmentId,
    required this.occurredOn,
    this.quantity = 1,
    this.note,
    this.reportedBy,
    required this.reportedVia,
    this.externalRef,
    this.confirmedAt,
    this.confirmedBy,
  });

  factory KpiException.fromRow(Map<String, dynamic> r) => KpiException(
    id: r['id'] as String?,
    companyId: r['company_id'] as String,
    kpiId: r['kpi_id'] as String,
    employeeId: r['employee_id'] as String?,
    departmentId: r['department_id'] as String?,
    occurredOn: _date(r['occurred_on']),
    quantity: _num(r['quantity']) ?? 1,
    note: r['note'] as String?,
    reportedBy: r['reported_by'] as String?,
    reportedVia: _reportedViaFromCode(r['reported_via'] as String?),
    externalRef: r['external_ref'] as String?,
    confirmedAt: _dateOrNull(r['confirmed_at']),
    confirmedBy: r['confirmed_by'] as String?,
  );

  Map<String, dynamic> toInsertPayload() => {
    'company_id': companyId,
    'kpi_id': kpiId,
    'employee_id': employeeId,
    'department_id': departmentId,
    'occurred_on': _dateOnly(occurredOn),
    'quantity': quantity,
    'note': note,
    'reported_by': reportedBy,
    'reported_via': reportedViaCodes[reportedVia],
    'external_ref': externalRef,
  };
}

/// A count someone reported for a whole period — "8 of 10 campaigns on time
/// this month". Mirrors `kpi_readings`
/// (supabase/migrations/20260814000005_kpi_inputs.sql), which shares its
/// `coalesce`-based unique identity with `kpi_results`: one reading per KPI
/// x period x scope.
class KpiReading {
  /// Null for a not-yet-written reading — the repository assigns a real id
  /// on insert.
  final String? id;
  final String companyId;
  final String kpiId;
  final String period;
  final KpiScope scope;
  final String? employeeId;
  final String? departmentId;
  final num? numerator;
  final num? denominator;
  final String? note;
  final String? reportedBy;
  final ReportedVia reportedVia;

  /// A Lark record id (or similar) used for idempotent re-sync. Null for
  /// anything entered directly in the app.
  final String? externalRef;

  const KpiReading({
    this.id,
    required this.companyId,
    required this.kpiId,
    required this.period,
    required this.scope,
    this.employeeId,
    this.departmentId,
    this.numerator,
    this.denominator,
    this.note,
    this.reportedBy,
    required this.reportedVia,
    this.externalRef,
  });

  factory KpiReading.fromRow(Map<String, dynamic> r) => KpiReading(
    id: r['id'] as String?,
    companyId: r['company_id'] as String,
    kpiId: r['kpi_id'] as String,
    period: r['period'] as String,
    scope: kpiScopeFromCode(r['scope'] as String?),
    employeeId: r['employee_id'] as String?,
    departmentId: r['department_id'] as String?,
    numerator: _num(r['numerator']),
    denominator: _num(r['denominator']),
    note: r['note'] as String?,
    reportedBy: r['reported_by'] as String?,
    reportedVia: _reportedViaFromCode(r['reported_via'] as String?),
    externalRef: r['external_ref'] as String?,
  );

  Map<String, dynamic> toInsertPayload() => {
    'company_id': companyId,
    'kpi_id': kpiId,
    'period': period,
    'scope': kpiScopeCodes[scope],
    'employee_id': employeeId,
    'department_id': departmentId,
    'numerator': numerator,
    'denominator': denominator,
    'note': note,
    'reported_by': reportedBy,
    'reported_via': reportedViaCodes[reportedVia],
    'external_ref': externalRef,
  };
}
