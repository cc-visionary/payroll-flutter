# Task Assignments (shared accountability) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce the `wp_task_assignments` table (the first-class shared-accountability model), backfill every current owner/card into exactly one PRIMARY assignment, and switch the per-person load view to attribute hours via assignments — producing byte-identical numbers to today, verified against prod.

**Architecture:** A new `wp_task_assignments` table targets EITHER a role card OR an employee (exactly one), with an `assignment_role` (PRIMARY/CONTRIBUTOR) and `allocation_pct`. A backfill maps each ACTIVE-or-archived task's ownership to one PRIMARY assignment: explicit `owner_employee_id` → a person PRIMARY @100%; else `role_scorecard_id` → a card PRIMARY @100%. `wp_person_load` is rewritten to attribute via PRIMARY assignments (person → allocation% to that person; card → allocation% split across the card's active holders), with an owner/card **fallback** for any task that has no assignment yet (tasks created via the current form between this step and steps 5–6). Because the backfill mirrors ownership exactly and every allocation is 100, the view's output is unchanged — proven by a prod before/after snapshot. **`rebalance.dart` (the Balance draft-preview split) is deliberately NOT touched here** — it stays on owner/card, which is numerically identical while all allocations are 100; step 5 aligns it when the % editor makes allocations vary. This keeps step 4's blast radius to one view.

**Tech Stack:** Supabase Postgres (table, RLS, `security_invoker` view), Flutter/Dart (model + repo read), Deno (migration test).

## Global Constraints

- Repo gates on `flutter analyze` only (0 errors). Do NOT run `dart format`; match surrounding style.
- Migrations are forward-only; new files only. Prod DB password is NOT in the repo — apply with `supabase db push` (answer `Y`). Only company on prod is GameCove Inc. (`11111111-1111-1111-1111-000000000001`).
- `env/prod.json` holds `SUPABASE_URL` + a privileged `service_role` key. Use it ONLY for the stated prod verifications/snapshots; STATE each use in the report. Verifications must be read-only or reverted.
- **The non-negotiable invariant: `wp_person_load` output must be identical before and after this step.** The plan's prod parity snapshot (Task 2) is the gate — if any employee's `hours_fixed`/`hours_growing_base`/`tasks_owned` changes, STOP.
- Exact enum values: `assignment_role in ('PRIMARY','CONTRIBUTOR')`; `allocation_pct` numeric in [0,100].
- `wp_task_assignments` schema is fixed by the spec (`docs/superpowers/specs/2026-07-23-accountability-model-design.md:94-117`) — use it verbatim.
- Follow the existing `wp_*` RLS pattern (company-scoped select; SUPER_ADMIN/ADMIN/HR write) and `security_invoker = true` on the view.
- Nothing user-visible changes in this step (spec Sequencing item 4). No UI work here.

---

## File Structure

- `supabase/migrations/20260724000001_wp_task_assignments.sql` — **create.** Table + indexes + RLS + backfill.
- `supabase/migrations/20260724000002_wp_person_load_from_assignments.sql` — **create.** Rewrite `wp_person_load` to attribute via assignments (+ owner/card fallback). Same output columns.
- `lib/data/models/workforce_planning.dart` — **modify.** Add `WpTaskAssignment` model (fromRow/toUpsert).
- `lib/data/repositories/workforce_planning_repository.dart` — **modify.** Add `taskAssignments()` read (paged, like `tasks()`).
- `supabase/tests/wp_task_assignments_backfill_test.ts` — **create.** Deno test: backfill correctness + idempotent + totals unchanged on throwaway Postgres.
- Tests: `test/data/models/wp_task_assignment_test.dart` (create).

---

### Task 1: Table + RLS + backfill migration

**Files:**
- Create: `supabase/migrations/20260724000001_wp_task_assignments.sql`

**Interfaces:**
- Produces: table `wp_task_assignments(id, company_id, task_id, role_scorecard_id, employee_id, assignment_role, allocation_pct, created_at, updated_at)` with the three unique indexes + `one_target` check; backfilled so every task with an owner or a card has exactly one PRIMARY assignment.

- [ ] **Step 1: Write the migration**

```sql
-- Shared accountability: a task's ownership becomes first-class assignment rows.
-- One PRIMARY (Accountable) per task; CONTRIBUTORs (Responsible) added later.
-- A row targets EITHER a role card (the position) OR a specific employee (the
-- exception override) -- exactly one, enforced by one_target.

create table wp_task_assignments (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null references companies(id) on delete cascade,
  task_id           uuid not null references wp_tasks(id) on delete cascade,
  role_scorecard_id uuid references role_scorecards(id) on delete cascade,
  employee_id       uuid references employees(id) on delete cascade,
  assignment_role   text not null default 'CONTRIBUTOR'
                    check (assignment_role in ('PRIMARY','CONTRIBUTOR')),
  allocation_pct    numeric not null default 0
                    check (allocation_pct >= 0 and allocation_pct <= 100),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint one_target check ((role_scorecard_id is null) != (employee_id is null))
);

create unique index wp_task_assignments_card
  on wp_task_assignments (task_id, role_scorecard_id) where role_scorecard_id is not null;
create unique index wp_task_assignments_person
  on wp_task_assignments (task_id, employee_id) where employee_id is not null;
-- At most one PRIMARY per task.
create unique index wp_task_assignments_one_primary
  on wp_task_assignments (task_id) where assignment_role = 'PRIMARY';
create index wp_task_assignments_task on wp_task_assignments (task_id);

-- RLS: company-scoped read; SUPER_ADMIN/ADMIN/HR write (mirrors wp_tasks).
alter table wp_task_assignments enable row level security;
create policy wp_task_assignments_select on wp_task_assignments for select
  using (company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN');
create policy wp_task_assignments_write on wp_task_assignments for all
  using (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR')
         and (company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN'))
  with check (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR')
         and (company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN'));

-- Backfill: current ownership -> exactly one PRIMARY assignment @100%.
-- (a) explicit owner -> person PRIMARY. Idempotent via NOT EXISTS + the
--     one_primary index. Covers all statuses so a restored task keeps it.
insert into wp_task_assignments (company_id, task_id, employee_id, assignment_role, allocation_pct)
select t.company_id, t.id, t.owner_employee_id, 'PRIMARY', 100
from wp_tasks t
where t.owner_employee_id is not null
  and not exists (select 1 from wp_task_assignments a
                  where a.task_id = t.id and a.assignment_role = 'PRIMARY');

-- (b) no owner, has a card -> card PRIMARY.
insert into wp_task_assignments (company_id, task_id, role_scorecard_id, assignment_role, allocation_pct)
select t.company_id, t.id, t.role_scorecard_id, 'PRIMARY', 100
from wp_tasks t
where t.owner_employee_id is null and t.role_scorecard_id is not null
  and not exists (select 1 from wp_task_assignments a
                  where a.task_id = t.id and a.assignment_role = 'PRIMARY');

comment on table wp_task_assignments is
  'First-class accountability assignments. One PRIMARY per task; targets a role '
  'card OR an employee. allocation_pct scales the task hours in wp_person_load.';
```

- [ ] **Step 2: Apply to prod**

Run: `supabase db push` → `Y`. Expected: applied, no error.

- [ ] **Step 3: Verify the backfill (service_role — flag this use)**

Using `SUPABASE_URL` + service_role from `env/prod.json` (`BASE="$SUPABASE_URL/rest/v1"`):

```bash
# (i) exactly one PRIMARY per task that has an owner or a card:
curl -s "$BASE/wp_tasks?select=id&or=(owner_employee_id.not.is.null,role_scorecard_id.not.is.null)" -H "apikey: $SR" -H "Authorization: Bearer $SR" | jq length
curl -s "$BASE/wp_task_assignments?select=id&assignment_role=eq.PRIMARY" -H "apikey: $SR" -H "Authorization: Bearer $SR" | jq length
# these two counts must be EQUAL.
# (ii) no task has >1 PRIMARY (the index guarantees it; confirm the insert didn't error).
# (iii) spot-check one owned task -> a person PRIMARY @100; one owner-less carded task -> a card PRIMARY @100.
```
Expected: the two counts match; spot-checks show `allocation_pct = 100` and the right target column set.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260724000001_wp_task_assignments.sql
git commit -m "data(workforce): wp_task_assignments table + backfill owners as PRIMARY"
```

---

### Task 2: Switch `wp_person_load` to attribute via assignments

**Files:**
- Create: `supabase/migrations/20260724000002_wp_person_load_from_assignments.sql`

**Interfaces:**
- Consumes: `wp_task_assignments` (Task 1).
- Produces: `wp_person_load` with UNCHANGED output columns (`employee_id, company_id, tasks_owned, hours_fixed, hours_growing_base, capacity_hours, growth_multiplier`), now driven by PRIMARY assignments with an owner/card fallback.

- [ ] **Step 1: Capture the prod BEFORE snapshot (service_role — flag this use)**

Before applying anything in this task, snapshot the current view for every employee:

```bash
curl -s "$BASE/wp_person_load?select=employee_id,tasks_owned,hours_fixed,hours_growing_base&order=employee_id" \
  -H "apikey: $SR" -H "Authorization: Bearer $SR" > /tmp/wpl_before.json
```
Keep `/tmp/wpl_before.json` — it is the parity baseline.

- [ ] **Step 2: Write the view migration**

```sql
-- Attribute per-person load via PRIMARY assignments; allocation_pct scales the
-- hours. A person PRIMARY gives that employee allocation_pct% of the task's
-- hours; a card PRIMARY splits allocation_pct% evenly across the card's ACTIVE
-- holders (same split the old view did for card ownership). Tasks with NO
-- assignment yet (created via the current form before steps 5-6) fall back to
-- owner/card exactly as before, so no task is ever dropped. Output columns are
-- unchanged, so dependents and Dart are unaffected; because the backfill
-- mirrors ownership at 100%, every current number is preserved (parity-checked).
create or replace view wp_person_load with (security_invoker = true) as
with holders as (
  select e.id as employee_id, e.role_scorecard_id,
         count(*) over (partition by e.role_scorecard_id) as holder_count
  from employees e
  where e.employment_status = 'ACTIVE' and e.deleted_at is null
    and e.role_scorecard_id is not null
),
assigned as (
  -- person PRIMARY -> that employee, allocation_pct% of the hours
  select a.employee_id, tc.task_id,
         tc.hours_per_month_base * a.allocation_pct / 100.0 as hours, tc.is_growing
  from wp_task_computed tc
  join wp_task_assignments a
    on a.task_id = tc.task_id and a.assignment_role = 'PRIMARY' and a.employee_id is not null
  union all
  -- card PRIMARY -> allocation_pct% split evenly across the card's active holders
  select h.employee_id, tc.task_id,
         tc.hours_per_month_base * a.allocation_pct / 100.0 / h.holder_count, tc.is_growing
  from wp_task_computed tc
  join wp_task_assignments a
    on a.task_id = tc.task_id and a.assignment_role = 'PRIMARY' and a.role_scorecard_id is not null
  join holders h on h.role_scorecard_id = a.role_scorecard_id
),
fallback as (
  -- tasks with NO assignment yet: attribute by owner/card exactly as before
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
```

- [ ] **Step 3: Apply to prod**

Run: `supabase db push` → `Y`. Expected: applied, no error (CREATE OR REPLACE keeps the column list, so dependents are fine).

- [ ] **Step 4: Prod parity check — the gate (service_role — flag this use)**

```bash
curl -s "$BASE/wp_person_load?select=employee_id,tasks_owned,hours_fixed,hours_growing_base&order=employee_id" \
  -H "apikey: $SR" -H "Authorization: Bearer $SR" > /tmp/wpl_after.json
diff <(jq -S . /tmp/wpl_before.json) <(jq -S . /tmp/wpl_after.json) && echo "PARITY OK" || echo "PARITY FAIL"
```
Expected: **`PARITY OK`** — byte-identical. If it prints `PARITY FAIL` or shows any diff, STOP and report; do not proceed. (Floating-point note: both sides compute `hours_per_month_base` identically and multiply by `100/100.0`; if a pure formatting difference appears — e.g. `39.5` vs `39.500` — re-compare numerically per employee rather than as strings, and only accept if every value is arithmetically equal.)

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260724000002_wp_person_load_from_assignments.sql
git commit -m "data(workforce): wp_person_load attributes via PRIMARY assignments (parity-preserved)"
```

---

### Task 3: `WpTaskAssignment` model + repository read

**Files:**
- Modify: `lib/data/models/workforce_planning.dart` (add the model near `WpTask`)
- Modify: `lib/data/repositories/workforce_planning_repository.dart` (add `taskAssignments()`)
- Test: `test/data/models/wp_task_assignment_test.dart` (create)

**Interfaces:**
- Produces:
  - `class WpTaskAssignment { final String id, companyId, taskId; final String? roleScorecardId, employeeId; final String assignmentRole; final double allocationPct; ... fromRow ... toUpsert(companyId) }`
  - `Future<List<WpTaskAssignment>> WorkforcePlanningRepository.taskAssignments()` — paged like `tasks()`.

This is a read-only foothold for steps 5–6; nothing consumes it in the split yet (the split is in SQL for step 4).

- [ ] **Step 1: Write the failing model test**

```dart
// test/data/models/wp_task_assignment_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';

void main() {
  test('fromRow reads a card PRIMARY assignment', () {
    final a = WpTaskAssignment.fromRow({
      'id': 'a1', 'company_id': 'c', 'task_id': 't1',
      'role_scorecard_id': 'rs1', 'employee_id': null,
      'assignment_role': 'PRIMARY', 'allocation_pct': 100,
    });
    expect(a.roleScorecardId, 'rs1');
    expect(a.employeeId, isNull);
    expect(a.assignmentRole, 'PRIMARY');
    expect(a.allocationPct, 100);
  });

  test('fromRow reads a person CONTRIBUTOR with a fractional pct', () {
    final a = WpTaskAssignment.fromRow({
      'id': 'a2', 'company_id': 'c', 'task_id': 't1',
      'role_scorecard_id': null, 'employee_id': 'e1',
      'assignment_role': 'CONTRIBUTOR', 'allocation_pct': 42.5,
    });
    expect(a.employeeId, 'e1');
    expect(a.assignmentRole, 'CONTRIBUTOR');
    expect(a.allocationPct, 42.5);
  });

  test('toUpsert writes the target + role + pct', () {
    const a = WpTaskAssignment(id: '', companyId: 'c', taskId: 't1',
        roleScorecardId: 'rs1', assignmentRole: 'PRIMARY', allocationPct: 60);
    final m = a.toUpsert('c');
    expect(m['task_id'], 't1');
    expect(m['role_scorecard_id'], 'rs1');
    expect(m['employee_id'], isNull);
    expect(m['assignment_role'], 'PRIMARY');
    expect(m['allocation_pct'], 60);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/data/models/wp_task_assignment_test.dart`
Expected: FAIL — `WpTaskAssignment` undefined.

- [ ] **Step 3: Add the model** (in `workforce_planning.dart`, after `WpTask`)

```dart
class WpTaskAssignment {
  final String id, companyId, taskId;
  final String? roleScorecardId, employeeId;
  final String assignmentRole; // 'PRIMARY' | 'CONTRIBUTOR'
  final double allocationPct;
  const WpTaskAssignment({
    required this.id, required this.companyId, required this.taskId,
    this.roleScorecardId, this.employeeId,
    this.assignmentRole = 'CONTRIBUTOR', this.allocationPct = 0});
  factory WpTaskAssignment.fromRow(Map<String, dynamic> r) => WpTaskAssignment(
    id: r['id'] as String, companyId: r['company_id'] as String,
    taskId: r['task_id'] as String,
    roleScorecardId: r['role_scorecard_id'] as String?,
    employeeId: r['employee_id'] as String?,
    assignmentRole: r['assignment_role'] as String? ?? 'CONTRIBUTOR',
    allocationPct: _d(r['allocation_pct']));
  Map<String, dynamic> toUpsert(String companyId) => {
    'company_id': companyId, 'task_id': taskId,
    'role_scorecard_id': roleScorecardId, 'employee_id': employeeId,
    'assignment_role': assignmentRole, 'allocation_pct': allocationPct,
  };
}
```
(`_d` is the existing double coercion helper in this file — confirm its name and reuse it; if it is `_d`/`_dn`, use whichever coerces a non-null num to double.)

- [ ] **Step 4: Add the repository read** (in `workforce_planning_repository.dart`, near `tasks()`)

```dart
  /// Paged for the same reason as [tasks] — grows with every assignment.
  Future<List<WpTaskAssignment>> taskAssignments() => fetchAllPages((from, to) async {
        final rows = await _client
            .from('wp_task_assignments')
            .select()
            .order('task_id')
            .range(from, to);
        return rows.cast<Map<String, dynamic>>().map(WpTaskAssignment.fromRow).toList();
      });
```

- [ ] **Step 5: Run to verify it passes + analyze**

Run: `flutter test test/data/models/wp_task_assignment_test.dart`
Expected: PASS (3 tests).
Run: `flutter analyze lib/data/models/workforce_planning.dart lib/data/repositories/workforce_planning_repository.dart`
Expected: 0 errors.

- [ ] **Step 6: Commit**

```bash
git add lib/data/models/workforce_planning.dart lib/data/repositories/workforce_planning_repository.dart test/data/models/wp_task_assignment_test.dart
git commit -m "feat(workforce): WpTaskAssignment model + paged repository read"
```

---

### Task 4: Deno migration/backfill test on throwaway Postgres

**Files:**
- Create: `supabase/tests/wp_task_assignments_backfill_test.ts`

**Interfaces:**
- Consumes: the migrations from Tasks 1–2 (assumed applied to the local test DB).

Mirror the shape of `supabase/tests/delete_workflow_test.ts`: `DATABASE_URL` gate (skip when unset), `withTx` rollback wrapper, small `seed*` helpers, `postgres` superuser (RLS bypassed). Seed a company, employees (some holding a card, some soft-deleted), role_scorecards, and wp_tasks with known owner/card/neither combinations. Then assert:

- [ ] **Step 1: Write the test**

Cover:
1. **Backfill correctness:** after the backfill has run (it ran as part of the migration on the test DB), every wp_task with `owner_employee_id` has exactly one PRIMARY person assignment @100; every owner-less carded task has exactly one PRIMARY card assignment @100; a task with neither has zero assignments.
2. **One PRIMARY per task:** attempting to insert a second PRIMARY for a task throws (the `wp_task_assignments_one_primary` unique index).
3. **`one_target`:** inserting a row with both `role_scorecard_id` and `employee_id` (or neither) throws.
4. **Totals unchanged:** `select employee_id, hours_fixed, hours_growing_base from wp_person_load order by employee_id` equals the values computed from the seeded ownership by hand (compute the expected split — explicit owner full hours; card split across active non-deleted holders — and assert equality for each seeded employee).
5. **Idempotent:** re-running the backfill inserts (the two INSERT…NOT EXISTS statements) a second time adds zero rows.

Use assertions on row counts and numeric equality (allow a tiny epsilon for the divided hours). Follow the existing file's `assert`/`assertEquals` imports and `withTx` pattern exactly.

- [ ] **Step 2: Run it (best-effort — local Supabase may be unavailable)**

Run: `DATABASE_URL=postgres://postgres:postgres@127.0.0.1:54322/postgres deno test --allow-net --allow-env supabase/tests/wp_task_assignments_backfill_test.ts`
Expected: PASS. **Known caveat:** local Supabase on 54322 is often occupied by another project on this machine (see the team's local-RLS-testing notes) — if the DB is unreachable, the test SKIPS (by design) rather than fails. If it skips, report that it could not be executed locally and rely on the Task 2 prod parity check as the live guard; do NOT block the plan on an unrunnable local DB.

- [ ] **Step 3: Commit**

```bash
git add supabase/tests/wp_task_assignments_backfill_test.ts
git commit -m "test(workforce): wp_task_assignments backfill + parity Deno test"
```

---

### Task 5: Full-suite + analyze gate

- [ ] **Step 1: Full suite**

Run: `flutter test`
Expected: all pass (prior 1029 + the new model tests; 1 pre-existing skip). The split logic in `rebalance.dart` is UNCHANGED, so all workforce tests must remain green untouched — if any changed, something was modified that shouldn't have been. STOP and report if a pre-existing test fails.

- [ ] **Step 2: Analyze**

Run: `flutter analyze`
Expected: 0 errors.

---

## Self-Review

**Spec coverage** (spec §"Assignment (new)", §"How the per-person numbers come out", Sequencing item 4):
- `wp_task_assignments` table with the exact schema + three unique indexes + `one_target` → Task 1. ✓
- Backfill each owner/card → one PRIMARY assignment → Task 1 (person for explicit owner, card otherwise). ✓
- Split extended: card assignment → allocation% split across active holders; person assignment → allocation% to that person; Σ handled → Task 2's `assigned` CTE. ✓
- `owner_employee_id` retained (not dropped) for rollback, no longer the source of truth once assignments exist → Task 2 reads assignments first, owner/card only as fallback for un-assigned tasks. ✓
- "Nothing user-visible changes yet" → Task 2 prod parity check proves `wp_person_load` output is identical; `rebalance.dart` untouched so Balance is identical by construction. ✓
- Migration tested on throwaway Postgres (every owner → one PRIMARY; totals unchanged; idempotent) → Task 4. ✓
- Company-scoped RLS on the new table → Task 1. ✓

**Deferred (correctly NOT here):** the Dart `rebalance.dart` split switch to assignments, and any allocation ≠ 100 — both belong to step 5 (the assignment panel + % editor), which is the first step that makes allocations vary and thus needs the Dart split to honor them. Until then owner/card and assignments are numerically identical.

**Placeholder scan:** every migration and Dart step has complete code; the Deno test (Task 4) specifies the five exact assertions and the harness to mirror rather than restating a whole file — acceptable because the assertions and pattern are pinned.

**Type consistency:** `WpTaskAssignment` fields/`fromRow`/`toUpsert` (Task 3) match the table columns (Task 1) and the test (Task 3). The view's output columns (Task 2) are identical to the pre-existing `wp_person_load` (recon §B), so `WpPersonLoad.fromRow` is unaffected.

**Risk register:** (1) parity — mitigated by the before/after prod snapshot gate (Task 2 Step 4). (2) a task with neither owner nor card nor assignment — correctly contributes to nobody (matches today). (3) a card PRIMARY on a card with zero active holders — contributes to nobody (matches today's vacant-role behavior). (4) `resolveEffectiveOwner` uses a holder predicate missing `deletedAt == null` (recon §D) — NOT touched here (it's a display label, not the load split), left as its own pre-existing known divergence.
