import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/kpi.dart';
import '../models/role_kpi.dart';
import '../models/role_scorecard.dart';

/// The checkbox state to show when the assignment section opens: if the employee
/// has no assignment, all role KPIs are checked (they're tracked on the full
/// set by default); otherwise only the assigned KPIs that are still on the role.
Set<String> initialCheckedKpiIds(Set<String> assigned, List<String> roleKpiIds) {
  if (assigned.isEmpty) return roleKpiIds.toSet();
  final inter = roleKpiIds.where(assigned.contains).toSet();
  // A role change can leave assigned rows that no longer match the role; treat
  // that like "no assignment" so the UI mirrors the migration's full-set fallback.
  return inter.isEmpty ? roleKpiIds.toSet() : inter;
}

/// What to persist for [checked] out of [roleKpiIds]: only KPIs that are
/// actually on the role are considered (a concurrent role edit can leave a stale
/// checked id). Persist nothing when none-on-role or all-on-role are checked —
/// both mean "default: full role set" — otherwise the on-role subset in role
/// order.
List<String> kpiIdsToPersist(Set<String> checked, List<String> roleKpiIds) {
  final onRole = roleKpiIds.where(checked.contains).toList();
  if (onRole.isEmpty || onRole.length == roleKpiIds.length) return const [];
  return onRole;
}

class KpiAssignee {
  final String employeeId;
  final String name;
  final String? roleTitle;
  const KpiAssignee({required this.employeeId, required this.name, this.roleTitle});
}

/// kpiId -> employees effectively tracked on it. An employee tracks a KPI if it
/// is on their role card AND (no per-employee subset intersects their role -> the
/// full role set, else only the subset). Mirrors generate_employee_review.
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
    final onRoleSubset =
        subset == null ? const <String>{} : subset.where(roleSet.contains).toSet();
    final effective = onRoleSubset.isEmpty ? roleSet : onRoleSubset;
    for (final kpiId in effective) {
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
    return rows.cast<Map<String, dynamic>>().map(RoleScorecard.fromRow).toList();
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
    return RoleScorecard.fromRow(row);
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
      row = await _client.from('role_scorecards').insert(payload).select().single();
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

  /// The target/frequency this KPI is typically used with on role cards — the
  /// most recent role_scorecard_kpis link that has a target. Used to pre-fill
  /// the role-card editor when a library KPI is picked (target is per-role, so
  /// the library entry has none of its own). Returns nulls when the KPI is not
  /// yet used with a target anywhere.
  Future<({String? target, String? frequency})> kpiDefaultsFromUsage(
    String kpiId,
  ) async {
    final rows = await _client
        .from('role_scorecard_kpis')
        .select('target, frequency')
        .eq('kpi_id', kpiId)
        .not('target', 'is', null)
        .order('updated_at', ascending: false)
        .limit(1);
    final list = (rows as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) return (target: null, frequency: null);
    return (
      target: list.first['target'] as String?,
      frequency: list.first['frequency'] as String?,
    );
  }

  Future<Kpi> upsertKpi(String companyId, Kpi kpi) async {
    // The library dedupes case-insensitively (unique index on
    // company_id, lower(trim(name))), a functional index PostgREST's onConflict
    // cannot target — so find-then-insert rather than upsert. Stored names are
    // already trimmed by the migration and inserts, so lower-case compare is enough.
    final name = kpi.name.trim();
    final rows = await _client.from('kpis').select().eq('company_id', companyId);
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
  }) async {
    final fields = <String, dynamic>{
      'name': name.trim(),
      'category': (category?.trim().isEmpty ?? true) ? null : category!.trim(),
      'description':
          (description?.trim().isEmpty ?? true) ? null : description!.trim(),
      'measurement_unit': (measurementUnit?.trim().isEmpty ?? true)
          ? null
          : measurementUnit!.trim(),
      'is_active': true,
    };
    if (id != null && id.isNotEmpty) {
      final row = await _client
          .from('kpis')
          .update(fields)
          .eq('id', id)
          .select()
          .single();
      return Kpi.fromRow(row);
    }
    final existingRows =
        await _client.from('kpis').select().eq('company_id', companyId);
    final target = name.trim().toLowerCase();
    for (final r in (existingRows as List).cast<Map<String, dynamic>>()) {
      if ((r['name'] as String).trim().toLowerCase() == target) {
        final row = await _client
            .from('kpis')
            .update(fields)
            .eq('id', r['id'])
            .select()
            .single();
        return Kpi.fromRow(row);
      }
    }
    final row = await _client
        .from('kpis')
        .insert({'company_id': companyId, ...fields})
        .select()
        .single();
    return Kpi.fromRow(row);
  }

  /// Replaces a role card's KPI links with [links]. Creates library KPIs for
  /// entries with a null kpiId (find-or-create by name), then reconciles the
  /// link rows (insert new, update target/frequency/order, delete removed).
  Future<void> saveRoleScorecardKpis(
    String roleScorecardId,
    String companyId,
    List<KpiLinkInput> links,
  ) async {
    // 1. Resolve every link to a kpi_id (create library rows for new names).
    final resolved = <({String kpiId, String target, String frequency})>[];
    for (final link in links) {
      var kpiId = link.kpiId;
      if (kpiId == null) {
        final kpi = await upsertKpi(
          companyId,
          Kpi(
            id: '',
            companyId: companyId,
            name: link.name,
            category: link.category,
            measurementUnit: link.measurementUnit,
          ),
        );
        kpiId = kpi.id;
      }
      resolved.add((kpiId: kpiId, target: link.target, frequency: link.frequency));
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
    // 3. Upsert the current links with their order.
    if (deduped.isNotEmpty) {
      await _client.from('role_scorecard_kpis').upsert([
        for (var i = 0; i < deduped.length; i++)
          {
            'role_scorecard_id': roleScorecardId,
            'kpi_id': deduped[i].kpiId,
            'target':
                deduped[i].target.trim().isEmpty ? null : deduped[i].target.trim(),
            'frequency': deduped[i].frequency.trim().isEmpty
                ? null
                : deduped[i].frequency.trim(),
            'sort_order': i,
          },
      ], onConflict: 'role_scorecard_id,kpi_id');
    }
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
        .update({'key_responsibilities': const []}).eq('id', cardId);
  }

  Future<List<RoleKpi>> roleKpis(String roleScorecardId) async {
    final rows = await _client
        .from('role_scorecard_kpis')
        .select('kpi_id, target, frequency, sort_order, kpis(name)')
        .eq('role_scorecard_id', roleScorecardId)
        .order('sort_order');
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(RoleKpi.fromRow)
        .toList();
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

  /// Replace the employee's KPI assignment with [kpiIds]. Empty clears it
  /// (employee falls back to the full role set).
  Future<void> saveEmployeeKpis(String employeeId, List<String> kpiIds) async {
    await _client.from('employee_kpis').delete().eq('employee_id', employeeId);
    if (kpiIds.isNotEmpty) {
      await _client.from('employee_kpis').insert([
        for (final id in kpiIds) {'employee_id': employeeId, 'kpi_id': id},
      ]);
    }
  }

  /// kpiId -> employees effectively tracked on it, across the whole company.
  /// Powers the KPI Library screen's "who's tracking this" line. See
  /// [employeesByKpi] for the assignment logic.
  Future<Map<String, List<KpiAssignee>>> assignedEmployeesByKpi() async {
    final emps = await _client
        .from('employees')
        .select('id, first_name, last_name, role_scorecard_id, role_scorecards(job_title)')
        .isFilter('deleted_at', null)
        .order('first_name');
    final roleLinks =
        await _client.from('role_scorecard_kpis').select('role_scorecard_id, kpi_id');
    final ek = await _client.from('employee_kpis').select('employee_id, kpi_id');

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
      (roleKpiIds[r['role_scorecard_id'] as String] ??= {}).add(r['kpi_id'] as String);
    }
    final employeeSubsets = <String, Set<String>>{};
    for (final r in (ek as List).cast<Map<String, dynamic>>()) {
      (employeeSubsets[r['employee_id'] as String] ??= {}).add(r['kpi_id'] as String);
    }
    return employeesByKpi(
      employees: employees,
      roleKpiIds: roleKpiIds,
      employeeSubsets: employeeSubsets,
    );
  }
}

final roleScorecardRepositoryProvider =
    Provider<RoleScorecardRepository>((ref) => RoleScorecardRepository(Supabase.instance.client));

final roleScorecardListProvider = FutureProvider<List<RoleScorecard>>((ref) {
  return ref.watch(roleScorecardRepositoryProvider).list();
});

final scorecardEmployeeCountProvider = FutureProvider<Map<String, int>>((ref) {
  return ref.watch(roleScorecardRepositoryProvider).employeeCountByScorecard();
});

final kpiLibraryProvider = FutureProvider<List<Kpi>>((ref) {
  return ref.watch(roleScorecardRepositoryProvider).listKpis();
});

final kpiAssignedEmployeesProvider =
    FutureProvider<Map<String, List<KpiAssignee>>>((ref) {
  return ref.watch(roleScorecardRepositoryProvider).assignedEmployeesByKpi();
});

final roleKpisProvider =
    FutureProvider.family<List<RoleKpi>, String>((ref, roleScorecardId) {
  return ref.watch(roleScorecardRepositoryProvider).roleKpis(roleScorecardId);
});

final employeeAssignedKpiIdsProvider =
    FutureProvider.family<Set<String>, String>((ref, employeeId) {
  return ref.watch(roleScorecardRepositoryProvider).employeeAssignedKpiIds(employeeId);
});
