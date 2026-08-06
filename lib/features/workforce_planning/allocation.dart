/// Allocation percentages are edited as whole-ish numbers (1 decimal). Every
/// simplifier returns a list that totals EXACTLY 100 — the last entry absorbs
/// the rounding remainder, so "split equally" across 3 never shows 99.9.
double _round1(double v) => (v * 10).roundToDouble() / 10;

double allocationTotal(Iterable<double> pcts) =>
    pcts.fold<double>(0, (s, p) => s + p);

List<double> splitEqually(int n) {
  if (n <= 0) return const [];
  if (n == 1) return [100];
  final each = _round1(100 / n);
  final out = List<double>.filled(n, each);
  out[n - 1] = _round1(100 - each * (n - 1));
  return out;
}

List<double> ownerMajority(
  int n, {
  int primaryIndex = 0,
  double primaryPct = 60,
}) {
  if (n <= 0) return const [];
  if (n == 1) return [100];
  final rest = splitEqually(
    n - 1,
  ).map((p) => _round1(p * (100 - primaryPct) / 100)).toList();
  final out = <double>[];
  var r = 0;
  for (var i = 0; i < n; i++) {
    out.add(i == primaryIndex ? primaryPct : rest[r++]);
  }
  // The last non-primary entry absorbs any rounding remainder.
  final lastOther = n - 1 == primaryIndex ? n - 2 : n - 1;
  out[lastOther] = _round1(out[lastOther] + (100 - allocationTotal(out)));
  return out;
}

List<double> clearAllocations(int n) => List<double>.filled(n < 0 ? 0 : n, 0);
