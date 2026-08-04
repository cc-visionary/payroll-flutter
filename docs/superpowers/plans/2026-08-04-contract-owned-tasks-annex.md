# Contract Annex A — Personally-Owned Tasks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Employee-mode employment contracts append the employee's personally-owned, off-card, ACTIVE `wp_tasks` to Annex A as trailing responsibility areas.

**Architecture:** Reuse `responsibilitiesFromAssignedTasks` (gains an optional `fallbackArea` label) to convert the owned-task fetch into trailing areas; a new pure `dedupeAppendedAreas` drops name collisions against the already-assembled list; `RoleScorecardRepository.activeTasksOwnedBy` is the one thin fetch; the employment contract's employee-mode autofill wires it together best-effort. Card-authored output stays byte-identical (existing "Risk #2" invariant).

**Tech Stack:** Flutter/Dart, Supabase (PostgREST), Riverpod. Spec: `docs/superpowers/specs/2026-08-04-contract-owned-tasks-annex-design.md`.

## Global Constraints

- Gate on `flutter analyze` (repo root). Do NOT run `dart format` — match each file's surrounding style.
- Card-authored responsibilities must be untouched: the existing Annex A gate in `test/data/models/role_scorecard_responsibilities_test.dart` must pass unchanged.
- `fallbackArea` default is `'Shared'` — existing call sites and tests must behave identically.
- The owned-task append label is exactly `'Additional Responsibilities'`.
- Applicant-mode contracts, `_onPickerCompanyChanged`, the role-card PDF, and saved documents are untouched.
- Contract generation must never break on a workforce-planning read: the fetch is try/catch → empty list.
- Run tests with `flutter test <path>` from `/home/ccvisionary/Documents/Work/[07] Projects/payroll-flutter`.

---

### Task 1: Model functions — `fallbackArea` param + `dedupeAppendedAreas`

**Files:**
- Modify: `lib/data/models/role_scorecard.dart` (function `responsibilitiesFromAssignedTasks`, ~line 83; add `dedupeAppendedAreas` after it)
- Test: `test/data/models/role_scorecard_responsibilities_test.dart` (extend — existing `WpTask` fixtures in this file show the construction pattern)

**Interfaces:**
- Consumes: existing `ResponsibilityArea({required String area, required List<String> tasks})` (const), `WpTask` (const, only `id`/`companyId`/`name` required).
- Produces:
  - `responsibilitiesFromAssignedTasks(String cardId, List<WpTask> assignedToCard, {String fallbackArea = 'Shared'})`
  - `List<ResponsibilityArea> dedupeAppendedAreas(List<ResponsibilityArea> existing, List<ResponsibilityArea> appended)`

- [ ] **Step 1: Write the failing tests**

Add to `test/data/models/role_scorecard_responsibilities_test.dart` (inside `main()`, as a new top-level `group`):

```dart
  group('owned-task append primitives', () {
    test('fallbackArea labels area-less tasks; default stays Shared', () {
      const noArea = WpTask(
        id: 't-x',
        companyId: 'c1',
        name: 'Ad-hoc vendor audit',
        roleScorecardId: 'card-2',
        areaSort: 5,
        taskSort: 1,
      );
      expect(
        responsibilitiesFromAssignedTasks('card-1', [noArea]).single.area,
        'Shared',
      );
      expect(
        responsibilitiesFromAssignedTasks(
          'card-1',
          [noArea],
          fallbackArea: 'Additional Responsibilities',
        ).single.area,
        'Additional Responsibilities',
      );
    });

    group('dedupeAppendedAreas', () {
      const existing = [
        ResponsibilityArea(
            area: 'Ops', tasks: ['Pack orders', 'Book couriers']),
      ];

      test('drops case-insensitive/whitespace name collisions, prunes empty areas',
          () {
        final out = dedupeAppendedAreas(existing, const [
          ResponsibilityArea(area: 'Logistics', tasks: ['  pack orders ']),
        ]);
        expect(out, isEmpty);
      });

      test('keeps non-colliding tasks in order, dedupes within appended', () {
        final out = dedupeAppendedAreas(existing, const [
          ResponsibilityArea(
              area: 'Finance', tasks: ['Reconcile Xendit', 'Book couriers']),
          ResponsibilityArea(area: 'Extra', tasks: ['Reconcile Xendit']),
        ]);
        expect(out.length, 1);
        expect(out.single.area, 'Finance');
        expect(out.single.tasks, ['Reconcile Xendit']);
      });

      test('empty appended → empty; empty existing keeps appended verbatim', () {
        expect(dedupeAppendedAreas(existing, const []), isEmpty);
        const appended = [
          ResponsibilityArea(area: 'A', tasks: ['One', 'Two']),
        ];
        expect(dedupeAppendedAreas(const [], appended), appended);
      });
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/data/models/role_scorecard_responsibilities_test.dart`
Expected: FAIL — compile errors: named parameter `fallbackArea` not defined; `dedupeAppendedAreas` undefined.

- [ ] **Step 3: Implement**

In `lib/data/models/role_scorecard.dart`:

1. Change the signature of `responsibilitiesFromAssignedTasks` (keep the body identical except the bucket line):

```dart
List<ResponsibilityArea> responsibilitiesFromAssignedTasks(
  String cardId,
  List<WpTask> assignedToCard, {
  String fallbackArea = 'Shared',
}) {
```

and replace the line `final area = rawArea.isEmpty ? 'Shared' : rawArea;` with:

```dart
    final area = rawArea.isEmpty ? fallbackArea : rawArea;
```

Also update the doc comment's last line (`A task with no `responsibility_area` lands in a "Shared" bucket.`) to:

```dart
/// A task with no `responsibility_area` lands in the [fallbackArea] bucket
/// ("Shared" by default; the contract's owned-task append passes
/// "Additional Responsibilities").
```

2. Add directly after that function:

```dart
/// Drops from [appended] any task whose trimmed, case-insensitive name
/// already appears in [existing] or earlier in [appended]; prunes areas
/// left empty. Order is otherwise preserved. The employment contract's
/// Annex A uses this so a task that is both shared to the card and
/// personally owned by the employee doesn't render twice.
List<ResponsibilityArea> dedupeAppendedAreas(
  List<ResponsibilityArea> existing,
  List<ResponsibilityArea> appended,
) {
  final seen = <String>{
    for (final a in existing)
      for (final t in a.tasks) t.trim().toLowerCase(),
  };
  final out = <ResponsibilityArea>[];
  for (final a in appended) {
    final kept = <String>[];
    for (final t in a.tasks) {
      final key = t.trim().toLowerCase();
      if (key.isEmpty || !seen.add(key)) continue;
      kept.add(t);
    }
    if (kept.isNotEmpty) {
      out.add(ResponsibilityArea(area: a.area, tasks: kept));
    }
  }
  return out;
}
```

Note the "empty existing keeps appended verbatim" test compares with `equals(appended)` semantics — returning newly-built `ResponsibilityArea` objects fails `expect(..., appended)` unless `ResponsibilityArea` implements `==`. It does NOT, so make the function return the original area object when nothing was dropped from it:

```dart
    if (kept.length == a.tasks.length) {
      out.add(a); // untouched — preserve identity for callers and tests
    } else if (kept.isNotEmpty) {
      out.add(ResponsibilityArea(area: a.area, tasks: kept));
    }
```

(Use this variant in the final implementation, replacing the simpler `if (kept.isNotEmpty)` block above. The dedupe-within-appended test still passes because its second area loses its only task.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/data/models/role_scorecard_responsibilities_test.dart`
Expected: PASS — the new group AND every pre-existing test (the Annex A gate) unchanged.

- [ ] **Step 5: Commit**

```bash
git add lib/data/models/role_scorecard.dart test/data/models/role_scorecard_responsibilities_test.dart
git commit -m "feat(scorecards): fallbackArea label + dedupeAppendedAreas for Annex A appends"
```

---

### Task 2: Repository fetch — `activeTasksOwnedBy`

**Files:**
- Modify: `lib/data/repositories/role_scorecard_repository.dart` (add after `assignedTasksByCard`, ~line 445)

**Interfaces:**
- Consumes: `WpTask.fromRow` (already used in this file by `assignedTasksByCard`).
- Produces: `Future<List<WpTask>> RoleScorecardRepository.activeTasksOwnedBy(String employeeId)` — Task 3 calls it via `roleScorecardRepositoryProvider` (defined in this file at ~line 489).

No unit test — thin Supabase select, no local Supabase for this repo (ports 54321/54322 belong to other projects). Verification is `flutter analyze`; behavior is covered by the Task 3 GUI smoke.

- [ ] **Step 1: Implement**

```dart
  /// ACTIVE tasks personally owned by [employeeId], for the employment
  /// contract's Annex A append (spec:
  /// 2026-08-04-contract-owned-tasks-annex-design.md). Archived work is
  /// excluded here; authored-on-own-card filtering happens in
  /// responsibilitiesFromAssignedTasks. Task counts per person are small
  /// (tens), so no paging.
  Future<List<WpTask>> activeTasksOwnedBy(String employeeId) async {
    final rows = (await _client
            .from('wp_tasks')
            .select()
            .eq('owner_employee_id', employeeId)
            .eq('status', 'ACTIVE'))
        .cast<Map<String, dynamic>>();
    return rows.map(WpTask.fromRow).toList();
  }
```

- [ ] **Step 2: Verify**

Run: `flutter analyze`
Expected: no new issues (pre-existing repo baseline only).

- [ ] **Step 3: Commit**

```bash
git add lib/data/repositories/role_scorecard_repository.dart
git commit -m "feat(scorecards): activeTasksOwnedBy fetch for contract Annex A"
```

---

### Task 3: Contract autofill wiring (employee mode)

**Files:**
- Modify: `lib/features/documents/templates/employment_contract_template.dart` (employee-mode autofill: owned-task fetch after the scorecard block at ~line 631-640; responsibilities mapping at ~line 715-720; imports at top)

**Interfaces:**
- Consumes: `responsibilitiesFromAssignedTasks(cardId, tasks, fallbackArea:)` and `dedupeAppendedAreas(existing, appended)` (Task 1, exported by the already-imported `role_scorecard.dart`); `activeTasksOwnedBy` via `roleScorecardRepositoryProvider` (Task 2).
- Produces: no new interfaces — behavior only. Applicant path untouched.

- [ ] **Step 1: Add the import**

The template imports `role_scorecard.dart` but NOT the repository. Add with the other `../../../data/repositories/` imports:

```dart
import '../../../data/repositories/role_scorecard_repository.dart';
```

- [ ] **Step 2: Fetch + convert owned tasks (employee mode only)**

In the EMPLOYEE MODE section, directly after the `RoleScorecard? scorecard;` try/catch block (the one reading `roleScorecardByIdProvider(scorecardId)`, ~line 631-640), add:

```dart
    // Personally-owned, off-card ACTIVE tasks append to Annex A as trailing
    // areas (spec: 2026-08-04-contract-owned-tasks-annex-design.md).
    // Best-effort like the scorecard read above — contract generation never
    // breaks on a workforce-planning read.
    List<ResponsibilityArea> ownedExtra = const [];
    try {
      final owned = await ctx.ref
          .read(roleScorecardRepositoryProvider)
          .activeTasksOwnedBy(emp.id);
      ownedExtra = responsibilitiesFromAssignedTasks(
        scorecardId ?? '',
        owned,
        fallbackArea: 'Additional Responsibilities',
      );
    } catch (_) {
      ownedExtra = const [];
    }
```

(`scorecardId` is the existing local from the scorecard block; `?? ''` covers the no-card employee — nothing is treated as authored, so every owned task appends.)

- [ ] **Step 3: Append in the responsibilities mapping**

Replace the employee-mode inputs construction's responsibilities argument (~line 715):

```dart
      responsibilities: scorecard == null
          ? const []
          : scorecard.responsibilities
              .map((r) =>
                  ContractResponsibility(area: r.area, tasks: r.tasks))
              .toList(),
```

with:

```dart
      responsibilities: [
        ...?scorecard?.responsibilities,
        ...dedupeAppendedAreas(
            scorecard?.responsibilities ?? const [], ownedExtra),
      ]
          .map((r) => ContractResponsibility(area: r.area, tasks: r.tasks))
          .toList(),
```

Do NOT touch the applicant-mode construction (~line 603) — it has no employee and stays card-only.

- [ ] **Step 4: Verify**

Run: `flutter test test/data/models/role_scorecard_responsibilities_test.dart test/features/documents/ && flutter analyze`
Expected: all PASS (documents suite exercises contract build/fromJson paths; the autofill DB path itself is covered by GUI smoke), analyze at baseline.

- [ ] **Step 5: Run the full suite once**

Run: `flutter test`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/features/documents/templates/employment_contract_template.dart
git commit -m "feat(documents): contract Annex A appends employee's owned off-card tasks"
```

---

### GUI smoke (post-merge, manual — combined with the pending signatories smoke)

1. Pick an employee who owns an ACTIVE `wp_task` not on their role card (Workforce Planning → Tasks tab shows owners); generate an Employment Contract → Annex A shows the task under its area (or "Additional Responsibilities") AFTER the card's duties.
2. Generate a contract for an employee with no off-card owned tasks → Annex A identical to before this feature.
3. Applicant-mode offer letter → unchanged.
