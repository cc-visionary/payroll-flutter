import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/applicant.dart';

/// Filter parameters for the applicants list. Mirrors EmployeeListQuery
/// (lib/data/repositories/employee_repository.dart:208) for consistency.
class ApplicantListQuery {
  final String? search;          // name/email substring (case-insensitive)
  final List<String>? statuses;  // null = all statuses
  final String? roleScorecardId;
  final String? hiringEntityId;
  final bool includeArchived;    // include soft-deleted (deleted_at not null)
  const ApplicantListQuery({
    this.search,
    this.statuses,
    this.roleScorecardId,
    this.hiringEntityId,
    this.includeArchived = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ApplicantListQuery &&
          search == other.search &&
          _eq(statuses, other.statuses) &&
          roleScorecardId == other.roleScorecardId &&
          hiringEntityId == other.hiringEntityId &&
          includeArchived == other.includeArchived;

  @override
  int get hashCode => Object.hash(
        search,
        Object.hashAll(statuses ?? const []),
        roleScorecardId,
        hiringEntityId,
        includeArchived,
      );

  static bool _eq(List<String>? a, List<String>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class ApplicantRepository {
  final SupabaseClient _client;
  ApplicantRepository(this._client);

  Future<List<Applicant>> list(ApplicantListQuery q) async {
    var builder = _client.from('applicants').select('*');
    if (!q.includeArchived) {
      builder = builder.isFilter('deleted_at', null);
    }
    if (q.statuses != null && q.statuses!.isNotEmpty) {
      builder = builder.inFilter('status', q.statuses!);
    }
    if (q.roleScorecardId != null) {
      builder = builder.eq('role_scorecard_id', q.roleScorecardId!);
    }
    if (q.hiringEntityId != null) {
      builder = builder.eq('hiring_entity_id', q.hiringEntityId!);
    }
    if (q.search != null && q.search!.trim().isNotEmpty) {
      final s = '%${q.search!.trim()}%';
      builder = builder.or('first_name.ilike.$s,last_name.ilike.$s,email.ilike.$s');
    }
    final rows = await builder.order('applied_at', ascending: false);
    return (rows as List)
        .map((r) => ApplicantFromRow.fromRow(r as Map<String, dynamic>))
        .toList();
  }

  Future<Applicant?> byId(String id) async {
    final row = await _client.from('applicants').select('*').eq('id', id).maybeSingle();
    if (row == null) return null;
    return ApplicantFromRow.fromRow(row);
  }

  /// Counts grouped by status. Used by the Kanban header to show "{n} in this
  /// column" without paging through every row.
  Future<Map<String, int>> countByStatus() async {
    final rows = await _client
        .from('applicants')
        .select('status')
        .isFilter('deleted_at', null);
    final out = <String, int>{};
    for (final r in (rows as List)) {
      final s = (r as Map<String, dynamic>)['status'] as String;
      out[s] = (out[s] ?? 0) + 1;
    }
    return out;
  }
}

final applicantRepositoryProvider =
    Provider<ApplicantRepository>((ref) => ApplicantRepository(Supabase.instance.client));

final applicantListProvider =
    FutureProvider.family<List<Applicant>, ApplicantListQuery>((ref, q) =>
        ref.read(applicantRepositoryProvider).list(q));

final applicantByIdProvider =
    FutureProvider.family<Applicant?, String>((ref, id) =>
        ref.read(applicantRepositoryProvider).byId(id));

final applicantsCountByStatusProvider =
    FutureProvider<Map<String, int>>((ref) =>
        ref.read(applicantRepositoryProvider).countByStatus());
