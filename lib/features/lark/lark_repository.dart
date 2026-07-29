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

/// Result of the `sync-lark-master-data` edge function. Unlike the other Lark
/// syncs this has its own shape: it MATCHES linked Lark rows against existing
/// employees and merges their personal details in. On a dry run it writes
/// nothing and additionally returns [changedFieldCounts]. The function returns
/// HTTP 200 even on a handled failure, signalling it via [ok] == false + [error].
class LarkMasterDataResult {
  /// False when the function reported a handled failure (`{ok:false,error}`).
  final bool ok;
  final String? error;
  /// Total Lark rows scanned.
  final int total;
  /// Lark rows linked to an existing app employee.
  final int matched;
  /// Of [matched], how many got (or, on a dry run, would get) >=1 field filled.
  final int updated;
  /// Matched rows that needed no change.
  final int noop;
  /// Lark rows with no "Lark Profile" set yet (HR hasn't linked them).
  final int skippedUnlinked;
  /// Rows linked to a Lark user that isn't an app employee yet.
  final int skippedUnmatched;
  final List<String> errors;
  /// Dry-run only: {fieldKey: count} of fields that would change.
  final Map<String, int> changedFieldCounts;
  /// Rows the sync couldn't apply, one entry per skipped person. Returned on
  /// both dry-run and real runs; length == [skippedUnlinked] + [skippedUnmatched].
  /// [LarkUnapplied.reason] is `NO_PROFILE` (link them in Lark) or `NOT_IN_APP`
  /// (add the employee, then run the Employees sync).
  final List<LarkUnapplied> unapplied;
  const LarkMasterDataResult({
    required this.ok,
    this.error,
    required this.total,
    required this.matched,
    required this.updated,
    required this.noop,
    required this.skippedUnlinked,
    required this.skippedUnmatched,
    required this.errors,
    required this.changedFieldCounts,
    required this.unapplied,
  });
  factory LarkMasterDataResult.fromJson(Map<String, dynamic> j) {
    final counts = <String, int>{};
    final raw = j['changed_field_counts'];
    if (raw is Map) {
      raw.forEach((k, v) {
        final n = v is int ? v : int.tryParse('$v');
        if (n != null) counts['$k'] = n;
      });
    }
    final unapplied = (j['unapplied'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((e) => LarkUnapplied(
              name: e['name']?.toString() ?? '—',
              reason: e['reason']?.toString() ?? '',
            ))
        .toList();
    return LarkMasterDataResult(
      ok: j['ok'] as bool? ?? false,
      error: j['error'] as String?,
      total: j['total'] as int? ?? 0,
      matched: j['matched'] as int? ?? 0,
      updated: j['updated'] as int? ?? 0,
      noop: j['noop'] as int? ?? 0,
      skippedUnlinked: j['skipped_unlinked'] as int? ?? 0,
      skippedUnmatched: j['skipped_unmatched'] as int? ?? 0,
      errors: (j['errors'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      changedFieldCounts: counts,
      unapplied: unapplied,
    );
  }
}

/// One row a Lark sync couldn't apply, shared across syncs. [name] is a
/// best-effort display label (a person's name, falling back to a Lark user id).
/// [reason] is sync-specific: `NO_PROFILE`/`NOT_IN_APP` for master data,
/// `NO_RESPONDENT`/`NOT_IN_APP` for self-evals.
class LarkUnapplied {
  final String name;
  final String reason;
  const LarkUnapplied({required this.name, required this.reason});
}

/// Result of the `sync-lark-self-evals` edge function. Mirrors
/// [LarkMasterDataResult]: rich shape, and failures come back as `ok:false` at
/// HTTP 200. Writes rows into `lark_self_eval_responses`; on a dry run [synced]
/// is the would-be count and nothing is written.
class LarkSelfEvalResult {
  /// False when the function reported a handled failure (`{ok:false,error}`).
  final bool ok;
  final String? error;
  /// Total Lark self-eval rows scanned.
  final int total;
  /// Responses written (or, on a dry run, that would be written).
  final int synced;
  /// Rows whose Base record has no submitter set.
  final int skippedNoRespondent;
  /// Rows whose submitter isn't a linked app employee.
  final int skippedUnmatched;
  /// Per review type (e.g. `PROBATIONARY_M1`, `QUARTERLY`): matched + synced.
  final Map<String, ({int matched, int synced})> byType;
  /// Rows the sync couldn't apply, one per skipped submitter.
  final List<LarkUnapplied> unapplied;
  final List<String> errors;
  const LarkSelfEvalResult({
    required this.ok,
    this.error,
    required this.total,
    required this.synced,
    required this.skippedNoRespondent,
    required this.skippedUnmatched,
    required this.byType,
    required this.unapplied,
    required this.errors,
  });
  factory LarkSelfEvalResult.fromJson(Map<String, dynamic> j) {
    final byType = <String, ({int matched, int synced})>{};
    final rawBy = j['by_type'];
    if (rawBy is Map) {
      rawBy.forEach((k, v) {
        if (v is Map) {
          int pick(Object? x) => x is int ? x : int.tryParse('$x') ?? 0;
          byType['$k'] = (matched: pick(v['matched']), synced: pick(v['synced']));
        }
      });
    }
    final unapplied = (j['unapplied'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((e) {
      final rawName = e['name']?.toString();
      final larkId = e['larkUserId']?.toString();
      final display = (rawName != null && rawName.trim().isNotEmpty)
          ? rawName
          : (larkId != null && larkId.isNotEmpty ? larkId : '—');
      return LarkUnapplied(name: display, reason: e['reason']?.toString() ?? '');
    }).toList();
    return LarkSelfEvalResult(
      ok: j['ok'] as bool? ?? false,
      error: j['error'] as String?,
      total: j['total'] as int? ?? 0,
      synced: j['synced'] as int? ?? 0,
      skippedNoRespondent: j['skipped_no_respondent'] as int? ?? 0,
      skippedUnmatched: j['skipped_unmatched'] as int? ?? 0,
      byType: byType,
      unapplied: unapplied,
      errors: (j['errors'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
    );
  }
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
  Future<LarkSyncResult> syncCashAdvances(String companyId, {DateTime? from, DateTime? to, String? larkUserId}) =>
      _invoke('sync-lark-cash-advances', {
        'company_id': companyId,
        if (from != null) 'from': from.toIso8601String().substring(0, 10),
        if (to != null) 'to': to.toIso8601String().substring(0, 10),
        if (larkUserId != null) 'lark_user_id': larkUserId,
      });
  Future<LarkSyncResult> syncReimbursements(String companyId, {DateTime? from, DateTime? to, String? larkUserId}) =>
      _invoke('sync-lark-reimbursements', {
        'company_id': companyId,
        if (from != null) 'from': from.toIso8601String().substring(0, 10),
        if (to != null) 'to': to.toIso8601String().substring(0, 10),
        if (larkUserId != null) 'lark_user_id': larkUserId,
      });
  Future<LarkSyncResult> syncCalendar(String companyId, int year) =>
      _invoke('sync-lark-calendar', {'company_id': companyId, 'year': year});

  /// Master-data sync has a richer result shape than the other syncs (and
  /// signals failure via `ok:false` at HTTP 200), so it bypasses [_invoke] and
  /// parses [LarkMasterDataResult] directly. Error handling mirrors [_invoke].
  /// Pass [dryRun] to preview counts without writing anything.
  Future<LarkMasterDataResult> syncMasterData({
    required String companyId,
    bool dryRun = false,
  }) async {
    try {
      final res = await _client.functions.invoke('sync-lark-master-data',
          body: {'company_id': companyId, 'dry_run': dryRun});
      final data = res.data;
      if (data is Map<String, dynamic>) {
        return LarkMasterDataResult.fromJson(data);
      }
      throw Exception('Unexpected response from sync-lark-master-data: $data');
    } on FunctionException catch (e) {
      throw Exception('sync-lark-master-data failed (status ${e.status}): ${e.details ?? e.reasonPhrase}');
    }
  }

  /// Self-eval sync. Same rich-shape / `ok:false`-at-200 contract as
  /// [syncMasterData]; parses [LarkSelfEvalResult] directly. Pass [dryRun] to
  /// preview counts without writing anything.
  Future<LarkSelfEvalResult> syncSelfEvals({
    required String companyId,
    bool dryRun = false,
  }) async {
    try {
      final res = await _client.functions.invoke('sync-lark-self-evals',
          body: {'company_id': companyId, 'dry_run': dryRun});
      final data = res.data;
      if (data is Map<String, dynamic>) {
        return LarkSelfEvalResult.fromJson(data);
      }
      throw Exception('Unexpected response from sync-lark-self-evals: $data');
    } on FunctionException catch (e) {
      throw Exception('sync-lark-self-evals failed (status ${e.status}): ${e.details ?? e.reasonPhrase}');
    }
  }
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
