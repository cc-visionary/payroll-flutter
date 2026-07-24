import '../../data/models/workforce_planning.dart';
import 'text_similarity.dart';

/// An existing accountability that looks like what the author is typing.
class SimilarMatch {
  final WpTask task;
  final double score;
  const SimilarMatch({required this.task, required this.score});
}

/// Existing ACTIVE accountabilities whose name is close to [typed], best match
/// first. Used to stop a manager retyping work the business already tracks —
/// the duplicate that would then double-count its hours.
///
/// [threshold] defaults to 0.5, not 0.6: the motivating example from the
/// design spec — typing "Pack and dispatch orders" when "Pack, label, check
/// and dispatch online orders" already exists — scores only 0.571 on the
/// Jaccard word-set similarity (4 shared words / 7 union words), and Jaccard
/// further penalises a longer, more specific existing name even when it's
/// obviously the same work. This warning is advisory (one tap dismisses it,
/// one tap adopts the match), so a false positive costs a glance while a
/// miss costs a duplicated accountability and double-counted hours — bias
/// toward recall.
List<SimilarMatch> findSimilarAccountabilities({
  required String typed,
  required List<WpTask> all,
  String? excludeId,
  double threshold = 0.5,
  int limit = 3,
}) {
  if (normalizeName(typed).length < 3) return const [];
  final out = <SimilarMatch>[];
  for (final t in all) {
    if (t.id == excludeId) continue;
    if (t.status != 'ACTIVE') continue;
    if (t.isExpectation) continue;
    final s = nameSimilarity(typed, t.name);
    if (s >= threshold) out.add(SimilarMatch(task: t, score: s));
  }
  out.sort((a, b) => b.score.compareTo(a.score));
  return out.length <= limit ? out : out.sublist(0, limit);
}
