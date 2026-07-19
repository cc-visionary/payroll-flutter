# Workforce Capacity Planning — Structure Tab + Org Chart (Plan 3 of 4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** A shared `OrgTreeView` widget that powers (a) the `/org-chart` screen — a working read-only reporting tree, replacing its *Coming Soon* stub — and (b) the Workforce Planning **Structure tab** — the same tree, draggable: drag a responsibility onto another person to reassign its owner, and drag a person under a different manager to restructure reporting, with a cycle guard.

**Architecture:** `OrgTreeView` builds an indented, expandable tree from `employees.reports_to_id` via the Plan 1 `buildOrgTree`, with optional per-node `trailing` (load chip), `nodeWrapper` (drag/drop), and `expandedExtras` (task chips) hooks. `/org-chart` uses the bare read-only form; the Structure tab supplies the hooks. Drop decisions run through the pure `reportingDropError` (Plan 1 `wouldCreateCycle`); writes go through `reassignTaskOwner` (Plan 1 repo) and a new `updateReportsTo` (employee repo). Every write invalidates the read providers.

**Tech Stack:** Flutter (Material 3, Riverpod, `Draggable`/`DragTarget`), Plan 1 `org_tree`/`capacity_math`, Plan 2 `wp_providers` + `LoadStatusChip`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-19-workforce-capacity-planning-design.md`. Plan 3 of 4 — the LAST; Plans 1/2/2b are merged and **the migrations are applied to prod**. This plan folds in the user's "integrate the org chart + remove Coming Soon where it works" ask (Org Chart only; Assets/Compensation stay stubs — no feature behind them).
- **Design (`PRODUCT.md`):** single purple CTA; reuse `LoadStatusChip` (`tabs/load_chip.dart`); 6px radius; indented tree (NOT a connector-line canvas); `AppTheme.mono` for numbers; no cyan/sky.
- Repo gates on **`flutter analyze` only**; add ZERO new issues. Match surrounding style.
- **Plan 1/2 API on `main`:** `org_tree.dart` (`OrgNode`, `buildOrgTree`, `wouldCreateCycle`); `capacity_math.personLoad`/`loadStatus`; repo `reassignTaskOwner(String, String?)`; providers `wpActiveEmployeesProvider`/`wpPersonLoadsProvider`/`wpTasksProvider`/`wpGrowthMultiplierProvider`; `ownerComputedProvider` (public family in `tabs/role_view_tab.dart`); `employeeListProvider(const EmployeeListQuery())` (from `employee_repository.dart`, what `wpActiveEmployeesProvider` reads); `LoadStatusChip(status:)`. `Employee` fields `id`/`firstName`/`lastName`/`jobTitle`/`reportsToId`.
- **STALE-DATA obligation:** task drop → invalidate `wpTasksProvider`+`wpPersonLoadsProvider`+`ownerComputedProvider`; reporting drop → invalidate `employeeListProvider(const EmployeeListQuery())`.
- `employees.reports_to_id` is already HR/Admin-writable (`employees_admin_write`, `20260423000004`) — no migration.
- `/org-chart` is visible to ALL users (`shell.dart` nav `_always`, no router HR-guard) → the org-chart view shows only name/title/reporting (NO load% or task data — that's the HR-only Structure tab).
- **GUI-smoke caveat (accepted by the user):** drag gestures can't be fully exercised in widget tests. Pure drop-decision logic is unit-tested; the tree render (both consumers) is widget-tested; the drag/drop interaction needs a manual GUI smoke pass.

---

## File Structure

**Create:**
- `lib/features/workforce_planning/org_tree_view.dart` — `OrgTreeView` shared widget.
- `lib/features/workforce_planning/structure_rows.dart` — `reportingDropError` (pure).
- `test/features/workforce_planning/structure_rows_test.dart`
- `test/features/workforce_planning/org_tree_view_test.dart`
- `test/features/workforce_planning/structure_tab_test.dart`

**Modify:**
- `lib/data/repositories/employee_repository.dart` — add `updateReportsTo`.
- `lib/features/org_chart/org_chart_screen.dart` — `ComingSoon` → read-only `OrgTreeView`.
- `lib/features/workforce_planning/tabs/structure_tab.dart` — placeholder → draggable `OrgTreeView`.

---

### Task 1: Reporting write + drop-decision helper

**Files:**
- Modify: `lib/data/repositories/employee_repository.dart`
- Create: `lib/features/workforce_planning/structure_rows.dart`
- Test: `test/features/workforce_planning/structure_rows_test.dart`

**Interfaces:**
- Produces: `EmployeeRepository.updateReportsTo(String employeeId, String? managerId)`; `String? reportingDropError({required String movingId, required String newParentId, required List<({String id, String? parentId})> people})` (null = OK; else an error message).

- [ ] **Step 1: Write the failing test** — `test/features/workforce_planning/structure_rows_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/workforce_planning/structure_rows.dart';

void main() {
  final people = <({String id, String? parentId})>[
    (id: 'ceo', parentId: null), (id: 'coo', parentId: 'ceo'),
    (id: 'gm', parentId: 'coo'), (id: 'ops', parentId: 'ceo'),
  ];
  test('rejects self-drop', () {
    expect(reportingDropError(movingId: 'coo', newParentId: 'coo', people: people),
        "A person can't report to themselves.");
  });
  test('rejects a reporting loop', () {
    expect(reportingDropError(movingId: 'coo', newParentId: 'gm', people: people),
        'That would create a reporting loop.');
  });
  test('allows a valid re-parent', () {
    expect(reportingDropError(movingId: 'gm', newParentId: 'ops', people: people), isNull);
  });
}
```

- [ ] **Step 2: Run to verify it fails** — `flutter test test/features/workforce_planning/structure_rows_test.dart` → FAIL (undefined).

- [ ] **Step 3: Write `structure_rows.dart`**
```dart
import 'org_tree.dart';

/// Error for a reporting drag (make [movingId] report to [newParentId]), or null
/// when valid. Guards self-parenting and cycles. A drop on the current manager is
/// a harmless idempotent write and returns null.
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

- [ ] **Step 4: Add `updateReportsTo` to `employee_repository.dart`** — next to `archive`:
```dart
  /// Sets an employee's manager (or clears it when [managerId] is null). Used by
  /// the Workforce Planning Structure tab's reporting drag. HR/Admin-gated by the
  /// employees table's `employees_admin_write` RLS policy.
  Future<void> updateReportsTo(String employeeId, String? managerId) async {
    await _client.from('employees').update({'reports_to_id': managerId}).eq('id', employeeId);
  }
```

- [ ] **Step 5: Tests + analyze** — `flutter test .../structure_rows_test.dart` → PASS (3); `flutter analyze lib/features/workforce_planning/structure_rows.dart lib/data/repositories/employee_repository.dart test/features/workforce_planning/structure_rows_test.dart` → clean.

- [ ] **Step 6: Commit**
```bash
git add lib/features/workforce_planning/structure_rows.dart lib/data/repositories/employee_repository.dart test/features/workforce_planning/structure_rows_test.dart
git commit -m "feat(workforce): reporting drop-decision helper + updateReportsTo"
```

---

### Task 2: Shared `OrgTreeView` + read-only Org Chart (remove Coming Soon)

**Files:**
- Create: `lib/features/workforce_planning/org_tree_view.dart`
- Modify: `lib/features/org_chart/org_chart_screen.dart`
- Test: `test/features/workforce_planning/org_tree_view_test.dart`

**Interfaces:**
- Produces: `class OrgTreeView extends StatefulWidget` with:
  ```dart
  OrgTreeView({
    required List<({String id, String? parentId})> people,
    required Map<String, Employee> empById,
    Widget Function(Employee emp)? trailing,               // e.g. a load chip
    Widget Function(Employee emp, Widget row)? nodeWrapper, // e.g. Draggable/DragTarget
    List<Widget> Function(Employee emp)? expandedExtras,    // e.g. task chips (shown when expanded)
  })
  ```
  It builds `buildOrgTree(people)`, holds a `Set<String> _expanded` (roots start expanded), and renders each node indented `depth*24`: a caret (shown when the node has children OR non-empty `expandedExtras`), the person's `First Last` + muted job title, and `trailing?(emp)`. When expanded, it renders `expandedExtras?(emp)` (indented) then the children recursively. `nodeWrapper?(emp, row)` wraps each person row (defaults to the row itself).

- [ ] **Step 1: Write the failing test** — `test/features/workforce_planning/org_tree_view_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/features/workforce_planning/org_tree_view.dart';

Employee _e(String id, String f, String l, String? mgr) => Employee(
      id: id, companyId: 'c', employeeNumber: id, firstName: f, lastName: l,
      jobTitle: 'Role $id', reportsToId: mgr, employmentType: 'FULL_TIME',
      employmentStatus: 'ACTIVE', hireDate: DateTime(2024, 1, 1), isRankAndFile: true,
      isOtEligible: false, isNdEligible: false, isHolidayPayEligible: false,
      sssEligibilityOverride: false, philhealthEligibilityOverride: false,
      pagibigEligibilityOverride: false, taxOnFullEarnings: false);

void main() {
  testWidgets('renders the reporting hierarchy (manager + report)', (tester) async {
    final emps = {'ceo': _e('ceo', 'Cy', 'Oh', null), 'coo': _e('coo', 'Coo', 'Boss', 'ceo')};
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: OrgTreeView(
      people: const [(id: 'ceo', parentId: null), (id: 'coo', parentId: 'ceo')],
      empById: emps,
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Cy Oh'), findsOneWidget);
    expect(find.text('Coo Boss'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to verify it fails** — FAIL (undefined `OrgTreeView`).

- [ ] **Step 3: Implement `org_tree_view.dart`**

A `StatefulWidget` (state holds `late Set<String> _expanded` initialised to the root ids in `initState`). `build`: `final roots = buildOrgTree(widget.people);` then `SingleChildScrollView(padding: 16, child: Column(crossAxisAlignment: start, children: [for (final r in roots) ..._nodes(r, 0)]))`. `_nodes(OrgNode node, int depth)`:
```dart
List<Widget> _nodes(OrgNode node, int depth) {
  final emp = widget.empById[node.id];
  final extras = widget.expandedExtras?.call(emp!) ?? const <Widget>[];
  final hasKids = node.children.isNotEmpty || extras.isNotEmpty;
  final expanded = _expanded.contains(node.id);
  final row = Padding(
    padding: EdgeInsets.only(left: depth * 24.0, top: 2, bottom: 2),
    child: Row(children: [
      SizedBox(width: 28, child: hasKids
        ? IconButton(visualDensity: VisualDensity.compact, iconSize: 20,
            icon: Icon(expanded ? Icons.expand_more : Icons.chevron_right),
            onPressed: () => setState(() => expanded ? _expanded.remove(node.id) : _expanded.add(node.id)))
        : null),
      if (emp != null) ...[
        Text('${emp.firstName} ${emp.lastName}', style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        Flexible(child: Text(emp.jobTitle ?? '', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12), overflow: TextOverflow.ellipsis)),
      ] else Text(node.id),
      if (emp != null && widget.trailing != null) ...[const SizedBox(width: 8), widget.trailing!(emp)],
    ]),
  );
  final wrapped = (emp != null && widget.nodeWrapper != null) ? widget.nodeWrapper!(emp, row) : row;
  return [
    wrapped,
    if (expanded) ...[
      if (extras.isNotEmpty)
        Padding(padding: EdgeInsets.only(left: (depth + 1) * 24.0, top: 2, bottom: 6), child: Wrap(spacing: 6, runSpacing: 6, children: extras)),
      for (final c in node.children) ..._nodes(c, depth + 1),
    ],
  ];
}
```
Imports: `package:flutter/material.dart`, `../../data/models/employee.dart`, `org_tree.dart`.

- [ ] **Step 4: Rewrite `org_chart_screen.dart`** to a `ConsumerWidget` that reads employees and renders the read-only tree (removing `ComingSoonScreen`):
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/breakpoints.dart';
import '../../app/shell.dart';
import '../../data/models/employee.dart';
import '../workforce_planning/org_tree_view.dart';
import '../workforce_planning/wp_providers.dart';

/// Live reporting structure across the company, from employees.reports_to_id.
/// Read-only (name + title); the Workforce Planning Structure tab adds load +
/// drag-to-restructure for HR/Admin.
class OrgChartScreen extends ConsumerWidget {
  const OrgChartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final empsAsync = ref.watch(wpActiveEmployeesProvider);
    return Scaffold(
      drawer: isMobile(context) ? const AppDrawer() : null,
      appBar: AppBar(title: const Text('Org Chart')),
      body: empsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
        data: (emps) {
          if (emps.isEmpty) return const Center(child: Text('No employees to show.'));
          final empById = {for (final e in emps) e.id: e};
          final people = [for (final e in emps) (id: e.id, parentId: e.reportsToId)];
          return OrgTreeView(people: people, empById: empById);
        },
      ),
    );
  }
}
```

- [ ] **Step 5: Tests + analyze + full suite**

Run: `flutter test test/features/workforce_planning/org_tree_view_test.dart` → PASS.
Run: `flutter analyze lib/features/workforce_planning/org_tree_view.dart lib/features/org_chart/org_chart_screen.dart test/features/workforce_planning/org_tree_view_test.dart` → clean.
Run: `flutter test` → full suite green. **If a test asserted the old Org Chart "Coming Soon" copy, update it** to the new tree (report the change).

- [ ] **Step 6: Commit**
```bash
git add lib/features/workforce_planning/org_tree_view.dart lib/features/org_chart/org_chart_screen.dart test/features/workforce_planning/org_tree_view_test.dart
git commit -m "feat(org-chart): live reporting tree via shared OrgTreeView (remove Coming Soon)"
```

---

### Task 3: Structure tab (draggable org tree)

**Files:**
- Modify: `lib/features/workforce_planning/tabs/structure_tab.dart`
- Test: `test/features/workforce_planning/structure_tab_test.dart`

**Interfaces:**
- Consumes: `OrgTreeView`, `wpActiveEmployeesProvider`, `wpPersonLoadsProvider`, `wpTasksProvider`, `wpGrowthMultiplierProvider`, `reportingDropError`, `capacity_math.personLoad`/`loadStatus`, `LoadStatusChip`, `reassignTaskOwner`, `updateReportsTo`, `ownerComputedProvider`, `employeeListProvider`.
- Produces: `StructureTab` — the draggable tree.

- [ ] **Step 1: Write the failing widget test** — `test/features/workforce_planning/structure_tab_test.dart` (renders the tree; a manager + report appear). Use the same `Employee` builder helper as `org_tree_view_test.dart`, overriding `wpActiveEmployeesProvider` with `[ceo, coo(reportsTo ceo)]`, `wpPersonLoadsProvider`/`wpTasksProvider` empty, `wpConfigProvider` null; pump `ProviderScope(... child: MaterialApp(home: Scaffold(body: StructureTab())))`; assert both names render.

- [ ] **Step 2: Run to verify it fails** — FAIL (placeholder text).

- [ ] **Step 3: Implement `structure_tab.dart`**

A `ConsumerWidget`. Watch the 4 providers; `.isLoading`/`.error` gates (mirror `balance_tab.dart`). Build `empById`, `people`, `loadById` (employeeId→WpPersonLoad), `tasksByOwner` (ownerEmployeeId→List<WpTask>), and `mult = ref.watch(wpGrowthMultiplierProvider)`. Return `OrgTreeView` with the three hooks:

- `trailing: (emp) { final l = loadById[emp.id]; return l == null ? const SizedBox.shrink() : LoadStatusChip(status: loadStatus(personLoad(l, multiplier: mult))); }`
- `expandedExtras: (emp) => [for (final t in tasksByOwner[emp.id] ?? const <WpTask>[]) Draggable<_TaskPayload>(data: _TaskPayload(t.id), feedback: Material(color: Colors.transparent, child: Chip(label: Text(t.name))), childWhenDragging: Opacity(opacity: 0.4, child: Chip(label: Text(t.name))), child: Chip(label: Text(t.name)))]`
- `nodeWrapper: (emp, row) => DragTarget<Object>(onAcceptWithDetails: (d) => _onDrop(ref, context, d.data, emp.id, people), builder: (ctx, cand, rej) => Draggable<_PersonPayload>(data: _PersonPayload(emp.id), feedback: Material(color: Colors.transparent, child: Card(child: Padding(padding: const EdgeInsets.all(8), child: Text('${emp.firstName} ${emp.lastName}')))), childWhenDragging: Opacity(opacity: 0.4, child: row), child: Container(decoration: cand.isNotEmpty ? BoxDecoration(border: Border.all(color: Theme.of(ctx).colorScheme.primary), borderRadius: BorderRadius.circular(6)) : null, child: row)))`

Payload classes at file scope: `class _TaskPayload { final String taskId; const _TaskPayload(this.taskId); }` and `class _PersonPayload { final String employeeId; const _PersonPayload(this.employeeId); }`.

`_onDrop`:
```dart
Future<void> _onDrop(WidgetRef ref, BuildContext context, Object data, String targetId,
    List<({String id, String? parentId})> people) async {
  void snack(String m) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m))); }
  try {
    if (data is _TaskPayload) {
      await ref.read(workforcePlanningRepositoryProvider).reassignTaskOwner(data.taskId, targetId);
      ref.invalidate(wpTasksProvider);
      ref.invalidate(wpPersonLoadsProvider);
      ref.invalidate(ownerComputedProvider);
    } else if (data is _PersonPayload) {
      if (data.employeeId == targetId) return;
      final err = reportingDropError(movingId: data.employeeId, newParentId: targetId, people: people);
      if (err != null) { snack(err); return; }
      await ref.read(employeeRepositoryProvider).updateReportsTo(data.employeeId, targetId);
      ref.invalidate(employeeListProvider(const EmployeeListQuery()));
    }
  } catch (e) {
    snack('Could not apply the change: $e');
  }
}
```
Imports: `org_tree_view.dart`, `../structure_rows.dart`, `../capacity_math.dart`, `../wp_providers.dart`, `load_chip.dart`, `role_view_tab.dart` (for `ownerComputedProvider`), `../../../data/repositories/{workforce_planning_repository,employee_repository}.dart`, `../../../data/models/{employee,workforce_planning}.dart`.

> **GUI-smoke flag:** `Draggable` inside the `SingleChildScrollView` in `OrgTreeView` can fight vertical scroll. If the manual GUI smoke shows scroll/drag conflict, switch the two `Draggable`s to `LongPressDraggable` (same `data`/`feedback`/`child` API) — press-and-hold to drag, leaving scroll intact.

- [ ] **Step 4: Test + analyze + full suite** — `flutter test .../structure_tab_test.dart` → PASS; `flutter analyze lib/features/workforce_planning/tabs/structure_tab.dart test/...` → clean; `flutter test` → green.

- [ ] **Step 5: Commit**
```bash
git add lib/features/workforce_planning/tabs/structure_tab.dart test/features/workforce_planning/structure_tab_test.dart
git commit -m "feat(workforce): Structure tab — draggable org tree (transfer + restructure)"
```

---

## Self-Review

**Spec + ask coverage:**
- Indented reporting tree from `reports_to_id` → `OrgTreeView` (Task 2). ✓
- **Org Chart integrated + Coming Soon removed** → Task 2 (`/org-chart` renders `OrgTreeView` read-only). ✓ (Assets/Compensation intentionally left as stubs — no feature behind them.)
- Drag a responsibility → reassign owner + invalidate → Task 3 (`_TaskPayload`). ✓
- Drag a person under a manager → `reports_to_id` + guard + invalidate → Tasks 1+3 (`_PersonPayload` → `reportingDropError` → `updateReportsTo`). ✓
- Cycle/self guard → Task 1. Load chip per node (reuse `LoadStatusChip`); no canvas. ✓
- No migration (reporting write already HR/Admin-permitted). ✓
- **Flagged:** drag gestures need a manual GUI smoke (render + drop-decision are tested).

**Placeholder scan:** none — full widget/helper/repo code. The one runtime-sensitive area (drag) is flagged for GUI smoke with a concrete `LongPressDraggable` fallback, not left as a TODO.

**Type consistency:** `reportingDropError` matches its test + the Task 3 caller; `OrgTreeView` hook signatures (`trailing`/`nodeWrapper`/`expandedExtras`) match both consumers (org-chart passes none; Structure passes all three); `_TaskPayload`/`_PersonPayload` consistent in `Draggable.data` + `_onDrop`; `buildOrgTree`/`OrgNode`/`wouldCreateCycle`/`updateReportsTo`/`reassignTaskOwner`/provider names match `main`; invalidation targets match the stale-data obligation.
