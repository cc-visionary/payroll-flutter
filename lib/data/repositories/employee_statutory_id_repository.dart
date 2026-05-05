import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Per-employee government ID numbers (SSS, PhilHealth, Pag-IBIG, …) stored
/// in the `employee_statutory_ids` table — one row per `(employee_id, id_type)`.
class EmployeeStatutoryIdRepository {
  final SupabaseClient _client;
  EmployeeStatutoryIdRepository(this._client);

  /// Returns `{id_type: id_number}` for a single employee.
  Future<Map<String, String>> byEmployee(String employeeId) async {
    final rows = await _client
        .from('employee_statutory_ids')
        .select('id_type, id_number')
        .eq('employee_id', employeeId);
    final out = <String, String>{};
    for (final r in (rows as List<dynamic>).cast<Map<String, dynamic>>()) {
      out[r['id_type'] as String] = r['id_number'] as String;
    }
    return out;
  }

  /// Upsert a batch of `(id_type → id_number)` for an employee. A null/empty
  /// value deletes the row for that type. Trims whitespace.
  Future<void> upsertAll(
    String employeeId,
    Map<String, String?> idsByType,
  ) async {
    final toUpsert = <Map<String, dynamic>>[];
    final toDelete = <String>[];
    idsByType.forEach((type, raw) {
      final v = raw?.trim() ?? '';
      if (v.isEmpty) {
        toDelete.add(type);
      } else {
        toUpsert.add({
          'employee_id': employeeId,
          'id_type': type,
          'id_number': v,
        });
      }
    });
    if (toUpsert.isNotEmpty) {
      await _client
          .from('employee_statutory_ids')
          .upsert(toUpsert, onConflict: 'employee_id,id_type');
    }
    if (toDelete.isNotEmpty) {
      await _client
          .from('employee_statutory_ids')
          .delete()
          .eq('employee_id', employeeId)
          .inFilter('id_type', toDelete);
    }
  }
}

final employeeStatutoryIdRepositoryProvider =
    Provider<EmployeeStatutoryIdRepository>(
  (ref) => EmployeeStatutoryIdRepository(Supabase.instance.client),
);

/// `{id_type: id_number}` map for a single employee. Watched by the profile.
final employeeStatutoryIdsProvider =
    FutureProvider.family<Map<String, String>, String>((ref, employeeId) async {
  final repo = ref.watch(employeeStatutoryIdRepositoryProvider);
  return repo.byEmployee(employeeId);
});
