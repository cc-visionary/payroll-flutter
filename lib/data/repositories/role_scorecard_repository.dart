import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/kpi.dart';
import '../models/role_scorecard.dart';

class RoleScorecardRepository {
  final SupabaseClient _client;
  RoleScorecardRepository(this._client);

  Future<List<RoleScorecard>> list({bool onlyActive = true}) async {
    var q = _client
        .from('role_scorecards')
        .select(
          '*, role_scorecard_kpis(target, frequency, sort_order, kpis(name, measurement_unit))',
        );
    if (onlyActive) q = q.eq('is_active', true);
    final rows = await q.order('job_title');
    return rows.cast<Map<String, dynamic>>().map(RoleScorecard.fromRow).toList();
  }

  Future<RoleScorecard?> byId(String id) async {
    final row = await _client
        .from('role_scorecards')
        .select(
          '*, role_scorecard_kpis(target, frequency, sort_order, kpis(name, measurement_unit))',
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

  Future<Kpi> upsertKpi(String companyId, Kpi kpi) async {
    final row = await _client
        .from('kpis')
        .upsert(kpi.toInsert(companyId), onConflict: 'company_id,name')
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
    for (var i = 0; i < links.length; i++) {
      final link = links[i];
      var kpiId = link.kpiId;
      if (kpiId == null) {
        final kpi = await upsertKpi(companyId, Kpi(
          id: '', companyId: companyId, name: link.name,
          category: link.category, measurementUnit: link.measurementUnit));
        kpiId = kpi.id;
      }
      resolved.add((kpiId: kpiId, target: link.target, frequency: link.frequency));
    }
    // 2. Delete links no longer present.
    final keepIds = resolved.map((r) => r.kpiId).toList();
    var del = _client.from('role_scorecard_kpis').delete()
        .eq('role_scorecard_id', roleScorecardId);
    if (keepIds.isNotEmpty) {
      del = del.not('kpi_id', 'in', '(${keepIds.join(',')})');
    }
    await del;
    // 3. Upsert the current links with their order.
    if (resolved.isNotEmpty) {
      await _client.from('role_scorecard_kpis').upsert([
        for (var i = 0; i < resolved.length; i++)
          {
            'role_scorecard_id': roleScorecardId,
            'kpi_id': resolved[i].kpiId,
            'target': resolved[i].target.trim().isEmpty ? null : resolved[i].target.trim(),
            'frequency': resolved[i].frequency.trim().isEmpty ? null : resolved[i].frequency.trim(),
            'sort_order': i,
          },
      ], onConflict: 'role_scorecard_id,kpi_id');
    }
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
