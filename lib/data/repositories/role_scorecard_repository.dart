import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/kpi.dart';
import '../models/kpi_goal.dart';
import '../models/role_kpi.dart';
import '../models/role_outcome.dart';
import '../models/role_scorecard.dart';
import '../models/workforce_planning.dart';

/// Which boxes to tick for an employee whose stored set is [assigned].
///
/// The stored set IS the set. An empty result means nobody has chosen yet —
/// a gap to close, not "tracks everything". That changed in 20260811000002,
/// which backfilled an explicit set for everyone who had an effective one.
/// Ids no longer on the role are dropped: an employee can be moved to a
/// different card, leaving rows that point at the old role's KPIs.
Set<String> initialCheckedKpiIds(
  Set<String> assigned,
  List<String> roleKpiIds,
) => roleKpiIds.where(assigned.contains).toSet();

/// What to store for [checked], in role order so the rows read predictably.
///
/// Unlike the pre-20260811000002 rule this never collapses a full selection to
/// the empty list — "tracks all three" and "nobody has chosen" are different
/// states and scoring has to tell them apart.
List<String> kpiIdsToPersist(Set<String> checked, List<String> roleKpiIds) =>
    roleKpiIds.where(checked.contains).toList();

class KpiAssignee {
  final String employeeId;
  final String name;
  final String? roleTitle;
  const KpiAssignee({
    required this.employeeId,
    required this.name,
    this.roleTitle,
  });
}

/// kpiId -> employees effectively tracked on it. An employee tracks a KPI iff
/// it is on their role card AND in their stored set. There is no "empty means
/// all" fallback: per Spec A Decision 4 an employee whose stored set does not
/// intersect their role has NO set — a gap the Needs-attention strip flags
/// ("N people have no KPI set"), not somebody tracking everything. Defaulting
/// here would make that chip contradict the people list beside it and would
/// credit KPIs to a person nobody has curated.
///
/// NOTE: the SQL `generate_employee_review` (20260718000006) still carries the
/// old fallback via its `not v_has_assignment` branch. Scoring is Spec B; that
/// function must be brought in line before it is used for scoring.
Map<String, List<KpiAssignee>> employeesByKpi({
  required List<({KpiAssignee assignee, String? roleScorecardId})> employees,
  required Map<String, Set<String>> roleKpiIds,
  required Map<String, Set<String>> employeeSubsets,
}) {
  final out = <String, List<KpiAssignee>>{};
  for (final e in employees) {
    final rsId = e.roleScorecardId;
    if (rsId == null) continue;
    final roleSet = roleKpiIds[rsId] ?? const <String>{};
    if (roleSet.isEmpty) continue;
    final subset = employeeSubsets[e.assignee.employeeId];
    final onRoleSubset = subset == null
        ? const <String>{}
        : subset.where(roleSet.contains).toSet();
    for (final kpiId in onRoleSubset) {
      (out[kpiId] ??= []).add(e.assignee);
    }
  }
  return out;
}

class RoleScorecardRepository {
  final SupabaseClient _client;
  RoleScorecardRepository(this._client);

  Future<List<RoleScorecard>> list({bool onlyActive = true}) async {
    var q = _client
        .from('role_scorecards')
        .select(
          '*, role_scorecard_kpis(target, frequency, sort_order, kpis(name, measurement_unit)), '
          'wp_tasks(id, name, responsibility_area, area_sort, task_sort, status)',
        );
    if (onlyActive) q = q.eq('is_active', true);
    final rows = await q.order('job_title');
    final cards = rows
        .cast<Map<String, dynamic>>()
        .map(RoleScorecard.fromRow)
        .toList();
    return _withSharedResponsibilities(cards);
  }

  Future<RoleScorecard?> byId(String id) async {
    final row = await _client
        .from('role_scorecards')
        .select(
          '*, role_scorecard_kpis(target, frequency, sort_order, kpis(name, measurement_unit)), '
          'wp_tasks(id, name, responsibility_area, area_sort, task_sort, status)',
        )
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    final merged = await _withSharedResponsibilities([
      RoleScorecard.fromRow(row),
    ]);
    return merged.first;
  }

  /// A card's responsibility list = its authored ones (already on [cards],
  /// built from the wp_tasks embed) UNION the accountabilities shared to it
  /// via an assignment. Authored rows are never touched — the shared rows are
  /// appended as trailing areas (see responsibilitiesFromAssignedTasks) so a
  /// card's authored order/wording, which the role-card PDF and the
  /// employment contract's Annex A render, can never be altered by sharing
  /// (Risk #2; see the Annex A gate in role_scorecard_responsibilities_test).
  Future<List<RoleScorecard>> _withSharedResponsibilities(
    List<RoleScorecard> cards,
  ) async {
    if (cards.isEmpty) return cards;
    final assigned = await assignedTasksByCard();
    return [
      for (final card in cards)
        card.withExtraResponsibilities(
          responsibilitiesFromAssignedTasks(
            card.id,
            assigned[card.id] ?? const [],
          ),
        ),
    ];
  }

  /// Returns {role_scorecard_id → count of non-archived employees}.
  Future<Map<String, int>> employeeCountByScorecard() async {
    final rows = await _client
        .from('employees')
        .select('role_scorecard_id')
        .isFilter('deleted_at', null);
    final out = <String, int>{};
    for (final r in rows) {
      final id = r['role_scorecard_id'] as String?;
      if (id == null) continue;
      out[id] = (out[id] ?? 0) + 1;
    }
    return out;
  }

  Future<RoleScorecard> upsert(RoleScorecard card) async {
    final payload = card.toUpsertPayload();
    final existing = await _client
        .from('role_scorecards')
        .select('id')
        .eq('id', card.id)
        .maybeSingle();
    Map<String, dynamic> row;
    if (existing == null) {
      row = await _client
          .from('role_scorecards')
          .insert(payload)
          .select()
          .single();
    } else {
      row = await _client
          .from('role_scorecards')
          .update(payload)
          .eq('id', card.id)
          .select()
          .single();
    }
    return RoleScorecard.fromRow(row);
  }

  /// Drafts a new INACTIVE role card seeded from a cluster of unassigned
  /// accountabilities, then repoints those tasks onto it. The card is inactive
  /// because it is a proposal for HR to finish (mission, KPIs, wage), not a live
  /// role — "here is a pile of unowned work" becomes "here is the role we need
  /// to hire for", with the tasks already attached. Returns the new card id.
  Future<String> createDraftRoleFromTasks({
    required String companyId,
    required String jobTitle,
    required List<String> taskIds,
  }) async {
    final row = await _client
        .from('role_scorecards')
        .insert({
          'company_id': companyId,
          'job_title': jobTitle,
          'mission_statement': '',
          'wage_type': 'MONTHLY',
          'work_hours_per_day': 8,
          'work_days_per_week': 'MON_FRI',
          'is_active': false,
          'effective_date': DateTime.now().toIso8601String().substring(0, 10),
        })
        .select('id')
        .single();
    final id = row['id'] as String;
    if (taskIds.isNotEmpty) {
      await _client
          .from('wp_tasks')
          .update({'role_scorecard_id': id})
          .inFilter('id', taskIds);
      // Keep the PRIMARY assignment in lockstep with the repointed card — these
      // tasks come from the unassigned pool (no owner by construction), so the
      // correct PRIMARY is a card assignment @100 on the new draft card.
      await _client
          .from('wp_task_assignments')
          .delete()
          .inFilter('task_id', taskIds)
          .eq('assignment_role', 'PRIMARY');
      await _client.from('wp_task_assignments').insert([
        for (final tid in taskIds)
          {
            'company_id': companyId,
            'task_id': tid,
            'role_scorecard_id': id,
            'assignment_role': 'PRIMARY',
            'allocation_pct': 100,
          },
      ]);
    }
    return id;
  }

  Future<void> delete(String id) async {
    await _client.from('role_scorecards').delete().eq('id', id);
  }

  Future<List<Kpi>> listKpis({bool onlyActive = true}) async {
    var q = _client.from('kpis').select();
    if (onlyActive) q = q.eq('is_active', true);
    final rows = await q.order('category').order('name');
    return rows.cast<Map<String, dynamic>>().map(Kpi.fromRow).toList();
  }

  Future<void> deactivateKpi(String kpiId) async {
    await _client.from('kpis').update({'is_active': false}).eq('id', kpiId);
  }

  Future<Kpi> upsertKpi(String companyId, Kpi kpi) async {
    // The library dedupes case-insensitively (unique index on
    // company_id, lower(trim(name))), a functional index PostgREST's onConflict
    // cannot target — so find-then-insert rather than upsert. Stored names are
    // already trimmed by the migration and inserts, so lower-case compare is enough.
    final name = kpi.name.trim();
    final rows = await _client
        .from('kpis')
        .select()
        .eq('company_id', companyId);
    for (final r in (rows as List).cast<Map<String, dynamic>>()) {
      if ((r['name'] as String).trim().toLowerCase() == name.toLowerCase()) {
        return Kpi.fromRow(r);
      }
    }
    final row = await _client
        .from('kpis')
        .insert(kpi.toInsert(companyId))
        .select()
        .single();
    return Kpi.fromRow(row);
  }

  /// Create or update a library KPI from the management screen. When [id] is
  /// non-null it updates that row in place (rename + fields + reactivate).
  /// When [id] is null it finds an existing row by case-insensitive name
  /// (active OR inactive) and updates+reactivates it, else inserts — so
  /// re-adding a deactivated name reactivates it rather than silently no-op'ing.
  Future<Kpi> saveLibraryKpi({
    String? id,
    required String companyId,
    required String name,
    String? category,
    String? description,
    String? measurementUnit,
    String valueType = 'COUNT',
    String? numeratorLabel,
    String? numeratorSource,
    String? denominatorLabel,
    String? denominatorSource,
    String? unit,
    String cadence = 'WEEKLY',
    String? proofType,
    // Defaults false: the only caller today (the KPI library screen's name
    // editor) never shows the measurable-definition fields, so it never has
    // an opinion on them. A plain `update(fields)` is a partial update in
    // intent but not in effect — Postgrest writes every key present in the
    // map — so including value_type/cadence/numerator_*/denominator_*/unit/
    // proof_type unconditionally would NULL (or reset to their defaults) a
    // definition the caller never saw, the moment a future KPI-pane caller
    // renames a KPI without also resending its formula. Only flip this to
    // true from a caller that actually renders and submits those fields.
    bool writeDefinition = false,
  }) async {
    String? blank(String? v) =>
        (v == null || v.trim().isEmpty) ? null : v.trim();
    final fields = <String, dynamic>{
      'name': name.trim(),
      'category': blank(category),
      'description': blank(description),
      'measurement_unit': blank(measurementUnit),
      'is_active': true,
      if (writeDefinition) ...{
        'value_type': valueType,
        'numerator_label': blank(numeratorLabel),
        'numerator_source': blank(numeratorSource),
        'denominator_label': blank(denominatorLabel),
        'denominator_source': blank(denominatorSource),
        'unit': blank(unit),
        'cadence': cadence,
        'proof_type': blank(proofType),
      },
    };
    if (id != null && id.isNotEmpty) {
      // Read the current cadence/unit before overwriting them — the links'
      // derived columns are re-rendered from the difference (see
      // [_rederiveLinkColumns]). Skipped when this caller has no opinion on
      // the definition, because then neither can have changed.
      final before = writeDefinition
          ? (await _client
                    .from('kpis')
                    .select('cadence, unit')
                    .eq('id', id)
                    .limit(1))
                .cast<Map<String, dynamic>>()
                .firstOrNull
          : null;
      final row = await _client
          .from('kpis')
          .update(fields)
          .eq('id', id)
          .select()
          .single();
      final saved = Kpi.fromRow(row);
      await _rederiveLinkColumns(kpiId: id, before: before, after: saved);
      return saved;
    }
    final existingRows = await _client
        .from('kpis')
        .select()
        .eq('company_id', companyId);
    final target = name.trim().toLowerCase();
    for (final r in (existingRows as List).cast<Map<String, dynamic>>()) {
      if ((r['name'] as String).trim().toLowerCase() == target) {
        final row = await _client
            .from('kpis')
            .update(fields)
            .eq('id', r['id'])
            .select()
            .single();
        final saved = Kpi.fromRow(row);
        await _rederiveLinkColumns(
          kpiId: r['id'] as String,
          // Already in hand from the name-resolution select above.
          before: writeDefinition ? r : null,
          after: saved,
        );
        return saved;
      }
    }
    final row = await _client
        .from('kpis')
        .insert({'company_id': companyId, ...fields})
        .select()
        .single();
    // A row that did not exist a moment ago has no links to re-derive.
    return Kpi.fromRow(row);
  }

  /// Re-renders the `role_scorecard_kpis` columns that are DERIVED from a
  /// library KPI, after [saveLibraryKpi] changed what they derive from.
  ///
  /// `frequency` comes from the KPI's cadence and `target` from the link's
  /// stored goal rendered with the KPI's unit — but both are only ever
  /// written by [saveRoleScorecardKpis], which nothing invokes when a manager
  /// corrects the library entry. So moving "Return Rate" from WEEKLY to
  /// MONTHLY left every link saying `frequency = 'Weekly'`, and the next
  /// employment contract's Annex A printed "Weekly". This lives beside the
  /// derivation it mirrors so the two cannot drift.
  ///
  /// A link with no stored goal keeps its existing `target` untouched: there
  /// is nothing to re-render it from, and its free text is the same thing an
  /// opinion-less upsert protects (see [KpiLinkInput.writeGoal]).
  Future<void> _rederiveLinkColumns({
    required String kpiId,
    required Map<String, dynamic>? before,
    required Kpi after,
  }) async {
    if (before == null) return;
    final cadenceChanged = (before['cadence'] as String?) != after.cadence;
    final unitChanged = (before['unit'] as String?) != after.unit;
    if (!cadenceChanged && !unitChanged) return;

    final frequency = frequencyLabelFromCadence(after.cadence);
    final rows = await _client
        .from('role_scorecard_kpis')
        .select('id, goal_direction, goal_value, goal_value_max')
        .eq('kpi_id', kpiId);
    for (final r in (rows as List).cast<Map<String, dynamic>>()) {
      final patch = <String, dynamic>{};
      // A cadence outside WEEKLY/MONTHLY/QUARTERLY has no label; blanking
      // the column would be worse than leaving the old text.
      if (cadenceChanged && frequency != null) patch['frequency'] = frequency;
      if (unitChanged) {
        final goal = KpiGoal.fromRow(r);
        if (goal != null) patch['target'] = formatGoal(goal, after.unit);
      }
      if (patch.isEmpty) continue;
      await _client
          .from('role_scorecard_kpis')
          .update(patch)
          .eq('id', r['id'] as String);
    }
  }

  /// Source systems already named on some KPI, for the definition form's
  /// autocomplete. Suggestions only — the columns are free text so a new
  /// channel (Shopee, Shopify, Temu) needs neither a migration nor a release.
  Future<List<String>> distinctKpiSources() async {
    final rows = await _client
        .from('kpis')
        .select('numerator_source, denominator_source');
    final out = <String>{};
    for (final r in (rows as List).cast<Map<String, dynamic>>()) {
      for (final key in ['numerator_source', 'denominator_source']) {
        final v = (r[key] as String?)?.trim();
        if (v != null && v.isNotEmpty) out.add(v);
      }
    }
    final list = out.toList()..sort();
    return list;
  }

  /// Replaces a role card's KPI links with [links]. Creates library KPIs for
  /// entries with a null kpiId (find-or-create by name), then reconciles the
  /// link rows (insert new, update target/frequency/order, delete removed).
  ///
  /// Whether a link's structured goal columns are written at all is the
  /// caller's decision, carried on [KpiLinkInput.writeGoal] — see step 3.
  Future<void> saveRoleScorecardKpis(
    String roleScorecardId,
    String companyId,
    List<KpiLinkInput> links,
  ) async {
    // 1. Resolve every link to a kpi_id (create library rows for new names).
    final resolved = <({String kpiId, KpiLinkInput link, String? cadence})>[];
    for (final link in links) {
      var kpiId = link.kpiId;
      // The caller supplies the cadence for an existing library KPI; only a
      // brand-new one has to be read back off the row we just created.
      var cadence = link.cadence;
      if (kpiId == null) {
        final kpi = await upsertKpi(
          companyId,
          Kpi(
            id: '',
            companyId: companyId,
            name: link.name,
            category: link.category,
            measurementUnit: link.measurementUnit,
            unit: link.unit,
            cadence: link.cadence ?? 'WEEKLY',
          ),
        );
        kpiId = kpi.id;
        // Do NOT `cadence ??= kpi.cadence` here: the caller supplies the
        // cadence for an existing library KPI, and when it doesn't (e.g. the
        // form screen's `_KpiDraft` never threading `kpiId`/`cadence` back
        // for an existing card's KPIs), adopting the library row's cadence
        // would silently overwrite whatever frequency text the user typed —
        // frequencyLabelFromCadence(null) below correctly falls back to it
        // instead.
      }
      resolved.add((kpiId: kpiId, link: link, cadence: cadence));
    }
    // Collapse duplicate library KPIs (same kpi_id attached twice) to the first
    // occurrence — matches the (role_scorecard_id, kpi_id) uniqueness and avoids
    // Postgres "ON CONFLICT DO UPDATE cannot affect row a second time".
    final seen = <String>{};
    final deduped = [
      for (final r in resolved)
        if (seen.add(r.kpiId)) r,
    ];
    // 2. Delete links no longer present.
    final keepIds = deduped.map((r) => r.kpiId).toList();
    var del = _client
        .from('role_scorecard_kpis')
        .delete()
        .eq('role_scorecard_id', roleScorecardId);
    if (keepIds.isNotEmpty) {
      del = del.not('kpi_id', 'in', '(${keepIds.join(',')})');
    }
    await del;
    // 3. Upsert the current links with their order. target and frequency are
    //    DERIVED — from the goal and the KPI's cadence — so the free-text
    //    columns the PDF and contract templates read can never drift from the
    //    structured values.
    //
    //    Three row SHAPES, and one upsert per shape:
    //
    //    a) The caller owns the goal ([KpiLinkInput.ownsGoal]) — the four goal
    //       columns are written from `goalColumns`, nulls included, so the
    //       workbench can clear a goal as well as set one.
    //    b) The caller has no opinion AND a structured goal is already stored
    //       — nothing goal-shaped is sent at all, so the columns survive
    //       untouched rather than being nulled.
    //    c) The caller has no opinion and there is no stored goal to protect —
    //       the free-text `target` is written as given.
    //
    //    Only shape (a) has a caller today: `KpisPane` is the sole caller of
    //    this method and passes `ownsGoal: true` on every link, so (b) and (c)
    //    are unreachable in production. They are kept because "no opinion"
    //    is a real position for a future caller to hold — a bulk importer, an
    //    onboarding seed, a Lark sync that knows a KPI belongs on a role but
    //    nothing about its target — and because getting (b) wrong is silent:
    //    it does not throw, it reverts a target that the role-card PDF and
    //    the next employment contract's Annex A then print. Anyone adding
    //    such a caller must set `ownsGoal` deliberately; leaving it false is
    //    a claim that the stored goal is more authoritative than yours.
    //
    //    They cannot share one batch. Postgrest sends a bulk upsert with
    //    `?columns=<union of every row's keys>` (postgrest 2.6.0,
    //    `PostgrestQueryBuilder._setColumnsSearchParam`) and PostgREST treats
    //    that list as the statement's column set: a row that omitted a key is
    //    inserted with NULL for it, and `resolution=merge-duplicates` expands
    //    to `on conflict do update set <every listed column> =
    //    excluded.<column>`. A shape-(b) row riding along with a shape-(a) one
    //    would therefore still have target/goal_* written — as NULL, which is
    //    the very wipe this guards against. Homogeneous batches are what make
    //    "omit the key" actually mean "leave the column alone".
    if (deduped.isEmpty) return;
    final needsStoredGoals = deduped.any((r) => !r.link.ownsGoal);
    final kpiIdsWithStoredGoal = needsStoredGoals
        ? await _kpiIdsWithStoredGoal(roleScorecardId)
        : const <String>{};

    final ownedRows = <Map<String, dynamic>>[];
    final protectedRows = <Map<String, dynamic>>[];
    final legacyTextRows = <Map<String, dynamic>>[];
    for (var i = 0; i < deduped.length; i++) {
      final r = deduped[i];
      final base = <String, dynamic>{
        'role_scorecard_id': roleScorecardId,
        'kpi_id': r.kpiId,
        'sort_order': i,
        'frequency':
            frequencyLabelFromCadence(r.cadence) ??
            (r.link.frequency.trim().isEmpty
                ? null
                : r.link.frequency.trim()),
      };
      if (r.link.ownsGoal) {
        // `target` still comes from the goal whenever there IS one. With no
        // goal it falls back to whatever free text the caller supplied,
        // because owning the goal columns does not mean owning every link's
        // history: the workbench saves a card's whole KPI set in one call, so
        // legacy links the manager never touched ride along with the one they
        // edited, and `target` is the only copy of their typed prose. The
        // caller marks the difference by sending no text for a link whose
        // goal it authored and has now cleared — see goalColumns.
        ownedRows.add({
          ...base,
          ...goalColumns(
            r.link.goal,
            r.link.unit,
            legacyTarget: r.link.target,
          ),
        });
      } else if (kpiIdsWithStoredGoal.contains(r.kpiId)) {
        protectedRows.add(base);
      } else {
        legacyTextRows.add({
          ...base,
          'target': r.link.target.trim().isEmpty ? null : r.link.target.trim(),
        });
      }
    }
    for (final batch in [ownedRows, protectedRows, legacyTextRows]) {
      if (batch.isEmpty) continue;
      await _client
          .from('role_scorecard_kpis')
          .upsert(batch, onConflict: 'role_scorecard_id,kpi_id');
    }
  }

  /// The kpi_ids on [roleScorecardId] whose link already carries a structured
  /// goal. Read only when some incoming link has no opinion on the goal (see
  /// [KpiLinkInput.writeGoal]) — the workbench never pays for this query.
  Future<Set<String>> _kpiIdsWithStoredGoal(String roleScorecardId) async {
    final rows = await _client
        .from('role_scorecard_kpis')
        .select('kpi_id, goal_direction')
        .eq('role_scorecard_id', roleScorecardId)
        .not('goal_direction', 'is', null);
    return {
      for (final r in (rows as List).cast<Map<String, dynamic>>())
        r['kpi_id'] as String,
    };
  }

  /// Applies a responsibility diff (see diffResponsibilities) for one card, then
  /// clears the card's legacy key_responsibilities column so any caller that
  /// reads it without the wp_tasks embed (e.g. upsert()'s return row) doesn't
  /// see stale JSON.
  Future<void> saveResponsibilities({
    required String cardId,
    required List<Map<String, dynamic>> inserts,
    required List<Map<String, dynamic>> updates,
    required List<String> deleteIds,
  }) async {
    if (inserts.isNotEmpty) await _client.from('wp_tasks').insert(inserts);
    for (final u in updates) {
      final m = Map<String, dynamic>.from(u);
      final id = m.remove('id') as String;
      await _client.from('wp_tasks').update(m).eq('id', id);
    }
    if (deleteIds.isNotEmpty) {
      await _client.from('wp_tasks').delete().inFilter('id', deleteIds);
    }
    await _client
        .from('role_scorecards')
        .update({'key_responsibilities': const []})
        .eq('id', cardId);
  }

  Future<List<RoleKpi>> roleKpis(String roleScorecardId) async {
    final rows = await _client
        .from('role_scorecard_kpis')
        .select(
          'kpi_id, target, frequency, goal_direction, goal_value, goal_value_max, kpis(name, unit, cadence)',
        )
        .eq('role_scorecard_id', roleScorecardId)
        .order('sort_order');
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(RoleKpi.fromRow)
        .toList();
  }

  /// A role's desired outcomes, in author order. See [RoleOutcome] for why
  /// [RoleOutcome.responsibilityArea] is a plain string match rather than a
  /// foreign key.
  Future<List<RoleOutcome>> outcomes(String roleId) async {
    final rows = await _client
        .from('role_outcomes')
        .select()
        .eq('role_scorecard_id', roleId)
        .order('sort_order');
    return rows.cast<Map<String, dynamic>>().map(RoleOutcome.fromRow).toList();
  }

  /// Upserts [outcomes] for [roleId], writing `sort_order` from each entry's
  /// list position — the same rule [saveRoleScorecardKpis] uses for its
  /// links. Rows dropped from [outcomes] are NOT deleted here; the caller
  /// removes them explicitly via [deleteOutcome].
  Future<void> saveOutcomes(String roleId, List<RoleOutcome> outcomes) async {
    if (outcomes.isEmpty) return;
    final rows = [
      for (var i = 0; i < outcomes.length; i++)
        {...outcomes[i].toUpsertPayload(), 'sort_order': i},
    ];
    await _client.from('role_outcomes').upsert(rows);
  }

  Future<void> deleteOutcome(String id) async {
    await _client.from('role_outcomes').delete().eq('id', id);
  }

  Future<Set<String>> employeeAssignedKpiIds(String employeeId) async {
    final rows = await _client
        .from('employee_kpis')
        .select('kpi_id')
        .eq('employee_id', employeeId);
    return {
      for (final r in (rows as List).cast<Map<String, dynamic>>())
        r['kpi_id'] as String,
    };
  }

  /// Replace the employee's KPI assignment with [kpiIds]. Empty leaves no
  /// rows — since 20260811000002 that means nobody has chosen yet (a gap to
  /// close), NOT "falls back to the full role set"; that pre-migration
  /// fallback no longer exists anywhere in the app.
  Future<void> saveEmployeeKpis(String employeeId, List<String> kpiIds) async {
    await _client.from('employee_kpis').delete().eq('employee_id', employeeId);
    if (kpiIds.isNotEmpty) {
      await _client.from('employee_kpis').insert([
        for (final id in kpiIds) {'employee_id': employeeId, 'kpi_id': id},
      ]);
    }
  }

  /// Accountabilities reaching a card through an ASSIGNMENT (the shared ones),
  /// as opposed to those authored on it via wp_tasks.role_scorecard_id.
  /// Keyed by role_scorecard_id.
  Future<Map<String, List<WpTask>>> assignedTasksByCard() async {
    final rows =
        (await _client
                .from('wp_task_assignments')
                .select('role_scorecard_id, wp_tasks(*)')
                .not('role_scorecard_id', 'is', null))
            .cast<Map<String, dynamic>>();
    final out = <String, List<WpTask>>{};
    for (final r in rows) {
      final cardId = r['role_scorecard_id'] as String?;
      final t = r['wp_tasks'];
      if (cardId == null || t is! Map) continue;
      final task = WpTask.fromRow(t.cast<String, dynamic>());
      if (task.status != 'ACTIVE') continue;
      (out[cardId] ??= []).add(task);
    }
    return out;
  }

  /// ACTIVE tasks personally owned by [employeeId], for the employment
  /// contract's Annex A append (spec:
  /// 2026-08-04-contract-owned-tasks-annex-design.md). Archived work is
  /// excluded here; authored-on-own-card filtering happens in
  /// responsibilitiesFromAssignedTasks. Task counts per person are small
  /// (tens), so no paging.
  Future<List<WpTask>> activeTasksOwnedBy(String employeeId) async {
    final rows =
        (await _client
                .from('wp_tasks')
                .select()
                .eq('owner_employee_id', employeeId)
                .eq('status', 'ACTIVE'))
            .cast<Map<String, dynamic>>();
    return rows.map(WpTask.fromRow).toList();
  }

  /// kpiId -> employees effectively tracked on it, across the whole company.
  /// Powers the KPI Library screen's "who's tracking this" line. See
  /// [employeesByKpi] for the assignment logic.
  Future<Map<String, List<KpiAssignee>>> assignedEmployeesByKpi() async {
    final emps = await _client
        .from('employees')
        .select(
          'id, first_name, last_name, role_scorecard_id, role_scorecards(job_title)',
        )
        .isFilter('deleted_at', null)
        .order('first_name');
    final roleLinks = await _client
        .from('role_scorecard_kpis')
        .select('role_scorecard_id, kpi_id');
    final ek = await _client
        .from('employee_kpis')
        .select('employee_id, kpi_id');

    final employees = [
      for (final e in (emps as List).cast<Map<String, dynamic>>())
        (
          assignee: KpiAssignee(
            employeeId: e['id'] as String,
            name: '${e['first_name'] ?? ''} ${e['last_name'] ?? ''}'.trim(),
            roleTitle: (e['role_scorecards'] as Map?)?['job_title'] as String?,
          ),
          roleScorecardId: e['role_scorecard_id'] as String?,
        ),
    ];
    final roleKpiIds = <String, Set<String>>{};
    for (final r in (roleLinks as List).cast<Map<String, dynamic>>()) {
      (roleKpiIds[r['role_scorecard_id'] as String] ??= {}).add(
        r['kpi_id'] as String,
      );
    }
    final employeeSubsets = <String, Set<String>>{};
    for (final r in (ek as List).cast<Map<String, dynamic>>()) {
      (employeeSubsets[r['employee_id'] as String] ??= {}).add(
        r['kpi_id'] as String,
      );
    }
    return employeesByKpi(
      employees: employees,
      roleKpiIds: roleKpiIds,
      employeeSubsets: employeeSubsets,
    );
  }

  /// The two maps the Needs-attention strip's "no KPI set" signal needs:
  /// each role's KPI ids, and each employee's stored KPI ids. Two queries
  /// company-wide rather than the per-card/per-employee round trips
  /// [roleKpisProvider] and [employeeAssignedKpiIdsProvider] would need one
  /// per holder — this is the same pair of tables [assignedEmployeesByKpi]
  /// already reads, just returned as maps instead of folded into per-KPI
  /// assignee lists.
  Future<
    ({
      Map<String, Set<String>> roleKpiIdsByCard,
      Map<String, Set<String>> assignedKpiIdsByEmployee,
    })
  >
  kpiAssignmentMaps() async {
    final roleLinks = await _client
        .from('role_scorecard_kpis')
        .select('role_scorecard_id, kpi_id');
    final ek = await _client
        .from('employee_kpis')
        .select('employee_id, kpi_id');

    final roleKpiIdsByCard = <String, Set<String>>{};
    for (final r in (roleLinks as List).cast<Map<String, dynamic>>()) {
      (roleKpiIdsByCard[r['role_scorecard_id'] as String] ??= {}).add(
        r['kpi_id'] as String,
      );
    }
    final assignedKpiIdsByEmployee = <String, Set<String>>{};
    for (final r in (ek as List).cast<Map<String, dynamic>>()) {
      (assignedKpiIdsByEmployee[r['employee_id'] as String] ??= {}).add(
        r['kpi_id'] as String,
      );
    }
    return (
      roleKpiIdsByCard: roleKpiIdsByCard,
      assignedKpiIdsByEmployee: assignedKpiIdsByEmployee,
    );
  }

  /// kpiId -> the job titles of the role cards linking it. Roles and PEOPLE
  /// differ: a KPI on a card with no current holder has a role but nobody
  /// tracking it, which is precisely the state 20260811000001's cleanup
  /// deactivates rather than deletes.
  Future<Map<String, List<String>>> roleTitlesByKpi() async {
    final rows = await _client
        .from('role_scorecard_kpis')
        .select('kpi_id, role_scorecards(job_title)');
    final out = <String, List<String>>{};
    for (final r in (rows as List).cast<Map<String, dynamic>>()) {
      final title = (r['role_scorecards'] as Map?)?['job_title'] as String?;
      if (title == null) continue;
      (out[r['kpi_id'] as String] ??= []).add(title);
    }
    for (final list in out.values) {
      list.sort();
    }
    return out;
  }
}

final roleScorecardRepositoryProvider = Provider<RoleScorecardRepository>(
  (ref) => RoleScorecardRepository(Supabase.instance.client),
);

final roleScorecardListProvider = FutureProvider<List<RoleScorecard>>((ref) {
  return ref.watch(roleScorecardRepositoryProvider).list();
});

final scorecardEmployeeCountProvider = FutureProvider<Map<String, int>>((ref) {
  return ref.watch(roleScorecardRepositoryProvider).employeeCountByScorecard();
});

final kpiLibraryProvider = FutureProvider<List<Kpi>>((ref) {
  return ref.watch(roleScorecardRepositoryProvider).listKpis();
});

/// Every library KPI regardless of `is_active` — for NAME RESOLUTION only,
/// never for populating a picker's suggestions (those stay active-only via
/// [kpiLibraryProvider]). `upsertKpi` resolves a name against every row
/// (see its query above), silently reactivating a deactivated one on match;
/// a caller that only resolves against the active list would fall through
/// to "define a new KPI" for a retired name that the server would actually
/// have matched — a new KPI seeded with a form default cadence instead of
/// the retired KPI's real one.
final kpiLibraryAllProvider = FutureProvider<List<Kpi>>((ref) {
  return ref
      .watch(roleScorecardRepositoryProvider)
      .listKpis(onlyActive: false);
});

final kpiSourcesProvider = FutureProvider<List<String>>((ref) {
  return ref.watch(roleScorecardRepositoryProvider).distinctKpiSources();
});

final kpiAssignedEmployeesProvider =
    FutureProvider<Map<String, List<KpiAssignee>>>((ref) {
      return ref
          .watch(roleScorecardRepositoryProvider)
          .assignedEmployeesByKpi();
    });

/// kpiId -> job titles of the role cards linking it. Sits beside
/// [kpiAssignedEmployeesProvider] in the KPI Library: roles and people
/// differ, because a KPI on a vacant card has a role but no holder tracking
/// it yet — see [RoleScorecardRepository.roleTitlesByKpi].
final kpiRoleTitlesProvider = FutureProvider<Map<String, List<String>>>((ref) {
  return ref.watch(roleScorecardRepositoryProvider).roleTitlesByKpi();
});

final roleKpisProvider = FutureProvider.family<List<RoleKpi>, String>((
  ref,
  roleScorecardId,
) {
  return ref.watch(roleScorecardRepositoryProvider).roleKpis(roleScorecardId);
});

/// A role's desired outcomes, in author order. See
/// [RoleScorecardRepository.outcomes].
final roleOutcomesProvider = FutureProvider.family<List<RoleOutcome>, String>((
  ref,
  roleScorecardId,
) {
  return ref.watch(roleScorecardRepositoryProvider).outcomes(roleScorecardId);
});

final employeeAssignedKpiIdsProvider =
    FutureProvider.family<Set<String>, String>((ref, employeeId) {
      return ref
          .watch(roleScorecardRepositoryProvider)
          .employeeAssignedKpiIds(employeeId);
    });

/// Company-wide role->KPI and employee->KPI maps in one round trip, for the
/// Needs-attention strip's "no KPI set" signal. See
/// [RoleScorecardRepository.kpiAssignmentMaps].
final wpKpiAssignmentMapsProvider = FutureProvider<
  ({
    Map<String, Set<String>> roleKpiIdsByCard,
    Map<String, Set<String>> assignedKpiIdsByEmployee,
  })
>((ref) {
  return ref.watch(roleScorecardRepositoryProvider).kpiAssignmentMaps();
});
