import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/shift_template.dart';

class ShiftTemplateRepository {
  final SupabaseClient _client;
  ShiftTemplateRepository(this._client);

  /// [onlyActive] defaults to `true` so every existing caller keeps today's
  /// behaviour unchanged. Pass `false` when a deactivated shift must still
  /// resolve historically — e.g. the HR dashboard, which must read the same
  /// shift set payroll used, or its late/OT figures diverge from the payslip
  /// that already paid it (same class of bug as `roleScorecardRepo.list(
  /// onlyActive: false)`).
  Future<List<ShiftTemplate>> list({bool onlyActive = true}) async {
    var q = _client.from('shift_templates').select();
    if (onlyActive) q = q.eq('is_active', true);
    final rows = await q.order('code');
    return rows.cast<Map<String, dynamic>>().map(ShiftTemplate.fromRow).toList();
  }

  /// Permanently delete a shift template. Postgres FKs will throw 23503 when
  /// the row is still referenced by attendance records or role scorecards; we
  /// map that to a friendlier exception so the UI can show a helpful message.
  Future<void> delete(String id) async {
    try {
      await _client.from('shift_templates').delete().eq('id', id);
    } on PostgrestException catch (e) {
      if (e.code == '23503') {
        throw Exception(
          'Shift is still referenced by attendance or role scorecards. '
          'Reassign those rows to a different shift first.',
        );
      }
      rethrow;
    }
  }
}

final shiftTemplateRepositoryProvider = Provider<ShiftTemplateRepository>(
    (ref) => ShiftTemplateRepository(Supabase.instance.client));

final shiftTemplateListProvider = FutureProvider<List<ShiftTemplate>>(
    (ref) => ref.watch(shiftTemplateRepositoryProvider).list());
