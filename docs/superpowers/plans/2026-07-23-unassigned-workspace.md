# Unassigned Workspace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A dedicated "Unassigned" surface in the workforce-planning hub that lists ACTIVE accountabilities reaching nobody, clusters similar ones together, and lets a manager Archive them (no longer needed), Assign them to a role card, or draft a new role from a cluster (needed but no role does it yet).

**Architecture:** A pure derivation (`unassigned_workspace.dart`) reuses the existing orphan predicate from `rebalance.dart` and groups orphans into name-similarity clusters (new `text_similarity.dart`, a normalized-token Jaccard the step-6 duplicate check will reuse), each carrying its total hours. Two thin repo methods — assign-to-card and draft-a-role-from-tasks — mutate `wp_tasks.role_scorecard_id` (and, for a new role, insert an inactive `role_scorecards` row); archiving reuses the existing `setTaskArchived`. A new 5th hub tab renders the clusters with per-row and per-cluster actions. This is step 3 of the accountability model, built on CURRENT data — pre-`wp_task_assignments`; at step 4 "assign to a card" upgrades to a PRIMARY assignment with no UI change.

**Tech Stack:** Flutter (Material 3, Riverpod, GoRouter), Supabase (PostgREST), `flutter_test`.

## Global Constraints

- Repo gates on `flutter analyze` only (must end 0 errors). Do NOT run `dart format`; match each file's surrounding style.
- This step adds NO migration — it works on current columns (`role_scorecard_id`, `owner_employee_id`, `status`, `criticality`, `hours_per_month`). Forward-only rule still holds for any future migration.
- This app is for MANAGERS; employees never see this UI (spec §"Two audiences"). No employee-facing surface here.
- "Orphan / unassigned" for step 3 = the EXISTING current-data notion, reused verbatim from `rebalance.dart`'s `unassignedTasks`: an ACTIVE task with no draft-move, no `ownerEmployeeId`, and either (no card AND no `externalRef`) OR (a card whose ACTIVE non-deleted holders are empty); legacy capacity-model rows (`roleScorecardId == null && externalRef != null`) are excluded. Do NOT invent a second predicate. At step 4 the criterion becomes "no PRIMARY assignment" with no UI change.
- Design system (`PRODUCT.md`): numbers/hours via `AppTheme.mono(context)`; tinted borderless chips via `StatusChip(label:, tone:)` (`lib/app/status_colors.dart`); criticality chip via `criticalityTone`/`criticalityLabel` (`lib/features/workforce_planning/task_badges.dart`); single purple CTA; the `TabIntro`/`WpGlossary` pattern (`lib/features/workforce_planning/tabs/tab_intro.dart`) to explain new vocabulary.
- Nothing is auto-archived or auto-created — every action is an explicit human click (spec §"Unassigned work").
- A drafted role is created INACTIVE (`isActive: false`) — it is a proposal for HR to finish, not a live role.

---

## File Structure

- `lib/features/workforce_planning/text_similarity.dart` — **create.** `normalizeName`, `nameSimilarity`, `clusterBySimilarity`. Pure, reused by the step-6 duplicate check later.
- `lib/features/workforce_planning/unassigned_workspace.dart` — **create.** `UnassignedItem`, `UnassignedCluster`, `buildUnassignedWorkspace(...)`. Pure.
- `lib/data/repositories/workforce_planning_repository.dart` — **modify.** Add `setTaskCard(taskId, roleScorecardId)`.
- `lib/data/repositories/role_scorecard_repository.dart` — **modify.** Add `createDraftRoleFromTasks(...)` (insert inactive card + repoint the tasks' `role_scorecard_id`).
- `lib/features/workforce_planning/tabs/unassigned_tab.dart` — **create.** The workspace UI.
- `lib/features/workforce_planning/tabs/tab_intro.dart` — **modify.** Add a `WpGlossary.proposeRole` entry (reuse existing `WpGlossary.unassigned`).
- `lib/features/workforce_planning/workforce_planning_screen.dart` — **modify.** Add the 5th "Unassigned" tab.
- Tests: `test/features/workforce_planning/text_similarity_test.dart`, `test/features/workforce_planning/unassigned_workspace_test.dart`, `test/features/workforce_planning/unassigned_tab_test.dart` (create).

---

### Task 1: Text similarity for clustering

**Files:**
- Create: `lib/features/workforce_planning/text_similarity.dart`
- Test: `test/features/workforce_planning/text_similarity_test.dart`

**Interfaces:**
- Produces: `String normalizeName(String)`, `double nameSimilarity(String a, String b)` (0..1 Jaccard over word sets), `List<List<T>> clusterBySimilarity<T>(List<T> items, String Function(T) nameOf, {double threshold})`.

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/workforce_planning/text_similarity_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/workforce_planning/text_similarity.dart';

void main() {
  test('normalizeName lowercases, strips punctuation, collapses whitespace', () {
    expect(normalizeName('  Pack, Label &  Dispatch!! '), 'pack label dispatch');
  });

  test('nameSimilarity is 1.0 for the same words in any order, 0 for disjoint', () {
    expect(nameSimilarity('pack and dispatch orders', 'dispatch orders and pack'), 1.0);
    expect(nameSimilarity('reconcile bank statements', 'design social ads'), 0.0);
  });

  test('nameSimilarity is a fraction for partial overlap', () {
    // {pack, orders} vs {pack, orders, daily}: intersection 2, union 3
    expect(nameSimilarity('pack orders', 'pack orders daily'), closeTo(2 / 3, 1e-9));
  });

  test('clusterBySimilarity groups names above the threshold, isolates the rest', () {
    final items = ['Pack orders', 'Pack the orders', 'Reconcile bank statements'];
    final clusters = clusterBySimilarity<String>(items, (s) => s, threshold: 0.5);
    // two packing names cluster; the finance one stands alone
    expect(clusters.length, 2);
    expect(clusters.firstWhere((c) => c.length == 2).toSet(),
        {'Pack orders', 'Pack the orders'});
    expect(clusters.any((c) => c.single == 'Reconcile bank statements'), isTrue);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/workforce_planning/text_similarity_test.dart`
Expected: FAIL — file/functions do not exist.

- [ ] **Step 3: Implement**

```dart
// lib/features/workforce_planning/text_similarity.dart

/// Lowercase, strip non-alphanumeric to spaces, collapse whitespace. The
/// canonical form for comparing/clustering accountability names.
String normalizeName(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ');

Set<String> _words(String s) {
  final n = normalizeName(s);
  return n.isEmpty ? <String>{} : n.split(' ').toSet();
}

/// Jaccard similarity over the two names' word sets: |A∩B| / |A∪B|, in 0..1.
/// Order-independent and cheap; good enough to cluster near-duplicate
/// responsibilities without a full edit-distance library.
double nameSimilarity(String a, String b) {
  final wa = _words(a), wb = _words(b);
  if (wa.isEmpty && wb.isEmpty) return 1.0;
  if (wa.isEmpty || wb.isEmpty) return 0.0;
  final inter = wa.intersection(wb).length;
  final union = wa.union(wb).length;
  return inter / union;
}

/// Greedy single-link clustering: each item joins the first existing cluster
/// whose FIRST member it matches at or above [threshold], else starts its own.
/// Deterministic (input order preserved), which keeps the UI and tests stable.
List<List<T>> clusterBySimilarity<T>(
  List<T> items,
  String Function(T) nameOf, {
  double threshold = 0.6,
}) {
  final clusters = <List<T>>[];
  for (final item in items) {
    List<T>? match;
    for (final c in clusters) {
      if (nameSimilarity(nameOf(c.first), nameOf(item)) >= threshold) {
        match = c;
        break;
      }
    }
    if (match != null) {
      match.add(item);
    } else {
      clusters.add([item]);
    }
  }
  return clusters;
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/workforce_planning/text_similarity_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/workforce_planning/text_similarity.dart test/features/workforce_planning/text_similarity_test.dart
git commit -m "feat(workforce): normalized-token name similarity + clustering"
```

---

### Task 2: The Unassigned workspace derivation

**Files:**
- Create: `lib/features/workforce_planning/unassigned_workspace.dart`
- Test: `test/features/workforce_planning/unassigned_workspace_test.dart`

**Interfaces:**
- Consumes: `clusterBySimilarity` (Task 1); `WpTask`, `WpTaskComputed`, `Employee`; the orphan predicate mirrored from `rebalance.dart`.
- Produces:
  - `class UnassignedItem { final WpTask task; final double hours; }`
  - `class UnassignedCluster { final String label; final List<UnassignedItem> items; double get totalHours; int get count; }`
  - `List<UnassignedCluster> buildUnassignedWorkspace({required List<WpTask> tasks, required List<Employee> employees, required Map<String, WpTaskComputed> computedByTaskId, required double multiplier, double threshold = 0.6})`

**Interface note:** the orphan predicate MUST match `rebalance.dart`'s `unassignedTasks` (see Global Constraints). Reuse `_activeHolders`-equivalent logic: a card is "staffed" iff some employee has `employmentStatus == 'ACTIVE' && deletedAt == null && roleScorecardId == cardId`. Hours come from `computedByTaskId[t.id]`: `isGrowing ? hoursPerMonthBase * multiplier : hoursPerMonthBase` (0 when absent — archived/uncosted). Clusters are ordered by descending `totalHours` (heaviest gap first); items within a cluster by descending hours then name; the cluster `label` is the shortest item name in the cluster (a readable representative).

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/workforce_planning/unassigned_workspace_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/unassigned_workspace.dart';

Employee _e(String id, {String? card, String status = 'ACTIVE'}) => Employee(
      id: id, companyId: 'c', firstName: id, lastName: 'x',
      employmentStatus: status, roleScorecardId: card);

WpTask _t(String id, String name,
        {String? card, String? owner, String? ext, String status = 'ACTIVE'}) =>
    WpTask(id: id, companyId: 'c', name: name, roleScorecardId: card,
        ownerEmployeeId: owner, externalRef: ext, status: status);

WpTaskComputed _c(String id, double hours) =>
    WpTaskComputed(taskId: id, companyId: 'c', hoursPerMonthBase: hours);

void main() {
  test('an owned task and a staffed-card task are NOT unassigned', () {
    final res = buildUnassignedWorkspace(
      tasks: [
        _t('owned', 'Owned work', owner: 'e1'),
        _t('staffed', 'Staffed work', card: 'rs1'),
      ],
      employees: [_e('e1'), _e('e2', card: 'rs1')],
      computedByTaskId: {}, multiplier: 1,
    );
    expect(res, isEmpty);
  });

  test('a legacy capacity-model row is excluded', () {
    final res = buildUnassignedWorkspace(
      tasks: [_t('leg', 'Legacy row', ext: 'T9')],
      employees: const [], computedByTaskId: {}, multiplier: 1,
    );
    expect(res, isEmpty);
  });

  test('an archived orphan is excluded', () {
    final res = buildUnassignedWorkspace(
      tasks: [_t('a', 'Old packing', status: 'ARCHIVED')],
      employees: const [], computedByTaskId: {}, multiplier: 1,
    );
    expect(res, isEmpty);
  });

  test('orphans cluster by name similarity, heaviest cluster first, with hours', () {
    final res = buildUnassignedWorkspace(
      tasks: [
        _t('p1', 'Pack orders'),                 // no card, no owner -> orphan
        _t('p2', 'Pack the orders'),
        _t('f1', 'Reconcile bank statements', card: 'empty'), // card w/ no holders -> orphan
      ],
      employees: const [], // 'empty' card has zero active holders
      computedByTaskId: {'p1': _c('p1', 10), 'p2': _c('p2', 5), 'f1': _c('f1', 20)},
      multiplier: 1,
    );
    expect(res.length, 2);
    // finance cluster (20h) outranks packing cluster (15h)
    expect(res.first.totalHours, 20);
    expect(res.first.count, 1);
    final packing = res[1];
    expect(packing.count, 2);
    expect(packing.totalHours, 15);
    expect(packing.items.first.hours, 10); // heaviest item first
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/workforce_planning/unassigned_workspace_test.dart`
Expected: FAIL — file/symbols do not exist.

- [ ] **Step 3: Implement**

```dart
// lib/features/workforce_planning/unassigned_workspace.dart
import '../../data/models/employee.dart';
import '../../data/models/workforce_planning.dart';
import 'text_similarity.dart';

/// One ACTIVE accountability that reaches nobody, with its projected hours.
class UnassignedItem {
  final WpTask task;
  final double hours;
  const UnassignedItem({required this.task, required this.hours});
}

/// A group of similar unassigned accountabilities — the unit a manager acts on
/// (archive each, assign each, or draft one role from the whole group).
class UnassignedCluster {
  final String label;
  final List<UnassignedItem> items;
  const UnassignedCluster({required this.label, required this.items});
  double get totalHours =>
      items.fold(0.0, (sum, i) => sum + i.hours);
  int get count => items.length;
}

bool _cardStaffed(List<Employee> employees, String cardId) => employees.any((e) =>
    e.employmentStatus == 'ACTIVE' &&
    e.deletedAt == null &&
    e.roleScorecardId == cardId);

double _hoursOf(WpTaskComputed? c, double multiplier) {
  if (c == null) return 0;
  return c.isGrowing ? c.hoursPerMonthBase * multiplier : c.hoursPerMonthBase;
}

/// Every ACTIVE accountability reaching nobody, grouped into name-similarity
/// clusters ordered heaviest-first. Orphan predicate mirrors rebalance.dart's
/// `unassignedTasks` exactly (see the plan's Global Constraints).
List<UnassignedCluster> buildUnassignedWorkspace({
  required List<WpTask> tasks,
  required List<Employee> employees,
  required Map<String, WpTaskComputed> computedByTaskId,
  required double multiplier,
  double threshold = 0.6,
}) {
  final orphans = <WpTask>[];
  for (final t in tasks) {
    if (t.status != 'ACTIVE') continue;
    if (t.ownerEmployeeId != null) continue;
    final cardId = t.roleScorecardId;
    if (cardId == null && t.externalRef != null) continue; // legacy reference
    final orphaned = cardId == null || !_cardStaffed(employees, cardId);
    if (!orphaned) continue;
    orphans.add(t);
  }

  final clusters = clusterBySimilarity<WpTask>(
      orphans, (t) => t.name, threshold: threshold);

  final out = <UnassignedCluster>[];
  for (final group in clusters) {
    final items = [
      for (final t in group)
        UnassignedItem(task: t, hours: _hoursOf(computedByTaskId[t.id], multiplier)),
    ]..sort((a, b) {
        final c = b.hours.compareTo(a.hours);
        return c != 0 ? c : a.task.name.toLowerCase().compareTo(b.task.name.toLowerCase());
      });
    // Shortest name is the most readable representative label.
    final label = group
        .map((t) => t.name)
        .reduce((a, b) => a.length <= b.length ? a : b);
    out.add(UnassignedCluster(label: label, items: items));
  }
  out.sort((a, b) => b.totalHours.compareTo(a.totalHours));
  return out;
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/workforce_planning/unassigned_workspace_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/workforce_planning/unassigned_workspace.dart test/features/workforce_planning/unassigned_workspace_test.dart
git commit -m "feat(workforce): unassigned-workspace derivation with clustering"
```

---

### Task 3: Repo — assign an orphan to a card, and draft a role from tasks

**Files:**
- Modify: `lib/data/repositories/workforce_planning_repository.dart` (after `reassignTaskOwner`, ~line 137)
- Modify: `lib/data/repositories/role_scorecard_repository.dart` (after `upsert`, ~line 125)

**Interfaces:**
- Produces:
  - `Future<void> WorkforcePlanningRepository.setTaskCard(String taskId, String? roleScorecardId)` — sets `wp_tasks.role_scorecard_id` (the accountability's home card; null unlinks). Assigning to a staffed card gives it a derived owner and removes it from the unassigned set.
  - `Future<String> RoleScorecardRepository.createDraftRoleFromTasks({required String companyId, required String jobTitle, required List<String> taskIds})` — inserts an INACTIVE `role_scorecards` row, repoints each task's `role_scorecard_id` to it, returns the new card id.

These are thin PostgREST writes (the repos have no unit tests); they are exercised by the Task 4 widget test via fake repos.

- [ ] **Step 1: Add `setTaskCard` to the workforce repo**

After `reassignTaskOwner` (`workforce_planning_repository.dart:137`), add:

```dart
  /// Sets (or clears) an accountability's home card. Assigning an orphan to a
  /// staffed card gives it a derived owner via that card's holders, which is
  /// how work leaves the unassigned set pre-`wp_task_assignments`. At step 4
  /// this becomes a PRIMARY assignment insert with no caller change.
  Future<void> setTaskCard(String taskId, String? roleScorecardId) async =>
      _client.from('wp_tasks')
          .update({'role_scorecard_id': roleScorecardId})
          .eq('id', taskId);
```

- [ ] **Step 2: Add `createDraftRoleFromTasks` to the role-scorecard repo**

After `upsert` (`role_scorecard_repository.dart:125`), add:

```dart
  /// Drafts a new INACTIVE role card seeded from a cluster of unassigned
  /// accountabilities, then repoints those tasks onto it. The card is inactive
  /// because it is a proposal for HR to finish (mission, KPIs, wage), not a live
  /// role — "here is a pile of unowned work" becomes "here is the role we need
  /// to hire for", with the tasks already attached. Returns the new card id.
  Future<String> createDraftRoleFromTasks({
    required String companyId,
    required String jobTitle,
    required List<String> taskIds,
  }) async {
    final row = await _client.from('role_scorecards').insert({
      'company_id': companyId,
      'job_title': jobTitle,
      'mission_statement': '',
      'wage_type': 'MONTHLY',
      'work_hours_per_day': 8,
      'work_days_per_week': 'MON_FRI',
      'is_active': false,
      'effective_date': DateTime.now().toIso8601String(),
    }).select('id').single();
    final id = row['id'] as String;
    if (taskIds.isNotEmpty) {
      await _client.from('wp_tasks')
          .update({'role_scorecard_id': id})
          .inFilter('id', taskIds);
    }
    return id;
  }
```

(`.inFilter` is the confirmed codebase idiom — this same repo already uses it at `role_scorecard_repository.dart:319` (`.delete().inFilter('id', deleteIds)`).)

- [ ] **Step 3: Verify it compiles**

Run: `flutter analyze lib/data/repositories/workforce_planning_repository.dart lib/data/repositories/role_scorecard_repository.dart`
Expected: 0 errors.

- [ ] **Step 4: Commit**

```bash
git add lib/data/repositories/workforce_planning_repository.dart lib/data/repositories/role_scorecard_repository.dart
git commit -m "feat(workforce): assign-to-card and draft-role-from-tasks repo methods"
```

---

### Task 4: The Unassigned tab UI

**Files:**
- Create: `lib/features/workforce_planning/tabs/unassigned_tab.dart`
- Modify: `lib/features/workforce_planning/tabs/tab_intro.dart` (add a glossary entry)
- Test: `test/features/workforce_planning/unassigned_tab_test.dart`

**Interfaces:**
- Consumes: `buildUnassignedWorkspace` (Task 2); `setTaskCard`, `setTaskArchived`, `createDraftRoleFromTasks` (Task 3); the same providers `TasksTab` uses (`wpTasksProvider`, `wpActiveEmployeesProvider`, `wpAllTaskComputedProvider`, `wpGrowthMultiplierProvider` for the multiplier — a `Provider<double>`, `roleScorecardListProvider`).
- Produces: `class UnassignedTab extends ConsumerStatefulWidget` (const constructor).

**UI shape:** `TabIntro` (purpose "Work that reaches nobody — archive it, assign it, or draft a role for it."; details = a new `WpGlossary.proposeRole` entry + existing `WpGlossary.unassigned`, `WpGlossary.derived`). Then, when empty, a friendly "Nothing unassigned — every accountability reaches someone." Otherwise a scrollable list of clusters. Each cluster is a `Card`/section with a header row: the cluster `label`, a `StatusChip` "N items · Xh" (mono hours), and a `FilledButton.icon('Propose role from these')` when `count >= 2`. Under it, each `UnassignedItem` row: task name, criticality chip (`criticalityTone`/`criticalityLabel` when set), mono hours, and a trailing action row: an "Assign ▾" `PopupMenuButton` listing ACTIVE role cards (tap → `setTaskCard(task.id, cardId)`), and an "Archive" `IconButton` (tap → confirm → `setTaskArchived(task.id, true)`). "Propose role from these" opens a small dialog prompting a job title (prefilled from the cluster label) → `createDraftRoleFromTasks(companyId, jobTitle, [taskIds])` → success snackbar "Drafted '<title>' (inactive) with N responsibilities." After any mutation, invalidate the read providers (mirror `TasksTab._invalidateAfterTaskChange`: `wpTasksProvider`, `wpPersonLoadsProvider`, `wpAllTaskComputedProvider`, `ownerComputedProvider`, `roleScorecardListProvider`).

- [ ] **Step 1: Add the glossary entry**

In `lib/features/workforce_planning/tabs/tab_intro.dart`, in `class WpGlossary`, add:

```dart
  static const proposeRole = (
    term: 'Propose role from these',
    meaning: 'When several unassigned responsibilities form a coherent job, '
        'draft a new (inactive) role card seeded with them — turning a pile of '
        'unowned work into the role you need to staff, hours already totalled.',
  );
```

- [ ] **Step 2: Write the failing widget test**

```dart
// test/features/workforce_planning/unassigned_tab_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';
import 'package:payroll_flutter/data/repositories/workforce_planning_repository.dart';
import 'package:payroll_flutter/features/workforce_planning/tabs/unassigned_tab.dart';
import 'package:payroll_flutter/features/workforce_planning/wp_providers.dart';

class _FakeRepo implements WorkforcePlanningRepository {
  final List<(String, bool)> archived = [];
  final List<(String, String?)> carded = [];
  @override
  Future<void> setTaskArchived(String id, bool a) async => archived.add((id, a));
  @override
  Future<void> setTaskCard(String id, String? c) async => carded.add((id, c));
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeCards implements RoleScorecardRepository {
  final List<(String, List<String>)> drafted = [];
  @override
  Future<String> createDraftRoleFromTasks({
      required String companyId, required String jobTitle, required List<String> taskIds}) async {
    drafted.add((jobTitle, taskIds));
    return 'new-card';
  }
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

final _card = RoleScorecard(
  id: 'rs1', companyId: 'c', jobTitle: 'Ops', missionStatement: '',
  responsibilities: const [], kpis: const [], wageType: 'MONTHLY',
  workHoursPerDay: 8, workDaysPerWeek: 'MON_FRI', isActive: true,
  effectiveDate: DateTime(2026, 1, 1));

const _p1 = WpTask(id: 'p1', companyId: 'c', name: 'Pack orders', hoursPerMonth: 10);
const _p2 = WpTask(id: 'p2', companyId: 'c', name: 'Pack the orders', hoursPerMonth: 5);

Widget _host(_FakeRepo repo, _FakeCards cards) => ProviderScope(
      overrides: [
        wpTasksProvider.overrideWith((ref) async => const [_p1, _p2]),
        wpActiveEmployeesProvider.overrideWith((ref) async => const []),
        wpAllTaskComputedProvider.overrideWith((ref) async => const [
              WpTaskComputed(taskId: 'p1', companyId: 'c', hoursPerMonthBase: 10),
              WpTaskComputed(taskId: 'p2', companyId: 'c', hoursPerMonthBase: 5),
            ]),
        wpGrowthMultiplierProvider.overrideWithValue(1.0),
        roleScorecardListProvider.overrideWith((ref) async => [_card]),
        workforcePlanningRepositoryProvider.overrideWithValue(repo),
        roleScorecardRepositoryProvider.overrideWithValue(cards),
      ],
      child: MaterialApp(
        home: Scaffold(body: SizedBox(width: 1200, height: 900, child: const UnassignedTab())),
      ),
    );

void main() {
  testWidgets('renders a cluster of the two similar orphans with total hours', (tester) async {
    await tester.pumpWidget(_host(_FakeRepo(), _FakeCards()));
    await tester.pumpAndSettle();
    expect(find.text('Pack orders'), findsWidgets);
    expect(find.textContaining('Propose role from these'), findsOneWidget);
  });

  testWidgets('Propose role drafts an inactive card from the cluster', (tester) async {
    final cards = _FakeCards();
    await tester.pumpWidget(_host(_FakeRepo(), cards));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Propose role from these'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Draft role'));
    await tester.pumpAndSettle();
    expect(cards.drafted, hasLength(1));
    expect(cards.drafted.single.$2.toSet(), {'p1', 'p2'});
  });
}
```

(Confirm the exact provider names by reading `lib/features/workforce_planning/wp_providers.dart` — use whatever `TasksTab` imports for tasks/employees/computed/config/cards and the repository providers. If `roleScorecardRepositoryProvider` lives elsewhere, import from there. Adjust the override list to the real names; keep the assertions.)

- [ ] **Step 3: Run to verify it fails**

Run: `flutter test test/features/workforce_planning/unassigned_tab_test.dart`
Expected: FAIL — `unassigned_tab.dart` does not exist.

- [ ] **Step 4: Implement `unassigned_tab.dart`**

Build the widget per the "UI shape" above. Read `lib/features/workforce_planning/tabs/tasks_tab.dart` first for the established patterns to mirror: how it reads the same providers, its `_invalidateAfterTaskChange`, its confirm-dialog shape (`_confirmArchive`), and its `StatusChip`/mono usage. Concretely:
- A `ConsumerStatefulWidget`; in `build`, watch `wpTasksProvider`, `wpActiveEmployeesProvider`, `wpAllTaskComputedProvider`, `roleScorecardListProvider` (FutureProviders — spinner while any is loading, error text on error, mirror `TasksTab` lines ~90–112), and read `wpGrowthMultiplierProvider` (a plain `Provider<double>`).
- Build `computedByTaskId = {for (final c in allComputed) c.taskId: c}` and `multiplier = ref.watch(wpGrowthMultiplierProvider)`.
- `final clusters = buildUnassignedWorkspace(tasks: tasks, employees: employees, computedByTaskId: computedByTaskId, multiplier: multiplier);`
- Render `TabIntro` + (empty message OR the cluster list). Hours via `AppTheme.mono(context)`. Criticality chip via `criticalityTone(t.criticality)` / `criticalityLabel(t.criticality)` (skip when null).
- "Assign ▾" `PopupMenuButton<String>` items from the ACTIVE cards (`cards.where((c) => c.isActive)`), `onSelected: (cardId) async { await repo.setTaskCard(task.id, cardId); _invalidate(); snackbar('Assigned to <title>'); }`.
- "Archive" → confirm dialog (copy: 'Archive "<name>"? It leaves the unassigned list and everyone\'s load but is kept and can be restored.') → `repo.setTaskArchived(task.id, true)` → `_invalidate()`.
- "Propose role from these" (shown when `cluster.count >= 2`, and also allow single-item propose via the row if desired — keep to clusters of 2+ for the button per spec) → `showDialog` with a `TextField` prefilled `cluster.label` and a `FilledButton('Draft role')` → `cardsRepo.createDraftRoleFromTasks(companyId: companyId, jobTitle: title, taskIds: [for (i in cluster.items) i.task.id])` → `_invalidate()` → snackbar.
- `_invalidate()` mirrors `TasksTab._invalidateAfterTaskChange(ref, cardIds)` — invalidate `wpTasksProvider`, `wpPersonLoadsProvider`, `wpAllTaskComputedProvider`, `ownerComputedProvider`, `roleScorecardListProvider`.

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/features/workforce_planning/unassigned_tab_test.dart`
Expected: PASS (2 tests). If the Propose dialog's button label differs, align the test and widget on the exact same string ('Draft role').

- [ ] **Step 6: Analyze + commit**

Run: `flutter analyze lib/features/workforce_planning/`
Expected: 0 errors.

```bash
git add lib/features/workforce_planning/tabs/unassigned_tab.dart lib/features/workforce_planning/tabs/tab_intro.dart test/features/workforce_planning/unassigned_tab_test.dart
git commit -m "feat(workforce): Unassigned tab — cluster, assign, archive, propose role"
```

---

### Task 5: Wire the 5th hub tab

**Files:**
- Modify: `lib/features/workforce_planning/workforce_planning_screen.dart` (`:29-30` controller length, `:64-72` TabBar, `:75-80` TabBarView)

**Interfaces:**
- Consumes: `UnassignedTab` (Task 4).

- [ ] **Step 1: Add the tab**

In `workforce_planning_screen.dart`:
- Change `DefaultTabController(length: 4` → `length: 5`.
- Add `Tab(text: 'Unassigned')` to the `TabBar` tabs. Place it after `'Tasks'` (last), so the existing four keep their positions and order (Balance, Roles, Structure, Tasks, Unassigned).
- Add `const UnassignedTab()` as the matching 5th child in the `TabBarView` children (same position).
- Add the import for `UnassignedTab`.

- [ ] **Step 2: Verify the hub renders all five tabs**

Add a lightweight assertion to the existing hub test if one exists (search `test/` for `WorkforcePlanningScreen`); otherwise verify manually via analyze + the Task 4 test. If a hub widget test exists, extend it to `expect(find.text('Unassigned'), findsOneWidget)`.

Run: `flutter analyze lib/features/workforce_planning/workforce_planning_screen.dart`
Expected: 0 errors.

- [ ] **Step 3: Commit**

```bash
git add lib/features/workforce_planning/workforce_planning_screen.dart
git commit -m "feat(workforce): add the Unassigned hub tab"
```

---

### Task 6: Full-suite + analyze gate

- [ ] **Step 1: Full suite**

Run: `flutter test`
Expected: all pass (prior 1007 + the new tests; 1 pre-existing skip). If a PRE-EXISTING test fails unexpectedly, STOP and report — do not rewrite its assertions.

- [ ] **Step 2: Analyze**

Run: `flutter analyze`
Expected: 0 errors.

---

## Self-Review

**Spec coverage** (spec §"Unassigned work — decide, don't let it rot", §"The Unassigned workspace", Sequencing item 3):
- Track ACTIVE work reaching nobody → Task 2 derivation (reuses the current orphan predicate). ✓
- Archive if not needed → Task 4 (existing `setTaskArchived`). ✓
- Assign if needed → Task 4 "Assign ▾" → `setTaskCard` (Task 3). ✓
- Cluster similar unowned items + show total hours → Task 1 (similarity) + Task 2 (clusters w/ `totalHours`) + Task 4 (header). ✓
- "Propose role from these" drafts an INACTIVE card seeded with the selected accountabilities → Task 3 `createDraftRoleFromTasks` + Task 4 dialog. ✓
- Nothing auto-created/auto-archived; every action a human click → Task 4 (all actions are explicit + Archive confirms). ✓
- Dedicated view / its own tab section → Task 5 (5th hub tab). ✓
- Managers only, no employee surface → the whole feature is in the HR/admin-gated hub. ✓
- Deferred to later steps (correctly NOT here): the needs-attention strip that embeds these actions inline (plan 3b); literal "no PRIMARY assignment" and per-person % (step 4+). The similarity util (Task 1) is deliberately built now for reuse by step 6's duplicate check.

**Placeholder scan:** Task 4's UI step describes the widget with concrete provider names, action wiring, and exact strings ('Draft role', 'Propose role from these'); it directs the implementer to mirror `TasksTab` for the established patterns rather than restating hundreds of lines — acceptable because the exact behaviors, method calls, and copy are all specified. No "TBD"/"handle edge cases".

**Type consistency:** `buildUnassignedWorkspace(...)` signature and the `UnassignedCluster`/`UnassignedItem` shapes are identical between Task 2's definition and Task 4's use. `setTaskCard(String, String?)`, `setTaskArchived(String, bool)`, `createDraftRoleFromTasks({companyId, jobTitle, taskIds}) -> Future<String>` match between Task 3 and the Task 4 fakes/calls. `clusterBySimilarity<T>(list, nameOf, {threshold})` matches between Task 1 and Task 2.

**Open decisions surfaced for the handoff:** (1) the workspace is a NEW 5th hub tab (vs a section inside Tasks) — spec says "its own tab section"; a tab is the discoverable reading. (2) "Assign" targets a role CARD (sets `role_scorecard_id`), not a specific person — matches the model (assignments target positions) and upgrades cleanly at step 4; a per-person exception assignment is deferred to step 5.
