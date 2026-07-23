/// Lowercase, strip non-alphanumeric to spaces, collapse whitespace. The
/// canonical form for comparing/clustering accountability names.
String normalizeName(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ');

Set<String> _words(String s) {
  final n = normalizeName(s);
  return n.isEmpty ? <String>{} : n.split(' ').toSet();
}

/// Jaccard similarity over the two names' word sets: |A∩B| / |A∪B|, in 0..1.
/// Order-independent and cheap; good enough to cluster near-duplicate
/// responsibilities without a full edit-distance library.
double nameSimilarity(String a, String b) {
  final wa = _words(a), wb = _words(b);
  if (wa.isEmpty && wb.isEmpty) return 1.0;
  if (wa.isEmpty || wb.isEmpty) return 0.0;
  final inter = wa.intersection(wb).length;
  final union = wa.union(wb).length;
  return inter / union;
}

/// Greedy single-link clustering: each item joins the first existing cluster
/// whose FIRST member it matches at or above [threshold], else starts its own.
/// Deterministic (input order preserved), which keeps the UI and tests stable.
List<List<T>> clusterBySimilarity<T>(
  List<T> items,
  String Function(T) nameOf, {
  double threshold = 0.6,
}) {
  final clusters = <List<T>>[];
  for (final item in items) {
    List<T>? match;
    for (final c in clusters) {
      if (nameSimilarity(nameOf(c.first), nameOf(item)) >= threshold) {
        match = c;
        break;
      }
    }
    if (match != null) {
      match.add(item);
    } else {
      clusters.add([item]);
    }
  }
  return clusters;
}
