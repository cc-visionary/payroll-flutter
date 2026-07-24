# Assignment Panel + % Allocation (step 5b) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a manager set per-role / per-person **allocation %** on an accountability — with one-click simplifiers and a live `= 100%` check — so shared work splits the way they intend, edited in ONE place instead of per profile.

**Architecture:** The PRIMARY assignment's *target* keeps coming from the existing owner/card mechanism (Owner dropdown, Balance drag, Unassigned "Assign") — unchanged and familiar. The new panel owns **the PRIMARY's allocation %** and **all CONTRIBUTOR rows** (target + %). Percentages already flow end-to-end: `wp_person_load` (step 4) and `attributeTask` (step 5a) both scale by `allocation_pct`. The one blocking gap is that the SQL view still filters `assignment_role = 'PRIMARY'`, so contributors would be invisible to it — Task 1 fixes that BEFORE any contributor can exist. Pure allocation math (simplifiers + the total check) lives in its own tested file; the panel is a widget on the accountability editor.

**Tech Stack:** Supabase Postgres (view + trigger), Flutter (Material 3, Riverpod), `flutter_test`.

## Global Constraints

- Repo gates on `flutter analyze` only (0 errors). Do NOT run `dart format`; match surrounding style.
- Migrations forward-only; apply with `supabase db push` (answer `Y`). Prod password is NOT in the repo. `env/prod.json` holds `SUPABASE_URL` + `service_role` — use ONLY for the stated verifications and STATE each use.
- **Task 1 is a hard gate and MUST land before any CONTRIBUTOR row can be written** (Task 3 is the first thing that can write one). Its prod parity check must show `wp_person_load` unchanged (today every row is a PRIMARY @100, so dropping the PRIMARY predicate changes nothing).
- `allocation_pct` is numeric in [0,100] (DB CHECK). Exactly one PRIMARY per task (partial unique index). A row targets EITHER a role card OR an employee (`one_target`).
- Attribution semantics (must stay identical in SQL and Dart): person assignment → `hours * pct/100` to that employee; card assignment → `hours * pct/100` split evenly across the card's ACTIVE, non-deleted holders; leftover (`hours − Σ reached`) is unattributed.
- Managers-only surface. Design system (`PRODUCT.md`): `AppTheme.mono` for numbers/percentages; tinted borderless `StatusChip`; single purple CTA.
- Do NOT change the Owner dropdown, `reassignTaskOwner`, or `setTaskCard` semantics in this step — the PRIMARY *target* still derives from owner/card. Only its **percentage** and the **contributor rows** are panel-owned.

---

## File Structure

- `supabase/migrations/20260724000003_wp_person_load_all_assignments.sql` — **create.** Drop the `assignment_role = 'PRIMARY'` predicate from both `assigned` legs; add the `set_updated_at` trigger on `wp_task_assignments`.
- `lib/features/workforce_planning/allocation.dart` — **create.** Pure: `allocationTotal`, `splitEqually`, `ownerMajority`, `clearAllocations`.
- `lib/data/repositories/workforce_planning_repository.dart` — **modify.** `upsertAssignment`, `deleteAssignment`, `replaceAssignments`; make `_syncPrimaryFromTask` preserve an existing PRIMARY's `allocation_pct` when its target is unchanged.
- `lib/features/workforce_planning/tabs/assignment_panel.dart` — **create.** The panel widget.
- `lib/features/workforce_planning/tabs/task_form_dialog.dart` — **modify.** Host the panel (edit mode only).
- `lib/features/workforce_planning/needs_attention.dart` — **modify.** Add the spec'd Process signal "shares don't total 100%".
- Tests: `test/features/workforce_planning/allocation_test.dart`, `assignment_panel_test.dart` (create); extend `needs_attention_test.dart`.

---

### Task 1: SQL gate — count CONTRIBUTORs, and keep `updated_at` fresh

**Files:** Create `supabase/migrations/20260724000003_wp_person_load_all_assignments.sql`

**Interfaces:** `wp_person_load` output columns UNCHANGED; now attributes via ALL assignment rows (PRIMARY *and* CONTRIBUTOR).

- [ ] **Step 1: Capture the prod BEFORE snapshot (service_role — flag this use)**

```bash
BASE="$SUPABASE_URL/rest/v1"
curl -s "$BASE/wp_person_load?select=employee_id,tasks_owned,hours_fixed,hours_growing_base&order=employee_id" \
  -H "apikey: $SR" -H "Authorization: Bearer $SR" > /tmp/wpl5b_before.json
```

- [ ] **Step 2: Write the migration**

```sql
-- Contributors carry hours too. The step-4 view filtered assignment_role =
-- 'PRIMARY', which was correct only while PRIMARY was the sole row type; the
-- spec's own worked example has a CONTRIBUTOR at 40%. Drop the predicate from
-- both legs so every assignment's allocation_pct is attributed. This also makes
-- the fallback CTE correct: a task with only a CONTRIBUTOR is now attributed
-- through `assigned` instead of vanishing from load.
--
-- Output columns are unchanged. Numerically inert today: every existing row is a
-- PRIMARY @100, so the same rows are selected as before (parity-checked).
create or replace view wp_person_load with (security_invoker = true) as
with holders as (
  select e.id as employee_id, e.role_scorecard_id,
         count(*) over (partition by e.role_scorecard_id) as holder_count
  from employees e
  where e.employment_status = 'ACTIVE' and e.deleted_at is null
    and e.role_scorecard_id is not null
),
assigned as (
  select a.employee_id, tc.task_id,
         tc.hours_per_month_base * a.allocation_pct / 100.0 as hours, tc.is_growing
  from wp_task_computed tc
  join wp_task_assignments a
    on a.task_id = tc.task_id and a.employee_id is not null
  union all
  select h.employee_id, tc.task_id,
         tc.hours_per_month_base * a.allocation_pct / 100.0 / h.holder_count, tc.is_growing
  from wp_task_computed tc
  join wp_task_assignments a
    on a.task_id = tc.task_id and a.role_scorecard_id is not null
  join holders h on h.role_scorecard_id = a.role_scorecard_id
),
fallback as (
  select tc.owner_employee_id as employee_id, tc.task_id,
         tc.hours_per_month_base as hours, tc.is_growing
  from wp_task_computed tc
  where tc.owner_employee_id is not null
    and not exists (select 1 from wp_task_assignments a where a.task_id = tc.task_id)
  union all
  select h.employee_id, tc.task_id,
         tc.hours_per_month_base / h.holder_count, tc.is_growing
  from wp_task_computed tc
  join wp_tasks t on t.id = tc.task_id
  join holders  h on h.role_scorecard_id = t.role_scorecard_id
  where tc.owner_employee_id is null and t.role_scorecard_id is not null
    and not exists (select 1 from wp_task_assignments a where a.task_id = tc.task_id)
),
attributed as (
  select * from assigned
  union all
  select * from fallback
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

-- Deferred from step 4: keep updated_at fresh once rows start being UPDATEd
-- (the % editor is the first thing that UPDATEs them).
create trigger _wp_task_assignments_updated before update on wp_task_assignments
  for each row execute function set_updated_at();
```

- [ ] **Step 3: Apply + parity-check (service_role — flag this use)**

Run `supabase db push` → `Y`. Then:
```bash
curl -s "$BASE/wp_person_load?select=employee_id,tasks_owned,hours_fixed,hours_growing_base&order=employee_id" \
  -H "apikey: $SR" -H "Authorization: Bearer $SR" > /tmp/wpl5b_after.json
diff <(jq -S . /tmp/wpl5b_before.json) <(jq -S . /tmp/wpl5b_after.json) && echo "PARITY OK" || echo "PARITY FAIL"
```
Expected **PARITY OK**. If FAIL, STOP and report — do not commit.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260724000003_wp_person_load_all_assignments.sql
git commit -m "data(workforce): wp_person_load counts contributors; updated_at trigger"
```

---

### Task 2: Pure allocation math + simplifiers

**Files:** Create `lib/features/workforce_planning/allocation.dart` + `test/features/workforce_planning/allocation_test.dart`

**Interfaces:**
- `double allocationTotal(Iterable<double> pcts)` — sum.
- `List<double> splitEqually(int n)` — n equal shares summing to exactly 100 (last absorbs the rounding remainder).
- `List<double> ownerMajority(int n, {int primaryIndex = 0, double primaryPct = 60})` — `primaryPct` to `primaryIndex`, the rest split equally over the remaining `n-1` (exactly 100 total). With `n == 1` → `[100]`.
- `List<double> clearAllocations(int n)` — n zeros.

Percentages are rounded to 1 decimal; the LAST element absorbs any remainder so the total is exactly 100 (no drifting 99.9).

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/workforce_planning/allocation_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/workforce_planning/allocation.dart';

void main() {
  test('allocationTotal sums', () {
    expect(allocationTotal([60, 40]), 100);
    expect(allocationTotal(const <double>[]), 0);
  });

  test('splitEqually always totals exactly 100', () {
    for (final n in [1, 2, 3, 4, 6, 7]) {
      final s = splitEqually(n);
      expect(s.length, n);
      expect(allocationTotal(s), closeTo(100, 1e-9), reason: 'n=$n must total 100');
    }
    expect(splitEqually(2), [50, 50]);
    expect(splitEqually(4), [25, 25, 25, 25]);
  });

  test('splitEqually(3) is 33.3/33.3/33.4 — the last absorbs the remainder', () {
    final s = splitEqually(3);
    expect(s[0], 33.3);
    expect(s[1], 33.3);
    expect(s[2], 33.4);
  });

  test('ownerMajority gives the primary 60 and splits 40 across the rest', () {
    expect(ownerMajority(2), [60, 40]);
    final three = ownerMajority(3);
    expect(three[0], 60);
    expect(allocationTotal(three), closeTo(100, 1e-9));
    expect(ownerMajority(1), [100], reason: 'a sole assignee takes everything');
  });

  test('ownerMajority honors a non-zero primaryIndex', () {
    final s = ownerMajority(3, primaryIndex: 1);
    expect(s[1], 60);
    expect(allocationTotal(s), closeTo(100, 1e-9));
  });

  test('clearAllocations zeroes every row', () {
    expect(clearAllocations(3), [0, 0, 0]);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/workforce_planning/allocation_test.dart` → FAIL (file missing).

- [ ] **Step 3: Implement**

```dart
// lib/features/workforce_planning/allocation.dart

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

List<double> ownerMajority(int n, {int primaryIndex = 0, double primaryPct = 60}) {
  if (n <= 0) return const [];
  if (n == 1) return [100];
  final rest = splitEqually(n - 1).map((p) => _round1(p * (100 - primaryPct) / 100)).toList();
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
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/workforce_planning/allocation_test.dart` → PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/workforce_planning/allocation.dart test/features/workforce_planning/allocation_test.dart
git commit -m "feat(workforce): pure allocation math + split/owner-majority/clear simplifiers"
```

---

### Task 3: Repository writes for assignments

**Files:** Modify `lib/data/repositories/workforce_planning_repository.dart`

**Interfaces:**
- `Future<void> upsertAssignment(WpTaskAssignment a)` — insert when `a.id.isEmpty`, else update `assignment_role` + `allocation_pct` (never the target — a target change is a delete + insert).
- `Future<void> deleteAssignment(String id)`.
- `Future<void> setAllocations(Map<String, double> pctById)` — bulk % write, one statement per row (mirrors `updateTaskCosts`' per-row loop).
- **`_syncPrimaryFromTask` must PRESERVE an existing PRIMARY's `allocation_pct` when its target is unchanged**, so a later `saveTask` cannot silently reset a manually-set percentage back to 100.

- [ ] **Step 1: Make `_syncPrimaryFromTask` preserve the percentage**

Replace its body so it reads the current PRIMARY first and keeps that row's `allocation_pct` when the computed target matches:

```dart
  Future<void> _syncPrimaryFromTask(String taskId) async {
    final t = await _client.from('wp_tasks')
        .select('company_id, owner_employee_id, role_scorecard_id')
        .eq('id', taskId).maybeSingle();
    if (t == null) return;
    final payload = primaryAssignmentPayload(
      companyId: t['company_id'] as String,
      taskId: taskId,
      ownerEmployeeId: t['owner_employee_id'] as String?,
      roleScorecardId: t['role_scorecard_id'] as String?,
    );
    // Keep a manually-set percentage when the PRIMARY still points at the same
    // target — otherwise editing an unrelated field would silently reset a
    // deliberate 60/40 split back to 100.
    final existing = await _client.from('wp_task_assignments')
        .select('employee_id, role_scorecard_id, allocation_pct')
        .eq('task_id', taskId).eq('assignment_role', 'PRIMARY').maybeSingle();
    if (existing != null && payload != null &&
        existing['employee_id'] == payload['employee_id'] &&
        existing['role_scorecard_id'] == payload['role_scorecard_id']) {
      return; // same target — leave the row (and its pct) untouched
    }
    await _client.from('wp_task_assignments').delete()
        .eq('task_id', taskId).eq('assignment_role', 'PRIMARY');
    if (payload != null) {
      await _client.from('wp_task_assignments').insert(payload);
    }
  }
```

- [ ] **Step 2: Add the three write methods** (near `taskAssignments()`)

```dart
  /// Inserts a new assignment or updates an existing one's role/percentage.
  /// A TARGET change is a delete + insert, not an update — the partial unique
  /// indexes are on (task_id, target), so mutating the target in place could
  /// collide with a sibling row.
  Future<void> upsertAssignment(WpTaskAssignment a) async {
    if (a.id.isEmpty) {
      await _client.from('wp_task_assignments').insert(a.toUpsert(a.companyId));
    } else {
      await _client.from('wp_task_assignments').update({
        'assignment_role': a.assignmentRole,
        'allocation_pct': a.allocationPct,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', a.id);
    }
  }

  Future<void> deleteAssignment(String id) async =>
      _client.from('wp_task_assignments').delete().eq('id', id);

  /// Bulk percentage write (the panel's simplifiers). One statement per row —
  /// PostgREST has no multi-row-different-values update.
  Future<void> setAllocations(Map<String, double> pctById) async {
    for (final e in pctById.entries) {
      await _client.from('wp_task_assignments').update({
        'allocation_pct': e.value,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', e.key);
    }
  }
```

- [ ] **Step 3: Verify it compiles**

Run: `flutter analyze lib/data/repositories/workforce_planning_repository.dart` → 0 errors.

- [ ] **Step 4: Commit**

```bash
git add lib/data/repositories/workforce_planning_repository.dart
git commit -m "feat(workforce): assignment write methods; PRIMARY sync keeps a manual %"
```

---

### Task 4: The assignment panel widget

**Files:** Create `lib/features/workforce_planning/tabs/assignment_panel.dart` + `test/features/workforce_planning/assignment_panel_test.dart`

**Interfaces:** `class AssignmentPanel extends ConsumerStatefulWidget` — `AssignmentPanel({required String taskId, required String companyId, required double taskHours, required List<RoleScorecard> cards, required List<Employee> employees})`.

**Shape** (spec §"The assignment panel + simplifiers"):
```
Assigned                                   = 100% ✓
  Sales & Ops Assistant   [PRIMARY]   [ 60 ]%   → Evander 39.5h
  Kiosk Sales Rep         [CONTRIB ▾] [ 40 ]%   → 2 people, 13.2h each
  [ Split equally ]  [ Owner majority ]  [ Clear ]        [+ Add contributor]
```
- Watch `wpAssignmentsByTaskProvider`; take this task's rows. While loading → a slim placeholder.
- Header: "Assigned" + a live total `StatusChip`: `= 100%` (`StatusTone.success`) when `allocationTotal` is within 0.05 of 100, else `⚠ N%` (`StatusTone.warning`). Total via `allocationTotal`, rendered with `AppTheme.mono`.
- One row per assignment: target label (card `jobTitle` or employee full name — look up from `cards`/`employees`, fall back to the raw id), a role chip (PRIMARY = `StatusTone.info`, CONTRIBUTOR = `StatusTone.neutral`), a numeric `TextField` for the % (key `ValueKey('pct-<assignmentId>')`), and the DERIVED per-person hours read-only on the right: for a person row `taskHours * pct/100`; for a card row `"<n> people, <each>h each"` where each = `taskHours * pct/100 / n` (n = ACTIVE non-deleted holders of that card; 0 holders → "no active holder"). Mono for all numbers.
- The PRIMARY row's role chip is NOT editable (its target comes from the Owner/card); CONTRIBUTOR rows get a delete (✕) button → `deleteAssignment`.
- Simplifiers write every row at once via `setAllocations`: **Split equally** → `splitEqually(n)`; **Owner majority** → `ownerMajority(n, primaryIndex: <index of the PRIMARY row>)`; **Clear** → `clearAllocations(n)`.
- **+ Add contributor** → a dialog picking a role card OR an employee → `upsertAssignment(WpTaskAssignment(id: '', companyId: companyId, taskId: taskId, roleScorecardId: …, employeeId: …, assignmentRole: 'CONTRIBUTOR', allocationPct: 0))`.
- After EVERY write: `ref.invalidate(wpTaskAssignmentsProvider)` plus the standard workforce refresh (mirror `TasksTab._invalidateAfterTaskChange`; the assignments list is what this panel renders, so it must be invalidated or the panel shows stale rows).

- [ ] **Step 1: Write the failing widget test**

Host `AssignmentPanel` in a `ProviderScope` overriding `wpAssignmentsByTaskProvider` with one card PRIMARY @60 and one person CONTRIBUTOR @40 for task `t1`, plus a fake repo capturing `setAllocations`/`deleteAssignment`/`upsertAssignment`. Assert:
1. the live total chip reads `= 100%`;
2. tapping **Split equally** calls `setAllocations` with both ids at 50;
3. with a single row at 60 the chip reads `⚠ 60%`.
Mirror `unassigned_tab_test.dart` for the fake-repo + `ProviderScope` shape, and give the host a wide viewport (`tester.view.physicalSize`) as that file does.

- [ ] **Step 2: Run to verify it fails** — file missing.

- [ ] **Step 3: Implement** per the shape above. Read `lib/features/workforce_planning/tabs/unassigned_tab.dart` first and mirror its provider-reading, invalidation, and `StatusChip`/mono conventions.

- [ ] **Step 4: Run to verify it passes**, then `flutter analyze lib/features/workforce_planning/` → 0 errors.

- [ ] **Step 5: Commit**

```bash
git add lib/features/workforce_planning/tabs/assignment_panel.dart test/features/workforce_planning/assignment_panel_test.dart
git commit -m "feat(workforce): assignment panel — % per role/person with simplifiers"
```

---

### Task 5: Host the panel on the accountability editor

**Files:** Modify `lib/features/workforce_planning/tabs/task_form_dialog.dart`

- [ ] **Step 1: Embed the panel**

In `TaskFormDialog`'s body, AFTER the Owner dropdown (~:399-407) and before the Responsibility/card section, add — **only when editing an existing task** (a new task has no id yet, so it can have no assignments):

```dart
            if (widget.existing != null && widget.existing!.id.isNotEmpty) ...[
              const SizedBox(height: 16),
              AssignmentPanel(
                taskId: widget.existing!.id,
                companyId: widget.companyId,
                taskHours: /* the task's monthly hours, see below */,
                cards: widget.cards,
                employees: widget.employees,
              ),
            ],
```
For `taskHours`, use the dialog's own costing inputs if a computed value is not available: `widget.existing!.hoursPerMonth ?? 0` is acceptable for the derived-hours preview (a driver-costed task shows 0 preview until step 6 threads the computed value in — note this in the panel's empty state as "hours preview unavailable" rather than showing a wrong number). Add the import.

- [ ] **Step 2: Verify the dialog still behaves**

Run: `flutter test test/features/workforce_planning/task_form_dialog_test.dart` → PASS (the existing tests construct the dialog with `existing: null` or a bare task; the panel must not break them — if a test constructs `existing` with a non-empty id and no provider override, the panel must degrade to its loading/empty placeholder rather than throwing).
Run: `flutter analyze lib/features/workforce_planning/` → 0 errors.

- [ ] **Step 3: Commit**

```bash
git add lib/features/workforce_planning/tabs/task_form_dialog.dart
git commit -m "feat(workforce): accountability editor hosts the assignment panel"
```

---

### Task 6: Needs-attention signal — shares don't total 100%

**Files:** Modify `lib/features/workforce_planning/needs_attention.dart`; extend `test/features/workforce_planning/needs_attention_test.dart`

The spec lists this Process signal; it was correctly deferred until allocations could vary. Now they can.

- [ ] **Step 1: Write the failing test**

Add a case: `buildNeedsAttention` with a task whose assignments total 70 emits a Process/medium item targeting `AttentionTarget.tasks` with count 1 and a label containing "don't total 100%". A task totalling exactly 100 emits nothing.

- [ ] **Step 2: Extend the derivation**

Add `required Map<String, List<WpTaskAssignment>> assignmentsByTask` (default `const {}`) to `buildNeedsAttention`, and a signal counting ACTIVE, non-expectation tasks that HAVE assignments whose `allocationTotal` differs from 100 by more than 0.05:

```dart
  final misallocated = tasks.where((t) =>
      t.status == 'ACTIVE' && !t.isExpectation &&
      (assignmentsByTask[t.id] ?? const []).isNotEmpty &&
      (allocationTotal((assignmentsByTask[t.id] ?? const []).map((a) => a.allocationPct)) - 100).abs() > 0.05).length;
  add(AttentionCategory.process, AttentionSeverity.medium, misallocated,
      "${_plural(misallocated, 'responsibility', 'responsibilities')} whose shares don't total 100%",
      AttentionTarget.tasks);
```
Import `allocation.dart`. Then pass `assignmentsByTask` from `NeedsAttentionStrip` (it already watches the other providers — add `wpAssignmentsByTaskProvider`, read defensively with `.asData?.value ?? const {}` so it never blocks first paint).

- [ ] **Step 3: Run** the needs-attention + strip tests → PASS. `flutter analyze` → 0 errors.

- [ ] **Step 4: Commit**

```bash
git add lib/features/workforce_planning/needs_attention.dart lib/features/workforce_planning/tabs/needs_attention_strip.dart test/features/workforce_planning/needs_attention_test.dart
git commit -m "feat(workforce): needs-attention flags shares that don't total 100%"
```

---

### Task 7: Full-suite + analyze gate

- [ ] **Step 1:** `flutter test` — all pass (prior 1050 + new; 1 pre-existing skip). If a PRE-EXISTING test fails, STOP and report; do not rewrite assertions.
- [ ] **Step 2:** `flutter analyze` — 0 errors.

---

## Self-Review

**Spec coverage** (§"The assignment panel + simplifiers", §"How the per-person numbers come out"):
- Per-role/person allocation % edited in ONE place → Tasks 4–5. ✓
- Live `= 100%` / `⚠ 92%` check → Task 4. ✓
- Simplifiers writing every row at once (Split equally / Owner majority 60-40 / Clear) → Tasks 2 + 4. ✓
- Per-person hours shown inline, derived + read-only → Task 4. ✓
- PRIMARY + CONTRIBUTOR (RACI) → contributors addable in Task 4; PRIMARY target still from owner/card (stated design choice). ✓
- Σ% ≠ 100 surfaced, never silently dropped → Task 6 (needs-attention) + the panel's live check; the hours leftover already flows to unattributed via step 5a's `attributeTask`. ✓

**Entry criteria from the 5a review:** #1 (drop the `PRIMARY` predicate, fix the fallback consequence) → Task 1, the hard gate. #5 (`set_updated_at` trigger) → Task 1. #3 (Σ% > 100 makes `unattributed` negative) → prevented in practice by the panel's live check + the Task 6 signal; the underlying clamp is NOT added here — recorded as a follow-up. #2/#6 (orphan-predicate fork; DRY the invalidation list) → explicitly NOT in scope; still recorded. #4 (first-paint flash) → not in scope.

**Deliberately NOT in this step:** changing the Owner dropdown / `reassignTaskOwner` / `setTaskCard` to write assignments directly (the PRIMARY *target* stays owner/card-derived — that migration belongs with step 6's authoring rework); and threading a driver-costed task's computed hours into the panel preview (Task 5 notes the limitation).

**Placeholder scan:** Tasks 4–5 specify exact widget behavior, keys, tone mapping, method calls and copy, and point at a concrete file to mirror rather than restating it — consistent with how the Unassigned tab was specified and built. No "TBD".

**Type consistency:** `allocationTotal`/`splitEqually`/`ownerMajority`/`clearAllocations` signatures match between Task 2 and their uses in Tasks 4 and 6. `upsertAssignment(WpTaskAssignment)`, `deleteAssignment(String)`, `setAllocations(Map<String,double>)` match between Task 3 and Task 4. `assignmentsByTask` is `Map<String, List<WpTaskAssignment>>` everywhere.

**Risk:** Task 1 touches prod — gated by the before/after parity snapshot (inert today because every row is a PRIMARY @100). Task 3's `_syncPrimaryFromTask` change is the one that keeps a manual % from being silently reset; it must be verified by review since the repo has no unit tests.
