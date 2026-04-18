import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/attendance_day.dart';

class AttendanceRepository {
  final SupabaseClient _client;
  AttendanceRepository(this._client);

  /// Patch a single attendance row by id. The caller supplies a raw payload
  /// mapping column → value; this method stamps `override_by_id`,
  /// `override_at`, and delegates the rest. Returns the refreshed row.
  Future<AttendanceDay> updateRecord({
    required String id,
    required Map<String, dynamic> patch,
    String? overrideById,
  }) async {
    final payload = Map<String, dynamic>.from(patch)
      ..['override_at'] = DateTime.now().toIso8601String();
    if (overrideById != null) payload['override_by_id'] = overrideById;
    final row = await _client
        .from('attendance_day_records')
        .update(payload)
        .eq('id', id)
        .select('*, employees!inner(employee_number, first_name, last_name)')
        .single();
    return AttendanceDay.fromRow(row);
  }

  /// Upsert a row by (employee_id, attendance_date). Inserts a MANUAL record
  /// when the day has no record yet, or applies the patch to the existing
  /// row. Callers must supply at minimum `day_type` + `attendance_status` on
  /// insert via the patch.
  Future<AttendanceDay> upsertByDate({
    required String employeeId,
    required DateTime date,
    required Map<String, dynamic> patch,
    String? overrideById,
  }) async {
    final iso = date.toIso8601String().substring(0, 10);
    final existing = await _client
        .from('attendance_day_records')
        .select('id')
        .eq('employee_id', employeeId)
        .eq('attendance_date', iso)
        .maybeSingle();
    if (existing != null) {
      return updateRecord(
        id: existing['id'] as String,
        patch: patch,
        overrideById: overrideById,
      );
    }
    final payload = <String, dynamic>{
      'employee_id': employeeId,
      'attendance_date': iso,
      'source_type': 'MANUAL',
      if (overrideById != null) 'entered_by_id': overrideById,
      if (overrideById != null) 'override_by_id': overrideById,
      'override_at': DateTime.now().toIso8601String(),
      ...patch,
    };
    final row = await _client
        .from('attendance_day_records')
        .insert(payload)
        .select('*, employees!inner(employee_number, first_name, last_name)')
        .single();
    return AttendanceDay.fromRow(row);
  }

  Future<void> deleteRecord(String id) async {
    await _client.from('attendance_day_records').delete().eq('id', id);
  }

  Future<List<AttendanceDay>> listByRange({
    required DateTime start,
    required DateTime end,
    String? employeeId,
  }) async {
    final startIso = start.toIso8601String().substring(0, 10);
    final endIso = end.toIso8601String().substring(0, 10);
    var q = _client
        .from('attendance_day_records')
        .select('*, employees!inner(employee_number, first_name, last_name)')
        .gte('attendance_date', startIso)
        .lte('attendance_date', endIso);
    if (employeeId != null) q = q.eq('employee_id', employeeId);
    final rows = await q.order('attendance_date', ascending: false);
    final out = <AttendanceDay>[];
    for (final r in rows) {
      try {
        out.add(AttendanceDay.fromRow(r as Map<String, dynamic>));
      } catch (e) {
        // ignore: avoid_print
        print('AttendanceDay.fromRow failed for ${r['id']}: $e\nrow=$r');
      }
    }
    return out;
  }
}

final attendanceRepositoryProvider =
    Provider<AttendanceRepository>((ref) => AttendanceRepository(Supabase.instance.client));

class AttendanceQuery {
  final DateTime start;
  final DateTime end;
  final String? employeeId;
  const AttendanceQuery({required this.start, required this.end, this.employeeId});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AttendanceQuery &&
          other.start == start &&
          other.end == end &&
          other.employeeId == employeeId);

  @override
  int get hashCode => Object.hash(start, end, employeeId);
}

final attendanceListProvider =
    FutureProvider.family<List<AttendanceDay>, AttendanceQuery>((ref, q) {
  return ref.watch(attendanceRepositoryProvider).listByRange(
        start: q.start,
        end: q.end,
        employeeId: q.employeeId,
      );
});
