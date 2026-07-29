// Field-agnostic three-way merge for the Lark master-data sync. Lark is the
// source, but an app edit (the app value has diverged from the last value Lark
// sent) is sacred and never overwritten; a blank value from Lark never wipes an
// existing app value. See docs/superpowers/specs/2026-07-25-employee-master-data-sync-design.md.

export type FieldMerge = { value: string | null; snapshot: string | null; changed: boolean };

const _blank = (v: string | null): boolean => v == null || v.trim() === '';

/// Merge ONE field. `current` = the app value now, `snapshot` = the last value
/// Lark sent for it, `incoming` = the new value from Lark.
export function mergeField(
  current: string | null,
  snapshot: string | null,
  incoming: string | null,
): FieldMerge {
  const cur = current ?? '';
  const snap = snapshot ?? '';
  // App diverged from the last Lark value -> the app owns this field. Freeze the
  // snapshot so it keeps reading as diverged on every future sync.
  if (cur !== '' && cur !== snap) {
    return { value: current, snapshot: snapshot, changed: false };
  }
  // A blank incoming never wipes an existing value nor advances the snapshot.
  if (_blank(incoming)) {
    return { value: current, snapshot: snapshot, changed: false };
  }
  // App is empty, or still tracks Lark -> follow Lark.
  return { value: incoming, snapshot: incoming, changed: incoming !== cur };
}

/// Merge a whole record keyed by field. Returns only the fields that changed,
/// plus the advanced snapshot to persist.
export function mergeRecord(
  current: Record<string, string | null>,
  snapshot: Record<string, string | null>,
  incoming: Record<string, string | null>,
): { updates: Record<string, string | null>; snapshot: Record<string, string | null> } {
  const updates: Record<string, string | null> = {};
  const newSnapshot: Record<string, string | null> = { ...snapshot };
  for (const key of Object.keys(incoming)) {
    const m = mergeField(current[key] ?? null, snapshot[key] ?? null, incoming[key] ?? null);
    if (m.changed) updates[key] = m.value;
    newSnapshot[key] = m.snapshot;
  }
  return { updates, snapshot: newSnapshot };
}
