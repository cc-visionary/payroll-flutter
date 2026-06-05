import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/job_listing.dart';

class JobListingListQuery {
  final String? search; // title ILIKE
  final List<String>? statuses; // null = all
  final String? hiringEntityId;
  final String? roleScorecardId;
  final bool includeArchived;
  const JobListingListQuery({
    this.search,
    this.statuses,
    this.hiringEntityId,
    this.roleScorecardId,
    this.includeArchived = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JobListingListQuery &&
          search == other.search &&
          _listEq(statuses, other.statuses) &&
          hiringEntityId == other.hiringEntityId &&
          roleScorecardId == other.roleScorecardId &&
          includeArchived == other.includeArchived;

  @override
  int get hashCode => Object.hash(
    search,
    Object.hashAll(statuses ?? const []),
    hiringEntityId,
    roleScorecardId,
    includeArchived,
  );

  static bool _listEq(List<String>? a, List<String>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class JobListingRepository {
  final SupabaseClient _client;
  JobListingRepository(this._client);

  Future<List<JobListing>> list(JobListingListQuery q) async {
    var b = _client.from('job_listings').select('*');
    if (!q.includeArchived) {
      b = b.isFilter('deleted_at', null);
    }
    if (q.statuses != null && q.statuses!.isNotEmpty) {
      b = b.inFilter('status', q.statuses!);
    }
    if (q.hiringEntityId != null) {
      b = b.eq('hiring_entity_id', q.hiringEntityId!);
    }
    if (q.roleScorecardId != null) {
      b = b.eq('role_scorecard_id', q.roleScorecardId!);
    }
    if (q.search != null && q.search!.trim().isNotEmpty) {
      b = b.ilike('title', '%${q.search!.trim()}%');
    }
    final rows = await b.order('created_at', ascending: false);
    return (rows as List)
        .map((r) => JobListing.fromRow(r as Map<String, dynamic>))
        .toList();
  }

  Future<JobListing?> byId(String id) async {
    final row = await _client
        .from('job_listings')
        .select('*')
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    return JobListing.fromRow(row);
  }

  Future<String> upsert({
    String? id,
    required String companyId,
    required String hiringEntityId,
    required String roleScorecardId,
    required String title,
    required int targetHeadcount,
    required String status,
    String? notes,
    DateTime? closedAt,
    required String setByUserId,
  }) async {
    final isCreate = id == null;
    final payload = <String, dynamic>{
      'company_id': companyId,
      'hiring_entity_id': hiringEntityId,
      'role_scorecard_id': roleScorecardId,
      'title': title,
      'target_headcount': targetHeadcount,
      'status': status,
      'notes': notes,
      if (closedAt != null) 'closed_at': closedAt.toIso8601String(),
      if (isCreate) 'created_by_id': setByUserId,
    };
    if (id != null) {
      await _client.from('job_listings').update(payload).eq('id', id);
      return id;
    }
    final inserted = await _client
        .from('job_listings')
        .insert(payload)
        .select('id')
        .single();
    return inserted['id'] as String;
  }

  Future<void> softDelete(String id) async {
    await _client
        .from('job_listings')
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', id);
  }
}

final jobListingRepositoryProvider = Provider<JobListingRepository>(
  (ref) => JobListingRepository(Supabase.instance.client),
);

final jobListingListProvider =
    FutureProvider.family<List<JobListing>, JobListingListQuery>(
      (ref, q) => ref.read(jobListingRepositoryProvider).list(q),
    );

final jobListingByIdProvider = FutureProvider.family<JobListing?, String>(
  (ref, id) => ref.read(jobListingRepositoryProvider).byId(id),
);

enum ListingEffectiveStatus { open, filled, paused, closed }

extension ListingEffectiveStatusX on ListingEffectiveStatus {
  String get label => switch (this) {
    ListingEffectiveStatus.open => 'Open',
    ListingEffectiveStatus.filled => 'Filled',
    ListingEffectiveStatus.paused => 'Paused',
    ListingEffectiveStatus.closed => 'Closed',
  };
}

/// Pure derivation — used by both the live provider and tests.
ListingEffectiveStatus deriveEffectiveStatus({
  required String status,
  required int filled,
  required int target,
}) {
  if (status == 'PAUSED') return ListingEffectiveStatus.paused;
  if (status == 'CLOSED') return ListingEffectiveStatus.closed;
  return filled >= target
      ? ListingEffectiveStatus.filled
      : ListingEffectiveStatus.open;
}

/// Live filled count: number of active, non-archived employees whose
/// (role_scorecard_id, hiring_entity_id) matches the listing.
final listingFilledCountProvider = FutureProvider.family<int, String>((
  ref,
  listingId,
) async {
  final listing = await ref.watch(jobListingByIdProvider(listingId).future);
  if (listing == null) return 0;
  final rows = await Supabase.instance.client
      .from('employees')
      .select('id')
      .eq('role_scorecard_id', listing.roleScorecardId)
      .eq('hiring_entity_id', listing.hiringEntityId)
      .eq('employment_status', 'ACTIVE')
      .isFilter('deleted_at', null);
  return (rows as List).length;
});

/// Effective status: composes the persisted `status` with the derived
/// filled count.
final listingEffectiveStatusProvider =
    FutureProvider.family<ListingEffectiveStatus, String>((
      ref,
      listingId,
    ) async {
      final listing = await ref.watch(jobListingByIdProvider(listingId).future);
      if (listing == null) return ListingEffectiveStatus.closed;
      final filled = await ref.watch(
        listingFilledCountProvider(listingId).future,
      );
      return deriveEffectiveStatus(
        status: listing.status,
        filled: filled,
        target: listing.targetHeadcount,
      );
    });
