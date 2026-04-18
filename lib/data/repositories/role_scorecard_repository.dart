import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/role_scorecard.dart';

class RoleScorecardRepository {
  final SupabaseClient _client;
  RoleScorecardRepository(this._client);

  Future<List<RoleScorecard>> list({bool onlyActive = true}) async {
    var q = _client.from('role_scorecards').select();
    if (onlyActive) q = q.eq('is_active', true);
    final rows = await q.order('job_title');
    return rows.cast<Map<String, dynamic>>().map(RoleScorecard.fromRow).toList();
  }

  Future<RoleScorecard?> byId(String id) async {
    final row = await _client.from('role_scorecards').select().eq('id', id).maybeSingle();
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
}

final roleScorecardRepositoryProvider =
    Provider<RoleScorecardRepository>((ref) => RoleScorecardRepository(Supabase.instance.client));

final roleScorecardListProvider = FutureProvider<List<RoleScorecard>>((ref) {
  return ref.watch(roleScorecardRepositoryProvider).list();
});

final scorecardEmployeeCountProvider = FutureProvider<Map<String, int>>((ref) {
  return ref.watch(roleScorecardRepositoryProvider).employeeCountByScorecard();
});
