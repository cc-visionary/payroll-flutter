import '../../../data/models/compensation_change.dart';

/// Selects the compensation change in effect as of [asOf].
///
/// Qualifying rows: status SCHEDULED or APPLIED, not soft-deleted, and
/// `effectiveDate <= asOf`. Among those, the one with the greatest
/// `effectiveDate` wins; ties break on newest `createdAt`, then `id`.
/// Returns null when nothing qualifies — the caller then falls back to the
/// role scorecard's `base_salary` / `wage_type`.
CompensationChange? effectiveCompensation(
  List<CompensationChange> changes,
  DateTime asOf,
) {
  CompensationChange? best;
  for (final c in changes) {
    if (c.deletedAt != null) continue;
    if (c.status != 'SCHEDULED' && c.status != 'APPLIED') continue;
    if (c.effectiveDate.isAfter(asOf)) continue;
    if (best == null || _beats(c, best)) best = c;
  }
  return best;
}

bool _beats(CompensationChange a, CompensationChange b) {
  final byDate = a.effectiveDate.compareTo(b.effectiveDate);
  if (byDate != 0) return byDate > 0;
  final byCreated = a.createdAt.compareTo(b.createdAt);
  if (byCreated != 0) return byCreated > 0;
  return a.id.compareTo(b.id) > 0;
}
