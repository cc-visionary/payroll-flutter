# Role Workbench — Plan 4: Needs Attention

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface the two gaps the measurable model created — people with no KPI set, and KPIs that are not yet measurable — as click-through chips on the Needs-attention strip, and let the KPI Library show which roles use each KPI.

**Architecture:** Two new `AttentionItem`s computed in the existing pure `buildNeedsAttention`, plus one repository-backed count in the KPI Library. No new screens, no new routes, no migration.

**Tech Stack:** Flutter (Material 3, Riverpod, GoRouter), Supabase Postgres, `flutter_test`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-11-role-workbench-design.md`. Plans 1 and 2 are merged; their Global Constraints still bind.
- **`buildNeedsAttention` is pure and must stay pure** — it takes lists and returns items. New signals are computed from new parameters passed in, never from a provider read inside it.
- **A chip only appears when its count is greater than zero.** The `add()` helper already enforces this; do not bypass it.
- The repo gates on `flutter analyze` only: 0 errors, 0 warnings; 192 pre-existing `info` lints — add none.
- **Do not run `dart format`.** Match the surrounding style of each file.
- Never claim a test passed or the analyzer was clean without pasting the command output.
- Widget tests use `initSupabaseStub()` from `test/support/supabase_stub.dart`.
- Baseline depends on whether Plan 3 has landed. Record the number you actually start from and do not regress it.

## What already exists — do not rebuild it

Verified against the current tree:

- `AttentionItem` (`lib/features/workforce_planning/needs_attention.dart:21`) carries `category`, `severity`, `label`, `count`, `target`.
- `AttentionTarget` (`:19`) already has `roles` and `kpiLibrary`. **Neither new chip needs a new enum value.**
- `NeedsAttentionStrip` (`tabs/needs_attention_strip.dart:118-137`) **already** wraps every chip in an `InkWell` calling `_go(context, item.target)`, except `balance` — which is deliberately inert because the strip lives on the Balance tab. `_go` (`:13-25`) maps `roles`→tab 1, `tasks`→3, `unassigned`→4, and pushes `/kpi-library` for `kpiLibrary`.

So the spec's "existing chips become click-through" is **already delivered**. This plan adds signals, not plumbing. If you find yourself editing `_go` or the `InkWell`, stop and re-read — you are probably duplicating something that works.

## File Structure

| File | Responsibility |
|---|---|
| `lib/features/workforce_planning/needs_attention.dart` (modify) | two new signals |
| `lib/features/workforce_planning/tabs/needs_attention_strip.dart` (modify) | pass the new inputs |
| `lib/data/repositories/role_scorecard_repository.dart` (modify) | roles-per-KPI count |
| `lib/features/kpi_library/kpi_library_screen.dart` (modify) | render it |

---

### Task 1: "N people with no KPI set"

**Files:**
- Modify: `lib/features/workforce_planning/needs_attention.dart`
- Modify: `lib/features/workforce_planning/tabs/needs_attention_strip.dart`
- Test: `test/features/workforce_planning/needs_attention_test.dart` (exists; add cases and extend its `_run` wrapper)

**Interfaces:**
- Consumes: `employeeNeedsKpiSet` (`lib/features/kpi_library/kpi_set_rules.dart`).
- Produces: `buildNeedsAttention` gains a named parameter `Map<String, Set<String>> assignedKpiIdsByEmployee = const {}`, defaulted so existing call sites and tests compile unchanged.

**The rule, and the trap in it.** An employee needs a KPI set when the set of their stored ids **that are on their own role** is empty. Not when their raw stored set is empty. Plan 2 hit exactly this bug in the People pane: a holder whose only tracked KPI was later removed from the role read "tracks 0 of 3" with no warning. Filter by the employee's role's KPI ids before testing, the same way `people_pane.dart` now does.

Count only ACTIVE, non-deleted employees who hold a role card. Someone with no `roleScorecardId` has no role KPIs to be measured on and must not be counted — that is a different gap, already covered by the structure chips.

- [ ] **Step 1: Write the failing test**

`test/features/workforce_planning/needs_attention_test.dart` already exists and
has its own conventions — **read it before writing**. Every case there goes
through a `_run({...})` wrapper (`:62-77`) rather than calling
`buildNeedsAttention` directly, and it defines `_card(String id, {bool active,
String? dept})`, `_kpi(String id, {bool active, String? unit, String? dept})`,
`_load` and `_t`. There is **no** employee helper; add one, copying the
`_emp(String id, String name, String? cardId)` from
`test/features/workforce_planning/role_lens_test.dart:27`, which compiles
against the current `Employee`.

First extend `_run` with the two new parameters, defaulted, and thread them
through to `buildNeedsAttention`. Then add:

```dart
  test('flags only holders whose ON-ROLE set is empty', () {
    // e1 tracks one of its role's KPIs -> fine.
    // e2 stores only an id that is NOT on its role -> reads as absent.
    // e3 stores nothing -> absent.
    // e4 holds no role card at all -> not this signal's business.
    final items = _run(
      employees: [
        _emp('e1', 'One', 'card-1'),
        _emp('e2', 'Two', 'card-1'),
        _emp('e3', 'Three', 'card-1'),
        _emp('e4', 'Four', null),
      ],
      cards: [_card('card-1')],
      roleKpiIdsByCard: const {
        'card-1': {'k1', 'k2'},
      },
      assignedKpiIdsByEmployee: const {
        'e1': {'k1'},
        'e2': {'zz'},
        'e3': <String>{},
      },
    );

    final item = items.singleWhere((i) => i.label.contains('no KPI set'));
    expect(item.count, 2);
    expect(item.target, AttentionTarget.roles);
  });

  test('says nothing when every holder has an on-role set', () {
    final items = _run(
      employees: [_emp('e1', 'One', 'card-1')],
      cards: [_card('card-1')],
      roleKpiIdsByCard: const {
        'card-1': {'k1'},
      },
      assignedKpiIdsByEmployee: const {
        'e1': {'k1'},
      },
    );
    expect(items.where((i) => i.label.contains('no KPI set')), isEmpty);
  });
```

`_emp` as copied sets `employmentStatus: 'ACTIVE'` and leaves `deletedAt` null,
which is what these cases need. If you also want a case proving a separated or
deleted holder is not counted, give `_emp` optional overrides rather than
hand-rolling a second `Employee` literal.

- [ ] **Step 2: Run it and watch it fail**

```
flutter test test/features/workforce_planning/needs_attention_test.dart
```

Expected: compile failure on the two unknown named parameters.

- [ ] **Step 3: Implement the signal**

Add both parameters to `buildNeedsAttention`, then in the People section:

```dart
  // An employee needs a set when the ids they store that are actually ON their
  // own role come to nothing. Testing the raw stored set instead is a real bug
  // we already shipped once: a holder whose only tracked KPI was later removed
  // from the role read as fully tracked.
  final noKpiSet = employees.where((e) {
    if (e.employmentStatus != 'ACTIVE' || e.deletedAt != null) return false;
    final cardId = e.roleScorecardId;
    if (cardId == null) return false;
    final onRole = (assignedKpiIdsByEmployee[e.id] ?? const <String>{})
        .intersection(roleKpiIdsByCard[cardId] ?? const <String>{});
    return employeeNeedsKpiSet(onRole);
  }).length;
  add(
    AttentionCategory.people,
    AttentionSeverity.medium,
    noKpiSet,
    '${_plural(noKpiSet, 'person has', 'people have')} no KPI set',
    AttentionTarget.roles,
  );
```

Check `_plural`'s exact shape before using it (`needs_attention.dart:43`) and match how the neighbouring signals phrase themselves; the label above is a sketch of the wording, not a spec.

- [ ] **Step 4: Feed it from the strip**

`NeedsAttentionStrip` must now supply both maps. `roleKpiIdsByCard` comes from the role→KPI links and `assignedKpiIdsByEmployee` from `employee_kpis`. Look for an existing provider before adding one — `roleKpisProvider` is per-card and `employeeAssignedKpiIdsProvider` is per-employee, so a strip-level aggregate probably needs one new repository method returning both maps in one round trip rather than N+1 queries across every employee. If you add one, say in your report why the existing per-entity providers were not usable.

Both parameters are defaulted, so the strip compiles before you wire them — but a chip that always reads zero is worse than no chip. Verify the wiring produces a real count.

- [ ] **Step 5: Run everything**

```
flutter test test/features/workforce_planning/needs_attention_test.dart
flutter test
flutter analyze lib test
```

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(wp): flag holders with no KPI set"
```

---

### Task 2: "N KPIs not yet measurable"

**Files:**
- Modify: `lib/features/workforce_planning/needs_attention.dart`
- Modify: `lib/features/workforce_planning/tabs/needs_attention_strip.dart`
- Test: `test/features/workforce_planning/needs_attention_test.dart`

**Interfaces:**
- Consumes: `isKpiDefined` (`lib/features/kpi_library/kpi_measurable.dart`), and the `Kpi` list the function already receives.
- Produces: no new parameter — `kpis` is already a parameter.

**Scope it to the library level, deliberately.** A KPI is *defined* when it has a unit, a numerator label and source, and a denominator pair if it is a RATIO. Whether it is *measurable for a role* additionally needs that role's link to carry a goal — but a chip counting link-level gaps would double-count a KPI used on four roles and would need the links passed in. Count **active library KPIs that are not defined**, and say so in the label. The per-role goal gap is visible in the workbench's KPIs pane, which already marks a goal-less link "not measurable yet".

- [ ] **Step 1: Write the failing test**

**A trap in the existing helper.** `_kpi`'s `unit:` parameter sets
`measurementUnit`, NOT the `unit` column added by `20260811000001` — and
`isKpiDefined` reads `unit`. A test written with the helper as it stands would
score every KPI "not defined" and the count would come out right for entirely
the wrong reason. Extend `_kpi` with the definition fields and give the new
column a distinct parameter name:

```dart
Kpi _kpi(
  String id, {
  bool active = true,
  String? unit, // legacy measurementUnit — NOT the definition's unit column
  String? dept,
  String valueType = 'COUNT',
  String? definitionUnit,
  String? numeratorLabel,
  String? numeratorSource,
  String? denominatorLabel,
  String? denominatorSource,
}) => Kpi(
  id: id,
  companyId: 'c',
  name: id,
  isActive: active,
  measurementUnit: unit,
  departmentId: dept,
  valueType: valueType,
  unit: definitionUnit,
  numeratorLabel: numeratorLabel,
  numeratorSource: numeratorSource,
  denominatorLabel: denominatorLabel,
  denominatorSource: denominatorSource,
);
```

Existing cases keep compiling because every new parameter is defaulted — check
that the ones asserting on the "no unit" signal still pass, since they rely on
`measurementUnit` being null and are unaffected by `definitionUnit`.

Then add:

```dart
  test('counts active library KPIs with an incomplete definition', () {
    final items = _run(
      kpis: [
        // Complete: a RATIO with both halves and a unit.
        _kpi('k1', valueType: 'RATIO', definitionUnit: '%',
            numeratorLabel: 'Returns', numeratorSource: 'BigSeller',
            denominatorLabel: 'Orders', denominatorSource: 'BigSeller'),
        // A RATIO missing its denominator.
        _kpi('k2', valueType: 'RATIO', definitionUnit: '%',
            numeratorLabel: 'Returns', numeratorSource: 'BigSeller'),
        // A legacy row with nothing but a name.
        _kpi('k3'),
        // Inactive rows are not a gap to close.
        _kpi('k4', active: false),
      ],
    );

    final item = items.singleWhere((i) => i.label.contains('measurable'));
    expect(item.count, 2);
    expect(item.target, AttentionTarget.kpiLibrary);
  });
```

Note this file's other KPI cases already assert on signals derived from the same
`kpis` list — run the whole file, not just your new case, and say in your report
whether any existing count shifted.

- [ ] **Step 2: Run it and watch it fail**

```
flutter test test/features/workforce_planning/needs_attention_test.dart
```

- [ ] **Step 3: Implement**

In the Process section:

```dart
  // Library-level only: a KPI nobody could produce a number for. The per-ROLE
  // gap (a link with no goal) is deliberately not counted here — it would
  // double-count a KPI used on four roles, and the workbench's KPIs pane
  // already marks a goal-less link "not measurable yet".
  final undefined = kpis.where((k) => k.isActive && !isKpiDefined(
    valueType: k.valueType,
    unit: k.unit,
    numeratorLabel: k.numeratorLabel,
    numeratorSource: k.numeratorSource,
    denominatorLabel: k.denominatorLabel,
    denominatorSource: k.denominatorSource,
  )).length;
```

- [ ] **Step 4: Run everything, then commit**

```
flutter test
flutter analyze lib test
```

```bash
git add -A
git commit -m "feat(wp): flag KPIs that cannot yet produce a number"
```

---

### Task 3: The KPI Library shows which roles use a KPI

**Files:**
- Modify: `lib/data/repositories/role_scorecard_repository.dart`
- Modify: `lib/features/kpi_library/kpi_library_screen.dart`
- Test: `test/features/kpi_library/kpi_library_screen_test.dart`

**Interfaces:**
- Consumes: `role_scorecard_kpis` joined to `role_scorecards`.
- Produces: `Future<Map<String, List<String>>> RoleScorecardRepository.roleTitlesByKpi()` — kpiId → the job titles linking it; and `kpiRoleTitlesProvider`.

The library already shows a people count per KPI (`assignedEmployeesByKpi` / `kpiAssignedEmployeesProvider`). The spec asks for a **roles** count beside it, and clicking a KPI listing the roles that use it. Roles and people differ: a KPI on a vacant card has roles but no people, which is exactly the state the Plan-1 cleanup treated specially.

One query, grouped in Dart — do not issue one per KPI.

- [ ] **Step 1: Write the failing test**

Add to `test/features/kpi_library/kpi_library_screen_test.dart` a case overriding the new provider with a known map and asserting the roles count renders beside the people count for a KPI. Read the file's existing overrides first and match them.

- [ ] **Step 2: Run it and watch it fail**

- [ ] **Step 3: Implement the repository method**

```dart
  /// kpiId -> the job titles of the role cards linking it. Roles and PEOPLE
  /// differ: a KPI on a card with no current holder has a role but nobody
  /// tracking it, which is precisely the state 20260811000001's cleanup
  /// deactivates rather than deletes.
  Future<Map<String, List<String>>> roleTitlesByKpi() async {
    final rows = await _client
        .from('role_scorecard_kpis')
        .select('kpi_id, role_scorecards(job_title)');
    final out = <String, List<String>>{};
    for (final r in (rows as List).cast<Map<String, dynamic>>()) {
      final title = (r['role_scorecards'] as Map?)?['job_title'] as String?;
      if (title == null) continue;
      (out[r['kpi_id'] as String] ??= []).add(title);
    }
    for (final list in out.values) {
      list.sort();
    }
    return out;
  }
```

Note the embed shape: PostgREST returns `[]` rather than null for an empty embed on a list query, so a fallback must test `is List`, not `isNotEmpty` — a lesson this repo has already paid for once.

- [ ] **Step 4: Render it**

Add the roles count beside the existing people count, and make it reveal the titles — a `Tooltip` matching how the people count already does it is the cheapest consistent option. Read that code before writing yours.

- [ ] **Step 5: Run everything, then commit**

```
flutter test
flutter analyze lib test
```

```bash
git add -A
git commit -m "feat(kpi): show which roles use each library KPI"
```

---

## Done when

- Both new chips appear only when their count is non-zero, and clicking them lands somewhere that can fix the gap.
- The KPI Library shows roles alongside people per KPI.
- `flutter test` green; `flutter analyze lib test` 0 errors, 0 warnings.
- No migration was added and none is needed.

## After this plan

Spec A is complete. The three outstanding migrations still need applying together, and the remaining deferred items are recorded in the plan-2 ledger. Spec B — KPI logging via Lark forms, peer voting, and the Employee-of-the-Month score — is the next brainstorm, not a plan.
