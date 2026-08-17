import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/kpi_source_config.dart';

/// Reads and writes the three configuration tables Task 3 created
/// (`20260815000002_kpi_source_config.sql`): `kpi_connections`,
/// `kpi_source_bindings`, `kpi_subject_map`. All three are admin-only,
/// company-scoped configuration — RLS (not an explicit `company_id` filter
/// here) is what scopes every read and write to the caller's company, same
/// pattern as `KpiResultRepository`'s `listByPeriod`/`readingsFor`
/// (kpi_result_repository.dart).
///
/// Every `upsert*` here writes the model's FULL `toUpsertPayload()` —
/// never a hand-picked subset. This repo has twice lost real data to a
/// caller that reconstructed a model field-by-field and forgot one; the
/// fix that class of bug needs is "always carry every field", not a
/// narrower write. Contrast `LeaveTypeRepository.setPaid`/`setActive`
/// (leave_type_repository.dart), which deliberately route a single-switch
/// UI edit through a one-column `update` instead of a whole-row upsert —
/// that shape does not apply here: nothing in this task's interface edits
/// one column of these three tables in isolation, so every write below is
/// a whole-row upsert.
class KpiSourceConfigRepository {
  KpiSourceConfigRepository(this._client);

  final SupabaseClient _client;

  // ===========================================================================
  // kpi_connections
  // ===========================================================================

  Future<List<KpiConnection>> listConnections() async {
    final rows = await _client.from('kpi_connections').select().order('name');
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(KpiConnection.fromRow)
        .toList();
  }

  /// Insert when [c.id] is null, update by id otherwise. On insert, `id` is
  /// stripped from the payload rather than sent as an explicit `null` —
  /// the column is `NOT NULL primary key default gen_random_uuid()`, and an
  /// explicit null in the write body would hit that constraint instead of
  /// letting the default apply.
  Future<void> upsertConnection(KpiConnection c) async {
    final payload = c.toUpsertPayload();
    if (c.id == null) {
      payload.remove('id');
      await _client.from('kpi_connections').insert(payload);
    } else {
      await _client
          .from('kpi_connections')
          .update(payload)
          .eq('id', c.id!);
    }
  }

  // ===========================================================================
  // kpi_source_bindings
  // ===========================================================================

  Future<List<KpiSourceBinding>> listBindings() async {
    final rows = await _client
        .from('kpi_source_bindings')
        .select()
        .order('object_name');
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(KpiSourceBinding.fromRow)
        .toList();
  }

  /// The one ACTIVE binding for [kpiId], or null if none is configured.
  ///
  /// `.maybeSingle()`, deliberately not `.single()`: most KPIs have no
  /// external binding at all, and that is a normal, common state — not an
  /// error `.single()` would throw on for zero rows. It is also
  /// deliberately not a bare `.eq('kpi_id', kpiId)` with a client-side
  /// "take the first": `kpi_source_bindings_kpi_active`
  /// (`20260815000002_kpi_source_config.sql`), a partial unique index on
  /// `(kpi_id) WHERE is_active`, guarantees at most one row can ever match
  /// `kpi_id = ... AND is_active = true` — so `.maybeSingle()`'s "zero or
  /// one" contract is not a hope here, it is provably what the DB allows
  /// for this exact filter. The `is_active` filter is load-bearing, not
  /// redundant: the index only constrains ACTIVE rows, so a retired
  /// binding for the same KPI can legitimately still exist, and omitting
  /// this filter would let `.maybeSingle()` throw the "multiple rows"
  /// error the index was meant to make impossible, or worse, return
  /// whichever inactive row Postgres happened to pick.
  Future<KpiSourceBinding?> bindingForKpi(String kpiId) async {
    final row = await _client
        .from('kpi_source_bindings')
        .select()
        .eq('kpi_id', kpiId)
        .eq('is_active', true)
        .maybeSingle();
    return row == null ? null : KpiSourceBinding.fromRow(row);
  }

  /// Insert when [b.id] is null, update by id otherwise. See
  /// [upsertConnection] for why `id` is stripped rather than sent as an
  /// explicit null on insert.
  Future<void> upsertBinding(KpiSourceBinding b) async {
    final payload = b.toUpsertPayload();
    if (b.id == null) {
      payload.remove('id');
      await _client.from('kpi_source_bindings').insert(payload);
    } else {
      await _client
          .from('kpi_source_bindings')
          .update(payload)
          .eq('id', b.id!);
    }
  }

  Future<void> deleteBinding(String id) async {
    await _client.from('kpi_source_bindings').delete().eq('id', id);
  }

  // ===========================================================================
  // kpi_subject_map
  // ===========================================================================

  Future<List<KpiSubjectMap>> subjectMapFor(String connectionId) async {
    final rows = await _client
        .from('kpi_subject_map')
        .select()
        .eq('connection_id', connectionId)
        .order('external_key');
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(KpiSubjectMap.fromRow)
        .toList();
  }

  /// Insert when [m.id] is null, update by id otherwise. See
  /// [upsertConnection] for why `id` is stripped rather than sent as an
  /// explicit null on insert.
  Future<void> upsertSubjectMapping(KpiSubjectMap m) async {
    final payload = m.toUpsertPayload();
    if (m.id == null) {
      payload.remove('id');
      await _client.from('kpi_subject_map').insert(payload);
    } else {
      await _client
          .from('kpi_subject_map')
          .update(payload)
          .eq('id', m.id!);
    }
  }

  Future<void> deleteSubjectMapping(String id) async {
    await _client.from('kpi_subject_map').delete().eq('id', id);
  }

  // ===========================================================================
  // fetch-kpi-source (Task 5's edge function)
  // ===========================================================================

  /// Invokes `fetch-kpi-source` (Task 5, `supabase/functions/fetch-kpi-source/
  /// index.ts`) for [bindingId]/[period] and returns its raw status/body pair
  /// -- the request body is exactly `{binding_id, period}`, per that
  /// function's own header comment, and a 200 body is `{rows: [...]}`.
  ///
  /// This is the shape `ConfiguredSourceFetcher`
  /// (`../../features/kpi_results/configured_source.dart`) expects, and it
  /// tears off cleanly as one: `repo.fetchSourceRows` satisfies the typedef
  /// with no adapter needed, the same technique `subjectMapFor` above already
  /// uses for `SubjectMapReader`.
  ///
  /// **Never throws on a non-2xx.** `functions.invoke` throws
  /// `FunctionException` for any status outside 200-299; that is caught here
  /// and turned into an ordinary `(statusCode, body)` pair instead --
  /// `ConfiguredSource.readDetailed` (configured_source.dart) already maps
  /// every non-2xx status to NO_DATA/MISSING_SOURCE, which is the correct,
  /// contained failure for one KPI's source. Letting this method throw
  /// instead would turn that into an uncaught exception several layers up
  /// (`computeResults`'s own `_readSource` guard exists for a THROWING
  /// source, not as a substitute for this method behaving), defeating the
  /// whole point of `ConfiguredSourceFetchResult` being a plain pair rather
  /// than a result callers must unwrap via try/catch.
  Future<({int statusCode, dynamic body})> fetchSourceRows({
    required String bindingId,
    required String period,
  }) async {
    try {
      final res = await _client.functions.invoke(
        'fetch-kpi-source',
        body: {'binding_id': bindingId, 'period': period},
      );
      return (statusCode: res.status, body: res.data);
    } on FunctionException catch (e) {
      return (statusCode: e.status, body: e.details);
    }
  }
}

final kpiSourceConfigRepositoryProvider = Provider<KpiSourceConfigRepository>(
  (ref) => KpiSourceConfigRepository(Supabase.instance.client),
);
