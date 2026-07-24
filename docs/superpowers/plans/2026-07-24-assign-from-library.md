# Assign From Library + Duplicate Warning (step 6) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop duplicate responsibilities at the source — warn when a newly-typed responsibility looks like one that already exists, let the author pick from **every** existing accountability (not just unlinked ones), and make picking one that already lives on another card **share** it (an assignment) instead of stealing it.

**Architecture:** Three independently-shippable slices, in dependency order. **Slice A** (Task 1) is a pure fuzzy-match + an inline warning in the card editor — zero blast radius, ships alone, and directly kills the "I retyped work that already existed" problem. **Slice B+C** (Tasks 2–4) is the shared-accountability payoff: the picker offers every ACTIVE accountability annotated with its home card; picking one already on another card inserts a CONTRIBUTOR `wp_task_assignments` row for this card rather than repointing `role_scorecard_id`; and a card's responsibility list becomes **authored ∪ assigned** so the shared row is actually visible. That read change reaches the role-card PDF and employment-contract Annex A, so Task 4 pins Annex A with a before/after regression test — the spec's own Risk #2.

**Tech Stack:** Flutter (Material 3, Riverpod), Supabase (PostgREST), `flutter_test`.

## Global Constraints

- Repo gates on `flutter analyze` only (0 errors). Do NOT run `dart format`; match surrounding style.
- NO migration — `wp_task_assignments` already exists (step 4) and already drives load (steps 4/5a/5b).
- **Annex A / role-card order is load-bearing** (spec Risk #2): sharing must NOT reorder or reword a card's *authored* responsibilities. Authored rows keep their `area_sort`/`task_sort` ordering and render first; assigned-but-not-authored rows are additive. Task 4's regression test is the gate.
- Reuse, don't re-derive: `nameSimilarity`/`normalizeName` from `lib/features/workforce_planning/text_similarity.dart` (built in step 3a exactly for this).
- Assigning an existing accountability to a second card creates a **CONTRIBUTOR** assignment (`allocation_pct: 0` — the manager sets the split in the step-5b panel). Never a second PRIMARY (the partial unique index forbids it).
- Each slice must leave the system coherent if the next is not built.

---

## File Structure

- `lib/features/workforce_planning/duplicate_check.dart` — **create.** Pure `findSimilarAccountabilities(...)`.
- `lib/features/responsibility_cards/role_scorecard_form_screen.dart` — **modify.** Inline duplicate warning (Task 1); picker over all accountabilities + share-don't-steal (Task 3).
- `lib/data/repositories/role_scorecard_repository.dart` — **modify.** Read a card's assigned accountabilities (Task 2); union them into the card's responsibilities (Task 4).
- Tests: `test/features/workforce_planning/duplicate_check_test.dart` (create); extend the role-card/Annex A tests (Task 4).

---

### Task 1 [Slice A — ships alone]: Duplicate warning when typing a new responsibility

**Files:** Create `lib/features/workforce_planning/duplicate_check.dart` + `test/features/workforce_planning/duplicate_check_test.dart`; modify `role_scorecard_form_screen.dart`.

**Interfaces:**
- `class SimilarMatch { final WpTask task; final double score; }`
- `List<SimilarMatch> findSimilarAccountabilities({required String typed, required List<WpTask> all, String? excludeId, double threshold = 0.6, int limit = 3})` — ACTIVE, non-expectation tasks whose `nameSimilarity(typed, t.name) >= threshold`, best score first, capped at `limit`. Returns empty for a blank/short `typed` (< 3 normalized chars).

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/workforce_planning/duplicate_check_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/duplicate_check.dart';

WpTask _t(String id, String name, {String status = 'ACTIVE', bool exp = false}) =>
    WpTask(id: id, companyId: 'c', name: name, status: status, isExpectation: exp);

void main() {
  final all = [
    _t('1', 'Pack, label, check and dispatch online orders'),
    _t('2', 'Reconcile bank statements'),
    _t('3', 'Old packing flow', status: 'ARCHIVED'),
    _t('4', 'Participate in training', exp: true),
  ];

  test('finds a near-duplicate above the threshold, best first', () {
    final m = findSimilarAccountabilities(typed: 'Pack and dispatch orders', all: all);
    expect(m, isNotEmpty);
    expect(m.first.task.id, '1');
  });

  test('ignores archived and expectation rows', () {
    expect(findSimilarAccountabilities(typed: 'Old packing flow', all: all)
        .any((m) => m.task.id == '3'), isFalse);
    expect(findSimilarAccountabilities(typed: 'Participate in training', all: all)
        .any((m) => m.task.id == '4'), isFalse);
  });

  test('returns nothing for unrelated or too-short input', () {
    expect(findSimilarAccountabilities(typed: 'Design social ads', all: all), isEmpty);
    expect(findSimilarAccountabilities(typed: 'ab', all: all), isEmpty);
    expect(findSimilarAccountabilities(typed: '   ', all: all), isEmpty);
  });

  test('excludeId keeps a row from matching itself', () {
    final m = findSimilarAccountabilities(
        typed: 'Reconcile bank statements', all: all, excludeId: '2');
    expect(m.any((x) => x.task.id == '2'), isFalse);
  });

  test('respects the limit', () {
    final many = [for (var i = 0; i < 10; i++) _t('$i', 'Pack orders daily $i')];
    expect(findSimilarAccountabilities(typed: 'Pack orders daily', all: many, limit: 3).length, 3);
  });
}
```

- [ ] **Step 2: Run to verify it fails** — file missing.

- [ ] **Step 3: Implement**

```dart
// lib/features/workforce_planning/duplicate_check.dart
import '../../data/models/workforce_planning.dart';
import 'text_similarity.dart';

/// An existing accountability that looks like what the author is typing.
class SimilarMatch {
  final WpTask task;
  final double score;
  const SimilarMatch({required this.task, required this.score});
}

/// Existing ACTIVE accountabilities whose name is close to [typed], best match
/// first. Used to stop a manager retyping work the business already tracks —
/// the duplicate that would then double-count its hours.
List<SimilarMatch> findSimilarAccountabilities({
  required String typed,
  required List<WpTask> all,
  String? excludeId,
  double threshold = 0.6,
  int limit = 3,
}) {
  if (normalizeName(typed).length < 3) return const [];
  final out = <SimilarMatch>[];
  for (final t in all) {
    if (t.id == excludeId) continue;
    if (t.status != 'ACTIVE') continue;
    if (t.isExpectation) continue;
    final s = nameSimilarity(typed, t.name);
    if (s >= threshold) out.add(SimilarMatch(task: t, score: s));
  }
  out.sort((a, b) => b.score.compareTo(a.score));
  return out.length <= limit ? out : out.sublist(0, limit);
}
```

- [ ] **Step 4: Run to verify it passes** — 5 tests.

- [ ] **Step 5: Surface it in the card editor**

In `role_scorecard_form_screen.dart`, the responsibility name fields are `RespDraft` rows inside `_AreaDraft`s (a new one is added at ~:689 as `RespDraft(id: null, name: '')`). For a row whose `id == null` (a genuinely NEW responsibility — an existing linked row must not nag), after its name `TextField`'s `onChanged`, compute `findSimilarAccountabilities(typed: value, all: <all wp_tasks>, limit: 1)` and, when non-empty, render an inline warning directly beneath that field:

> `Looks like "<match name>" (<its card's job title, or “no card”>) — assign that instead of creating a duplicate?`

styled with `StatusTone.warning` (via `StatusChip` or a warning-coloured `Text` with `Icons.warning_amber_rounded`, matching the file's existing warning treatments), plus a `TextButton('Use that one')` that replaces the draft with the matched task (same effect as picking it in "Link existing task": `RespDraft(id: match.task.id, name: match.task.name)`). Read all tasks from `ref.watch(wpTasksProvider).asData?.value ?? const <WpTask>[]` (the screen is already a `ConsumerStatefulWidget`; import `wp_providers.dart` if needed) and resolve the match's card title from the already-loaded scorecard list. **The warning must never block saving** — it is advisory.

- [ ] **Step 6: Verify + commit**

Run: `flutter test test/features/workforce_planning/duplicate_check_test.dart` → PASS.
Run: `flutter analyze lib/features/responsibility_cards/ lib/features/workforce_planning/` → 0 errors.
Run: `flutter test` → no regressions (the card-editor tests must still pass).

```bash
git add lib/features/workforce_planning/duplicate_check.dart lib/features/responsibility_cards/role_scorecard_form_screen.dart test/features/workforce_planning/duplicate_check_test.dart
git commit -m "feat(workforce): warn when a new responsibility duplicates an existing one"
```

---

### Task 2 [Slice B]: Read a card's ASSIGNED accountabilities

**Files:** Modify `lib/data/repositories/role_scorecard_repository.dart`

**Interfaces:** `Future<Map<String, List<WpTask>>> assignedTasksByCard()` — for every `wp_task_assignments` row with a `role_scorecard_id`, the ACTIVE `wp_tasks` it points at, grouped by card id. (One paged query joining through the assignment table.)

- [ ] **Step 1: Implement**

```dart
  /// Accountabilities reaching a card through an ASSIGNMENT (the shared ones),
  /// as opposed to those authored on it via wp_tasks.role_scorecard_id.
  /// Keyed by role_scorecard_id.
  Future<Map<String, List<WpTask>>> assignedTasksByCard() async {
    final rows = (await _client
            .from('wp_task_assignments')
            .select('role_scorecard_id, wp_tasks(*)')
            .not('role_scorecard_id', 'is', null))
        .cast<Map<String, dynamic>>();
    final out = <String, List<WpTask>>{};
    for (final r in rows) {
      final cardId = r['role_scorecard_id'] as String?;
      final t = r['wp_tasks'];
      if (cardId == null || t is! Map) continue;
      final task = WpTask.fromRow(t.cast<String, dynamic>());
      if (task.status != 'ACTIVE') continue;
      (out[cardId] ??= []).add(task);
    }
    return out;
  }
```
(PostgREST returns `[]` for an empty embed and a Map for a to-one embed — test with `is! Map`, per this repo's noted convention. Import `WpTask` if not already.)

- [ ] **Step 2: Verify it compiles** — `flutter analyze` on the file → 0 errors.

- [ ] **Step 3: Commit**

```bash
git add lib/data/repositories/role_scorecard_repository.dart
git commit -m "feat(workforce): read a card's assigned (shared) accountabilities"
```

---

### Task 3 [Slice B]: Picker over EVERY accountability — share instead of steal

**Files:** Modify `lib/features/responsibility_cards/role_scorecard_form_screen.dart` (`_linkExistingTask`, ~:181-207) + `lib/data/repositories/workforce_planning_repository.dart` if a helper is needed.

Today the picker pool is `roleScorecardId == null && status == 'ACTIVE'` (unlinked orphans only) and picking one repoints `role_scorecard_id` on save — i.e. it STEALS the row from wherever it was.

- [ ] **Step 1: Broaden the pool and annotate it**

Offer **every ACTIVE, non-expectation** accountability not already drafted on this card, each labelled with its home card's job title (or "unassigned") so the author can see they are sharing someone else's work. Sort unlinked ones first, then by name. Keep the existing "no candidates" snackbar path.

- [ ] **Step 2: Share, don't steal**

When the picked task has **no** `roleScorecardId` (a true orphan) → keep today's behavior (add a `RespDraft(id: picked.id, ...)`, so `saveResponsibilities` adopts it onto this card).

When the picked task **already belongs to another card** → do NOT add it as a draft (that would repoint `role_scorecard_id` and steal it). Instead insert a CONTRIBUTOR assignment for THIS card and refresh:

```dart
      await ref.read(workforcePlanningRepositoryProvider).upsertAssignment(
            WpTaskAssignment(
              id: '', companyId: widget.companyId, taskId: picked.id,
              roleScorecardId: <this card's id>,
              assignmentRole: 'CONTRIBUTOR', allocationPct: 0,
            ),
          );
      ref.invalidate(wpTaskAssignmentsProvider);
```
then show a snackbar: `Shared "<name>" from <other card> — set its split in the responsibility's Assignment panel.` (allocation starts at 0 so it cannot silently change anyone's load until the manager sets it.)

**Note:** this requires the card to already exist (it has an id). On a brand-new unsaved card, fall back to the orphan-only behavior and tell the user to save the card first.

- [ ] **Step 3: Verify + commit**

`flutter analyze` → 0 errors; `flutter test` → no regressions.
```bash
git commit -am "feat(workforce): assign from the whole library — share instead of steal"
```

---

### Task 4 [Slice C]: A card's responsibilities = authored ∪ assigned — with the Annex A gate

**Files:** Modify `lib/data/repositories/role_scorecard_repository.dart`; extend the role-card / Annex A tests.

**This is the Risk #2 task.** A card's responsibility list must gain the shared rows WITHOUT reordering or rewording the authored ones.

- [ ] **Step 1: Write the Annex A regression test FIRST**

Find the existing role-card responsibility/PDF/contract tests (search `test/` for `responsibilitiesFromTaskRows`, `role_card_pdf`, and the employment-contract Annex A prefill). Add a test that pins the ORDER and WORDING of a card's authored responsibilities (by `area_sort`/`task_sort`) and asserts they are byte-identical before and after an assigned-but-not-authored accountability is added — i.e. the shared row appends, never interleaves or renames.

- [ ] **Step 2: Union the two sources**

In `list()`/`byId()`, after building the authored responsibilities from the `wp_tasks` embed, append the card's assigned tasks (from Task 2's `assignedTasksByCard()`) that are not already present by id. Authored rows keep their existing `area_sort`/`task_sort` ordering and come FIRST; assigned-only rows follow, grouped under their own area (use the task's `responsibility_area`, or a "Shared" bucket when it has none).

- [ ] **Step 3: Run the gate**

`flutter test` — the new Annex A test AND every pre-existing role-card/PDF/contract test must pass. If a pre-existing assertion would need changing, STOP and report: that means sharing altered a card's authored output, which Risk #2 forbids.

- [ ] **Step 4: Commit**

```bash
git commit -am "feat(workforce): card responsibilities include shared accountabilities (Annex A pinned)"
```

---

### Task 5: Full-suite + analyze gate

- [ ] `flutter test` — all pass (prior 1061 + new; 1 pre-existing skip). STOP and report on any pre-existing failure.
- [ ] `flutter analyze` — 0 errors.

---

## Self-Review

**Spec coverage** (§"Authoring a role: assign, don't retype"):
- Searchable picker over EVERY existing accountability, not just the unlinked pool → Task 3. ✓
- Fuzzy-match warning "Looks like 'Packing' (Sales & Ops) — assign that instead of creating a duplicate?" → Task 1. ✓
- "Create new" stays available, one tap → unchanged (the warning is advisory and never blocks). ✓
- Assigning a card to an accountability = inserting a `wp_task_assignments` row → Task 3. ✓
- Card's responsibility list = assigned ∪ authored → Task 4. ✓
- Risk #2 (Annex A must not reorder/reword) → Task 4's regression gate. ✓

**Ordering rationale:** Task 1 is standalone and ships the anti-duplicate value immediately. Tasks 3 and 4 are a pair — Task 3 without Task 4 would let a manager share an accountability that then does not appear on the card, so if only part of this plan lands, stop after Task 1 or after Task 4, never between 3 and 4.

**Placeholder scan:** Task 1 has complete code; Tasks 2–4 give exact queries, the share-don't-steal rule, and the gate, and point at the concrete call sites — consistent with how earlier UI tasks in this project were specified.

**Type consistency:** `findSimilarAccountabilities`/`SimilarMatch` match between Task 1's definition and its use. `assignedTasksByCard() -> Map<String, List<WpTask>>` matches between Tasks 2 and 4. `upsertAssignment(WpTaskAssignment)` matches the step-5b repository.

**Deferred:** step 7 (Lark workload confirmation) — the spec itself says it needs its own spec once 1–6 land, and it is employee-facing (edge functions + message templates + a sent/answered status column).
