import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/applicant.dart';
import '../../../data/repositories/job_listing_repository.dart';

class ApplicantCard extends ConsumerWidget {
  final Applicant applicant;
  final String? jobTitle; // resolved from RoleScorecard by parent
  final String? entityName; // resolved from HiringEntity by parent
  final VoidCallback? onMoveToListing;
  const ApplicantCard({
    super.key,
    required this.applicant,
    this.jobTitle,
    this.entityName,
    this.onMoveToListing,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => context.go('/hiring/${applicant.id}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      applicant.fullName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (onMoveToListing != null)
                    IconButton(
                      icon: const Icon(Icons.move_down_outlined, size: 16),
                      tooltip: 'Move to listing…',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: onMoveToListing,
                    ),
                ],
              ),
              if (jobTitle != null) ...[
                const SizedBox(height: 4),
                Text(jobTitle!, style: TextStyle(fontSize: 12, color: muted)),
              ],
              const SizedBox(height: 6),
              _ListingBadge(listingId: applicant.listingId),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (entityName != null) ...[
                    Icon(Icons.business_outlined, size: 12, color: muted),
                    const SizedBox(width: 4),
                    Text(
                      entityName!,
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    _relative(applicant.appliedAt),
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _relative(DateTime d) {
    final delta = DateTime.now().difference(d);
    if (delta.inDays >= 1) return '${delta.inDays}d ago';
    if (delta.inHours >= 1) return '${delta.inHours}h ago';
    if (delta.inMinutes >= 1) return '${delta.inMinutes}m ago';
    return 'just now';
  }
}

class _ListingBadge extends ConsumerWidget {
  final String? listingId;
  const _ListingBadge({required this.listingId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (listingId == null) {
      return _badge(
        text: 'Talent Pool',
        bg: Colors.grey.shade100,
        fg: Colors.grey.shade700,
      );
    }
    final listing = ref.watch(jobListingByIdProvider(listingId!)).asData?.value;
    final missing = listing == null || listing.deletedAt != null;
    final text = missing ? '(deleted listing)' : listing.title;
    return _badge(
      text: text,
      bg: missing ? Colors.grey.shade100 : Colors.deepPurple.shade50,
      fg: missing ? Colors.grey.shade600 : Colors.deepPurple.shade800,
    );
  }

  Widget _badge({required String text, required Color bg, required Color fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}
