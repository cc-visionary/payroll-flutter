import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/shift_template.dart';

class ShiftTemplateRepository {
  final SupabaseClient _client;
  ShiftTemplateRepository(this._client);

  Future<List<ShiftTemplate>> list() async {
    final rows = await _client
        .from('shift_templates')
        .select()
        .eq('is_active', true)
        .order('code');
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
