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
}

final applicantRepositoryProvider =
    Provider<ApplicantRepository>((ref) => ApplicantRepository(Supabase.instance.client));
