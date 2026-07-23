# Criticality + Essential + Status Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every accountability (`wp_tasks` row) three job-analysis attributes — criticality (LOW→CRITICAL), an ADA essential-function flag, and an ACTIVE/ARCHIVED lifecycle status — surface criticality/essential as chips, and replace the per-row hard-delete with a reversible Archive.

**Architecture:** Three nullable/defaulted columns are added to `wp_tasks`; the `wp_task_computed` view excludes ARCHIVED rows so archived work silently drops out of load and every derived list without touching `wp_person_load`. A DB CHECK ties the existing `is_expectation` flag to `is_essential` (an expectation is by definition non-essential). The Flutter model carries the fields through; the task editor gains a criticality dropdown + essential switch; the Tasks tab renders chips and archives instead of deleting, with an "Archived" section to restore from.

**Tech Stack:** Supabase Postgres (migrations + `security_invoker` views), Flutter (Material 3, Riverpod), `flutter_test`.

## Global Constraints

- Repo gates on `flutter analyze` only — it must end clean (0 errors). Do **NOT** run `dart format`; match each file's existing surrounding style (the repo mixes old/new formatter styles).
- Migrations are **forward-only**; never edit an applied migration, always add a new file. New file: `supabase/migrations/20260723000005_task_criticality_essential_status.sql`.
- The prod DB password is **not** in the repo. Apply migrations with `supabase db push` (answer the `Y/n` prompt `Y`). The only company on prod is GameCove Inc.
- `env/prod.json` holds `SUPABASE_URL` and a privileged `service_role` key. Use it **only** for the reversible prod verifications in Task 1, and **state in the report each time you used it**. Every verification write must be reverted so prod data is left unchanged.
- Per `PRODUCT.md`: numbers/percentages use `AppTheme.mono(context)`; status chips are tinted + borderless via `StatusChip(label:, tone:)` from `lib/widgets/` with `StatusTone` from `lib/app/status_colors.dart` — never colored borders. Single purple CTA.
- Criticality values are exactly `LOW`, `MEDIUM`, `HIGH`, `CRITICAL` (uppercase in the DB). Status values are exactly `ACTIVE`, `ARCHIVED`.

---

## File Structure

- `supabase/migrations/20260723000005_task_criticality_essential_status.sql` — **create.** 3 columns, backfill, invariant CHECK, view rewrite.
- `lib/data/models/workforce_planning.dart` — **modify.** `WpTask` gains `criticality`, `isEssential`, `status`; `fromRow` / `toUpsert` / `copyWithSort`.
- `lib/features/workforce_planning/task_costing.dart` — **modify.** `CostDraft.applyTo` carries the new columns + `isExpectation` (they must not be dropped when a cost edit rebuilds the task).
- `lib/data/repositories/workforce_planning_repository.dart` — **modify.** Add `setTaskArchived`; extend `setTaskExpectation` to keep `is_essential` consistent.
- `lib/features/workforce_planning/task_badges.dart` — **create.** Pure `criticalityTone` / `criticalityLabel` display helpers.
- `lib/features/workforce_planning/tasks_rows.dart` — **modify.** Add pure `partitionByStatus`.
- `lib/features/workforce_planning/tabs/task_form_dialog.dart` — **modify.** Criticality dropdown + essential switch; `buildTaskFromForm` gains `criticality`/`isEssential` and preserves `isExpectation`.
- `lib/features/workforce_planning/tabs/tasks_tab.dart` — **modify.** Chips in the name cell; per-row Delete → Archive; Archived section with Restore.
- Tests: new `test/features/workforce_planning/task_badges_test.dart`, new `test/data/models/wp_task_status_essential_test.dart`, new `test/features/workforce_planning/tasks_tab_archive_test.dart`; extend `test/features/workforce_planning/task_costing_test.dart`, `test/features/workforce_planning/task_form_dialog_test.dart`, `test/features/workforce_planning/tasks_rows_test.dart`.

---

### Task 1: Migration — three columns, the expectation↔essential invariant, and archived-excluded load

**Files:**
- Create: `supabase/migrations/20260723000005_task_criticality_essential_status.sql`

**Interfaces:**
- Produces: columns `wp_tasks.criticality text`, `wp_tasks.is_essential boolean`, `wp_tasks.status text`; constraint `wp_tasks_expectation_non_essential`; `wp_task_computed` now returns only `status = 'ACTIVE'` rows (same columns as before).

- [ ] **Step 1: Write the migration file**

```sql
-- Accountability attributes: criticality (HRCI prioritiser / ADA "importance"),
-- is_essential (ADA essential-function flag), and status (ACTIVE/ARCHIVED
-- lifecycle). Archived work drops out of load and every derived list but stays
-- for reference and can be restored -- deleting a row that carries history is
-- the wrong tool, archiving is the right one.

alter table wp_tasks
  add column if not exists criticality text
    check (criticality is null or criticality in ('LOW','MEDIUM','HIGH','CRITICAL'));

alter table wp_tasks
  add column if not exists is_essential boolean not null default true;

alter table wp_tasks
  add column if not exists status text not null default 'ACTIVE'
    check (status in ('ACTIVE','ARCHIVED'));

comment on column wp_tasks.criticality is
  'Business criticality LOW..CRITICAL. The ADA essential-function test''s '
  '"importance" leg; answers "does the business stop if this fails".';
comment on column wp_tasks.is_essential is
  'ADA essential-function flag: work that is a reason the role exists, vs a '
  'catch-all. An expectation is by definition non-essential (see the '
  'wp_tasks_expectation_non_essential constraint).';
comment on column wp_tasks.status is
  'ACTIVE or ARCHIVED. ARCHIVED work is excluded from wp_task_computed (so it '
  'leaves load, derived task lists and the duplicate check) but is retained.';

-- An expectation is a non-essential catch-all: reconcile existing rows BEFORE
-- adding the constraint, or the pre-existing expectation rows (is_essential
-- defaulted true) would violate it.
update wp_tasks set is_essential = false where coalesce(is_expectation, false);

alter table wp_tasks
  add constraint wp_tasks_expectation_non_essential
  check (not (coalesce(is_expectation, false) and is_essential));

-- Re-point wp_task_computed to skip ARCHIVED rows. Output columns are unchanged
-- in name/order/type, so the dependent wp_person_load view needs no change; only
-- the row set shrinks (archived tasks stop contributing hours and stop appearing
-- in anyone's derived task list).
create or replace view wp_task_computed with (security_invoker = true) as
select
  x.task_id,
  x.company_id,
  x.owner_employee_id,
  x.node_id,
  x.skill_tier,
  x.risk,
  x.is_growing,
  x.times_per_month_base,
  x.minutes_each,
  case when x.direct_hours is not null
       then x.direct_hours
       else x.times_per_month_base * x.minutes_each / 60.0 end as hours_per_month_base
from (
  select
    t.id                as task_id,
    t.company_id,
    t.owner_employee_id,
    t.node_id,
    t.skill_tier,
    t.risk,
    t.hours_per_month   as direct_hours,
    (t.hours_per_month is null
       and t.times_source = 'driver'
       and coalesce(d.grows, false)) as is_growing,
    case when t.times_source = 'driver'
         then coalesce(d.value, 0) * t.driver_factor
         else coalesce(t.times_manual, 0) end as times_per_month_base,
    case when t.minutes_source = 'rate'
         then coalesce(r.minutes_each, 0)
         else coalesce(t.minutes_manual, 0) end as minutes_each
  from wp_tasks t
  left join wp_drivers d on d.id = t.driver_id
  left join wp_rates   r on r.id = t.rate_id
  where t.status = 'ACTIVE'
) x;
```

- [ ] **Step 2: Apply to prod**

Run: `supabase db push` and answer `Y`.
Expected: the new migration is listed as applied; no error. If `db push` reports the file already applied (a prior partial run), confirm the columns exist instead — see Step 3.

- [ ] **Step 3: Verify the columns + constraint landed (service_role — flag this use)**

Read `SUPABASE_URL` and the `service_role` key from `env/prod.json`. Pick any one task id:

```bash
BASE="$SUPABASE_URL/rest/v1"
# a) columns present + defaults applied
curl -s "$BASE/wp_tasks?select=id,criticality,is_essential,status&limit=1" \
  -H "apikey: $SERVICE_ROLE" -H "Authorization: Bearer $SERVICE_ROLE"
```
Expected: a row with `"is_essential": true` (or false if it is an expectation) and `"status": "ACTIVE"`.

- [ ] **Step 4: Verify the invariant CHECK rejects an essential expectation (reversible)**

```bash
# Grab an existing ACTIVE, non-expectation task id first, call it $TID.
curl -s -X PATCH "$BASE/wp_tasks?id=eq.$TID" \
  -H "apikey: $SERVICE_ROLE" -H "Authorization: Bearer $SERVICE_ROLE" \
  -H "Content-Type: application/json" -H "Prefer: return=minimal" \
  -d '{"is_expectation": true, "is_essential": true}' -w '%{http_code}\n'
```
Expected: HTTP `400`, Postgres error `23514`, constraint `wp_tasks_expectation_non_essential`. The row is unchanged. (No revert needed — the write was rejected.)

- [ ] **Step 5: Verify ARCHIVED drops out of wp_task_computed, then restore**

```bash
# Set one task ARCHIVED, confirm it vanishes from the view, then set it back.
curl -s -X PATCH "$BASE/wp_tasks?id=eq.$TID" \
  -H "apikey: $SERVICE_ROLE" -H "Authorization: Bearer $SERVICE_ROLE" \
  -H "Content-Type: application/json" -H "Prefer: return=minimal" \
  -d '{"status":"ARCHIVED"}' -w '%{http_code}\n'
curl -s "$BASE/wp_task_computed?task_id=eq.$TID&select=task_id" \
  -H "apikey: $SERVICE_ROLE" -H "Authorization: Bearer $SERVICE_ROLE"
# revert:
curl -s -X PATCH "$BASE/wp_tasks?id=eq.$TID" \
  -H "apikey: $SERVICE_ROLE" -H "Authorization: Bearer $SERVICE_ROLE" \
  -H "Content-Type: application/json" -H "Prefer: return=minimal" \
  -d '{"status":"ACTIVE"}' -w '%{http_code}\n'
```
Expected: after ARCHIVED, the `wp_task_computed` query returns `[]`; after the revert, `$TID` is ACTIVE again.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260723000005_task_criticality_essential_status.sql
git commit -m "data(workforce): criticality, essential-function and ARCHIVED status on tasks"
```

---

### Task 2: Model — `WpTask` carries criticality / isEssential / status

**Files:**
- Modify: `lib/data/models/workforce_planning.dart:61-144`
- Test: `test/data/models/wp_task_status_essential_test.dart` (create)

**Interfaces:**
- Consumes: the DB columns from Task 1.
- Produces: `WpTask.criticality` (`String?`), `WpTask.isEssential` (`bool`, default `true`), `WpTask.status` (`String`, default `'ACTIVE'`); `toUpsert` writes `criticality`, `is_essential` (enforcing the invariant), `status`.

- [ ] **Step 1: Write the failing tests**

```dart
// test/data/models/wp_task_status_essential_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';

void main() {
  test('fromRow reads criticality, is_essential and status with defaults', () {
    final t = WpTask.fromRow({
      'id': 't1', 'company_id': 'c', 'name': 'Pack',
      'criticality': 'HIGH', 'is_essential': true, 'status': 'ACTIVE',
    });
    expect(t.criticality, 'HIGH');
    expect(t.isEssential, isTrue);
    expect(t.status, 'ACTIVE');

    final bare = WpTask.fromRow({'id': 't2', 'company_id': 'c', 'name': 'x'});
    expect(bare.criticality, isNull);
    expect(bare.isEssential, isTrue, reason: 'default is essential');
    expect(bare.status, 'ACTIVE', reason: 'default is active');
  });

  test('toUpsert writes the three columns', () {
    const t = WpTask(
      id: 't1', companyId: 'c', name: 'Pack',
      criticality: 'CRITICAL', isEssential: true, status: 'ARCHIVED');
    final m = t.toUpsert('c');
    expect(m['criticality'], 'CRITICAL');
    expect(m['is_essential'], true);
    expect(m['status'], 'ARCHIVED');
  });

  test('toUpsert forces is_essential false when the task is an expectation', () {
    const t = WpTask(
      id: 't1', companyId: 'c', name: 'Grow',
      isExpectation: true, isEssential: true);
    expect(t.toUpsert('c')['is_essential'], false,
        reason: 'an expectation is by definition non-essential');
  });

  test('copyWithSort preserves the three columns', () {
    const t = WpTask(
      id: 't1', companyId: 'c', name: 'Pack',
      criticality: 'MEDIUM', isEssential: false, status: 'ARCHIVED');
    final moved = t.copyWithSort(areaSort: 3, taskSort: 4);
    expect(moved.criticality, 'MEDIUM');
    expect(moved.isEssential, isFalse);
    expect(moved.status, 'ARCHIVED');
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/data/models/wp_task_status_essential_test.dart`
Expected: FAIL — `criticality`/`isEssential`/`status` are not defined on `WpTask`.

- [ ] **Step 3: Add the fields**

In the field block (`workforce_planning.dart:63-65`), add `criticality` to the `String?` group and add the two typed fields near `hoursPerMonth`:

```dart
  /// Business criticality LOW/MEDIUM/HIGH/CRITICAL (nullable = unset). The ADA
  /// essential-function test's "importance" leg.
  final String? criticality;

  /// ADA essential-function flag. An expectation is always non-essential; the
  /// DB constraint and [toUpsert] keep the two consistent.
  final bool isEssential;

  /// Lifecycle: 'ACTIVE' or 'ARCHIVED'. ARCHIVED work leaves load and the
  /// derived lists (via wp_task_computed) but is retained and restorable.
  final String status;
```

In the constructor (`:81-88`) add the params with defaults:

```dart
    this.criticality, this.isEssential = true, this.status = 'ACTIVE',
```
(place them alongside `this.isExpectation = false, this.hoursPerMonth});` — keep `hoursPerMonth` last so existing positional-free named call sites are unaffected.)

In `fromRow` (`:89-106`), add:

```dart
    criticality: r['criticality'] as String?,
    isEssential: r['is_essential'] as bool? ?? true,
    status: r['status'] as String? ?? 'ACTIVE',
```

In `copyWithSort` (`:109-118`), add `criticality: criticality, isEssential: isEssential, status: status,`.

In `toUpsert` (`:120-143`), add to the returned map (near `'is_expectation': isExpectation,`):

```dart
      'criticality': _s(criticality),
      // An expectation is by definition non-essential — enforce it here so no
      // saveTask path can violate the wp_tasks_expectation_non_essential CHECK.
      'is_essential': isExpectation ? false : isEssential,
      'status': status,
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/data/models/wp_task_status_essential_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/data/models/workforce_planning.dart test/data/models/wp_task_status_essential_test.dart
git commit -m "feat(workforce): WpTask carries criticality, essential flag and status"
```

---

### Task 3: Costing — `applyTo` must not drop the new columns

**Files:**
- Modify: `lib/features/workforce_planning/task_costing.dart:77-102`
- Test: `test/features/workforce_planning/task_costing_test.dart:120-130` (extend the existing round-trip test)

**Interfaces:**
- Consumes: `WpTask.criticality/isEssential/status/isExpectation` from Task 2.
- Produces: `CostDraft.applyTo` returns a task that preserves all four (it already preserves `skillTier`/`risk`).

- [ ] **Step 1: Write the failing test** — extend the existing `applyTo` round-trip

Find the test around `test/features/workforce_planning/task_costing_test.dart:128` (`CostDraft.fromTask(t).applyTo(t)`). Ensure the source task sets the new columns and assert they survive. Add (adapt the existing `t` literal in that test to include the fields, then assert):

```dart
    expect(back.criticality, t.criticality);
    expect(back.isEssential, t.isEssential);
    expect(back.status, t.status);
    expect(back.isExpectation, t.isExpectation);
```
If the test's source `t` does not already set these, give it `criticality: 'HIGH', isEssential: false, status: 'ARCHIVED', isExpectation: true` so the assertions are meaningful.

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/workforce_planning/task_costing_test.dart`
Expected: FAIL — `applyTo` drops `criticality`/`isEssential`/`status`/`isExpectation` (they come back as defaults).

- [ ] **Step 3: Carry the columns in `applyTo`**

In `applyTo` (`task_costing.dart:77-102`), add before the closing `);`:

```dart
        criticality: t.criticality,
        isEssential: t.isEssential,
        status: t.status,
        isExpectation: t.isExpectation,
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/workforce_planning/task_costing_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/workforce_planning/task_costing.dart test/features/workforce_planning/task_costing_test.dart
git commit -m "fix(workforce): cost-edit round-trip preserves criticality/essential/status"
```

---

### Task 4: Repository — Archive/Restore + expectation keeps essential consistent

**Files:**
- Modify: `lib/data/repositories/workforce_planning_repository.dart:105-121`

**Interfaces:**
- Consumes: nothing new.
- Produces: `Future<void> setTaskArchived(String taskId, bool archived)`; `setTaskExpectation` now also writes `is_essential`.

These are thin PostgREST passthroughs (the repo has no unit tests; the DB CHECK from Task 1 is the real guard). They are exercised end-to-end by the Task 6 widget test via the fake repo.

- [ ] **Step 1: Extend `setTaskExpectation`**

Replace the body's update map so marking an expectation also sets `is_essential = false`, and clearing it restores the default `true`:

```dart
  Future<void> setTaskExpectation(String taskId, bool isExpectation) async {
    await _client.from('wp_tasks').update({
      'is_expectation': isExpectation,
      // Keep the invariant: an expectation is non-essential; a task made
      // costable again returns to the essential default. Setting is_essential in
      // the SAME statement avoids a window where the row violates the CHECK.
      'is_essential': !isExpectation,
      if (isExpectation) ...{
        'times_manual': null,
        'driver_id': null,
        'minutes_manual': null,
        'rate_id': null,
        'hours_per_month': null,
      },
    }).eq('id', taskId);
  }
```

- [ ] **Step 2: Add `setTaskArchived` right after `setTaskExpectation`**

```dart
  /// Archives (or restores) an accountability. ARCHIVED work leaves load and
  /// the derived lists (wp_task_computed filters on status) but is retained and
  /// can be restored — the correct tool for "no longer needed", vs a hard
  /// delete of a row that carries history.
  Future<void> setTaskArchived(String taskId, bool archived) async {
    await _client.from('wp_tasks')
        .update({'status': archived ? 'ARCHIVED' : 'ACTIVE'})
        .eq('id', taskId);
  }
```

- [ ] **Step 3: Verify it compiles**

Run: `flutter analyze lib/data/repositories/workforce_planning_repository.dart`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/data/repositories/workforce_planning_repository.dart
git commit -m "feat(workforce): archive/restore a task; expectation stays non-essential"
```

---

### Task 5: Editor — criticality dropdown + essential switch

**Files:**
- Modify: `lib/features/workforce_planning/tabs/task_form_dialog.dart` (`buildTaskFromForm` `:47-101`; state `:133-215`; body near `:321-350`)
- Test: `test/features/workforce_planning/task_form_dialog_test.dart` (extend)

**Interfaces:**
- Consumes: `WpTask.criticality/isEssential/isExpectation`.
- Produces: `buildTaskFromForm` gains `String? criticality` and `bool isEssential = true` params and preserves `existing?.isExpectation`; the dialog persists both controls.

- [ ] **Step 1: Write the failing pure tests**

Add to `task_form_dialog_test.dart`:

```dart
  test('buildTaskFromForm carries criticality and the essential flag', () {
    final t = buildTaskFromForm(
      companyId: 'c', name: 'Pack',
      timesSource: 'manual', minutesSource: 'manual',
      criticality: 'CRITICAL', isEssential: false);
    expect(t.criticality, 'CRITICAL');
    expect(t.isEssential, isFalse);
  });

  test('buildTaskFromForm preserves an existing expectation flag', () {
    const existing = WpTask(
      id: 't1', companyId: 'c', name: 'Grow', isExpectation: true);
    final t = buildTaskFromForm(
      existing: existing, companyId: 'c', name: 'Grow',
      timesSource: 'manual', minutesSource: 'manual');
    expect(t.isExpectation, isTrue,
        reason: 'editing a task must not silently clear its expectation flag');
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/workforce_planning/task_form_dialog_test.dart`
Expected: FAIL — `criticality`/`isEssential` are not params of `buildTaskFromForm`; `isExpectation` comes back `false`.

- [ ] **Step 3: Extend `buildTaskFromForm`**

Add two params to the signature (`:47-68`), after `String? hoursPerMonthText,`:

```dart
  String? criticality,
  bool isEssential = true,
```

In the returned `WpTask(...)` (`:71-100`), add:

```dart
    criticality: criticality,
    isEssential: isEssential,
    isExpectation: existing?.isExpectation ?? false,
```

- [ ] **Step 4: Add the dialog controls**

State (near `:152-153`):

```dart
  late String? _criticality = widget.existing?.criticality;
  late bool _essential = widget.existing?.isEssential ?? true;
```

Add a top-level const near `_risks` (`:8-9`):

```dart
const _criticalities = ['LOW', 'MEDIUM', 'HIGH', 'CRITICAL'];
```

In `_save` where it calls `buildTaskFromForm` (near `:204`), pass:

```dart
      criticality: _criticality,
      isEssential: _essential,
```

In the body, after the Skill tier / Risk `Row` (`:322-348`), insert:

```dart
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _present(_criticality, _criticalities),
                  isExpanded: true,
                  decoration: _dec('Criticality'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('— None —')),
                    ..._criticalities.map((v) =>
                        DropdownMenuItem<String?>(value: v, child: Text(v))),
                  ],
                  onChanged: (v) => setState(() => _criticality = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Essential function'),
                  subtitle: Text(
                    widget.existing?.isExpectation == true
                        ? 'Expectations are always non-essential'
                        : 'A reason the role exists',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  value: widget.existing?.isExpectation == true ? false : _essential,
                  // An expectation is locked to non-essential (the DB invariant);
                  // toggle it via the flag action on the Tasks tab, not here.
                  onChanged: widget.existing?.isExpectation == true
                      ? null
                      : (v) => setState(() => _essential = v),
                ),
              ),
            ]),
```

- [ ] **Step 5: Run to verify the pure tests pass + analyze**

Run: `flutter test test/features/workforce_planning/task_form_dialog_test.dart`
Expected: PASS (all, including the two new).
Run: `flutter analyze lib/features/workforce_planning/tabs/task_form_dialog.dart`
Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add lib/features/workforce_planning/tabs/task_form_dialog.dart test/features/workforce_planning/task_form_dialog_test.dart
git commit -m "feat(workforce): task editor sets criticality and the essential flag"
```

---

### Task 6: Tasks tab — chips, Archive-not-Delete, and an Archived section

**Files:**
- Create: `lib/features/workforce_planning/task_badges.dart`
- Create: `test/features/workforce_planning/task_badges_test.dart`
- Modify: `lib/features/workforce_planning/tasks_rows.dart` (add `partitionByStatus`)
- Modify: `test/features/workforce_planning/tasks_rows_test.dart` (test it)
- Modify: `lib/features/workforce_planning/tabs/tasks_tab.dart` (`:114`, `:128-144`, name cell `:1081`, actions `:1118-1122`, delete flow `:1287-1323`, and a new Archived section after `:281`)
- Create: `test/features/workforce_planning/tasks_tab_archive_test.dart`

**Interfaces:**
- Consumes: `WpTask.criticality/isEssential/status` (Task 2); `setTaskArchived` (Task 4); `StatusChip`, `StatusTone`.
- Produces: `criticalityTone(String?) -> StatusTone?`, `criticalityLabel(String?) -> String?`; `partitionByStatus(List<WpTask>) -> ({List<WpTask> active, List<WpTask> archived})`.

- [ ] **Step 1: Write the failing badge + partition tests**

```dart
// test/features/workforce_planning/task_badges_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/app/status_colors.dart';
import 'package:payroll_flutter/features/workforce_planning/task_badges.dart';

void main() {
  test('criticalityTone maps each level, null for unset/unknown', () {
    expect(criticalityTone('CRITICAL'), StatusTone.danger);
    expect(criticalityTone('HIGH'), StatusTone.warning);
    expect(criticalityTone('MEDIUM'), StatusTone.info);
    expect(criticalityTone('LOW'), StatusTone.neutral);
    expect(criticalityTone(null), isNull);
    expect(criticalityTone('BOGUS'), isNull);
  });

  test('criticalityLabel title-cases the level', () {
    expect(criticalityLabel('CRITICAL'), 'Critical');
    expect(criticalityLabel(null), isNull);
  });
}
```

Add to `test/features/workforce_planning/tasks_rows_test.dart`:

```dart
  test('partitionByStatus splits active from archived', () {
    const active = WpTask(id: 'a', companyId: 'c', name: 'A');
    const archived = WpTask(id: 'b', companyId: 'c', name: 'B', status: 'ARCHIVED');
    final p = partitionByStatus(const [active, archived]);
    expect(p.active.map((t) => t.id), ['a']);
    expect(p.archived.map((t) => t.id), ['b']);
  });
```

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/features/workforce_planning/task_badges_test.dart test/features/workforce_planning/tasks_rows_test.dart`
Expected: FAIL — `task_badges.dart` / `partitionByStatus` do not exist.

- [ ] **Step 3: Create `task_badges.dart`**

```dart
import '../../app/status_colors.dart';

/// Tinted, borderless chip tone for a criticality level (null = no chip).
StatusTone? criticalityTone(String? c) {
  switch (c) {
    case 'CRITICAL':
      return StatusTone.danger;
    case 'HIGH':
      return StatusTone.warning;
    case 'MEDIUM':
      return StatusTone.info;
    case 'LOW':
      return StatusTone.neutral;
    default:
      return null;
  }
}

/// Human label for a criticality level (null = unset).
String? criticalityLabel(String? c) =>
    (c == null || criticalityTone(c) == null)
        ? null
        : '${c[0]}${c.substring(1).toLowerCase()}';
```

- [ ] **Step 4: Add `partitionByStatus` to `tasks_rows.dart`**

After the `groupTasks` function, add:

```dart
/// Splits tasks into ACTIVE (shown, grouped, costed) and ARCHIVED (retained,
/// shown only in the collapsible Archived section, restorable).
({List<WpTask> active, List<WpTask> archived}) partitionByStatus(
    List<WpTask> tasks) {
  final active = <WpTask>[], archived = <WpTask>[];
  for (final t in tasks) {
    (t.status == 'ARCHIVED' ? archived : active).add(t);
  }
  return (active: active, archived: archived);
}
```

- [ ] **Step 5: Run to verify Steps 1 tests pass**

Run: `flutter test test/features/workforce_planning/task_badges_test.dart test/features/workforce_planning/tasks_rows_test.dart`
Expected: PASS.

- [ ] **Step 6: Wire the partition into the tab**

In `tasks_tab.dart`, right after `final tasks = tasksAsync.asData!.value;` (`:114`):

```dart
    final partition = partitionByStatus(tasks);
    final activeTasks = partition.active;
```

Replace `tasks` with `activeTasks` in the three grouping/scope spots:
- `:128` `final scopes = buildScopes(activeTasks, cards);`
- `:133` `tasksInScope(activeTasks, cards, scopeKey)`
- `:139` `final allGroups = groupTasks(activeTasks, cards);`

(Leave the `wholeArea` map and everything else as-is — they build off `allGroups`.)

- [ ] **Step 7: Chips in the name cell**

At the name `DataCell` (`:1081`), replace `_nameCell(t.name, _nameWidth(c.maxWidth, others))` with a small column that appends chips. Add this helper method to the `_TasksTabState` (near `_hoursCell`):

```dart
  Widget _nameWithBadges(BuildContext context, WpTask t, double width) {
    final tone = criticalityTone(t.criticality);
    final chips = <Widget>[
      if (tone != null)
        StatusChip(label: criticalityLabel(t.criticality)!, tone: tone),
      if (!t.isEssential)
        const StatusChip(label: 'Non-essential', tone: StatusTone.neutral),
    ];
    if (chips.isEmpty) return _nameCell(t.name, width);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _nameCell(t.name, width),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 4, children: chips),
      ],
    );
  }
```

and call `DataCell(_nameWithBadges(context, t, _nameWidth(c.maxWidth, others)))`. Ensure `task_badges.dart` and `status_colors.dart` are imported at the top of `tasks_tab.dart` (add the imports if missing).

- [ ] **Step 8: Replace the per-row Delete with Archive**

At the actions `Row` (`:1118-1122`), replace the Delete `IconButton` with:

```dart
                  IconButton(
                    tooltip: 'Archive (no longer needed)',
                    icon: const Icon(Icons.archive_outlined, size: 18),
                    onPressed: () => _confirmArchive(context, ref, t),
                  ),
```

Replace the `_confirmDelete` method (`:1287-1323`) with `_confirmArchive` (keep the same signature/mounted-guards/invalidation; only the copy, the icon-free non-destructive button, and the repo call change):

```dart
  Future<void> _confirmArchive(
    BuildContext context,
    WidgetRef ref,
    WpTask task,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Archive task?'),
        content: Text(
          'Archive "${task.name}"? It leaves everyone\'s load and the queues '
          'but is kept for reference and can be restored.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(workforcePlanningRepositoryProvider)
          .setTaskArchived(task.id, true);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not archive task: $e')),
      );
      return;
    }
    _invalidateAfterTaskChange(ref, [task.roleScorecardId]);
  }
```

(`_confirmBulkDeleteLegacy` and `repo.deleteTask` stay — genuine bulk removal of legacy imports is still a real delete.)

- [ ] **Step 9: Add the Archived section**

After the "Unattributed" block (`:275-282`, still inside the same list of children), add:

```dart
            if (partition.archived.isNotEmpty) ...[
              const SizedBox(height: 24),
              _ArchivedSection(
                tasks: partition.archived,
                onRestore: (t) async {
                  await ref.read(workforcePlanningRepositoryProvider)
                      .setTaskArchived(t.id, false);
                  _invalidateAfterTaskChange(ref, [t.roleScorecardId]);
                },
              ),
            ],
```

Add this small stateless widget at the bottom of the file:

```dart
class _ArchivedSection extends StatelessWidget {
  final List<WpTask> tasks;
  final Future<void> Function(WpTask) onRestore;
  const _ArchivedSection({required this.tasks, required this.onRestore});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text('Archived (${tasks.length})'),
      childrenPadding: const EdgeInsets.symmetric(horizontal: 8),
      children: [
        for (final t in tasks)
          ListTile(
            dense: true,
            title: Text(t.name),
            trailing: TextButton.icon(
              icon: const Icon(Icons.unarchive_outlined, size: 18),
              label: const Text('Restore'),
              onPressed: () => onRestore(t),
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 10: Write the widget tests**

```dart
// test/features/workforce_planning/tasks_tab_archive_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';
import 'package:payroll_flutter/data/repositories/workforce_planning_repository.dart';
import 'package:payroll_flutter/features/workforce_planning/tabs/tasks_tab.dart';
import 'package:payroll_flutter/features/workforce_planning/wp_providers.dart';

class _FakeRepo implements WorkforcePlanningRepository {
  final List<(String, bool)> archiveCalls = [];
  @override
  Future<void> setTaskArchived(String taskId, bool archived) async {
    archiveCalls.add((taskId, archived));
  }
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

final _card = RoleScorecard(
  id: 'rs1', companyId: 'c', jobTitle: 'Ops', missionStatement: '',
  responsibilities: const [], kpis: const [], wageType: 'MONTHLY',
  workHoursPerDay: 8, workDaysPerWeek: 'MON_FRI', isActive: true,
  effectiveDate: DateTime(2026, 1, 1));

const _node = WpNode(id: 'n1', companyId: 'c', code: '6', name: '6. Fulfill');
const _active = WpTask(
    id: 't1', companyId: 'c', name: 'Pack orders',
    roleScorecardId: 'rs1', responsibilityArea: 'Fulfilment',
    criticality: 'CRITICAL', hoursPerMonth: 10);
const _archived = WpTask(
    id: 't2', companyId: 'c', name: 'Old blindbox packing',
    roleScorecardId: 'rs1', responsibilityArea: 'Fulfilment',
    status: 'ARCHIVED');

Widget _host(_FakeRepo repo, {List<WpTask> tasks = const [_active, _archived]}) =>
    ProviderScope(
      overrides: [
        wpTasksProvider.overrideWith((ref) async => tasks),
        wpNodesProvider.overrideWith((ref) async => const [_node]),
        wpDriversProvider.overrideWith((ref) async => const []),
        wpRatesProvider.overrideWith((ref) async => const []),
        wpActiveEmployeesProvider.overrideWith((ref) async => const []),
        roleScorecardListProvider.overrideWith((ref) async => [_card]),
        workforcePlanningRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(home: Scaffold(body: TasksTab())),
    );

void main() {
  testWidgets('an active task shows its criticality chip; archived is hidden in a section',
      (tester) async {
    await tester.pumpWidget(_host(_FakeRepo()));
    await tester.pumpAndSettle();

    // Active row + its chip visible; archived name is not in the main grid.
    expect(find.text('Pack orders'), findsOneWidget);
    expect(find.text('Critical'), findsOneWidget);
    expect(find.text('Old blindbox packing'), findsNothing);

    // It lives behind the Archived (1) expander.
    expect(find.text('Archived (1)'), findsOneWidget);
    await tester.tap(find.text('Archived (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Old blindbox packing'), findsOneWidget);
  });

  testWidgets('the row Archive action calls setTaskArchived(true)', (tester) async {
    final repo = _FakeRepo();
    await tester.pumpWidget(_host(repo, tasks: const [_active]));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Archive (no longer needed)'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Archive'));
    await tester.pumpAndSettle();

    expect(repo.archiveCalls, [('t1', true)]);
  });

  testWidgets('Restore calls setTaskArchived(false)', (tester) async {
    final repo = _FakeRepo();
    await tester.pumpWidget(_host(repo, tasks: const [_archived]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Archived (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Restore'));
    await tester.pumpAndSettle();

    expect(repo.archiveCalls, [('t2', false)]);
  });
}
```

- [ ] **Step 11: Run the tab tests + analyze**

Run: `flutter test test/features/workforce_planning/tasks_tab_archive_test.dart`
Expected: PASS (3 tests). If the criticality chip is not found, confirm Step 7 wired `_nameWithBadges` into the name `DataCell` and that both the normal and any scoped render path use it.
Run: `flutter analyze lib/features/workforce_planning/`
Expected: no errors.

- [ ] **Step 12: Commit**

```bash
git add lib/features/workforce_planning/task_badges.dart \
        lib/features/workforce_planning/tasks_rows.dart \
        lib/features/workforce_planning/tabs/tasks_tab.dart \
        test/features/workforce_planning/task_badges_test.dart \
        test/features/workforce_planning/tasks_rows_test.dart \
        test/features/workforce_planning/tasks_tab_archive_test.dart
git commit -m "feat(workforce): criticality/essential chips, archive-not-delete, restore"
```

---

### Task 7: Full-suite + analyze gate

- [ ] **Step 1: Run the whole suite**

Run: `flutter test`
Expected: all pass (the step-1 count of 990 + the new tests; 1 pre-existing skip). If any PRE-EXISTING test fails for a reason this plan did not anticipate, STOP and report — do not rewrite its assertions.

- [ ] **Step 2: Analyze**

Run: `flutter analyze`
Expected: 0 errors (pre-existing infos/warnings elsewhere are fine).

- [ ] **Step 3: (no commit — gate only)**

---

## Self-Review

**Spec coverage** (spec §"The model" step-2 scope + Sequencing item 2):
- `criticality` column + chip → Task 1, Task 6. ✓
- `is_essential` column + ADA test made visible + expectation↔essential consistency → Task 1 (column+CHECK+backfill), Task 2 (toUpsert invariant), Task 4 (setTaskExpectation), Task 5 (switch). ✓
- `status ACTIVE/ARCHIVED`, archived drops out of load/queues but restorable, excluded from duplicate check → Task 1 (view excludes ARCHIVED — the duplicate check in later steps reads the same active set), Task 4 (setTaskArchived), Task 6 (partition + Archived section + Restore). ✓
- Archive replaces hard-delete → Task 6 (per-row action swap; bulk-legacy delete retained deliberately). ✓
- "Feeds needs-attention ranking" → the columns exist for step 3; no needs-attention UI built here (correct — that is step 3). ✓
- Design system (mono numbers, tinted borderless chips) → Task 6 uses `StatusChip`/`StatusTone`; hours already mono. ✓

**Placeholder scan:** none — every code step shows complete code and exact commands.

**Type consistency:** `criticalityTone(String?) → StatusTone?` and `criticalityLabel(String?) → String?` (Task 6) match their uses in `_nameWithBadges`. `partitionByStatus` record shape `({List<WpTask> active, List<WpTask> archived})` is consistent between definition (Task 6 Step 4) and use (Task 6 Step 6). `setTaskArchived(String, bool)` signature matches the fake repo override and both call sites. `buildTaskFromForm`'s new `criticality`/`isEssential` params match the `_save` call site.

**Out-of-scope guard:** no assignments table, no needs-attention strip, no Unassigned workspace — those are spec steps 3–5.
