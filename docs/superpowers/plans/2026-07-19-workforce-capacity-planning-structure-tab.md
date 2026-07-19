# Workforce Capacity Planning — Structure Tab (Plan 3 of 4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Fill the Structure tab with a draggable **indented org tree** — drag a responsibility (task) from one person onto another to reassign its owner, and drag a person under a different manager to restructure reporting — with a cycle guard.

**Architecture:** The tab builds an org tree from `employees.reports_to_id` via the Plan 1 `buildOrgTree`, renders it as an indented, expandable tree, and layers Flutter `Draggable`/`DragTarget` on each person row (drop zone) and each owned-task chip (drag source). Drop decisions run through pure, unit-tested helpers (`reportingDropError` using the Plan 1 `wouldCreateCycle`); the two writes go through `reassignTaskOwner` (Plan 1 repo) and a new `updateReportsTo` (employee repo). Every write invalidates the read providers so Balance/Role View/Structure stay consistent.

**Tech Stack:** Flutter (Material 3, Riverpod, `Draggable`/`DragTarget`), the Plan 1 backend + `org_tree`/`capacity_math`, Plan 2 `wp_providers` + `LoadStatusChip`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-19-workforce-capacity-planning-design.md` (Structure-tab section). Plan 3 of 4 — the LAST plan; Plans 1/2/2b are merged.
- **Design (`PRODUCT.md`):** single purple CTA; tinted borderless chips (reuse `LoadStatusChip` from `tabs/load_chip.dart`); 6px radius; 4px grid; `AppTheme.mono(context)` for any numbers; no cyan/sky. The tree is an **indented list**, NOT a connector-line canvas.
- Repo gates on **`flutter analyze` only** — no `dart format`; match surrounding style. Baseline adds ZERO new issues.
- **Plan 1/2 API on `main`:**
  - `org_tree.dart`: `class OrgNode { String id; String? parentId; List<OrgNode> children; }`; `List<OrgNode> buildOrgTree(List<({String id, String? parentId})> people)` (roots = null/absent parent); `bool wouldCreateCycle({required String movingId, required String newParentId, required List<({String id, String? parentId})> people})`.
  - `capacity_math.dart`: `double personLoad(WpPersonLoad, {double? multiplier})`, `LoadStatus loadStatus(double)`.
  - Repo: `reassignTaskOwner(String taskId, String? ownerEmployeeId)`.
  - Providers (`wp_providers.dart`): `wpActiveEmployeesProvider`, `wpPersonLoadsProvider`, `wpTasksProvider`, `wpGrowthMultiplierProvider`. `ownerComputedProvider` is a PUBLIC family in `tabs/role_view_tab.dart`. `employeeListProvider(const EmployeeListQuery())` (from `employee_repository.dart`) is what `wpActiveEmployeesProvider` reads.
  - `LoadStatusChip(status: LoadStatus)` in `tabs/load_chip.dart`.
  - `Employee` fields: `id`, `firstName`, `lastName`, `jobTitle`, `reportsToId`.
- **STALE-DATA obligation:** after a task drop → invalidate `wpTasksProvider` + `wpPersonLoadsProvider` + `ownerComputedProvider`. After a reporting drop → invalidate `employeeListProvider(const EmployeeListQuery())` (rebuilds the tree). HR/Admin gate is the route guard (no inline check).
- `employees.reports_to_id` is already HR/Admin-writable (policy `employees_admin_write`, `20260423000004`) — **no migration needed**.
- **GUI-smoke caveat:** drag gestures can't be fully exercised in widget tests. The pure drop-decision logic is unit-tested and the tree render is widget-tested; the actual drag/drop interaction needs a manual GUI smoke pass (flagged, not a merge blocker for the logic).

---

## File Structure

**Create:**
- `lib/features/workforce_planning/structure_rows.dart` — `reportingDropError(...)` (pure).
- `test/features/workforce_planning/structure_rows_test.dart`
- `test/features/workforce_planning/structure_tab_test.dart`

**Modify:**
- `lib/data/repositories/employee_repository.dart` — add `updateReportsTo`.
- `lib/features/workforce_planning/tabs/structure_tab.dart` — placeholder → the draggable tree.

---

### Task 1: Reporting write + drop-decision helper

**Files:**
- Modify: `lib/data/repositories/employee_repository.dart`
- Create: `lib/features/workforce_planning/structure_rows.dart`
- Test: `test/features/workforce_planning/structure_rows_test.dart`

**Interfaces:**
- Produces: `EmployeeRepository.updateReportsTo(String employeeId, String? managerId)`; `String? reportingDropError({required String movingId, required String newParentId, required List<({String id, String? parentId})> people})` (null = OK to apply; else an error message).

- [ ] **Step 1: Write the failing test**

`test/features/workforce_planning/structure_rows_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/workforce_planning/structure_rows.dart';

void main() {
  final people = <({String id, String? parentId})>[
    (id: 'ceo', parentId: null),
    (id: 'coo', parentId: 'ceo'),
    (id: 'gm', parentId: 'coo'),
    (id: 'ops', parentId: 'ceo'),
  ];

  test('rejects dropping a person onto themselves', () {
    expect(reportingDropError(movingId: 'coo', newParentId: 'coo', people: people),
        "A person can't report to themselves.");
  });
  test('rejects a move that would create a reporting loop', () {
    expect(reportingDropError(movingId: 'coo', newParentId: 'gm', people: people),
        'That would create a reporting loop.');
  });
  test('allows a valid re-parent', () {
    expect(reportingDropError(movingId: 'gm', newParentId: 'ops', people: people), isNull);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/workforce_planning/structure_rows_test.dart`
Expected: FAIL — undefined `reportingDropError`.

- [ ] **Step 3: Write `structure_rows.dart`**

```dart
import 'org_tree.dart';

/// Error message for a reporting drag (make [movingId] report to [newParentId]),
/// or null when the move is valid and should be applied. Guards self-parenting
/// and cycles (dropping a manager under one of its own descendants). A drop onto
/// the current manager is a harmless idempotent write and returns null.
String? reportingDropError({
  required String movingId,
  required String newParentId,
  required List<({String id, String? parentId})> people,
}) {
  if (movingId == newParentId) return "A person can't report to themselves.";
  if (wouldCreateCycle(movingId: movingId, newParentId: newParentId, people: people)) {
    return 'That would create a reporting loop.';
  }
  return null;
}
```

- [ ] **Step 4: Add `updateReportsTo` to `employee_repository.dart`**

Next to `archive` (`employee_repository.dart:66`), add:
```dart
  /// Sets an employee's manager (or clears it when [managerId] is null). Used by
  /// the Workforce Planning Structure tab's reporting drag. HR/Admin-gated by the
  /// employees table's `employees_admin_write` RLS policy.
  Future<void> updateReportsTo(String employeeId, String? managerId) async {
    await _client
        .from('employees')
        .update({'reports_to_id': managerId})
        .eq('id', employeeId);
  }
```

- [ ] **Step 5: Run tests + analyze**

Run: `flutter test test/features/workforce_planning/structure_rows_test.dart`
Expected: PASS (3).
Run: `flutter analyze lib/features/workforce_planning/structure_rows.dart lib/data/repositories/employee_repository.dart test/features/workforce_planning/structure_rows_test.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/features/workforce_planning/structure_rows.dart lib/data/repositories/employee_repository.dart test/features/workforce_planning/structure_rows_test.dart
git commit -m "feat(workforce): reporting drop-decision helper + updateReportsTo"
```

---

### Task 2: Structure tab (draggable org tree)

**Files:**
- Modify: `lib/features/workforce_planning/tabs/structure_tab.dart`
- Test: `test/features/workforce_planning/structure_tab_test.dart`

**Interfaces:**
- Consumes: `wpActiveEmployeesProvider`, `wpPersonLoadsProvider`, `wpTasksProvider`, `wpGrowthMultiplierProvider`, `buildOrgTree`, `reportingDropError`, `capacity_math.personLoad`, `LoadStatusChip`, `workforcePlanningRepositoryProvider.reassignTaskOwner`, `employeeRepositoryProvider.updateReportsTo`, `ownerComputedProvider` + `employeeListProvider` (for invalidation).
- Produces: `StructureTab` — the draggable, indented org tree.

- [ ] **Step 1: Write the failing widget test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/tabs/structure_tab.dart';
import 'package:payroll_flutter/features/workforce_planning/wp_providers.dart';

Employee _emp(String id, String first, String last, String? mgr) => Employee(
      id: id, companyId: 'c', employeeNumber: id, firstName: first, lastName: last,
      jobTitle: 'Role', reportsToId: mgr, employmentType: 'FULL_TIME',
      employmentStatus: 'ACTIVE', hireDate: DateTime(2024, 1, 1), isRankAndFile: true,
      isOtEligible: false, isNdEligible: false, isHolidayPayEligible: false,
      sssEligibilityOverride: false, philhealthEligibilityOverride: false,
      pagibigEligibilityOverride: false, taxOnFullEarnings: false);

void main() {
  testWidgets('renders the reporting tree (manager + report)', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        wpActiveEmployeesProvider.overrideWith((ref) async =>
            [_emp('ceo', 'Cy', 'Oh', null), _emp('coo', 'Coo', 'Boss', 'ceo')]),
        wpPersonLoadsProvider.overrideWith((ref) async => const []),
        wpTasksProvider.overrideWith((ref) async => const []),
        wpConfigProvider.overrideWith((ref) async => null),
      ],
      child: const MaterialApp(home: Scaffold(body: StructureTab())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Cy Oh'), findsOneWidget);
    expect(find.text('Coo Boss'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/workforce_planning/structure_tab_test.dart`
Expected: FAIL — placeholder text only.

- [ ] **Step 3: Implement `structure_tab.dart`**

A `ConsumerStatefulWidget` holding `Set<String> _expanded` (default: all root ids expanded). Build:
1. Watch the 4 providers; `.isLoading`/`.error` gates like `balance_tab.dart`.
2. `final employees = empsAsync.asData!.value;` build `people = [for (final e in employees) (id: e.id, parentId: e.reportsToId)]`, `roots = buildOrgTree(people)`, and maps: `empById` (id→Employee), `loadById` (id→WpPersonLoad from loads), `tasksByOwner` (ownerEmployeeId→List<WpTask> from wpTasks where ownerEmployeeId != null).
3. Render `SingleChildScrollView(padding: 16, child: Column(children: [for (final r in roots) ..._nodeWidgets(r, 0)]))`.
4. `_nodeWidgets(OrgNode node, int depth)` returns a list: the person row, then (if expanded) its task chips + its children's widgets (recursion), each indented `depth * 24`.
5. **Person row** = a `DragTarget<Object>` whose `builder` returns a `Draggable<_PersonPayload>`:
   ```dart
   DragTarget<Object>(
     onAcceptWithDetails: (d) => _onDrop(d.data, node.id, people),
     builder: (ctx, cand, rej) {
       final hovering = cand.isNotEmpty;
       return Draggable<_PersonPayload>(
         data: _PersonPayload(node.id),
         feedback: Material(child: _card(emp, load, dragging: true)),
         childWhenDragging: Opacity(opacity: 0.4, child: _card(emp, load)),
         child: Container(
           decoration: hovering ? BoxDecoration(border: Border.all(color: Theme.of(ctx).colorScheme.primary), borderRadius: BorderRadius.circular(6)) : null,
           child: _row(node, emp, load, depth, hasKids: node.children.isNotEmpty || tasks.isNotEmpty),
         ),
       );
     },
   )
   ```
   The row shows an expand caret (`IconButton`, toggles `_expanded`), name (`${e.firstName} ${e.lastName}`), job title (muted), and `LoadStatusChip(status: loadStatus(personLoad(load, multiplier: mult)))` when a load row exists.
6. **Task chip** (shown under an expanded node) = `Draggable<_TaskPayload>(data: _TaskPayload(task.id), feedback: Material(child: Chip(label: Text(task.name))), childWhenDragging: ..., child: Chip(label: Text(task.name)))` — laid out in a `Wrap`, indented `(depth+1)*24`.
7. `_onDrop(Object data, String targetPersonId, List<({String id, String? parentId})> people)`:
   ```dart
   Future<void> _onDrop(Object data, String targetId, List<({String id, String? parentId})> people) async {
     try {
       if (data is _TaskPayload) {
         await ref.read(workforcePlanningRepositoryProvider).reassignTaskOwner(data.taskId, targetId);
         ref.invalidate(wpTasksProvider);
         ref.invalidate(wpPersonLoadsProvider);
         ref.invalidate(ownerComputedProvider);
       } else if (data is _PersonPayload) {
         final err = reportingDropError(movingId: data.employeeId, newParentId: targetId, people: people);
         if (err != null) { _snack(err); return; }
         await ref.read(employeeRepositoryProvider).updateReportsTo(data.employeeId, targetId);
         ref.invalidate(employeeListProvider(const EmployeeListQuery()));
       }
     } catch (e) {
       _snack('Could not apply the change: $e');
     }
   }
   ```
   `_snack(msg)` guards `if (!mounted) return;` then `ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)))`.
8. Define the payloads at file scope: `class _TaskPayload { final String taskId; const _TaskPayload(this.taskId); }` and `class _PersonPayload { final String employeeId; const _PersonPayload(this.employeeId); }`.

Import: `../structure_rows.dart`, `../org_tree.dart`, `../capacity_math.dart`, `../wp_providers.dart`, `load_chip.dart`, `role_view_tab.dart` (for `ownerComputedProvider`), `../../../data/repositories/{workforce_planning_repository,employee_repository}.dart`, `../../../data/models/{employee,workforce_planning}.dart`, `../../../app/theme.dart`. Use `AppTheme.mono` for any numeric shown. Keep `_card`/`_row` helpers small; if the file exceeds ~230 lines that's acceptable for a recursive drag tree, but keep the payload classes + `_onDrop` + node builder clearly separated.

- [ ] **Step 4: Run the test + analyze + full suite**

Run: `flutter test test/features/workforce_planning/structure_tab_test.dart` → PASS (render test).
Run: `flutter analyze lib/features/workforce_planning/tabs/structure_tab.dart test/features/workforce_planning/structure_tab_test.dart` → clean.
Run: `flutter test` → full suite green.

- [ ] **Step 5: Commit**

```bash
git add lib/features/workforce_planning/tabs/structure_tab.dart test/features/workforce_planning/structure_tab_test.dart
git commit -m "feat(workforce): Structure tab — draggable org tree (transfer + restructure)"
```

---

## Self-Review

**Spec coverage (Structure tab):**
- Indented expandable org tree from `reports_to_id` → Task 2 (`buildOrgTree` + recursive render). ✓
- Drag a responsibility onto another person → reassigns owner → Task 2 `_onDrop` (`_TaskPayload` → `reassignTaskOwner` + invalidation). ✓
- Drag a person under a new manager → `reports_to_id` → Task 2 (`_PersonPayload` → `reportingDropError` guard → `updateReportsTo` + invalidation). ✓
- Cycle guard (`wouldCreateCycle` via `reportingDropError`) + self-parent guard → Task 1. ✓
- Load% chip per node (reuse `LoadStatusChip`); no connector canvas (indented tree) → Task 2. ✓
- No migration (reporting write already HR/Admin-permitted). ✓
- **Flagged:** drag gestures need a manual GUI smoke (widget tests cover render + the pure drop-decision; the `Draggable`/`DragTarget` interaction and the `feedback`/`childWhenDragging` overlays are the parts a running app must confirm).

**Placeholder scan:** none — full widget + helper + repo code given. The one runtime-sensitive area (drag/drop) is called out for GUI smoke, not left as a TODO.

**Type consistency:** `reportingDropError` signature matches its test + the Task 2 caller; `_TaskPayload`/`_PersonPayload` used consistently in `Draggable.data` and `_onDrop`; `buildOrgTree`/`OrgNode`/`wouldCreateCycle` used as defined on `main`; `updateReportsTo`/`reassignTaskOwner`/provider names match Plan 1/2; invalidation targets match the stale-data obligation (task drop → task providers; reporting drop → `employeeListProvider`).

**Open item for the implementer (Task 2):** `Draggable` inside a `SingleChildScrollView` can conflict on vertical drag — if the tree needs to scroll AND drag vertically, prefer `LongPressDraggable` (press-and-hold to start a drag, leaving normal scroll intact). Use `LongPressDraggable` for the person rows and task chips if the plain `Draggable` fights the scroll under `flutter analyze`/manual testing; both have the same `data`/`feedback`/`child` API.
