/// Postgrest caps every response at `max_rows` (1000 — see
/// supabase/config.toml). Any query that can exceed that must page, or it
/// silently returns a truncated slice and every downstream aggregate is
/// wrong. This walks `.range()` windows until a short page comes back.
///
/// [page] receives an inclusive (from, to) row range and returns that slice.
/// [maxPages] is a runaway guard — a source that always returns a full page
/// would otherwise loop forever.
Future<List<T>> fetchAllPages<T>(
  Future<List<T>> Function(int from, int to) page, {
  int pageSize = 1000,
  int maxPages = 200,
}) async {
  final out = <T>[];
  for (var i = 0; i < maxPages; i++) {
    final from = i * pageSize;
    final rows = await page(from, from + pageSize - 1);
    out.addAll(rows);
    if (rows.length < pageSize) break;
  }
  return out;
}
