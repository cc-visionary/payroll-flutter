import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/kpi_input.dart';
import '../models/kpi_result.dart';

/// Reads and writes `kpi_results` (supabase/migrations/20260814000004_kpi_results.sql),
/// plus the two ingestion-boundary tables results are derived from,
/// `kpi_exceptions` and `kpi_readings`
/// (supabase/migrations/20260814000005_kpi_inputs.sql) — see the class's
/// ingestion-boundary methods near the bottom of this file.
///
/// The results table's real uniqueness constraint is a functional (expression) index
/// on `coalesce(employee_id, ...)` / `coalesce(department_id, ...)` — Postgres
/// treats NULLs as distinct, so a plain unique constraint over the nullable
/// scope columns would let unlimited duplicate COMPANY rows through.
/// PostgREST's `onConflict` can only name a plain unique index by its column
/// list, not an expression index, so [upsertAll] deliberately never calls
/// `.upsert(...)`. See the note on `upsertKpi` in role_scorecard_repository.dart
/// for the first place this repo hit the same trap.
///
/// **Not paginated.** [listByPeriod] reads (and [upsertAll]'s find-then-insert
/// path re-reads) a whole period in one PostgREST call, so both are exposed to
/// the same `max_rows` truncation already tracked for attendance
/// (`attendance_repository.dart`'s `fetchAllPages`) and flagged as an open
/// decision for payroll_repository. A company with enough KPIs x scopes x
/// employees to exceed the cap in one period would silently see a partial
/// results screen and, worse, a recompute that "updates" rows it never
/// re-read (falling through to a duplicate insert instead). Not fixed here --
/// recorded so the next reader doesn't have to rediscover it.
class KpiResultRepository {
  KpiResultRepository(this._client);

  final SupabaseClient _client;

  /// All rows for [period], optionally narrowed to one KPI. RLS (not this
  /// filter) is what scopes the result to the caller's company.
  Future<List<KpiResult>> listByPeriod(String period, {String? kpiId}) async {
    var q = _client.from('kpi_results').select().eq('period', period);
    if (kpiId != null) q = q.eq('kpi_id', kpiId);
    final rows = await q;
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(KpiResult.fromRow)
        .toList();
  }

  /// Writes [rows], keyed by `(kpiId, period, scope, employeeId, departmentId)`
  /// rather than by `.id` — a freshly-computed [KpiResult] does not know
  /// whether a row for its key already exists.
  ///
  /// Find-then-insert/update, NOT `.upsert(...)`: see the class comment.
  /// Reads each distinct period in [rows] once, matches incoming rows against
  /// what already exists by key, then issues one batched insert for the rows
  /// with no match and one update per matched row (PostgREST has no
  /// per-row-different-values batch update).
  ///
  /// Not safe against two [rows] colliding on the same key within one call:
  /// a collision against an already-persisted row is silent last-write-wins
  /// (each matching update overwrites the last), while a collision between
  /// two brand-new rows is not deduplicated at all and fails on the identity
  /// index the moment the second insert lands. No caller produces duplicate
  /// keys today (the compute engine's own `scopesFor`/`populationFor` never
  /// emit two rows for one key); a future caller — the batch-recompute engine
  /// (Task 7) in particular — must dedupe by key before calling this.
  Future<void> upsertAll(List<KpiResult> rows) async {
    if (rows.isEmpty) return;

    final periods = rows.map((r) => r.period).toSet();
    final existingIdByKey = <String, String>{};
    for (final period in periods) {
      final existing = await listByPeriod(period);
      for (final e in existing) {
        final id = e.id;
        if (id == null) continue; // a row read back from the db always has one
        existingIdByKey[_key(
          kpiId: e.kpiId,
          period: e.period,
          scope: e.scope,
          employeeId: e.employeeId,
          departmentId: e.departmentId,
        )] = id;
      }
    }

    final toInsert = <Map<String, dynamic>>[];
    final updates = <(String id, Map<String, dynamic> payload)>[];
    for (final r in rows) {
      final payload = r.toUpsertPayload()..remove('id');
      final key = _key(
        kpiId: r.kpiId,
        period: r.period,
        scope: r.scope,
        employeeId: r.employeeId,
        departmentId: r.departmentId,
      );
      final existingId = existingIdByKey[key];
      if (existingId != null) {
        updates.add((existingId, payload));
      } else {
        toInsert.add(payload);
      }
    }

    if (toInsert.isNotEmpty) {
      await _client.from('kpi_results').insert(toInsert);
    }
    // `computed_at` defaults to now() on insert but has no update trigger, so
    // a recompute must stamp it explicitly here — otherwise the timestamp a
    // "last computed" screen reads would freeze at the row's first
    // computation and silently lie on every recompute after that, which is
    // the core operation of this engine.
    final now = DateTime.now().toUtc().toIso8601String();
    for (final (id, payload) in updates) {
      await _client
          .from('kpi_results')
          .update({...payload, 'computed_at': now})
          .eq('id', id);
    }
  }

  /// Mirrors the `coalesce(employee_id, '000...')` / `coalesce(department_id,
  /// '000...')` expression the identity index is built on — an empty string
  /// stands in for NULL here the same way the fixed uuid does there, just to
  /// make the two nullable columns hashable together with the rest of the key.
  String _key({
    required String kpiId,
    required String period,
    required KpiScope scope,
    String? employeeId,
    String? departmentId,
  }) => [
    kpiId,
    period,
    kpiScopeCodes[scope],
    employeeId ?? '',
    departmentId ?? '',
  ].join('|');

  // ===========================================================================
  // The ingestion boundary (supabase/migrations/20260814000005_kpi_inputs.sql)
  //
  // kpi_exceptions and kpi_readings are where manually-reported data lands —
  // the raw material kpi_results is derived FROM. recordException and
  // recordReading both write whatever `reported_via` / `external_ref` the
  // caller's model already carries; neither method decides provenance
  // itself. A future Lark sync is simply another caller of these same two
  // methods, passing `reportedVia: ReportedVia.lark` and an `externalRef`
  // (the Bitable record id) so a re-sync is idempotent against
  // kpi_exceptions' `unique (kpi_id, external_ref)` index — the same
  // pattern `supabase/functions/sync-lark-self-evals` already uses for
  // `lark_self_eval_responses`.
  // ===========================================================================

  /// Writes one exception occurrence. See the class-level note above on
  /// provenance and idempotency.
  Future<void> recordException(KpiException e) async {
    await _client.from('kpi_exceptions').insert(e.toInsertPayload());
  }

  /// Marks exception [id] confirmed by [confirmedBy] (a `users.id`), stamping
  /// `confirmed_at` to now. Until this runs, the row is inert:
  /// `confirmedCountFor` (exception_aggregation.dart) only sums exceptions
  /// with a non-null `confirmed_at` — an unconfirmed report must never move
  /// a KPI.
  Future<void> confirmException(
    String id, {
    required String confirmedBy,
  }) async {
    await _client
        .from('kpi_exceptions')
        .update({
          'confirmed_at': DateTime.now().toUtc().toIso8601String(),
          'confirmed_by': confirmedBy,
        })
        .eq('id', id);
  }

  /// Writes one period reading. See the class-level note above on
  /// provenance and idempotency.
  ///
  /// A single insert, not an upsert: unlike [upsertAll], this task does not
  /// define correction/replace semantics for an existing
  /// kpi/period/scope/employee/department reading — a second call for the
  /// same identity fails against `kpi_readings_identity`, the same
  /// coalesce-based unique index `kpi_results` uses, by design.
  Future<void> recordReading(KpiReading r) async {
    await _client.from('kpi_readings').insert(r.toInsertPayload());
  }

  /// Every exception row for [kpiId] whose `occurred_on` falls within
  /// [period] (`YYYY-MM`) — confirmed and unconfirmed alike. Filtering to
  /// confirmed-only is [confirmedCountFor]'s job (exception_aggregation.dart),
  /// not this read's; a caller that wants "how many happened at all"
  /// (confirmed or not) needs the unconfirmed rows too.
  Future<List<KpiException>> exceptionsFor(String kpiId, String period) async {
    final (start, end) = _periodBounds(period);
    final rows = await _client
        .from('kpi_exceptions')
        .select()
        .eq('kpi_id', kpiId)
        .gte('occurred_on', start)
        .lt('occurred_on', end);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(KpiException.fromRow)
        .toList();
  }

  /// Every reading row for [period], across every KPI and scope. RLS (not
  /// this filter) is what scopes the result to the caller's company —
  /// mirrors [listByPeriod] above.
  Future<List<KpiReading>> readingsFor(String period) async {
    final rows = await _client
        .from('kpi_readings')
        .select()
        .eq('period', period);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(KpiReading.fromRow)
        .toList();
  }

  /// The inclusive start and exclusive end date (`YYYY-MM-DD`) of [period]
  /// (`YYYY-MM`), for a `gte`/`lt` range filter over a `date` column.
  (String start, String end) _periodBounds(String period) {
    final parts = period.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final start = '$period-01';
    final nextMonth = month == 12
        ? DateTime.utc(year + 1, 1, 1)
        : DateTime.utc(year, month + 1, 1);
    final end =
        '${nextMonth.year.toString().padLeft(4, '0')}-'
        '${nextMonth.month.toString().padLeft(2, '0')}-01';
    return (start, end);
  }
}

final kpiResultRepositoryProvider = Provider<KpiResultRepository>(
  (ref) => KpiResultRepository(Supabase.instance.client),
);
