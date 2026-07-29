# Employee Master-Data Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** New hires registered in the Lark "Employee Information" Base flow into the app (create + update employee / statutory / bank records), one-way, matched by employee number, with a smart merge that never overwrites a field HR edited in the app.

**Architecture:** A Deno edge function (`sync-lark-master-data`) resolves the wiki-wrapped Base → reads its records → for each, applies a **field-agnostic three-way merge** (fill / apply-if-unchanged / skip-if-app-edited) against a per-employee snapshot, then upserts. The merge is a **pure, unit-tested TS module** (built + tested first, with no Lark/DB dependency); the Lark-read + field-mapping are built against the **real Base fields** once access is live.

**Tech Stack:** Deno (edge function + `deno test`), Supabase Postgres, Flutter (the manager "Sync from Lark" surface). Lark Bitable + Wiki Open APIs on `open.larksuite.com`, via `_shared/lark.ts` (tenant token).

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-25-employee-master-data-sync-design.md`. Strategy: `2026-07-25-lark-integration-strategy-design.md`.
- **One-way (Lark → App); Lark-primary; NO writeback.** **Match key = the Base "Lark Profile" person field → `employees.lark_user_id`** (the live Base has NO employee-number field; records read with `user_id_type=user_id`). Rows with an empty Lark Profile, or whose profile matches no app employee, are skipped and reported — HR setting the Lark Profile is the gate that admits a new hire into payroll.
- **v1 is ENRICH-ONLY** (updates existing linked employees). `employees.employee_number` + `hire_date` are NOT NULL and are not employee-entered form fields, so create-from-Lark is a deferred fast-follow (would seed employee_number from the Lark contact directory + hire_date from the Base "Start Date").
- **Synced fields (employee-entered form only):** First/Middle/Last Name, Birthday→birth_date, Email→personal_email, Present Address, Civil Status (uppercased), Contact #→phone_number, Emergency Contact/#/Relationship, TIN/SSS/PhilHealth/PAG-IBIG→statutory rows, Metrobank→bank(MBTC), GCash→bank(GCASH). **Never synced:** Department, Position, Status, Start Date, Contract Link (HR-managed; app owns role/employment).
- **Data-quality caveat:** SSS/PhilHealth/PAG-IBIG/Contact #/Emergency #/GCASH are **Number** fields in Lark → leading zeros already dropped. The mapper restores PH-mobile leading zeros (phone/emergency/GCash → `09…`); statutory IDs can't be safely reconstructed — recommend HR switch those 6 columns to **Text** in the form. TIN + Metrobank are already Text.
- **Smart merge:** app fields are editable; a field HR changed in the app is never overwritten; Lark still corrects untouched fields; a blank in Lark never wipes an app value.
- **Field ownership:** Lark owns the onboarding-form fields; the app owns department/role/employment/comp — the sync never touches those.
- Migrations forward-only. Repo gates on `flutter analyze` (0 errors) for Dart; do NOT run `dart format`.
- **Access is wiki-wrapped:** resolve wiki node `TNQSwJcM0iN16SkYCpllZvfIgdf` → Bitable `app_token` → tables → records. Needs the Lark app granted **wiki-read** (done) + **bitable-read**, and the Base **shared with the app**.

---

## PART A — Foundation (build now; no Lark, no DB dependency)

### Task 1: Migration — the merge snapshot column

**Files:** Create `supabase/migrations/20260725000001_employee_lark_master_snapshot.sql`

- [ ] **Step 1: Write the migration**

```sql
-- The last set of values Lark sent for an employee's onboarding-form fields,
-- keyed by field. The master-data sync compares the app's current value against
-- this to decide fill / apply / skip, so HR edits in the app are never
-- overwritten by a later sync. Additive; no data change.
alter table employees
  add column if not exists lark_master_snapshot jsonb not null default '{}'::jsonb;

comment on column employees.lark_master_snapshot is
  'Last values Lark sent per onboarding-form field; drives the master-data sync '
  'three-way merge so app edits are not overwritten. See sync-lark-master-data.';
```

- [ ] **Step 2: Apply to prod** — `supabase db push` → `Y`. (Additive, inert until the sync ships.) Verify the column exists via a service_role select of one row (flag the use).

- [ ] **Step 3: Commit** — `git commit -m "data(employees): lark_master_snapshot for master-data merge"`.

### Task 2: The pure merge module + Deno tests

**Files:** Create `supabase/functions/_shared/master_data_merge.ts` + `supabase/functions/_shared/master_data_merge_test.ts`

**Interfaces (Produces):**
- `type FieldMerge = { value: string | null; snapshot: string | null; changed: boolean }`
- `mergeField(current: string|null, snapshot: string|null, incoming: string|null): FieldMerge`
- `mergeRecord(current: Record<string,string|null>, snapshot: Record<string,string|null>, incoming: Record<string,string|null>): { updates: Record<string,string|null>; snapshot: Record<string,string|null> }`

- [ ] **Step 1: Write the failing tests**

```ts
// supabase/functions/_shared/master_data_merge_test.ts
import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { mergeField, mergeRecord } from './master_data_merge.ts';

Deno.test('fills an empty app field from Lark', () => {
  const m = mergeField(null, null, '0912');
  assertEquals(m.value, '0912'); assertEquals(m.snapshot, '0912'); assertEquals(m.changed, true);
});
Deno.test('applies a Lark correction when the app still tracks Lark', () => {
  const m = mergeField('old', 'old', 'new');       // app == snapshot
  assertEquals(m.value, 'new'); assertEquals(m.snapshot, 'new'); assertEquals(m.changed, true);
});
Deno.test('skips (app owns it) when the app diverged from the last Lark value', () => {
  const m = mergeField('hr-edit', 'lark-old', 'lark-new'); // app != snapshot
  assertEquals(m.value, 'hr-edit'); assertEquals(m.snapshot, 'lark-old'); assertEquals(m.changed, false);
});
Deno.test('a blank incoming never wipes an app value nor advances the snapshot', () => {
  const m = mergeField('has', 'has', '');
  assertEquals(m.value, 'has'); assertEquals(m.snapshot, 'has'); assertEquals(m.changed, false);
});
Deno.test('no-op when Lark repeats the value the app already has', () => {
  const m = mergeField('same', 'same', 'same');
  assertEquals(m.changed, false);
});
Deno.test('mergeRecord returns only changed fields + the advanced snapshot', () => {
  const r = mergeRecord(
    { phone: '111', tin: 'hr-fixed', addr: null },
    { phone: '111', tin: 'lark-old', addr: null },
    { phone: '222', tin: 'lark-new', addr: 'Main St' },
  );
  assertEquals(r.updates, { phone: '222', addr: 'Main St' }); // tin skipped (app owns it)
  assertEquals(r.snapshot.phone, '222');
  assertEquals(r.snapshot.tin, 'lark-old');   // frozen — app owns it
  assertEquals(r.snapshot.addr, 'Main St');
});
```

- [ ] **Step 2: Run to verify it fails** — `deno test supabase/functions/_shared/master_data_merge_test.ts` → FAIL (module missing).

- [ ] **Step 3: Implement**

```ts
// supabase/functions/_shared/master_data_merge.ts
// Field-agnostic three-way merge for the Lark master-data sync. Lark is the
// source, but an app edit (app value diverged from the last Lark value) is
// sacred and never overwritten; a blank in Lark never wipes an app value.
export type FieldMerge = { value: string | null; snapshot: string | null; changed: boolean };

const _blank = (v: string | null): boolean => v == null || v.trim() === '';

/** Merge ONE field. `current`=app now, `snapshot`=last value Lark sent, `incoming`=new Lark value. */
export function mergeField(
  current: string | null,
  snapshot: string | null,
  incoming: string | null,
): FieldMerge {
  const cur = current ?? '';
  const snap = snapshot ?? '';
  // App diverged from the last Lark value -> app owns it. Freeze the snapshot
  // so it keeps being recognised as diverged on every future sync.
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

/** Merge a whole record keyed by field. Returns only the changed fields + the new snapshot. */
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
```

- [ ] **Step 4: Run to verify it passes** — `deno test supabase/functions/_shared/master_data_merge_test.ts` → PASS (6 tests).

- [ ] **Step 5: Commit** — `git commit -m "feat(lark): field-agnostic master-data merge (protects app edits)"`.

---

## PART B — Live integration (access is LIVE: bitable-read granted + Base shared with the "Luxium People" app 2026-07-29)

**Live Base:** wiki node `TNQSwJcM0iN16SkYCpllZvfIgdf` → app_token `OJf1bkvKbasA2Us7ddRl7hT4gde`; table "Employee Information" = `tblEKPjhITgSTCuI` (33 records). Wiki token stored as secret `LARK_EMPLOYEE_BASE_WIKI_TOKEN`.

### Task 3: Wiki-resolve + Bitable read helpers (`_shared/lark.ts`) — ✅ DONE
`resolveWikiNode`, `listBaseTables`, `listBaseFields`, `listBaseRecords(opts.userIdType)`, `countBaseRecords`, `baseCellText`. Live-verified via the throwaway `lark-base-probe` (now deleted).

### Task 4: Field mapping (`_shared/master_data_map.ts`) — ✅ DONE
Pure `mapEmployeeInfoRecord(fields) -> { larkUserId, incoming, fullName }` + `routeKey(key)` (employee col / statutory id_type / bank code) + normalisers (`larkMsToPHDate`, `larkPersonId`, PH-mobile leading-zero restore). 8 deno tests green (`master_data_map_test.ts`). Uses the confirmed live field names; emits a flat `incoming` keyed for the 3-way merge.

### Task 5: `sync-lark-master-data` edge function — ✅ DONE (dry-run validated on prod)
Resolve wiki → read Employee Information (user_id person fields) → build lark_user_id→employee map (org-wide, linked+live) → per row: skip if unlinked/unmatched; else assemble `current` from employee cols + statutory + bank, `mergeRecord` vs `lark_master_snapshot`, route updates to employees/statutory(upsert on `employee_id,id_type`)/bank(update-or-insert), write back snapshot. `dry_run` mode returns aggregate change counts (no PII). Dry-run 2026-07-29: 33 total → 8 matched/updated, 17 unlinked, 8 unmatched, 0 errors; names untouched (merge correct). **Pending:** first real write (user go/no-go) + a Deno idempotency/app-edit-survives test on throwaway Postgres.

### Task 6: App "Sync from Lark" surface + read-only-origin badges — ⏳ IN PROGRESS
A manager action to invoke the sync + show the run summary; the Lark-owned fields on the employee profile badged "synced from Lark · last synced <t>" (editable — an edit claims the field). Widget-tested.

---

## Self-Review

**Spec coverage:** create-from-Lark + match-by-number (Task 5); smart merge protecting app edits (Task 2, the core; Task 5 applies it); field ownership (Task 4/5 touch only Lark-owned fields); snapshot storage (Task 1); wiki-wrapped access (Task 3); statutory/bank landing (Task 4); manager surface + badges (Task 6). ✓

**Placeholder scan:** Part A is complete, no-placeholder, TDD. Part B is *intentionally* deferred (not fabricated) because exact field names require live access — this is an honest gate, not a "TODO".

**Type consistency:** `mergeField`/`mergeRecord`/`FieldMerge` identical across Task 2 def, test, and Task 5 use. `lark_master_snapshot` (Task 1) is the store `mergeRecord` reads/writes.

**Sequencing:** Part A now (foundation, fully tested, de-risks the merge — the payroll-sensitive brain). Part B when the two remaining permissions land, so it's built + verified against the real Base, not guessed.
