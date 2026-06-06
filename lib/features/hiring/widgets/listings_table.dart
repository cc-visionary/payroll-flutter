import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../data/models/job_listing.dart';
import '../../../data/repositories/applicant_repository.dart';
import '../../../data/repositories/hiring_entity_repository.dart';
import '../../../data/repositories/job_listing_repository.dart';
import '../../../data/repositories/role_scorecard_repository.dart';
import '../../../widgets/responsive_table.dart';

class ListingsTable extends ConsumerStatefulWidget {
  const ListingsTable({super.key});
  @override
  ConsumerState<ListingsTable> createState() => _ListingsTableState();
}

class _ListingsTableState extends ConsumerState<ListingsTable> {
  String _search = '';
  String? _roleId;
  String? _entityId;
  String? _statusFilter; // 'OPEN' | 'PAUSED' | 'CLOSED' | 'FILLED' | null=All

  @override
  Widget build(BuildContext context) {
    // Server-side status filter only applies for OPEN/PAUSED/CLOSED.
    // FILLED is derived client-side after fetching OPEN listings.
    final statusesArg = (_statusFilter == null || _statusFilter == 'FILLED')
        ? null
        : <String>[_statusFilter!];
    final query = JobListingListQuery(
      search: _search.trim().isEmpty ? null : _search,
      statuses: statusesArg,
      hiringEntityId: _entityId,
      roleScorecardId: _roleId,
    );
    final async = ref.watch(jobListingListProvider(query));
    return Column(
      children: [
        _FilterBar(
          search: _search,
          onSearchChanged: (s) => setState(() => _search = s),
          roleId: _roleId,
          onRoleChanged: (v) => setState(() => _roleId = v),
          entityId: _entityId,
          onEntityChanged: (v) => setState(() => _entityId = v),
          status: _statusFilter,
          onStatusChanged: (v) => setState(() => _statusFilter = v),
        ),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Failed to load: $e')),
            data: (rows) {
              List<JobListing> filtered = rows;
              if (_statusFilter == 'FILLED') {
                // For v1: FILLED filter restricts to OPEN rows; the row widget
                // computes effective status. Acceptable trade-off vs. preloading
                // every effective status before render.
                filtered = rows.where((r) => r.status == 'OPEN').toList();
              }
              if (filtered.isEmpty) {
                return const Center(
                  child: Text(
                    'No listings yet. Create your first listing to start hiring.',
                  ),
                );
              }
              return ResponsiveTable(
                child: ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) => _ListingRow(listing: filtered[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FilterBar extends ConsumerWidget {
  final String search;
  final ValueChanged<String> onSearchChanged;
  final String? roleId;
  final ValueChanged<String?> onRoleChanged;
  final String? entityId;
  final ValueChanged<String?> onEntityChanged;
  final String? status;
  final ValueChanged<String?> onStatusChanged;
  const _FilterBar({
    required this.search,
    required this.onSearchChanged,
    required this.roleId,
    required this.onRoleChanged,
    required this.entityId,
    required this.onEntityChanged,
    required this.status,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roles =
        ref.watch(roleScorecardListProvider).asData?.value ?? const [];
    final entities =
        ref.watch(hiringEntityListProvider).asData?.value ?? const [];
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 240,
            child: TextField(
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search),
                labelText: 'Search title',
                border: OutlineInputBorder(),
              ),
              onChanged: onSearchChanged,
            ),
          ),
          DropdownButton<String?>(
            value: status,
            hint: const Text('Status: All'),
            items: const [
              DropdownMenuItem(value: null, child: Text('All statuses')),
              DropdownMenuItem(value: 'OPEN', child: Text('Open')),
              DropdownMenuItem(value: 'FILLED', child: Text('Filled')),
              DropdownMenuItem(value: 'PAUSED', child: Text('Paused')),
              DropdownMenuItem(value: 'CLOSED', child: Text('Closed')),
            ],
            onChanged: onStatusChanged,
          ),
          DropdownButton<String?>(
            value: entityId,
            hint: const Text('Brand: All'),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('All brands'),
              ),
              ...entities.map(
                (e) =>
                    DropdownMenuItem<String?>(value: e.id, child: Text(e.name)),
              ),
            ],
            onChanged: onEntityChanged,
          ),
          DropdownButton<String?>(
            value: roleId,
            hint: const Text('Role: All'),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('All roles'),
              ),
              ...roles.map(
                (r) => DropdownMenuItem<String?>(
                  value: r.id,
                  child: Text(r.jobTitle),
                ),
              ),
            ],
            onChanged: onRoleChanged,
          ),
        ],
      ),
    );
  }
}

class _ListingRow extends ConsumerWidget {
  final JobListing listing;
  const _ListingRow({required this.listing});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filledAsync = ref.watch(listingFilledCountProvider(listing.id));
    final effAsync = ref.watch(listingEffectiveStatusProvider(listing.id));
    final applicantsAsync = ref.watch(
      applicantListProvider(ApplicantListQuery(listingId: listing.id)),
    );
    final filled = filledAsync.asData?.value ?? 0;
    final eff = effAsync.asData?.value ?? ListingEffectiveStatus.open;
    final applicantCount = applicantsAsync.asData?.value.length ?? 0;
    final df = DateFormat('MMM d, yyyy');

    return InkWell(
      onTap: () => context.go('/hiring/listings/${listing.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Text(
                listing.title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              flex: 2,
              child: _BrandPill(entityId: listing.hiringEntityId),
            ),
            Expanded(
              flex: 2,
              child: _RolePill(scorecardId: listing.roleScorecardId),
            ),
            Expanded(
              flex: 2,
              child: Text('$filled / ${listing.targetHeadcount}'),
            ),
            Expanded(flex: 2, child: _StatusChip(status: eff)),
            Expanded(flex: 2, child: Text('$applicantCount applicants')),
            Expanded(flex: 2, child: Text(df.format(listing.createdAt))),
          ],
        ),
      ),
    );
  }
}

class _BrandPill extends ConsumerWidget {
  final String entityId;
  const _BrandPill({required this.entityId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entities =
        ref.watch(hiringEntityListProvider).asData?.value ?? const [];
    final match = entities.where((e) => e.id == entityId).firstOrNull;
    return Text(match?.name ?? '—');
  }
}

class _RolePill extends ConsumerWidget {
  final String scorecardId;
  const _RolePill({required this.scorecardId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scorecards =
        ref.watch(roleScorecardListProvider).asData?.value ?? const [];
    final match = scorecards.where((s) => s.id == scorecardId).firstOrNull;
    return Text(match?.jobTitle ?? '—');
  }
}

class _StatusChip extends StatelessWidget {
  final ListingEffectiveStatus status;
  const _StatusChip({required this.status});
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      ListingEffectiveStatus.open => (
        Colors.deepPurple.shade50,
        Colors.deepPurple.shade800,
      ),
      ListingEffectiveStatus.filled => (
        Colors.green.shade50,
        Colors.green.shade800,
      ),
      ListingEffectiveStatus.paused => (
        Colors.amber.shade50,
        Colors.amber.shade900,
      ),
      ListingEffectiveStatus.closed => (
        Colors.grey.shade200,
        Colors.grey.shade700,
      ),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          status.label,
          style: TextStyle(
            color: fg,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
