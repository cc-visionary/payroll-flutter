# KPI Cascade — Definitions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a KPI say what level it lives at, what it serves, how it rolls up and where its data comes from — and put a Desired Outcome between a role's accountability areas and its KPIs.

**Architecture:** Additive columns on `kpis` and `role_scorecard_kpis`, one new `role_outcomes` table, and one destructive migration that ends per-employee KPI curation. No results engine here: this plan makes definitions expressive enough for the engine to be built against. That engine is the second plan from the same spec.

**Tech Stack:** Flutter (Material 3, Riverpod 3.x), Supabase Postgres, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-08-13-kpi-cascade-design.md` — read it first, especially "Decisions" and "Removing `employee_kpis`".

## Global Constraints

- The repo gates on `flutter analyze` only: **0 errors, 0 warnings**. There are 192 pre-existing `info` lints — add none.
- **Do not run `dart format`.** This repo has mixed old/new formatter style and is not gated on it. Match the file you are editing.
- Never claim a test passed or the analyzer was clean without pasting the command output.
- **Migrations are applied by the user, never by an implementer.** You have no authority to run `supabase db push` or any database command. Commit the file and hand it over.
- Migrations must be idempotent in this repo's style: `add column if not exists`, `create table if not exists`, `drop policy if exists` before `create policy`. Read a recent migration before writing yours.
- Widget tests use `initSupabaseStub()` from `test/support/supabase_stub.dart`.
- Baseline: **1359 passing, 1 skipped**; `flutter analyze lib test` 0 errors / 0 warnings / 192 infos. Do not regress it.
- Vocabulary is **role**, never "seat". EOS is not the framework here.
- Two unapplied migrations already exist and ship with this work: `20260811000001_kpi_measurables.sql` and — until Task 7 deletes them — `20260811000002` and `20260812000001`.

## File Structure

| File | Responsibility |
|---|---|
| `supabase/migrations/20260814000001_kpi_cascade_fields.sql` (new) | Level, parent, roll-up type, data method, default target on `kpis` |
| `supabase/migrations/20260814000002_role_outcomes.sql` (new) | `role_outcomes` + RLS + `role_scorecard_kpis.outcome_id` |
| `supabase/migrations/20260814000003_role_inherited_kpis.sql` (new) | Rewrite `generate_employee_review`; drop `employee_kpis` |
| `lib/data/models/kpi.dart` (modify) | The four new fields and the default target |
| `lib/data/models/role_outcome.dart` (new) | `RoleOutcome` |
| `lib/data/repositories/role_scorecard_repository.dart` (modify) | Outcome CRUD; carry `outcome_id` on links |
| `lib/features/workforce_planning/role/outcomes_pane.dart` (new) | Authoring outcomes per accountability area |
| `lib/features/kpi_library/kpi_library_screen.dart` (modify) | The new fields and a level filter |

---

### Task 1: The four definition columns

**Files:**
- Create: `supabase/migrations/20260814000001_kpi_cascade_fields.sql`
- Modify: `lib/data/models/kpi.dart`
- Test: `test/data/models/kpi_cascade_fields_test.dart`

**Interfaces:**
- Produces: `Kpi.level`, `Kpi.parentKpiId`, `Kpi.rollupType`, `Kpi.dataMethod`, all `String?` except `level` and `rollupType` and `dataMethod` which are non-null with defaults; and the constant lists `kKpiLevels`, `kKpiRollupTypes`, `kKpiDataMethods`.

`kpis.department_id` **already exists** (applied `20260723000002_kpi_departments.sql`, already on the model). Do not add it again.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/kpi.dart';

void main() {
  test('reads the cascade fields off a row', () {
    final k = Kpi.fromRow({
      'id': 'k1',
      'company_id': 'c1',
      'name': 'Fulfillment Accuracy',
      'level': 'DEPARTMENT',
      'parent_kpi_id': 'k-company',
      'rollup_type': 'DIRECT',
      'data_method': 'HYBRID',
    });
    expect(k.level, 'DEPARTMENT');
    expect(k.parentKpiId, 'k-company');
    expect(k.rollupType, 'DIRECT');
    expect(k.dataMethod, 'HYBRID');
  });

  test('a row predating the migration falls back to sane defaults', () {
    // A narrowed select, or a client running before the migration lands,
    // must not throw. Same reason the measurable columns are defaulted.
    final k = Kpi.fromRow({'id': 'k1', 'company_id': 'c1', 'name': 'Old'});
    expect(k.level, 'PERSONAL');
    expect(k.rollupType, 'INDEPENDENT');
    expect(k.dataMethod, 'MANUAL_PERIODIC');
    expect(k.parentKpiId, isNull);
  });

  test('the defaults are the conservative ones', () {
    // INDEPENDENT means "compute only my own level" and MANUAL_PERIODIC means
    // "nobody claims this is automatic". An unconfigured KPI must not claim to
    // roll up into a company number or to be automatically sourced.
    expect(kKpiRollupTypes.first, 'DIRECT');
    expect(kKpiRollupTypes, contains('INDEPENDENT'));
    expect(kKpiDataMethods, contains('MANUAL_PERIODIC'));
    expect(kKpiLevels, ['PERSONAL', 'DEPARTMENT', 'COMPANY']);
  });

  test('toInsert carries the cascade fields', () {
    const k = Kpi(
      id: 'k1',
      companyId: 'c1',
      name: 'Case SLA',
      level: 'DEPARTMENT',
      parentKpiId: 'k0',
      rollupType: 'ALIGNED',
      dataMethod: 'AUTOMATIC',
    );
    final row = k.toInsert('c1');
    expect(row['level'], 'DEPARTMENT');
    expect(row['parent_kpi_id'], 'k0');
    expect(row['rollup_type'], 'ALIGNED');
    expect(row['data_method'], 'AUTOMATIC');
  });
}
```

- [ ] **Step 2: Run it, watch it fail**

Run: `flutter test test/data/models/kpi_cascade_fields_test.dart`
Expected: FAIL — `The named parameter 'level' isn't defined`.

- [ ] **Step 3: Write the migration**

```sql
-- The KPI cascade: a KPI now states which level it lives at, which higher
-- measure it serves, whether it may be recomputed at wider scopes, and where
-- its numbers come from.
--
-- Defaults are deliberately the conservative ones. INDEPENDENT means "compute
-- only my own level", so an unconfigured KPI never silently claims to roll up
-- into a company number. MANUAL_PERIODIC means "nobody has claimed this is
-- automatic" -- the type the owner wants LEAST used, which is exactly why it
-- is the honest default for a KPI nobody has classified.
--
-- department_id is NOT added here: 20260723000002 already added it.

alter table kpis
  add column if not exists level text not null default 'PERSONAL'
    check (level in ('PERSONAL','DEPARTMENT','COMPANY')),
  add column if not exists parent_kpi_id uuid references kpis(id) on delete set null,
  add column if not exists rollup_type text not null default 'INDEPENDENT'
    check (rollup_type in ('DIRECT','SHARED','ALIGNED','INDEPENDENT')),
  add column if not exists data_method text not null default 'MANUAL_PERIODIC'
    check (data_method in ('AUTOMATIC','HYBRID','MANUAL_EXCEPTION','MANUAL_PERIODIC')),
  -- The default target. A DEPARTMENT or COMPANY KPI has no role card to hang
  -- one on, so it cannot live only on role_scorecard_kpis.
  add column if not exists target_direction text
    check (target_direction is null or target_direction in ('HIGHER','LOWER')),
  add column if not exists target_value numeric;

create index if not exists kpis_company_level on kpis (company_id, level);
create index if not exists kpis_parent on kpis (parent_kpi_id);

comment on column kpis.rollup_type is
  'DIRECT: recompute at wider scopes from the same source. SHARED: department '
  'and company only, never personal. ALIGNED/INDEPENDENT: this level only.';
```

`on delete set null` for the parent, not cascade: deleting a company KPI must orphan its children, never delete real departmental measures.

- [ ] **Step 4: Add the fields to the model**

In `lib/data/models/kpi.dart`, beside the existing measurable block, add the constant lists and four fields. Follow the existing `fromRow` convention exactly — every new column is read with a `?? default`, for the reason already commented there.

```dart
const kKpiLevels = ['PERSONAL', 'DEPARTMENT', 'COMPANY'];
const kKpiRollupTypes = ['DIRECT', 'SHARED', 'ALIGNED', 'INDEPENDENT'];
const kKpiDataMethods = [
  'AUTOMATIC',
  'HYBRID',
  'MANUAL_EXCEPTION',
  'MANUAL_PERIODIC',
];
```

Fields on `Kpi`, with doc comments in the style of the ones already there:

```dart
  /// PERSONAL | DEPARTMENT | COMPANY — the scope this measure is designed for.
  final String level;

  /// The higher-level measure this one serves. Null at the top.
  final String? parentKpiId;

  /// DIRECT | SHARED | ALIGNED | INDEPENDENT. Governs whether the results
  /// engine may recompute this KPI at a wider scope.
  final String rollupType;

  /// AUTOMATIC | HYBRID | MANUAL_EXCEPTION | MANUAL_PERIODIC.
  final String dataMethod;

  /// HIGHER | LOWER, and the number that counts as healthy. The DEFAULT
  /// target: `role_scorecard_kpis.goal_*` overrides it for one role, and a
  /// DEPARTMENT or COMPANY scope has no role link so it uses this.
  final String? targetDirection;
  final num? targetValue;
```

Constructor params: `this.level = 'PERSONAL'`, `this.parentKpiId`, `this.rollupType = 'INDEPENDENT'`, `this.dataMethod = 'MANUAL_PERIODIC'`, `this.targetDirection`, `this.targetValue`.

`fromRow` additions:

```dart
    level: r['level'] as String? ?? 'PERSONAL',
    parentKpiId: r['parent_kpi_id'] as String?,
    rollupType: r['rollup_type'] as String? ?? 'INDEPENDENT',
    dataMethod: r['data_method'] as String? ?? 'MANUAL_PERIODIC',
    targetDirection: r['target_direction'] as String?,
    targetValue: r['target_value'] as num?,
```

`toInsert` additions:

```dart
    'level': level,
    'parent_kpi_id': parentKpiId,
    'rollup_type': rollupType,
    'data_method': dataMethod,
    'target_direction': targetDirection,
    'target_value': targetValue,
```

- [ ] **Step 5: Run the test, watch it pass**

Run: `flutter test test/data/models/kpi_cascade_fields_test.dart`
Expected: PASS, 4/4.

- [ ] **Step 6: Full suite and analyzer**

Run: `flutter test` then `flutter analyze lib test`
Expected: 1363 passing / 1 skipped; 0 errors, 0 warnings, 192 infos.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(kpi): level, parent, roll-up type, data method and a default target"
```

---

### Task 2: A KPI cannot be its own ancestor

**Files:**
- Create: `lib/features/kpi_library/kpi_parentage.dart`
- Test: `test/features/kpi_library/kpi_parentage_test.dart`

**Interfaces:**
- Consumes: nothing from Task 1 at runtime — this is pure logic over `({String id, String? parentId})` records.
- Produces: `String? kpiParentError({required String kpiId, required String newParentId, required List<({String id, String? parentId})> kpis, required String Function(String id) levelOf})`.

`parent_kpi_id` is a self-reference, so it can cycle. `lib/features/workforce_planning/org_tree.dart:51` already has a generic `wouldCreateCycle` over exactly this record shape — **reuse it, do not write a second cycle walk.**

There is a second rule beyond cycles: a KPI may only serve a HIGHER level. Personal → Department → Company. A department KPI parented to another department KPI is a modelling mistake that would make the cascade meaningless.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/kpi_library/kpi_parentage.dart';

void main() {
  const levels = {
    'p1': 'PERSONAL',
    'p2': 'PERSONAL',
    'd1': 'DEPARTMENT',
    'd2': 'DEPARTMENT',
    'c1': 'COMPANY',
  };
  String levelOf(String id) => levels[id]!;

  String? run(
    String kpiId,
    String parentId, {
    List<({String id, String? parentId})> kpis = const [],
  }) => kpiParentError(
    kpiId: kpiId,
    newParentId: parentId,
    kpis: kpis,
    levelOf: levelOf,
  );

  test('personal may serve department', () {
    expect(run('p1', 'd1'), isNull);
  });

  test('department may serve company', () {
    expect(run('d1', 'c1'), isNull);
  });

  test('personal may serve company directly', () {
    // Not every function has a department KPI in between. Skipping a level is
    // legal; going sideways or down is not.
    expect(run('p1', 'c1'), isNull);
  });

  test('a KPI may not serve its own level', () {
    expect(run('d1', 'd2'), 'A KPI can only serve a higher level.');
  });

  test('a KPI may not serve a lower level', () {
    expect(run('c1', 'd1'), 'A KPI can only serve a higher level.');
  });

  test('a KPI may not be its own parent', () {
    expect(run('d1', 'd1'), "A KPI can't serve itself.");
  });

  test('a cycle is refused', () {
    // d1 -> c1 already; making c1 serve d1 closes the loop.
    expect(
      run('c1', 'd1', kpis: const [
        (id: 'd1', parentId: 'c1'),
        (id: 'c1', parentId: null),
      ]),
      isNotNull,
    );
  });
}
```

- [ ] **Step 2: Run it, watch it fail**

Run: `flutter test test/features/kpi_library/kpi_parentage_test.dart`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Implement**

```dart
import '../workforce_planning/org_tree.dart';

const _rank = {'PERSONAL': 0, 'DEPARTMENT': 1, 'COMPANY': 2};

/// Error for parenting [kpiId] under [newParentId], or null when valid.
///
/// Two rules, and they fail for different reasons. The level rule is about
/// meaning: a cascade only cascades upward, so a department measure serving
/// another department measure says nothing. The cycle rule is about
/// termination: `parent_kpi_id` is a self-reference and a loop would hang any
/// walk up the tree.
///
/// [wouldCreateCycle] is reused verbatim from `org_tree.dart` — it is generic
/// over `({String id, String? parentId})` and has nothing to do with people.
String? kpiParentError({
  required String kpiId,
  required String newParentId,
  required List<({String id, String? parentId})> kpis,
  required String Function(String id) levelOf,
}) {
  if (kpiId == newParentId) return "A KPI can't serve itself.";
  final mine = _rank[levelOf(kpiId)] ?? 0;
  final theirs = _rank[levelOf(newParentId)] ?? 0;
  if (theirs <= mine) return 'A KPI can only serve a higher level.';
  if (wouldCreateCycle(
    movingId: kpiId,
    newParentId: newParentId,
    people: kpis,
  )) {
    return 'That would create a loop.';
  }
  return null;
}
```

- [ ] **Step 4: Run the test, watch it pass**

Run: `flutter test test/features/kpi_library/kpi_parentage_test.dart`
Expected: PASS, 7/7.

- [ ] **Step 5: Full suite, analyzer, commit**

```bash
git add -A
git commit -m "feat(kpi): refuse a parent that is sideways, downward or looping"
```

---

### Task 3: Desired outcomes

**Files:**
- Create: `supabase/migrations/20260814000002_role_outcomes.sql`
- Create: `lib/data/models/role_outcome.dart`
- Modify: `lib/data/repositories/role_scorecard_repository.dart`
- Test: `test/data/models/role_outcome_test.dart`

**Interfaces:**
- Produces: `RoleOutcome(id, companyId, roleScorecardId, responsibilityArea, text, sortOrder)` with `fromRow` and `toUpsertPayload`; and on `RoleScorecardRepository`: `Future<List<RoleOutcome>> outcomes(String roleId)`, `Future<void> saveOutcomes(String roleId, List<RoleOutcome> outcomes)`, `Future<void> deleteOutcome(String id)`.

An outcome is scoped to a role AND one of its accountability areas. The area is the **text** name, matching `wp_tasks.responsibility_area` — areas are not rows in this schema, which is why `areasByRole` in `lib/features/workforce_planning/role_structure.dart` groups by string.

- [ ] **Step 1: Write the migration**

```sql
-- Desired Outcomes sit between a role's responsibilities and its KPIs.
-- "Pack orders accurately" is work; "customers receive the correct product"
-- is the outcome; fulfillment accuracy is the number that proves it. Without
-- this layer every responsibility grows its own KPI, which is the failure the
-- KPI cascade spec exists to prevent.
--
-- responsibility_area is TEXT, not a foreign key: accountability areas are not
-- rows in this schema. They are the grouping string on wp_tasks, which is how
-- areasByRole() already derives them.

create table if not exists role_outcomes (
  id                  uuid primary key default gen_random_uuid(),
  company_id          uuid not null references companies(id) on delete cascade,
  role_scorecard_id   uuid not null references role_scorecards(id) on delete cascade,
  responsibility_area text not null,
  text                text not null,
  sort_order          integer not null default 0,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint role_outcomes_text_not_blank check (length(trim(text)) > 0)
);
create index if not exists role_outcomes_role on role_outcomes (role_scorecard_id);

drop trigger if exists _role_outcomes_updated on role_outcomes;
create trigger _role_outcomes_updated before update on role_outcomes
  for each row execute function set_updated_at();

alter table role_outcomes enable row level security;

-- Company-read, admin-write, mirroring kpis (20260718000001:99-105). An
-- outcome is role design, not a judgement about a person, so it carries no
-- personal data and needs no per-employee clause.
drop policy if exists role_outcomes_company_select on role_outcomes;
create policy role_outcomes_company_select on role_outcomes for select
  using (company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN');

drop policy if exists role_outcomes_company_write on role_outcomes;
create policy role_outcomes_company_write on role_outcomes for all
  using (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR','HR_ADMIN')
    and (company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN'))
  with check (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR','HR_ADMIN')
    and (company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN'));

-- Which outcome a role's KPI proves. Nullable: a KPI may exist before anyone
-- has written the outcome, and a COMPANY KPI has no role link at all.
alter table role_scorecard_kpis
  add column if not exists outcome_id uuid references role_outcomes(id) on delete set null;
```

`on delete set null` on the link, not cascade: deleting an outcome must not delete the KPI that was proving it.

- [ ] **Step 2: Write the failing model test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/role_outcome.dart';

void main() {
  test('round-trips a row', () {
    final o = RoleOutcome.fromRow({
      'id': 'o1',
      'company_id': 'c1',
      'role_scorecard_id': 'r1',
      'responsibility_area': 'Order Fulfillment',
      'text': 'Customers receive the correct product',
      'sort_order': 2,
    });
    expect(o.responsibilityArea, 'Order Fulfillment');
    expect(o.text, 'Customers receive the correct product');
    expect(o.sortOrder, 2);

    final payload = o.toUpsertPayload();
    expect(payload['responsibility_area'], 'Order Fulfillment');
    expect(payload['sort_order'], 2);
    expect(payload['role_scorecard_id'], 'r1');
  });

  test('sort_order defaults to zero when absent', () {
    final o = RoleOutcome.fromRow({
      'id': 'o1',
      'company_id': 'c1',
      'role_scorecard_id': 'r1',
      'responsibility_area': 'Returns',
      'text': 'Refunds land within SLA',
    });
    expect(o.sortOrder, 0);
  });
}
```

- [ ] **Step 3: Run it, watch it fail. Step 4: Implement the model and the three repository methods. Step 5: Run it, watch it pass.**

Repository methods go beside the existing KPI methods in `role_scorecard_repository.dart`, following the same `_client.from(...)` style already used there. `saveOutcomes` writes `sort_order` from list position, the way the existing responsibility saves do.

- [ ] **Step 6: Full suite, analyzer, commit**

```bash
git add -A
git commit -m "feat(wp): desired outcomes between a role's areas and its KPIs"
```

---

### Task 4: The Outcomes pane

**Files:**
- Create: `lib/features/workforce_planning/role/outcomes_pane.dart`
- Modify: `lib/features/workforce_planning/role/role_workbench_screen.dart`
- Test: `test/features/workforce_planning/role/outcomes_pane_test.dart`

**Interfaces:**
- Consumes: `RoleOutcome`, the three repository methods from Task 3, and `areasByRole` from `lib/features/workforce_planning/role_structure.dart`.

Read `responsibilities_pane.dart` in the same directory before writing this. Match its structure: its own save button, its own dirty tracking, no shared form key with the other panes. The workbench deliberately has no single form spanning panes — a manager fixing an outcome must not be blocked by an unrelated empty field elsewhere.

**Shape:** the role's accountability areas in authored order, each with its outcomes beneath it and an "Add outcome" affordance. An area with no outcome shows an explicit empty line rather than nothing — an invisible gap is the thing this pane exists to make visible.

- [ ] **Step 1: Write the failing widget test**

Cover at minimum:
- each accountability area from `wpTasksProvider` renders as a heading, in authored order
- an area with no outcomes shows the empty-state line, not blank space
- an outcome's text renders under its own area and not under another
- adding an outcome to one area and saving calls `saveOutcomes` with that area's name

Use `initSupabaseStub()` and a capturing fake repository, following `test/features/workforce_planning/role/role_details_pane_test.dart`'s `_CapturingRepository` pattern. Set `tester.view.physicalSize` tall — content below the fold never mounts otherwise, which is a documented trap in `test/support/supabase_stub.dart`.

- [ ] **Step 2: Run, watch fail. Step 3: Implement. Step 4: Run, watch pass.**

- [ ] **Step 5: Full suite, analyzer, commit**

```bash
git add -A
git commit -m "feat(wp): author desired outcomes per accountability area"
```

---

### Task 5: A KPI names the outcome it proves

**Files:**
- Modify: `lib/features/workforce_planning/role/kpis_pane.dart`
- Modify: `lib/data/repositories/role_scorecard_repository.dart`
- Modify: `lib/data/models/kpi.dart` (the `KpiLinkInput` class)
- Test: `test/features/workforce_planning/role/kpi_outcome_link_test.dart`

**Interfaces:**
- Consumes: `RoleOutcome` (Task 3), `outcome_id` on `role_scorecard_kpis` (Task 3).
- Produces: `KpiLinkInput.outcomeId` (`String?`), persisted by `saveRoleScorecardKpis`.

**Read this before touching the repository.** `saveRoleScorecardKpis` splits its writes into three homogeneous upsert batches on purpose. PostgREST sends the UNION of all rows' keys via `?columns=` and **silently NULLs any key a row omits**, so a mixed batch wipes columns. Adding `outcome_id` must not merge those batches. If you are unsure which batch a row belongs in, read `KpiLinkInput.writeGoal`'s doc comment — it documents the same class of bug, which reached a signed contract once.

- [ ] **Step 1: Write the failing test**

Assert the VALUE, not key presence: `expect(repo.saved!.single.outcomeId, 'o1')`. A `containsKey` check passes against the bug, because the buggy write emits the key with a null value. That exact trap was hit on this codebase before.

Also assert that saving a link with a null `outcomeId` does not disturb another link's stored outcome in the same call.

- [ ] **Step 2: Run, watch fail. Step 3: Implement. Step 4: Run, watch pass.**

In the pane, the selector lists only outcomes belonging to THIS role, grouped by area, plus a "— none —" option. A KPI with no outcome is legal and must stay legal.

- [ ] **Step 5: Full suite, analyzer, commit**

```bash
git add -A
git commit -m "feat(wp): a role's KPI names the outcome it proves"
```

---

### Task 6: The KPI Library speaks the cascade

**Files:**
- Modify: `lib/features/kpi_library/kpi_library_screen.dart`
- Test: `test/features/kpi_library/kpi_library_cascade_test.dart`

**Interfaces:**
- Consumes: everything from Tasks 1 and 2.

`kpi_library_screen.dart` is 761 lines. Do not restructure it wholesale; add to it in its existing style. If the KPI form section grows past readability while you work, extracting just that form into a sibling file is reasonable and in keeping with how this repo has split panes before.

**What to add:**
- Level, Roll-Up Type and Data Method as dropdowns on the KPI form, from `kKpiLevels` / `kKpiRollupTypes` / `kKpiDataMethods`.
- Parent KPI as a searchable select, validated through `kpiParentError` from Task 2. Show the returned message inline; do not save through it.
- Default target: direction + value, beside the existing measurable fields.
- A level filter on the list, defaulting to all.

- [ ] **Step 1: Write the failing widget test**

Cover at minimum:
- the level filter narrows the list to matching KPIs, and "all" restores it
- choosing a parent at the same level surfaces `kpiParentError`'s message and leaves the form unsaved
- a saved KPI round-trips its level, roll-up type and data method through the repository call

- [ ] **Step 2: Run, watch fail. Step 3: Implement. Step 4: Run, watch pass.**

- [ ] **Step 5: Full suite, analyzer, commit**

```bash
git add -A
git commit -m "feat(kpi): author level, parentage, roll-up and data method"
```

---

### Task 7: A person's KPIs are their role's KPIs

**Files:**
- Create: `supabase/migrations/20260814000003_role_inherited_kpis.sql`
- Delete: `supabase/migrations/20260811000002_explicit_employee_kpi_sets.sql`
- Delete: `supabase/migrations/20260812000001_employee_kpi_set_comment.sql`
- Delete: `lib/features/kpi_library/kpi_set_rules.dart`
- Modify: `lib/data/repositories/performance_repository.dart`, `lib/data/repositories/role_scorecard_repository.dart`, `lib/features/employees/profile/tabs/role_tab.dart`, `lib/features/workforce_planning/needs_attention.dart`, `lib/features/workforce_planning/role/people_pane.dart`
- Delete: `test/features/kpi_library/kpi_set_rules_test.dart`, `test/features/employees/employee_kpi_assignment_section_test.dart`, `test/data/repositories/employee_kpi_selection_test.dart`, `test/data/repositories/kpi_set_persistence_test.dart`

**This is the destructive task. Read the spec's "Removing `employee_kpis`" section before starting.**

`employee_kpis` is **live on production**, not an unapplied file. `20260718000006` defines `generate_employee_review`, a live SQL function that reads it: it intersects an employee's subset with their role's KPIs and falls back to the full role set when the subset is empty. Dropping the table without rewriting that function breaks review generation for everyone.

Because "no rows" already means "the whole role set", every employee without a curated subset is unaffected by definition. Only employees with a deliberately narrowed subset change behaviour — to their full role set, which is what pure inheritance means.

- [ ] **Step 1: Read the existing function**

Run: `cat supabase/migrations/20260718000006_review_from_employee_kpis.sql`

You are rewriting this function, not deleting it. Step 2 gives you the finished text — **diff it against the original yourself** and confirm the only differences are: the `v_has_assignment` declaration, the `select exists (...)` block that set it, the `and ( not v_has_assignment or exists (...) )` clause in the KPI loop, and two error strings. Everything else must be byte-identical. **Paste that diff into your report** — a reviewer cannot verify a SQL function rewrite from a description.

The two error strings are a deliberate extra: `'Employee has no Responsibility Card'` and `'Responsibility Card not found'` are old vocabulary, and this repo now says **role** everywhere. They become `'Employee has no role'` and `'Role not found'`. Flag them in your report rather than letting them look like an accidental diff.

- [ ] **Step 2: Write the migration**

```sql
-- Pure inheritance: a person's KPIs are their role's KPIs.
--
-- employee_kpis let an employee be tracked on a SUBSET of their role card's
-- KPIs, with zero rows meaning "the whole role set". That subset is retired:
-- a role now defines 2-4 KPIs and whoever holds it inherits them, so a new
-- hire is measurable on assignment and a role change moves measurement with
-- no per-employee setup.
--
-- generate_employee_review is rewritten FIRST, in this same migration, because
-- it reads employee_kpis and dropping the table under a live function would
-- break review generation for everyone.
--
-- Blast radius: employees with no curated subset are unaffected by definition,
-- since zero rows already meant the full role set. Employees with a narrowed
-- subset widen to their full role set -- which is the intent, not a defect.

create or replace function generate_employee_review(
  p_review_cycle_id uuid,
  p_employee_id uuid
) returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_cycle review_cycles%rowtype;
  v_employee employees%rowtype;
  v_card role_scorecards%rowtype;
  v_review_id uuid;
  v_item jsonb;
  v_index integer;
begin
  select * into v_cycle from review_cycles where id = p_review_cycle_id;
  if not found then raise exception 'Review cycle not found'; end if;

  select * into v_employee from employees
    where id = p_employee_id and deleted_at is null;
  if not found then raise exception 'Employee not found or archived'; end if;
  if v_employee.company_id <> v_cycle.company_id then
    raise exception 'Employee and review cycle belong to different companies';
  end if;
  if v_employee.role_scorecard_id is null then
    raise exception 'Employee has no role';
  end if;
  if v_employee.reports_to_id is null then
    raise exception 'Employee has no direct manager';
  end if;

  select * into v_card from role_scorecards where id = v_employee.role_scorecard_id;
  if not found then raise exception 'Role not found'; end if;

  select id into v_review_id from employee_reviews
    where review_cycle_id = p_review_cycle_id and employee_id = p_employee_id;
  if found then return v_review_id; end if;

  insert into employee_reviews (
    review_cycle_id, employee_id, employee_name_snapshot,
    responsibility_card_id, responsibility_card_version, direct_manager_id,
    review_type, review_period_start, review_period_end,
    responsibility_snapshot
  ) values (
    v_cycle.id, v_employee.id,
    concat_ws(' ', v_employee.first_name, v_employee.middle_name, v_employee.last_name),
    v_card.id, v_card.version, v_employee.reports_to_id,
    v_cycle.review_type, v_cycle.period_start, v_cycle.period_end,
    v_card.key_responsibilities
  ) returning id into v_review_id;

  -- Every KPI on the role, with no per-employee filter. This is the whole
  -- change: v_has_assignment and its EXISTS clause are gone.
  v_index := 0;
  for v_item in
    select jsonb_build_object(
      'name', k.name,
      'measurement', k.measurement_unit,
      'target', rsk.target
    ) as value
    from role_scorecard_kpis rsk
      join kpis k on k.id = rsk.kpi_id
    where rsk.role_scorecard_id = v_card.id
    order by rsk.sort_order
  loop
    insert into review_kpi_results (
      review_id, snapshot_order, kpi_name, description,
      measurement_unit, target_value, is_qualitative
    ) values (
      v_review_id, v_index,
      coalesce(v_item->>'name', ''),
      null, v_item->>'measurement', v_item->>'target',
      false
    );
    v_index := v_index + 1;
  end loop;

  v_index := 0;
  for v_item in select value from jsonb_array_elements(v_card.required_skills)
  loop
    insert into review_skill_ratings (
      review_id, snapshot_order, skill_name, skill_description,
      skill_category, required_level
    ) values (
      v_review_id, v_index, coalesce(v_item->>'name', ''),
      v_item->>'description', 'TECHNICAL',
      coalesce((v_item->>'required_level')::integer, 3)
    );
    v_index := v_index + 1;
  end loop;

  for v_item in select value from jsonb_array_elements(v_card.behavioral_expectations)
  loop
    insert into review_skill_ratings (
      review_id, snapshot_order, skill_name, skill_description,
      skill_category, required_level
    ) values (
      v_review_id, v_index, coalesce(v_item->>'name', ''),
      v_item->>'description', 'BEHAVIORAL', null
    );
    v_index := v_index + 1;
  end loop;

  return v_review_id;
end;
$$;

drop table if exists employee_kpis;
```

- [ ] **Step 3: Strip the Dart plumbing**

Remove per-employee KPI selection from each modified file. In `needs_attention.dart`, the "N people with no KPI set" signal becomes **"N roles with no KPI"** — the gap is now a role's, not a person's. Keep the zero-suppressing `add()` helper and the existing category/severity/target.

`wpKpiAssignmentMapsProvider` and its `roleKpiIdsByCard` / `assignedKpiIdsByEmployee` maps exist only to serve that signal. Check whether anything else consumes them before deleting; if nothing does, delete them too and say so.

- [ ] **Step 4: Delete the four obsolete test files, and update the ones that survive**

Do not delete a test merely because it mentions `employee_kpis` — read it first. A test asserting a rule that still holds should be retargeted, not removed. Report which you deleted and which you kept, with the reason for each.

- [ ] **Step 5: Full suite and analyzer**

Run: `flutter test` then `flutter analyze lib test`
Expected: green; 0 errors, 0 warnings, 192 infos. The count will DROP — say by how many and account for it.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(kpi): a person's KPIs are their role's KPIs"
```

---

## Done when

- A KPI carries level, parent, roll-up type, data method and a default target, and the Library can author and filter on them.
- A parent that is sideways, downward or looping is refused with a message.
- A role's accountability areas carry desired outcomes, and a role's KPI can name the outcome it proves.
- `generate_employee_review` reads the role's KPIs directly and `employee_kpis` is dropped in the same migration.
- `flutter test` green; `flutter analyze lib test` 0 errors, 0 warnings.
- Four migrations committed and handed over, **not applied**: the existing `20260811000001`, plus `20260814000001`, `20260814000002`, `20260814000003`. `20260811000002` and `20260812000001` are deleted by Task 7.

## Not in this plan

The results engine — `kpi_results`, `kpi_exceptions`, status, population resolution, the automatic source registry, the dashboard — is the second plan from this spec. It depends on every field this plan adds, which is why it is written after this one lands rather than alongside it.
