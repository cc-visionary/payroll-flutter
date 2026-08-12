import 'package:flutter/material.dart';

import 'duplicate_check.dart';

/// The advisory nudge shown under a responsibility-name field when what is
/// being typed looks like an accountability the business already tracks.
///
/// Carried over from the old (now-deleted) card editor, which ran
/// [findSimilarAccountabilities] live as you typed. What it prevents is a
/// SECOND `wp_tasks` row describing the same work: its hours are then counted
/// twice into load %, cost/hour, and the employment contract's Annex A.
///
/// Deliberately a warning and nothing more. The editor also offered a one-tap
/// "assign that one instead", but the workbench already has a home for that —
/// "Link existing" on a responsibility area — so rebuilding the adopt flow
/// here would be a second way to do one thing. Surfacing the collision is the
/// half that was actually missing.
///
/// Nothing blocks on it: two roles legitimately can carry similarly-named
/// work, and [findSimilarAccountabilities] deliberately biases toward recall
/// (see its threshold note), so false positives are expected and must cost
/// only a glance.
class SimilarNameWarning extends StatelessWidget {
  const SimilarNameWarning({super.key, required this.matches});

  /// Best match first, as [findSimilarAccountabilities] returns them. Empty
  /// renders nothing at all.
  final List<SimilarMatch> matches;

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) return const SizedBox.shrink();
    final top = matches.first.task;
    final cs = Theme.of(context).colorScheme;
    // Unlinked tasks are exactly the pool "Link existing" adopts from, so
    // only those get pointed at it. A match already sitting on a role card
    // cannot be adopted from that dialog, and telling a manager to use a
    // control that will not offer it is worse than saying nothing.
    final advice = top.roleScorecardId == null
        ? 'Use "Link existing" on the area to adopt it instead of retyping '
              'it — retyping makes a second row for the same work and '
              'double-counts its hours.'
        : 'It already sits on another role card. Retyping it here makes a '
              'second row for the same work and double-counts its hours.';
    return Padding(
      key: const ValueKey('similar-name-warning'),
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Similar to "${top.name}". $advice',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
