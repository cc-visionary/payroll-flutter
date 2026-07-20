# Responsibility ↔ Task Unification — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Make a role-card **responsibility** and a workforce-planning **task** the same object — so HR maintains one list (on the card) and load derives itself.

**Architecture:** Promote the 164 card responsibilities into `wp_tasks` (ordered via new `area_sort`/`task_sort`). `wp_person_load` is rewritten to attribute hours by explicit owner → else split across role holders → else unattributed. `RoleScorecard.responsibilities` is backfilled from those rows (the KPI-unification trick) so the card detail, PDF, role tab, and contract prefill keep working untouched. The card editor persists rows instead of JSON, keyed by row id so costing survives renames.

**Tech Stack:** Supabase Postgres (migration + view), Flutter/Riverpod, the Plan 1–3 workforce stack.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-20-responsibility-task-unification-design.md`. Read its "three burden-killers" — they are the point of the feature.
- Repo gates on **`flutter analyze` only** — no `dart format`. Migrations forward-only; validate on throwaway Postgres; **do NOT push to prod** (user's call).
- **`role_scorecards.key_responsibilities` is NOT NULL and stays** (rollback). `toUpsert` must keep writing the key (as `[]`) or INSERT fails with `23502` — recorded lesson from the KPI work.
- **Order is load-bearing:** the role-card PDF and employment-contract prefill render responsibilities in authored order. Never sort by name.
- **Costing must survive edits:** a responsibility row carries cadence/minutes/owner. The editor identifies rows by **id**, so a rename is an UPDATE, never delete+insert.
- Existing model/провider surface stays: `wp_person_load` keeps its exact column list, so `WpPersonLoad` and all Plan 2/3 consumers need no changes.
- Prod today: 7 active cards, 42 areas, 164 responsibility strings; 118 legacy `wp_tasks` (`external_ref not null`, `role_scorecard_id is null`).

---

## File Structure

**Create:**
- `supabase/migrations/20260720000002_responsibility_task_unification.sql`
- `lib/features/responsibility_cards/responsibility_rows.dart` — pure grouping + editor diff helpers.
- `test/features/responsibility_cards/responsibility_rows_test.dart`

**Modify:**
- `lib/data/models/role_scorecard.dart` — `fromRow` backfills from the embed; `toUpsert` writes `key_responsibilities: []`.
- `lib/data/repositories/role_scorecard_repository.dart` — selects gain the `wp_tasks` embed; add responsibility persist methods.
- `lib/features/responsibility_cards/role_scorecard_form_screen.dart` — persist rows, not JSON.
- `lib/features/workforce_planning/tabs/tasks_tab.dart` — regroup by card → area.

---

### Task 1: Migration (sort columns + promotion + load rewrite)

**Files:** Create `supabase/migrations/20260720000002_responsibility_task_unification.sql`

**Interfaces:** Produces `wp_tasks.area_sort`/`task_sort`; 164 promoted rows; `wp_person_load` with derived-owner attribution (same column list as before).

- [ ] **Step 1: Write the migration**

```sql
-- Unify role-card responsibilities with wp_tasks: a responsibility IS a task.
-- 1) ordering columns (the card PDF + contract prefill render in authored order)
-- 2) promote each active card's key_responsibilities into wp_tasks (uncosted)
-- 3) wp_person_load attributes hours: explicit owner -> else split across role
--    holders -> else unattributed. Column list is UNCHANGED so Dart is unaffected.

alter table wp_tasks
  add column if not exists area_sort int not null default 0,
  add column if not exists task_sort int not null default 0;

-- Promotion. Idempotent on (role_scorecard_id, lower(trim(area)), lower(trim(name))).
do $$
declare c record; a jsonb; t jsonb; ai int; ti int;
begin
  for c in select id, company_id, key_responsibilities from role_scorecards where is_active loop
    ai := 0;
    for a in select * from jsonb_array_elements(coalesce(c.key_responsibilities, '[]'::jsonb)) loop
      ti := 0;
      for t in select * from jsonb_array_elements(coalesce(a->'tasks', '[]'::jsonb)) loop
        insert into wp_tasks (company_id, name, role_scorecard_id, responsibility_area,
                              area_sort, task_sort, times_source, minutes_source)
        select c.company_id, trim(t #>> '{}'), c.id, a->>'area', ai, ti, 'manual', 'manual'
        where trim(coalesce(t #>> '{}', '')) <> ''
          and not exists (
            select 1 from wp_tasks w
            where w.role_scorecard_id = c.id
              and lower(trim(coalesce(w.responsibility_area, ''))) = lower(trim(coalesce(a->>'area', '')))
              and lower(trim(w.name)) = lower(trim(t #>> '{}'))
          );
        ti := ti + 1;
      end loop;
      ai := ai + 1;
    end loop;
  end loop;
end $$;

-- Attribution rewrite.
create or replace view wp_person_load with (security_invoker = true) as
with holders as (
  select e.id as employee_id, e.role_scorecard_id,
         count(*) over (partition by e.role_scorecard_id) as holder_count
  from employees e
  where e.employment_status = 'ACTIVE' and e.deleted_at is null
    and e.role_scorecard_id is not null
),
attributed as (
  -- explicit owner carries the full hours
  select tc.owner_employee_id as employee_id, tc.task_id,
         tc.hours_per_month_base as hours, tc.is_growing
  from wp_task_computed tc
  where tc.owner_employee_id is not null
  union all
  -- else split evenly across the holders of the task's role card
  select h.employee_id, tc.task_id,
         tc.hours_per_month_base / h.holder_count, tc.is_growing
  from wp_task_computed tc
  join wp_tasks t on t.id = tc.task_id
  join holders  h on h.role_scorecard_id = t.role_scorecard_id
  where tc.owner_employee_id is null and t.role_scorecard_id is not null
)
select
  e.id         as employee_id,
  e.company_id,
  count(a.task_id) as tasks_owned,
  coalesce(sum(a.hours) filter (where not a.is_growing), 0) as hours_fixed,
  coalesce(sum(a.hours) filter (where a.is_growing), 0)     as hours_growing_base,
  coalesce(ov.capacity_hours, cfg.default_capacity_hours, 160) as capacity_hours,
  coalesce(cfg.growth_multiplier, 1) as growth_multiplier
from employees e
left join attributed            a   on a.employee_id = e.id
left join wp_capacity_overrides ov  on ov.employee_id = e.id
left join wp_config             cfg on cfg.company_id = e.company_id
where e.employment_status = 'ACTIVE' and e.deleted_at is null
group by e.id, e.company_id, ov.capacity_hours, cfg.default_capacity_hours, cfg.growth_multiplier;
```

- [ ] **Step 2: Validate on a throwaway Postgres**

Reuse the harness from the Plan 1 validation (`initdb` on a free high port, socket dir `/tmp`, stub `companies`/`employees`/`role_scorecards` + `set_updated_at`/`auth_*`, then apply `20260719000001`, `20260719000002`, this migration). Assert:
- `area_sort`/`task_sort` exist; re-running the migration inserts no duplicates (idempotent).
- A card with 2 areas × 2 tasks promotes 4 rows with `area_sort` 0,0,1,1 and `task_sort` 0,1,0,1.
- Attribution: (a) explicit owner → full hours; (b) no owner + role with 2 holders → each gets half; (c) role with 0 holders → nobody accrues; (d) neither owner nor card → nobody accrues.

Expected: all four attribution cases match; second apply is a no-op.

- [ ] **Step 3: Commit**
```bash
git add supabase/migrations/20260720000002_responsibility_task_unification.sql
git commit -m "feat(workforce): promote card responsibilities into wp_tasks + derived-owner load"
```

---

### Task 2: Pure helpers (grouping + editor diff)

**Files:** Create `lib/features/responsibility_cards/responsibility_rows.dart`, `test/features/responsibility_cards/responsibility_rows_test.dart`

**Interfaces:** Produces
- `List<ResponsibilityArea> responsibilitiesFromTaskRows(List<Map<String, dynamic>> rows)` — group by `responsibility_area`, areas ordered by min `area_sort` (tie → name), tasks by `task_sort`. Rows with a blank area or blank name are skipped (those are non-responsibility tasks).
- `class RespDraft { final String? id; String name; }` and
  `({List<Map<String,dynamic>> inserts, List<Map<String,dynamic>> updates, List<String> deleteIds}) diffResponsibilities({required List<({String area, List<RespDraft> tasks})> draft, required List<Map<String,dynamic>> existingRows, required String cardId, required String companyId})` — rows keyed by **id** so a rename is an UPDATE (costing preserved); missing ids are inserts; existing ids absent from the draft are deletes. Assigns `area_sort`/`task_sort` from list position.

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/features/responsibility_cards/responsibility_rows.dart';

void main() {
  test('responsibilitiesFromTaskRows groups + orders by sort, not name', () {
    final rows = <Map<String, dynamic>>[
      {'name': 'Zebra task', 'responsibility_area': 'Alpha', 'area_sort': 0, 'task_sort': 0},
      {'name': 'Apple task', 'responsibility_area': 'Alpha', 'area_sort': 0, 'task_sort': 1},
      {'name': 'Only', 'responsibility_area': 'Beta', 'area_sort': 1, 'task_sort': 0},
      {'name': 'unlinked', 'responsibility_area': null, 'area_sort': 0, 'task_sort': 0},
    ];
    final out = responsibilitiesFromTaskRows(rows);
    expect(out.map((a) => a.area).toList(), ['Alpha', 'Beta']); // area_sort order
    expect(out.first.tasks, ['Zebra task', 'Apple task']);      // task_sort, NOT alphabetical
    expect(out.length, 2);                                       // blank-area row skipped
  });

  test('diffResponsibilities updates renames by id (preserves costing) and assigns sorts', () {
    final existing = <Map<String, dynamic>>[
      {'id': 't1', 'name': 'Old name', 'responsibility_area': 'Alpha'},
      {'id': 't2', 'name': 'Gone', 'responsibility_area': 'Alpha'},
    ];
    final d = diffResponsibilities(
      draft: [
        (area: 'Alpha', tasks: [RespDraft(id: 't1', name: 'New name'), RespDraft(id: null, name: 'Fresh')]),
      ],
      existingRows: existing,
      cardId: 'c1',
      companyId: 'co',
    );
    expect(d.updates.single['id'], 't1');
    expect(d.updates.single['name'], 'New name');   // rename = UPDATE, keeps hours
    expect(d.updates.single['task_sort'], 0);
    expect(d.inserts.single['name'], 'Fresh');
    expect(d.inserts.single['task_sort'], 1);
    expect(d.inserts.single['role_scorecard_id'], 'c1');
    expect(d.deleteIds, ['t2']);
  });
}
```

- [ ] **Step 2: Run to verify it fails** — `flutter test test/features/responsibility_cards/responsibility_rows_test.dart` → FAIL (undefined).

- [ ] **Step 3: Implement `responsibility_rows.dart`**

```dart
import '../../data/models/role_scorecard.dart';

/// Rebuilds a card's ordered responsibility tree from its wp_tasks rows.
/// Areas order by their smallest `area_sort` (ties by name); tasks by `task_sort`.
/// Rows with no area or no name are not card responsibilities and are skipped.
List<ResponsibilityArea> responsibilitiesFromTaskRows(List<Map<String, dynamic>> rows) {
  final areaSort = <String, int>{};
  final byArea = <String, List<({int sort, String name})>>{};
  for (final r in rows) {
    final area = (r['responsibility_area'] as String?)?.trim() ?? '';
    final name = (r['name'] as String?)?.trim() ?? '';
    if (area.isEmpty || name.isEmpty) continue;
    final aSort = (r['area_sort'] as num?)?.toInt() ?? 0;
    final tSort = (r['task_sort'] as num?)?.toInt() ?? 0;
    final prev = areaSort[area];
    areaSort[area] = prev == null || aSort < prev ? aSort : prev;
    (byArea[area] ??= []).add((sort: tSort, name: name));
  }
  final areas = byArea.keys.toList()
    ..sort((a, b) {
      final c = areaSort[a]!.compareTo(areaSort[b]!);
      return c != 0 ? c : a.compareTo(b);
    });
  return [
    for (final a in areas)
      ResponsibilityArea(
        area: a,
        tasks: (byArea[a]!..sort((x, y) => x.sort.compareTo(y.sort)))
            .map((e) => e.name)
            .toList(),
      ),
  ];
}

/// One editable responsibility line. [id] is the wp_tasks row id when it already
/// exists — that's what makes a rename an UPDATE instead of delete+insert (which
/// would discard the row's cadence/minutes/owner).
class RespDraft {
  final String? id;
  String name;
  RespDraft({this.id, required this.name});
}

/// Diffs the edited tree against the card's existing responsibility rows.
({List<Map<String, dynamic>> inserts, List<Map<String, dynamic>> updates, List<String> deleteIds})
    diffResponsibilities({
  required List<({String area, List<RespDraft> tasks})> draft,
  required List<Map<String, dynamic>> existingRows,
  required String cardId,
  required String companyId,
}) {
  final inserts = <Map<String, dynamic>>[];
  final updates = <Map<String, dynamic>>[];
  final kept = <String>{};
  for (var ai = 0; ai < draft.length; ai++) {
    final area = draft[ai].area.trim();
    if (area.isEmpty) continue;
    final tasks = draft[ai].tasks;
    for (var ti = 0; ti < tasks.length; ti++) {
      final name = tasks[ti].name.trim();
      if (name.isEmpty) continue;
      final id = tasks[ti].id;
      if (id == null) {
        inserts.add({
          'company_id': companyId,
          'role_scorecard_id': cardId,
          'responsibility_area': area,
          'name': name,
          'area_sort': ai,
          'task_sort': ti,
          'times_source': 'manual',
          'minutes_source': 'manual',
        });
      } else {
        kept.add(id);
        updates.add({
          'id': id,
          'responsibility_area': area,
          'name': name,
          'area_sort': ai,
          'task_sort': ti,
        });
      }
    }
  }
  final deleteIds = [
    for (final r in existingRows)
      if (r['id'] is String && !kept.contains(r['id'] as String)) r['id'] as String,
  ];
  return (inserts: inserts, updates: updates, deleteIds: deleteIds);
}
```

- [ ] **Step 4: Run tests + analyze** — tests PASS (2); `flutter analyze` on both files clean.

- [ ] **Step 5: Commit**
```bash
git add lib/features/responsibility_cards/responsibility_rows.dart test/features/responsibility_cards/responsibility_rows_test.dart
git commit -m "feat(workforce): pure responsibility grouping + editor diff helpers"
```

---

### Task 3: Model + repository backfill

**Files:** Modify `lib/data/models/role_scorecard.dart`, `lib/data/repositories/role_scorecard_repository.dart`. Test: extend `test/features/responsibility_cards/responsibility_rows_test.dart` (or a new model test).

**Interfaces:** Consumes Task 2's `responsibilitiesFromTaskRows`. Produces: `RoleScorecard.responsibilities` sourced from the embed; `toUpsert` writes `key_responsibilities: const []`; repo selects embed the rows; `saveResponsibilities(...)` applies a Task-2 diff.

- [ ] **Step 1: Repository selects gain the embed**

In `role_scorecard_repository.dart` lines ~70 and ~81, extend BOTH select strings:
```dart
'*, role_scorecard_kpis(target, frequency, sort_order, kpis(name, measurement_unit)), '
'wp_tasks(id, name, responsibility_area, area_sort, task_sort)'
```

- [ ] **Step 2: Model backfill**

In `role_scorecard.dart` `fromRow`, replace the `key_responsibilities` parse with the embed-backed build (keep the JSON parse ONLY as a fallback when the embed is absent, so any caller that doesn't select the embed still renders):
```dart
    final rawTasks = r['wp_tasks'];
    List<ResponsibilityArea> responsibilities;
    if (rawTasks is List && rawTasks.isNotEmpty) {
      responsibilities =
          responsibilitiesFromTaskRows(rawTasks.cast<Map<String, dynamic>>());
    } else if (rawResp is List) {
      // legacy fallback: the JSON column (pre-unification rows / selects without the embed)
      responsibilities =
          rawResp.cast<Map<String, dynamic>>().map(ResponsibilityArea.fromJson).toList();
    } else {
      responsibilities = const [];
    }
```
And in `toUpsert`, change the responsibilities line to write an empty array with a comment mirroring the `kpis` one:
```dart
    // Responsibilities now live in wp_tasks (see 20260720000002). The column is
    // NOT NULL and kept read-only for rollback — write [] to satisfy it on
    // INSERT; omitting the key raises 23502.
    'key_responsibilities': const [],
```

- [ ] **Step 3: Add the persist method to the repository**

```dart
  /// Applies a responsibility diff (see diffResponsibilities) for one card.
  Future<void> saveResponsibilities({
    required List<Map<String, dynamic>> inserts,
    required List<Map<String, dynamic>> updates,
    required List<String> deleteIds,
  }) async {
    if (inserts.isNotEmpty) await _client.from('wp_tasks').insert(inserts);
    for (final u in updates) {
      final id = u.remove('id') as String;
      await _client.from('wp_tasks').update(u).eq('id', id);
    }
    if (deleteIds.isNotEmpty) {
      await _client.from('wp_tasks').delete().inFilter('id', deleteIds);
    }
  }
```

- [ ] **Step 4: Contract-prefill regression test**

Add a test asserting a `RoleScorecard` built from embed rows produces the same `(area, tasks)` structure/order that the employment-contract prefill copies (`employment_contract_form.dart` maps `match.responsibilities` → `ContractResponsibility`). Build a card row with the embed, assert `responsibilities` area order and task order match the authored sorts.

- [ ] **Step 5: Analyze + full suite + commit**

Run `flutter analyze` (no new issues) and `flutter test` (green — watch for existing role-card tests that assumed the JSON path; update them to the embed and report).
```bash
git add lib/data/models/role_scorecard.dart lib/data/repositories/role_scorecard_repository.dart test/
git commit -m "feat(workforce): back RoleScorecard.responsibilities with wp_tasks rows"
```

---

### Task 4: Card editor persists rows

**Files:** Modify `lib/features/responsibility_cards/role_scorecard_form_screen.dart`

**Interfaces:** Consumes `RespDraft`, `diffResponsibilities`, `saveResponsibilities`.

- [ ] **Step 1: Carry row ids in the draft**

`_AreaDraft.tasks` currently is `List<String>`. Change it to `List<RespDraft>` so each line keeps its wp_tasks id. Seed it in the load path (`~line 86`) from the card's embed rows — the screen needs the raw rows, so load them via the repository's `byId` embed (or pass them in) and build `_AreaDraft(area, [RespDraft(id: …, name: …), …])`. The editor's add/remove/reorder UI (`~lines 454–500`) changes only in that a new line is `RespDraft(id: null, name: '')`.

- [ ] **Step 2: Persist rows instead of JSON**

At the save path (`~line 131`), stop putting `responsibilities:` into the card upsert (the model now writes `[]`). After the card upsert succeeds, call:
```dart
    final d = diffResponsibilities(
      draft: [for (final a in _areas) (area: a.area, tasks: a.tasks)],
      existingRows: _existingResponsibilityRows,   // captured on load
      cardId: savedCardId,
      companyId: companyId,
    );
    await ref.read(roleScorecardRepositoryProvider).saveResponsibilities(
        inserts: d.inserts, updates: d.updates, deleteIds: d.deleteIds);
    ref.invalidate(roleScorecardListProvider);
    ref.invalidate(wpTasksProvider);
    ref.invalidate(wpPersonLoadsProvider);
```
(For a NEW card, `savedCardId` comes from the upsert's returned row; `_existingResponsibilityRows` is empty.)

- [ ] **Step 3: Analyze + suite + manual-check note + commit**

`flutter analyze` clean; `flutter test` green. Report that editing a card's responsibilities now needs a GUI smoke (rename preserves hours; delete removes the row; reorder updates sorts).
```bash
git add lib/features/responsibility_cards/role_scorecard_form_screen.dart
git commit -m "feat(workforce): card editor persists responsibilities as task rows"
```

---

### Task 5: Tasks tab regrouped by card → area

**Files:** Modify `lib/features/workforce_planning/tabs/tasks_tab.dart`. Test: extend `test/features/workforce_planning/tasks_tab_test.dart`.

- [ ] **Step 1: Regroup the list**

Group tasks into, in order:
1. one group per **role card** (label = job title), each nested by **responsibility area** in `area_sort` order, tasks in `task_sort` order;
2. **From capacity model (N)** — `external_ref != null && role_scorecard_id == null`, collapsible, with a bulk-delete action;
3. **Unattributed (N)** — no card and no explicit owner and not in bucket 2.

Per row show: name · hours or a tinted **"not costed"** chip (when the task has no times/minutes) · effective owner with a **"derived"** hint when it comes from the role rather than an explicit owner · cadence. Keep edit/delete and the existing bulk-assign.

- [ ] **Step 2: Widget test**

Extend the existing test: a card-linked task renders under its card + area heading; a legacy task (external_ref set, no card) renders under "From capacity model"; an uncosted task shows the "not costed" chip.

- [ ] **Step 3: Analyze + suite + commit**
```bash
git add lib/features/workforce_planning/tabs/tasks_tab.dart test/features/workforce_planning/tasks_tab_test.dart
git commit -m "feat(workforce): Tasks tab grouped by role card and responsibility area"
```

---

## Self-Review

**Spec coverage:** promotion + ordering (Task 1) ✓; derived-owner split attribution (Task 1 view) ✓; backfill so PDF/contract/detail/role-tab keep working (Task 3) ✓; editor writes rows with costing preserved via id-keyed diff (Tasks 2+4) ✓; Tasks tab regroup with legacy + unattributed buckets and "not costed"/"derived" markers (Task 5) ✓; `key_responsibilities` kept and written as `[]` (Task 3) ✓; no forced dedupe/costing (nothing in the plan requires either) ✓.

**Placeholder scan:** none — SQL, helpers, and diff logic are complete. Task 4 references existing line numbers rather than reproducing 849 lines of editor; its two changes (draft carries ids; persist via diff) are specified with the exact call.

**Type consistency:** `responsibilitiesFromTaskRows` / `diffResponsibilities` / `RespDraft` signatures match their tests and the Task 3/4 callers; the embed field names (`id, name, responsibility_area, area_sort, task_sort`) match the migration's columns and the model's parse; `wp_person_load`'s column list is unchanged so `WpPersonLoad` and every Plan 2/3 consumer stay valid.

**Risk note for the executor:** Task 3 changes what every role-card consumer reads. Run the full suite after it and expect to update any test that hand-built a card row with `key_responsibilities`; report each change rather than silently rewriting assertions.
