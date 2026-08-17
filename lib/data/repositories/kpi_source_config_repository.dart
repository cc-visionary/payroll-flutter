import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/kpi_source_config.dart';
import '../pagination.dart';

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

  /// Pages past Postgrest's `max_rows` cap (1000, `supabase/config.toml`)
  /// -- see `fetchAllPages`'s doc comment. `listConnections` is unlikely to
  /// exceed the cap today, but a partial config read is the same class of
  /// silent wrongness as an unpaged `subjectMapFor`, and every other read
  /// in this class pages for exactly that reason.
  Future<List<KpiConnection>> listConnections() async {
    final rows = await fetchAllPages<Map<String, dynamic>>((from, to) async {
      final page = await _client
          .from('kpi_connections')
          .select()
          .order('name')
          .range(from, to);
      return (page as List<dynamic>).cast<Map<String, dynamic>>();
    });
    return rows.map(KpiConnection.fromRow).toList();
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

  /// Pages past Postgrest's `max_rows` cap -- see [listConnections]'s doc
  /// comment for why this pages even though it is unlikely to exceed 1000
  /// rows today.
  Future<List<KpiSourceBinding>> listBindings() async {
    final rows = await fetchAllPages<Map<String, dynamic>>((from, to) async {
      final page = await _client
          .from('kpi_source_bindings')
          .select()
          .order('object_name')
          .range(from, to);
      return (page as List<dynamic>).cast<Map<String, dynamic>>();
    });
    return rows.map(KpiSourceBinding.fromRow).toList();
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

  /// Pages past Postgrest's `max_rows` cap -- see [listConnections]'s doc
  /// comment. This one is not a defensive-only case: `kpi_subject_map`
  /// holds one row per external key PER CONNECTION -- for an EMPLOYEE-kind
  /// connection that is one row per employee -- so a company with more
  /// than 1000 staff can genuinely exceed the cap. Before this fix, a
  /// mapping past the cut silently read as absent from
  /// `subjectToEmployee`/`subjectToDepartment`
  /// (`../../features/kpi_results/configured_source.dart`), collapsing a
  /// real, present mapping's PERSONAL/DEPARTMENT result to `NO_DATA` and
  /// listing that person's key in Settings as unmapped when it plainly
  /// was not.
  Future<List<KpiSubjectMap>> subjectMapFor(String connectionId) async {
    final rows = await fetchAllPages<Map<String, dynamic>>((from, to) async {
      final page = await _client
          .from('kpi_subject_map')
          .select()
          .eq('connection_id', connectionId)
          .order('external_key')
          .range(from, to);
      return (page as List<dynamic>).cast<Map<String, dynamic>>();
    });
    return rows.map(KpiSubjectMap.fromRow).toList();
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
  // kpis.numerator_source (Task 8's one narrow write)
  // ===========================================================================

  /// Updates ONLY `kpis.numerator_source` for [kpiId] -- never any other
  /// column on that row. This is the one deliberate exception to this
  /// class's own "always carry every field" rule stated in the header
  /// comment above: that rule is about THIS class's three config tables,
  /// where every write is a whole row this class alone owns. `kpis` is not
  /// one of those tables -- it is owned by `RoleScorecardRepository`, whose
  /// `saveLibraryKpi(..., writeDefinition: true)`
  /// (`role_scorecard_repository.dart:245-259`) writes the KPI's ENTIRE
  /// measurable definition (`value_type`, `numerator_label`,
  /// `denominator_source`, `unit`, `cadence`, `proof_type`) in one call.
  /// Routing a Settings ▸ KPI Sources binding save through that method
  /// would blank every one of those fields the instant an admin points a
  /// KPI at a source, because Postgrest writes every key present in an
  /// `update` payload and this screen renders none of them. That exact
  /// shape has cost this repo real data twice already -- see this class's
  /// header comment -- so this single column gets its own single-column
  /// method instead, the same shape `LeaveTypeRepository.setPaid`/
  /// `setActive` already uses for the same reason.
  ///
  /// Call with `'cfg:<kpiId>'` (matching `ConfiguredSource.key`,
  /// `configured_source.dart`) whenever a binding for [kpiId] becomes, or
  /// stays, ACTIVE. Call with `null` on UNBIND -- deleting the binding, or
  /// switching its `is_active` off -- because `computeResults` resolves a
  /// KPI's source via `registry[kpi.numeratorSource]`
  /// (`compute_kpi_results.dart:332,367`) and Task 7's registry only ever
  /// builds a [ConfiguredSource] for an ACTIVE binding: a stale
  /// `cfg:<kpiId>` left behind after unbinding would name a registry key
  /// nothing answers to any more, and the KPI would read NO_DATA forever
  /// with nothing in the UI saying why.
  Future<void> setKpiNumeratorSource(
    String kpiId,
    String? numeratorSource,
  ) async {
    await _client
        .from('kpis')
        .update({'numerator_source': numeratorSource})
        .eq('id', kpiId);
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

/// Every connection, for Settings ▸ KPI Sources. No company_id filter here
/// for the same reason none of this repository's own methods take one --
/// see this file's header comment; RLS scopes it.
final kpiConnectionsProvider = FutureProvider<List<KpiConnection>>((ref) {
  return ref.watch(kpiSourceConfigRepositoryProvider).listConnections();
});

/// Every binding (active and retired), for Settings ▸ KPI Sources' bindings
/// table -- unlike [KpiSourceConfigRepository.bindingForKpi], which answers
/// "the one ACTIVE binding for this KPI", the screen needs the full list
/// once and derives each KPI's active binding from it client-side, rather
/// than making one round trip per KPI in the library.
final kpiSourceBindingsProvider = FutureProvider<List<KpiSourceBinding>>((
  ref,
) {
  return ref.watch(kpiSourceConfigRepositoryProvider).listBindings();
});

/// Subject-map rows for one connection, keyed by connection id -- Settings
/// only ever needs one connection's mappings on screen at a time (the
/// admin picks a connection first).
final kpiSubjectMapProvider =
    FutureProvider.family<List<KpiSubjectMap>, String>((ref, connectionId) {
      return ref
          .watch(kpiSourceConfigRepositoryProvider)
          .subjectMapFor(connectionId);
    });
