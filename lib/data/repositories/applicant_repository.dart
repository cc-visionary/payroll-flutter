import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/hiring/applicant_status.dart';
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

  /// Create or update an applicant. When [status] differs from the persisted
  /// row, validates the transition (throws IllegalTransition / MissingReason)
  /// and stamps status_changed_at = now() + status_changed_by_id.
  ///
  /// FK columns (role_scorecard_id, hiring_entity_id, department_id,
  /// referred_by_id) carry the SAME id values from the form — never copy
  /// the referenced record's data into a denormalized field on the
  /// applicant row. Source-of-truth stays on the referenced table.
  Future<String> upsert({
    String? id,
    required String companyId,
    required String firstName,
    String? middleName,
    required String lastName,
    String? suffix,
    required String email,
    String? phoneNumber,
    String? mobileNumber,
    required String roleScorecardId,    // hard-gated at form layer
    String? departmentId,
    String? hiringEntityId,
    String? source,
    String? referredById,
    String? linkedinUrl,
    String? portfolioUrl,
    String? expectedSalaryMin,          // Decimal string or null
    String? expectedSalaryMax,
    DateTime? expectedStartDate,
    required String status,
    String? rejectionReason,
    String? withdrawalReason,
    String? notes,
    required String setByUserId,
  }) async {
    // Look up prior status to detect change.
    String? priorStatus;
    if (id != null) {
      final prior = await _client.from('applicants').select('status').eq('id', id).maybeSingle();
      priorStatus = prior?['status'] as String?;
    }

    final isCreate = id == null;
    final statusChanged = isCreate || (priorStatus != null && priorStatus != status);
    if (statusChanged && !isCreate) {
      final reason = status == 'REJECTED'
          ? rejectionReason
          : status == 'WITHDRAWN'
              ? withdrawalReason
              : null;
      validateTransition(from: priorStatus!, to: status, reason: reason);
    }

    final payload = <String, dynamic>{
      'company_id': companyId,
      'first_name': firstName,
      'middle_name': middleName,
      'last_name': lastName,
      'suffix': suffix,
      'email': email,
      'phone_number': phoneNumber,
      'mobile_number': mobileNumber,
      'role_scorecard_id': roleScorecardId,
      'department_id': departmentId,
      'hiring_entity_id': hiringEntityId,
      'source': source,
      'referred_by_id': referredById,
      'linkedin_url': linkedinUrl,
      'portfolio_url': portfolioUrl,
      'expected_salary_min': expectedSalaryMin,
      'expected_salary_max': expectedSalaryMax,
      'expected_start_date': expectedStartDate?.toIso8601String().substring(0, 10),
      'status': status,
      'rejection_reason': rejectionReason,
      'withdrawal_reason': withdrawalReason,
      'notes': notes,
      if (statusChanged) 'status_changed_at': DateTime.now().toIso8601String(),
      if (statusChanged) 'status_changed_by_id': setByUserId,
      if (isCreate) 'created_by_id': setByUserId,
    };
    if (id != null) {
      await _client.from('applicants').update(payload).eq('id', id);
      return id;
    }
    final inserted = await _client.from('applicants').insert(payload).select('id').single();
    return inserted['id'] as String;
  }

  /// Atomically stamp `converted_to_employee_id`, `converted_at = now()`,
  /// and `status = 'HIRED'` on the applicant. Called from the convert flow
  /// AFTER the new Employee row commits. Uses an update that constrains on
  /// the prior status to avoid clobbering a record already marked HIRED
  /// (idempotency).
  ///
  /// Note: we transfer the FK value verbatim — never a denormalized copy.
  Future<void> markConverted({
    required String applicantId,
    required String employeeId,
  }) async {
    final now = DateTime.now().toIso8601String();
    await _client
        .from('applicants')
        .update({
          'converted_to_employee_id': employeeId,
          'converted_at': now,
          'status': 'HIRED',
          'status_changed_at': now,
        })
        .eq('id', applicantId)
        .eq('status', 'OFFER_ACCEPTED'); // idempotent guard
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
