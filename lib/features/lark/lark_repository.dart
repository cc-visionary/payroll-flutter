import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LarkSyncResult {
  final int total;
  final int created;
  final int updated;
  final int skipped;
  final List<String> errors;
  final String? note;
  const LarkSyncResult({
    required this.total,
    required this.created,
    required this.updated,
    required this.skipped,
    required this.errors,
    this.note,
  });
  factory LarkSyncResult.fromJson(Map<String, dynamic> j) => LarkSyncResult(
        total: j['total'] as int? ?? 0,
        created: j['created'] as int? ?? 0,
        updated: j['updated'] as int? ?? 0,
        skipped: j['skipped'] as int? ?? 0,
        errors: (j['errors'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
        note: j['note'] as String?,
      );
}

class LarkRepository {
  final SupabaseClient _client;
  LarkRepository(this._client);

  Future<({bool ok, String? detail})> ping() async {
    try {
      final res = await _client.functions.invoke('lark-ping');
      final data = res.data;
      if (data is Map && data['ok'] == true) {
        return (ok: true, detail: data['tenant_access_token_prefix']?.toString());
      }
      // Could be String (non-JSON response) or an error payload
      return (ok: false, detail: 'status=${res.status} data=$data');
    } catch (e) {
      return (ok: false, detail: e.toString());
    }
  }

  Future<LarkSyncResult> _invoke(String fn, Map<String, dynamic> body) async {
    try {
      final res = await _client.functions.invoke(fn, body: body);
      final data = res.data;
      if (data is Map<String, dynamic>) {
        return LarkSyncResult.fromJson(data);
      }
      throw Exception('Unexpected response from $fn: $data');
    } on FunctionException catch (e) {
      // Surface the actual response body so callers see Lark error codes / stack traces
      throw Exception('$fn failed (status ${e.status}): ${e.details ?? e.reasonPhrase}');
    }
  }

  Future<LarkSyncResult> syncEmployees(String companyId) =>
      _invoke('sync-lark-employees', {'company_id': companyId});
  Future<LarkSyncResult> syncShifts(String companyId) =>
      _invoke('sync-lark-shifts', {'company_id': companyId});
  Future<LarkSyncResult> syncAttendance(String companyId, {DateTime? from, DateTime? to}) =>
      _invoke('sync-lark-attendance', {
        'company_id': companyId,
        if (from != null) 'from': from.toIso8601String().substring(0, 10),
        if (to != null) 'to': to.toIso8601String().substring(0, 10),
      });
  Future<LarkSyncResult> syncLeaves(String companyId, {DateTime? from, DateTime? to}) =>
      _invoke('sync-lark-leaves', {
        'company_id': companyId,
        if (from != null) 'from': from.toIso8601String().substring(0, 10),
        if (to != null) 'to': to.toIso8601String().substring(0, 10),
      });
  Future<LarkSyncResult> syncOvertime(String companyId, {DateTime? from, DateTime? to}) =>
      _invoke('sync-lark-ot', {
        'company_id': companyId,
        if (from != null) 'from': from.toIso8601String().substring(0, 10),
        if (to != null) 'to': to.toIso8601String().substring(0, 10),
      });
  Future<LarkSyncResult> syncCashAdvances(String companyId, {DateTime? from, DateTime? to}) =>
      _invoke('sync-lark-cash-advances', {
        'company_id': companyId,
        if (from != null) 'from': from.toIso8601String().substring(0, 10),
        if (to != null) 'to': to.toIso8601String().substring(0, 10),
      });
  Future<LarkSyncResult> syncReimbursements(String companyId, {DateTime? from, DateTime? to}) =>
      _invoke('sync-lark-reimbursements', {
        'company_id': companyId,
        if (from != null) 'from': from.toIso8601String().substring(0, 10),
        if (to != null) 'to': to.toIso8601String().substring(0, 10),
      });
  Future<LarkSyncResult> syncCalendar(String companyId, int year) =>
      _invoke('sync-lark-calendar', {'company_id': companyId, 'year': year});
}

final larkRepositoryProvider =
    Provider<LarkRepository>((ref) => LarkRepository(Supabase.instance.client));

// Sync history stream
class SyncLogRow {
  final String id;
  final String syncType;
  final String? dateFrom;
  final String? dateTo;
  final String status;
  final int total;
  final int created;
  final int updated;
  final int errors;
  final DateTime startedAt;
  final String? syncedByEmail;
  final List<String> errorDetails;
  const SyncLogRow({
    required this.id,
    required this.syncType,
    this.dateFrom,
    this.dateTo,
    required this.status,
    required this.total,
    required this.created,
    required this.updated,
    required this.errors,
    required this.startedAt,
    this.syncedByEmail,
    this.errorDetails = const [],
  });
  factory SyncLogRow.fromRow(Map<String, dynamic> r) {
    final raw = r['error_details'];
    final details = raw is List
        ? raw.map((e) => e.toString()).toList()
        : const <String>[];
    return SyncLogRow(
      id: r['id'] as String,
      syncType: r['sync_type'] as String,
      dateFrom: r['date_from'] as String?,
      dateTo: r['date_to'] as String?,
      status: r['status'] as String,
      total: r['total_records'] as int? ?? 0,
      created: r['created_count'] as int? ?? 0,
      updated: r['updated_count'] as int? ?? 0,
      errors: r['error_count'] as int? ?? 0,
      startedAt: DateTime.parse(r['started_at'] as String),
      syncedByEmail: null,
      errorDetails: details,
    );
  }
}

final syncHistoryProvider = FutureProvider<List<SyncLogRow>>((ref) async {
  final rows = await Supabase.instance.client
      .from('lark_sync_logs')
      .select()
      .order('started_at', ascending: false)
      .limit(50);
  return rows.cast<Map<String, dynamic>>().map(SyncLogRow.fromRow).toList();
});
