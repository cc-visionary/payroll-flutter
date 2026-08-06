import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Lightweight client-side audit writer for export pathways that do NOT
/// flow through the `export_artifacts` table.
///
/// Use this from any export action that finishes outside the
/// payroll-run export pipeline: the PDF preview Download / Print
/// buttons (Quitclaim, COE, NTE, Payslip, 13th-month), ad-hoc CSV /
/// XLSX dumps (disbursement, finance tracking, statutory payables).
/// Flows that already insert a row into `export_artifacts` are covered
/// automatically by migration `20260506000009_audit_export_artifacts_trigger`
/// — call this in addition only if you need extra description detail
/// the trigger can't compose from the row itself.
class AuditRepository {
  final SupabaseClient _client;
  AuditRepository(this._client);

  /// Write a single EXPORT row to `audit_logs`.
  ///
  /// [description] — human-readable summary, e.g.
  ///   `'Quitclaim PDF downloaded: Donald Xu (EMP-001)'`.
  /// [entityType] — short table-name-like string
  ///   (`'payslips'`, `'document_template_pdf'`, `'payroll_disbursement'`).
  /// [entityId] — optional UUID for cross-reference (payslip id,
  ///   payroll_run id, etc.). Pass null when the export doesn't have a
  ///   stable database id.
  /// [metadata] — optional jsonb payload (filenames, sizes, counts,
  ///   totals) — surfaces inline in the audit-log screen.
  ///
  /// Failures are swallowed by design: an audit-log insert must never
  /// block the user's export. We accept the trade-off of occasionally
  /// missing an audit row over breaking a working export flow.
  Future<void> logExport({
    required String description,
    required String entityType,
    String? entityId,
    Map<String, dynamic>? metadata,
  }) async {
    final user = _client.auth.currentUser;
    final payload = <String, dynamic>{
      'user_id': user?.id,
      'user_email': user?.email,
      'action': 'EXPORT',
      'entity_type': entityType,
      'entity_id': entityId,
      'description': description,
      // Null-aware map entry: drop the key entirely when metadata is
      // null (rather than persisting an explicit JSON null).
      'metadata': ?metadata,
    };
    try {
      await _client.from('audit_logs').insert(payload);
    } catch (_) {
      // Intentional swallow — see class docstring.
    }
  }

  /// Write a single LOGIN row to `audit_logs`.
  ///
  /// Called from [AuthAuditService] when Supabase emits a `signedIn`
  /// event. Reads the freshly-authenticated user from `currentUser` —
  /// at this point the session is already established so the lookup is
  /// safe.
  ///
  /// No-op when `currentUser` is null (defensive: shouldn't happen on
  /// a real signedIn event but we'd rather skip the row than insert a
  /// nonsense one).
  ///
  /// Failures are swallowed by design — audit must never block the
  /// auth flow.
  Future<void> logLogin() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    try {
      await _client.from('audit_logs').insert({
        'user_id': user.id,
        'user_email': user.email,
        'action': 'LOGIN',
        'entity_type': 'users',
        'entity_id': user.id,
        'description': 'User signed in: ${user.email ?? user.id}',
      });
    } catch (_) {
      // Intentional swallow — see class docstring.
    }
  }

  /// Write a single LOGOUT row to `audit_logs`.
  ///
  /// [userId] / [userEmail] are the **previous** session's identity —
  /// captured before sign-out by the caller. By the time the
  /// `signedOut` event fires, `currentUser` is already null, so we
  /// cannot look it up here.
  ///
  /// No-op when [userId] is null (e.g. signedOut fired without a prior
  /// signedIn — happens during failed token refresh).
  ///
  /// Failures are swallowed by design — audit must never block the
  /// auth flow.
  Future<void> logLogout(String? userId, String? userEmail) async {
    if (userId == null) return;
    try {
      await _client.from('audit_logs').insert({
        'user_id': userId,
        'user_email': userEmail,
        'action': 'LOGOUT',
        'entity_type': 'users',
        'entity_id': userId,
        'description': 'User signed out: ${userEmail ?? userId}',
      });
    } catch (_) {
      // Intentional swallow — see class docstring.
    }
  }
}

final auditRepositoryProvider = Provider<AuditRepository>(
  (ref) => AuditRepository(Supabase.instance.client),
);
