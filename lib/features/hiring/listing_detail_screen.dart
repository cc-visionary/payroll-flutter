import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/repositories/applicant_repository.dart';
import '../../data/repositories/job_listing_repository.dart';
import '../documents/providers.dart'
    show hiringEntityByIdProvider, roleScorecardByIdProvider;
import 'widgets/applicant_kanban.dart';

class ListingDetailScreen extends ConsumerWidget {
  final String listingId;
  const ListingDetailScreen({super.key, required this.listingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listingAsync = ref.watch(jobListingByIdProvider(listingId));
    return Scaffold(
      appBar: AppBar(title: const Text('Listing')),
      body: listingAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (listing) {
          if (listing == null) {
            return const Center(child: Text('Listing not found'));
          }
          if (listing.deletedAt != null) {
            return const Center(child: Text('This listing has been deleted.'));
          }
          return Column(
            children: [
              _Header(listingId: listingId),
              Expanded(
                child: ApplicantKanban(
                  query: ApplicantListQuery(listingId: listingId),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    onPressed: () => context.go(
                      '/hiring/listings/$listingId/applicants/new',
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('Add applicant to this listing'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  final String listingId;
  const _Header({required this.listingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listing = ref.watch(jobListingByIdProvider(listingId)).asData?.value;
    if (listing == null) return const SizedBox.shrink();
    final filled =
        ref.watch(listingFilledCountProvider(listingId)).asData?.value ?? 0;
    final eff =
        ref.watch(listingEffectiveStatusProvider(listingId)).asData?.value ??
        ListingEffectiveStatus.open;
    final entity = ref
        .watch(hiringEntityByIdProvider(listing.hiringEntityId))
        .asData
        ?.value;
    final role = ref
        .watch(roleScorecardByIdProvider(listing.roleScorecardId))
        .asData
        ?.value;
    final df = DateFormat('MMM d, yyyy');
    final isPaused = listing.status == 'PAUSED';
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            listing.title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _Pill(label: entity?.name ?? '—'),
              _Pill(label: role?.jobTitle ?? '—'),
              _Pill(label: eff.label),
              _Pill(label: '$filled / ${listing.targetHeadcount}'),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Created ${df.format(listing.createdAt)}',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => context.go('/hiring/listings/$listingId/edit'),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit'),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    _togglePause(context, ref, listing.id, isPaused),
                icon: Icon(isPaused ? Icons.play_arrow : Icons.pause),
                label: Text(isPaused ? 'Reopen' : 'Pause'),
              ),
              if (listing.status != 'CLOSED')
                OutlinedButton.icon(
                  onPressed: () => _close(context, ref, listing.id),
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Close'),
                ),
              OutlinedButton.icon(
                onPressed: () => _delete(context, ref, listing.id),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _togglePause(
    BuildContext ctx,
    WidgetRef ref,
    String id,
    bool isPaused,
  ) async {
    await Supabase.instance.client
        .from('job_listings')
        .update({'status': isPaused ? 'OPEN' : 'PAUSED'})
        .eq('id', id);
    ref.invalidate(jobListingByIdProvider(id));
    ref.invalidate(jobListingListProvider);
  }

  Future<void> _close(BuildContext ctx, WidgetRef ref, String id) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('Close listing?'),
        content: const Text(
          'Closing a listing keeps it visible in the Closed filter but hides it from "Open" lists. Applicants on this listing keep their reference. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await Supabase.instance.client
        .from('job_listings')
        .update({
          'status': 'CLOSED',
          'closed_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id);
    ref.invalidate(jobListingByIdProvider(id));
    ref.invalidate(jobListingListProvider);
  }

  Future<void> _delete(BuildContext ctx, WidgetRef ref, String id) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('Delete listing?'),
        content: const Text(
          'Soft-deletes this listing. Applicants on it retain their listing_id (showing "(deleted listing)") and can be reassigned via Move-to-listing. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(jobListingRepositoryProvider).softDelete(id);
    ref.invalidate(jobListingListProvider);
    if (ctx.mounted) ctx.go('/hiring');
  }
}

class _Pill extends StatelessWidget {
  final String label;
  const _Pill({required this.label});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.grey.shade200,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      label,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );
}
