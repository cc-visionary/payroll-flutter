# Dart Split Honors Assignments (step 5a) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Switch the Dart load split (`rebalance.dart`, which drives the Balance tab's draft-move preview) to attribute a task's hours via `wp_task_assignments` + `allocation_pct` — matching the `wp_person_load` view — while producing byte-identical numbers on today's backfilled data, and surfacing hours that reach nobody (Σ% < 100 or a vacant-card share).

**Architecture:** One pure helper, `attributeTask`, computes a single task's per-employee shares (+ unattributed leftover) from its assignments (person → its %, card → its % split across active holders), a draft-move override (100% to the moved person), or — when the task has no assignments — an owner/card **fallback** identical to today's logic. Every split function (`hoursByEmployee`, `plannedTasksFor`, `buildProjections`'s tally, `unattributedHours`, `orphanHours`) routes through it. Because the existing `rebalance_test.dart` fixtures carry owner/card and no assignments, they exercise the fallback and stay green untouched; new tests pass assignments to verify %-attribution. In production, step-4's backfill+sync guarantees every owned/carded task has one PRIMARY @100, so the assignment path reproduces today's numbers exactly. This is step 5a — the engine alignment; step 5b (the % editor UI) is what makes allocations actually vary.

**Tech Stack:** Flutter/Dart (Riverpod), `flutter_test`. No Supabase changes (the table/view/backfill landed in step 4).

## Global Constraints

- Repo gates on `flutter analyze` only (0 errors). Do NOT run `dart format`; match surrounding style.
- NO migration, NO prod. Pure Dart over existing providers.
- **Invariant: on data with no assignments (the existing test fixtures), every split function must produce EXACTLY today's output.** The existing `rebalance_test.dart` must pass UNCHANGED — if any of its assertions need editing, something diverged; STOP.
- The assignment attribution rule (must match `wp_person_load` from step 4, migration `20260724000002`): a task's hours are distributed across ITS assignments; a person assignment gives that employee `hours * allocation_pct/100`; a card assignment splits `hours * allocation_pct/100` evenly across the card's ACTIVE, non-deleted holders (`_activeHolders`); the leftover (`hours − Σ reached`) is unattributed. A draft move (`moves[taskId]`) overrides everything: 100% to the moved person (preserves today's move semantics).
- "active holder" predicate stays exactly `employmentStatus == 'ACTIVE' && deletedAt == null && roleScorecardId == cardId` (`_activeHolders`, unchanged).
- Only in-scope files change (below). `rebalance.dart` is the highest-traffic file — do not restructure beyond routing the split through `attributeTask`.

---

## File Structure

- `lib/features/workforce_planning/rebalance.dart` — **modify.** Add `TaskShare` typedef + `attributeTask`; route the five split functions through it (each gains an `assignmentsByTask` param defaulting to `{}`).
- `lib/features/workforce_planning/wp_providers.dart` — **modify.** Add `wpTaskAssignmentsProvider` + `wpAssignmentsByTaskProvider` (grouped `Map<String, List<WpTaskAssignment>>`).
- `lib/features/workforce_planning/tabs/balance_tab.dart` — **modify.** Watch the assignments provider; thread `assignmentsByTask` into `buildProjections` / `plannedTasksFor` / `orphanHours` / `unattributedHours`.
- Test: `test/features/workforce_planning/attribute_task_test.dart` (create); extend `test/features/workforce_planning/rebalance_test.dart`.

---

### Task 1: `attributeTask` — the single attribution helper

**Files:**
- Modify: `lib/features/workforce_planning/rebalance.dart` (add near `_hoursOf`, ~line 96)
- Test: `test/features/workforce_planning/attribute_task_test.dart` (create)

**Interfaces:**
- Produces:
  - `typedef TaskShare = ({String employeeId, double hours, bool derived, int holderCount});`
  - `({List<TaskShare> shares, double unattributed}) attributeTask({required double hours, required WpTask task, required List<WpTaskAssignment> assignments, required List<Employee> Function(String cardId) holdersOf, String? moveOverride})`

**Rules (exactly):**
- `hours <= 0` → `(shares: [], unattributed: 0)`.
- `moveOverride != null` → `(shares: [(employeeId: moveOverride, hours: hours, derived: false, holderCount: 1)], unattributed: 0)`.
- `assignments` non-empty → for each assignment: `share = hours * allocationPct/100`; if `employeeId != null` add `(employeeId, share, derived: false, holderCount: 1)`; else if `roleScorecardId != null` let `hs = holdersOf(roleScorecardId)` — if empty, this share reaches nobody (contributes to unattributed); else add `(h.id, share/hs.length, derived: true, holderCount: hs.length)` for each holder. **`unattributed = hours − (sum of all shares' hours)`** (captures both Σ%<100 gaps and vacant-card shares in one subtraction).
- `assignments` empty (fallback, identical to today): `owner = task.ownerEmployeeId` → `[(owner, hours, false, 1)]`, unattributed 0; else `card = task.roleScorecardId` → holders empty → `(shares: [], unattributed: hours)`, else split `[(h, hours/n, true, n)]`, unattributed 0; else (no owner, no card) → `(shares: [], unattributed: hours)`.

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/workforce_planning/attribute_task_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/rebalance.dart';

Employee _e(String id, {String? card}) => Employee(
      id: id, companyId: 'c', employeeNumber: id, firstName: id, lastName: 'x',
      employmentType: 'REGULAR', employmentStatus: 'ACTIVE', hireDate: DateTime(2026),
      isRankAndFile: true, isOtEligible: false, isNdEligible: false,
      isHolidayPayEligible: false, taxOnFullEarnings: false, roleScorecardId: card);

const _task = WpTask(id: 't', companyId: 'c', name: 't');

WpTaskAssignment _pa(String emp, double pct, {String role = 'PRIMARY'}) => WpTaskAssignment(
    id: 'a', companyId: 'c', taskId: 't', employeeId: emp, assignmentRole: role, allocationPct: pct);
WpTaskAssignment _ca(String card, double pct, {String role = 'PRIMARY'}) => WpTaskAssignment(
    id: 'a', companyId: 'c', taskId: 't', roleScorecardId: card, assignmentRole: role, allocationPct: pct);

List<Employee> Function(String) _holders(List<Employee> emps) =>
    (cardId) => [for (final e in emps) if (e.roleScorecardId == cardId) e];

void main() {
  test('move override gives 100% to the moved person', () {
    final r = attributeTask(hours: 40, task: _task, assignments: const [],
        holdersOf: _holders(const []), moveOverride: 'x');
    expect(r.shares, [(employeeId: 'x', hours: 40.0, derived: false, holderCount: 1)]);
    expect(r.unattributed, 0);
  });

  test('two person assignments split by pct; Σ100 leaves nothing unattributed', () {
    final r = attributeTask(hours: 100, task: _task,
        assignments: [_pa('a', 60), _pa('b', 40, role: 'CONTRIBUTOR')],
        holdersOf: _holders(const []));
    expect(r.shares.firstWhere((s) => s.employeeId == 'a').hours, 60);
    expect(r.shares.firstWhere((s) => s.employeeId == 'b').hours, 40);
    expect(r.unattributed, 0);
  });

  test('card assignment splits its pct across active holders (derived)', () {
    final r = attributeTask(hours: 100, task: _task, assignments: [_ca('rs1', 60)],
        holdersOf: _holders([_e('h1', card: 'rs1'), _e('h2', card: 'rs1')]));
    // 60% = 60h across 2 holders = 30 each; 40% unallocated -> unattributed
    expect(r.shares.every((s) => s.hours == 30 && s.derived && s.holderCount == 2), isTrue);
    expect(r.unattributed, 40);
  });

  test('vacant card share is unattributed, not lost', () {
    final r = attributeTask(hours: 100, task: _task, assignments: [_ca('empty', 100)],
        holdersOf: _holders(const []));
    expect(r.shares, isEmpty);
    expect(r.unattributed, 100);
  });

  test('fallback: no assignments + owner -> owner full', () {
    const owned = WpTask(id: 't', companyId: 'c', name: 't', ownerEmployeeId: 'o');
    final r = attributeTask(hours: 40, task: owned, assignments: const [], holdersOf: _holders(const []));
    expect(r.shares, [(employeeId: 'o', hours: 40.0, derived: false, holderCount: 1)]);
    expect(r.unattributed, 0);
  });

  test('fallback: no assignments + card -> split across holders', () {
    const carded = WpTask(id: 't', companyId: 'c', name: 't', roleScorecardId: 'rs1');
    final r = attributeTask(hours: 40, task: carded, assignments: const [],
        holdersOf: _holders([_e('h1', card: 'rs1'), _e('h2', card: 'rs1')]));
    expect(r.shares.length, 2);
    expect(r.shares.every((s) => s.hours == 20 && s.derived), isTrue);
  });

  test('fallback: no assignments, no owner, no card -> all unattributed', () {
    final r = attributeTask(hours: 40, task: _task, assignments: const [], holdersOf: _holders(const []));
    expect(r.shares, isEmpty);
    expect(r.unattributed, 40);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/workforce_planning/attribute_task_test.dart`
Expected: FAIL — `attributeTask`/`TaskShare` undefined.

- [ ] **Step 3: Implement** (in `rebalance.dart`, after `_hoursOf`)

```dart
typedef TaskShare = ({String employeeId, double hours, bool derived, int holderCount});

/// Distributes ONE task's [hours] across the people who carry it, plus the
/// leftover that reaches nobody. Assignments win when present (person -> its
/// pct; card -> its pct split across active holders); a draft [moveOverride]
/// gives 100% to one person; with no assignments it falls back to owner/card
/// exactly as the pre-assignment split did. Mirrors wp_person_load.
({List<TaskShare> shares, double unattributed}) attributeTask({
  required double hours,
  required WpTask task,
  required List<WpTaskAssignment> assignments,
  required List<Employee> Function(String cardId) holdersOf,
  String? moveOverride,
}) {
  if (hours <= 0) return (shares: const <TaskShare>[], unattributed: 0);
  if (moveOverride != null) {
    return (
      shares: [(employeeId: moveOverride, hours: hours, derived: false, holderCount: 1)],
      unattributed: 0,
    );
  }
  final shares = <TaskShare>[];
  if (assignments.isNotEmpty) {
    for (final a in assignments) {
      final share = hours * a.allocationPct / 100.0;
      if (share <= 0) continue;
      if (a.employeeId != null) {
        shares.add((employeeId: a.employeeId!, hours: share, derived: false, holderCount: 1));
      } else if (a.roleScorecardId != null) {
        final hs = holdersOf(a.roleScorecardId!);
        if (hs.isEmpty) continue; // reaches nobody -> falls into unattributed below
        final per = share / hs.length;
        for (final h in hs) {
          shares.add((employeeId: h.id, hours: per, derived: true, holderCount: hs.length));
        }
      }
    }
    final reached = shares.fold<double>(0, (s, x) => s + x.hours);
    return (shares: shares, unattributed: hours - reached);
  }
  // Fallback (no assignments): owner/card, identical to the pre-assignment split.
  final owner = task.ownerEmployeeId;
  if (owner != null) {
    return (shares: [(employeeId: owner, hours: hours, derived: false, holderCount: 1)], unattributed: 0);
  }
  final cardId = task.roleScorecardId;
  if (cardId == null) return (shares: const <TaskShare>[], unattributed: hours);
  final hs = holdersOf(cardId);
  if (hs.isEmpty) return (shares: const <TaskShare>[], unattributed: hours);
  final per = hours / hs.length;
  return (
    shares: [for (final h in hs) (employeeId: h.id, hours: per, derived: true, holderCount: hs.length)],
    unattributed: 0,
  );
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/workforce_planning/attribute_task_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/workforce_planning/rebalance.dart test/features/workforce_planning/attribute_task_test.dart
git commit -m "feat(workforce): attributeTask — one split honoring assignments + allocation_pct"
```

---

### Task 2: Route `hoursByEmployee` + `buildProjections` through `attributeTask`

**Files:**
- Modify: `lib/features/workforce_planning/rebalance.dart` (`hoursByEmployee` :108-136; `buildProjections` :210-274)
- Test: `test/features/workforce_planning/rebalance_test.dart` (extend; existing tests must stay green)

**Interfaces:**
- Consumes: `attributeTask` (Task 1).
- Produces: `hoursByEmployee(...)` and `buildProjections(...)` each gain `Map<String, List<WpTaskAssignment>> assignmentsByTask = const {}` and delegate per-task attribution to `attributeTask`.

- [ ] **Step 1: Write a failing %-attribution test** (existing tests unchanged)

Add to `rebalance_test.dart`:

```dart
  test('hoursByEmployee honors a 60/40 person split via assignments', () {
    const t = WpTask(id: 't1', companyId: 'c', name: 'Pack');
    final h = hoursByEmployee(
      tasks: const [t],
      computedByTaskId: {'t1': _c('t1', 100)}, // reuse the file's WpTaskComputed helper
      employees: [_e('a'), _e('b')],       // reuse the file's Employee helper
      multiplier: 1,
      assignmentsByTask: {
        't1': const [
          WpTaskAssignment(id: 'x', companyId: 'c', taskId: 't1', employeeId: 'a',
              assignmentRole: 'PRIMARY', allocationPct: 60),
          WpTaskAssignment(id: 'y', companyId: 'c', taskId: 't1', employeeId: 'b',
              assignmentRole: 'CONTRIBUTOR', allocationPct: 40),
        ],
      },
    );
    expect(h['a'], 60);
    expect(h['b'], 40);
  });
```
(Use the existing helper names in `rebalance_test.dart` — read the file top for `_c`/`_emp`/`_t` and match them. If the computed-hours helper is named differently, use that.)

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/workforce_planning/rebalance_test.dart`
Expected: FAIL — `hoursByEmployee` has no `assignmentsByTask` param.

- [ ] **Step 3: Rewrite `hoursByEmployee` to delegate**

```dart
Map<String, double> hoursByEmployee({
  required List<WpTask> tasks,
  required Map<String, WpTaskComputed> computedByTaskId,
  required List<Employee> employees,
  required double multiplier,
  MoveDrafts moves = const {},
  Map<String, List<WpTaskAssignment>> assignmentsByTask = const {},
}) {
  final out = <String, double>{};
  final holdersByCard = <String, List<Employee>>{};
  List<Employee> holdersOf(String cardId) =>
      holdersByCard[cardId] ??= _activeHolders(employees, cardId);
  for (final t in tasks) {
    final hours = _hoursOf(computedByTaskId[t.id], multiplier);
    final r = attributeTask(
      hours: hours, task: t,
      assignments: assignmentsByTask[t.id] ?? const [],
      holdersOf: holdersOf, moveOverride: moves[t.id],
    );
    for (final s in r.shares) {
      out[s.employeeId] = (out[s.employeeId] ?? 0) + s.hours;
    }
  }
  return out;
}
```

- [ ] **Step 4: Thread `assignmentsByTask` through `buildProjections`**

In `buildProjections` add the param `Map<String, List<WpTaskAssignment>> assignmentsByTask = const {}`; pass it into BOTH `hoursByEmployee` calls (`now` and `planned`); and rewrite the tally loop (`:228-251`) to count a task for every distinct employee in its attribution:

```dart
  final counts = <String, int>{};
  final costed = <String, int>{};
  final holdersByCard = <String, List<Employee>>{};
  List<Employee> holdersOf(String cardId) =>
      holdersByCard[cardId] ??= _activeHolders(employees, cardId);
  for (final t in tasks) {
    if (t.isExpectation) continue;
    if (t.status != 'ACTIVE') continue;
    final hasHours = (computedByTaskId[t.id]?.hoursPerMonthBase ?? 0) > 0;
    final r = attributeTask(
      hours: _hoursOf(computedByTaskId[t.id], multiplier), task: t,
      assignments: assignmentsByTask[t.id] ?? const [],
      holdersOf: holdersOf, moves: moves are not applied to counts today, so pass moveOverride: null,
    );
    for (final id in {for (final s in r.shares) s.employeeId}) {
      counts[id] = (counts[id] ?? 0) + 1;
      if (hasHours) costed[id] = (costed[id] ?? 0) + 1;
    }
  }
```
NOTE: today's tally uses `moves[t.id] ?? t.ownerEmployeeId` — i.e. it DOES apply moves to the count. Preserve that: pass `moveOverride: moves[t.id]` into the tally's `attributeTask` call so a moved task counts for the destination person (matching today). (Correct the pseudo-line above accordingly — `moveOverride: moves[t.id]`.)

- [ ] **Step 5: Run to verify it passes (new + existing)**

Run: `flutter test test/features/workforce_planning/rebalance_test.dart`
Expected: PASS — the new 60/40 test AND every existing test (which pass empty `assignmentsByTask` → fallback → today's numbers). If any existing test fails, the fallback diverged from the old logic; fix `attributeTask`'s fallback, do NOT edit the test.

- [ ] **Step 6: Commit**

```bash
git add lib/features/workforce_planning/rebalance.dart test/features/workforce_planning/rebalance_test.dart
git commit -m "feat(workforce): hoursByEmployee/buildProjections attribute via assignments"
```

---

### Task 3: Route `plannedTasksFor`, `unattributedHours`, `orphanHours` through `attributeTask`

**Files:**
- Modify: `lib/features/workforce_planning/rebalance.dart` (`unattributedHours` :184-206; `orphanHours` :155-180; `plannedTasksFor` :278-318)
- Test: `test/features/workforce_planning/rebalance_test.dart` (extend; existing green)

**Interfaces:**
- Each gains `Map<String, List<WpTaskAssignment>> assignmentsByTask = const {}` and delegates to `attributeTask`.

- [ ] **Step 1: Write failing tests**

Add:
```dart
  test('plannedTasksFor returns a contributor\'s derived share', () {
    const t = WpTask(id: 't1', companyId: 'c', name: 'Pack');
    final rows = plannedTasksFor(
      employeeId: 'b',
      employees: [_e('a'), _e('b')],
      tasks: const [t],
      computedByTaskId: {'t1': _c('t1', 100)},
      multiplier: 1,
      assignmentsByTask: {
        't1': const [WpTaskAssignment(id: 'y', companyId: 'c', taskId: 't1', employeeId: 'b',
            assignmentRole: 'CONTRIBUTOR', allocationPct: 40)],
      },
    );
    expect(rows.single.hours, 40);
  });

  test('unattributedHours counts a Σ<100 gap', () {
    const t = WpTask(id: 't1', companyId: 'c', name: 'Pack');
    final u = unattributedHours(
      tasks: const [t], computedByTaskId: {'t1': _c('t1', 100)},
      employees: const [], multiplier: 1,
      assignmentsByTask: {
        't1': const [WpTaskAssignment(id: 'y', companyId: 'c', taskId: 't1', employeeId: 'a',
            assignmentRole: 'PRIMARY', allocationPct: 70)],
      },
    );
    expect(u, 30); // 30% of 100h reaches nobody
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/workforce_planning/rebalance_test.dart`
Expected: FAIL — params/behavior missing.

- [ ] **Step 3: Rewrite the three functions to delegate**

- `unattributedHours`: add the param; loop tasks, `total += attributeTask(...).unattributed` (passing `moveOverride: moves[t.id]`, `assignments: assignmentsByTask[t.id] ?? const []`, `holdersOf`). Remove the old inline owner/card logic.
- `orphanHours`: add the param; for each task compute `u = attributeTask(...).unattributed`; if `u <= 0` continue; classify: `if (t.externalRef != null && t.roleScorecardId == null) legacy += u; else genuine += u;` (preserves the legacy-reference bucket rule).
- `plannedTasksFor`: add the param; for each task, `r = attributeTask(...)`; for each `s in r.shares where s.employeeId == employeeId`, add `PlannedTask(task: t, hours: s.hours, derived: s.derived, holderCount: s.holderCount, moved: moves.containsKey(t.id))`. (A person normally appears at most once; if they appear via multiple assignments, sum is acceptable — but keep one row per task: sum the matching shares' hours, take `derived` = any-derived, `holderCount` from the derived share.) Keep the final sort.

- [ ] **Step 4: Run to verify it passes (new + existing)**

Run: `flutter test test/features/workforce_planning/rebalance_test.dart`
Expected: PASS — new tests + all existing (empty assignments → fallback). If an existing test fails, fix the fallback, not the test.

- [ ] **Step 5: Commit**

```bash
git add lib/features/workforce_planning/rebalance.dart test/features/workforce_planning/rebalance_test.dart
git commit -m "feat(workforce): plannedTasksFor/unattributed/orphan attribute via assignments"
```

---

### Task 4: Providers + Balance-tab threading

**Files:**
- Modify: `lib/features/workforce_planning/wp_providers.dart`
- Modify: `lib/features/workforce_planning/tabs/balance_tab.dart`

**Interfaces:**
- Produces: `wpTaskAssignmentsProvider` (`FutureProvider<List<WpTaskAssignment>>`); `wpAssignmentsByTaskProvider` (`FutureProvider<Map<String, List<WpTaskAssignment>>>` grouping by `taskId`).
- Consumes: those providers in `balance_tab.dart`, threaded into the split calls.

- [ ] **Step 1: Add the providers**

In `wp_providers.dart` (mirror `wpTasksProvider`):
```dart
final wpTaskAssignmentsProvider = FutureProvider<List<WpTaskAssignment>>(
    (ref) => ref.watch(workforcePlanningRepositoryProvider).taskAssignments());

final wpAssignmentsByTaskProvider =
    FutureProvider<Map<String, List<WpTaskAssignment>>>((ref) async {
  final all = await ref.watch(wpTaskAssignmentsProvider.future);
  final byTask = <String, List<WpTaskAssignment>>{};
  for (final a in all) {
    (byTask[a.taskId] ??= []).add(a);
  }
  return byTask;
});
```
(Import `WpTaskAssignment` if needed — it's in `workforce_planning.dart`, already imported for the other models.)

- [ ] **Step 2: Thread into `balance_tab.dart`**

- Watch `wpAssignmentsByTaskProvider`; include it in the loading/error gate alongside the other async reads (mirror the existing `.isLoading`/error handling around `:42-47`).
- Get `assignmentsByTask = ref.watch(wpAssignmentsByTaskProvider).asData?.value ?? const {}` and pass it into `buildProjections(...)`, `plannedTasksFor(...)`, `orphanHours(...)`, and `unattributedHours(...)` wherever the tab calls them (`:78`, `:86`, `:89`, and any `plannedTasksFor` call in the per-person panel).
- After a move Apply (`_applyMoves`, near `:746`), invalidate `wpTaskAssignmentsProvider` (and `wpAssignmentsByTaskProvider`) so the recomputed split reflects the synced PRIMARY rows — mirror how it already invalidates `wpTasksProvider`/`wpPersonLoadsProvider`.

- [ ] **Step 3: Analyze + verify Balance tests**

Run: `flutter analyze lib/features/workforce_planning/`
Expected: 0 errors.
Run: `flutter test test/features/workforce_planning/balance_tab_test.dart`
Expected: PASS. `balance_tab_test.dart`'s `_host` likely doesn't override the new provider — because `wpTaskAssignmentsProvider` hits `Supabase.instance.client`, it errors synchronously and `.asData?.value` is null → the tab uses `const {}` → fallback → today's behavior → tests green. If the tab GATES on the new provider being loaded and the test doesn't override it, the tab would spin forever; therefore do NOT hard-gate on the assignments provider — treat a null/error value as `const {}` (empty) rather than a loading blocker. Confirm the test passes; if it hangs, relax the gate to a null-coalesce.

- [ ] **Step 4: Commit**

```bash
git add lib/features/workforce_planning/wp_providers.dart lib/features/workforce_planning/tabs/balance_tab.dart
git commit -m "feat(workforce): Balance split reads task assignments"
```

---

### Task 5: Full-suite + analyze gate

- [ ] **Step 1: Full suite**

Run: `flutter test`
Expected: all pass (prior 1035 + new; 1 skip). The whole point of the fallback is that everything not passing assignments behaves as before — so ONLY the new tests should be net-new passes; no pre-existing test should change. STOP and report if a pre-existing test fails.

- [ ] **Step 2: Analyze**

Run: `flutter analyze`
Expected: 0 errors.

---

## Self-Review

**Spec coverage** (spec §"How the per-person numbers come out", the deferred step-4 items):
- Card assignment → allocation% split across active holders; person assignment → allocation% direct; Σ%<100 surfaced as unattributed → `attributeTask` (Task 1). ✓
- The Dart split (Balance draft preview) now honors assignments+% → Tasks 2–4. ✓
- Draft-move semantics preserved (move = 100% to one person) → `attributeTask` moveOverride. ✓
- Numbers unchanged on today's data → the fallback path + existing tests green (the invariant). ✓
- Unattributed hours surfaced (never silently dropped) → `unattributedHours`/`orphanHours` via `attributeTask`. ✓

**Deferred to step 5b (correctly NOT here):** the assignment panel UI (adding/removing contributors, editing %, the simplifiers, the live =100% check); repo writes for CONTRIBUTOR rows + allocation edits; the `set_updated_at` trigger (only needed once UPDATEs happen — 5b). This plan changes NO allocation (all stay 100 until 5b), so it is numerically inert in production today; it only re-plumbs the engine.

**Placeholder scan:** Task 2 Step 4's tally rewrite contains a deliberately-flagged pseudo-line ("moves are not applied…") immediately corrected in the NOTE to `moveOverride: moves[t.id]` — the implementer must use `moveOverride: moves[t.id]` to preserve today's move-counts-for-destination behavior. All other steps have complete code.

**Type consistency:** `TaskShare` and `attributeTask`'s return record shape are identical across all consumers. `assignmentsByTask` is `Map<String, List<WpTaskAssignment>>` in every function and both providers. `holdersOf` is `List<Employee> Function(String)` everywhere.

**Risk:** highest-traffic file. Mitigation: the fallback makes every existing test a regression guard (they pass empty assignments and must stay green byte-for-byte), and production data (one PRIMARY @100 from step-4 backfill) provably routes through the assignment path to the same numbers. If any existing `rebalance_test.dart` assertion would need changing, that is the signal the fallback diverged — STOP and fix the code, never the test.
