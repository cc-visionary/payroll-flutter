# Workforce Capacity Planning — Hub + Load Views (Plan 2 of 4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the `/workforce-planning` *Coming Soon* stub into a 5-tab hub and ship the two read tabs — **Balance** (load-per-person table) and **Role View** (per-person owned tasks + load + KPIs) — reading the Plan 1 backend.

**Architecture:** A `DefaultTabController` hub (HR/Admin-gated, route unchanged) hosts five tabs; this plan fills Balance and Role View and leaves Structure/Tasks/Drivers & Scenario as placeholders (Plans 2b/3). All display math goes through the Plan 1 `capacity_math` calculator; the join/shape logic is extracted into pure, unit-tested view-model builders so the widgets stay thin. Riverpod `FutureProvider`s wrap the Plan 1 repository.

**Tech Stack:** Flutter (Material 3, Riverpod, GoRouter), `AppTheme.mono` for numerics, `ResponsiveTable` for tables, the Plan 1 `workforce_planning_repository` + models + `capacity_math`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-19-workforce-capacity-planning-design.md`. This is Plan 2 of 4: **Plan 1 (Foundation) is merged**; Plan 2b = Tasks CRUD + Drivers & Scenario; Plan 3 = Structure drag-drop.
- **Design system (`PRODUCT.md` / `CLAUDE.md`):** light + dark system-driven; single Luxium purple CTA `#635BFF`/`#7F7DFC` (use `FilledButton` defaults — do NOT introduce cyan/sky accents); **status chips = tinted background + darker text, NO colored border**; 6px radius; 4px spacing grid; **Geist Mono via `AppTheme.mono(context)` for every number/percent/hour**; tables wrapped in `ResponsiveTable` (`lib/widgets/responsive_table.dart`, max 1100px, horizontal-scroll fallback).
- Repo gates on **`flutter analyze` only** — do NOT run `dart format`; match surrounding style. Baseline: 0 errors / 19 warnings / ~171 info pre-existing; add ZERO new issues.
- HR/Admin gate: reuse `ref.watch(userProfileProvider).asData?.value?.isHrOrAdmin`; the `/workforce-planning` route guard already redirects non-HR (`app/router.dart:108`). Mobile drawer via `isMobile(context)` + `const AppDrawer()` (`app/shell.dart`).
- Plan 1 API (already on `main`): repository `workforcePlanningRepositoryProvider` with `personLoads()`, `nodes()`, `drivers()`, `rates()`, `config()`, `tasks()`, `taskComputedForOwner(String)`; models in `lib/data/models/workforce_planning.dart`; `capacity_math.dart` exports `projectedHours(fixed,growingBase,mult)`, `loadFraction(hours,cap)`, `personLoad(WpPersonLoad,{multiplier})`, `loadStatus(fraction)→LoadStatus{under,ok,over}`.
- Employees: `employeeListProvider(const EmployeeListQuery())` → `AsyncValue<List<Employee>>` (fields `id`, `firstName`, `lastName`, `jobTitle`). KPI assignment: `kpiAssignedEmployeesProvider` → `AsyncValue<Map<String,List<KpiAssignee>>>` (kpiId → assignees; `KpiAssignee.employeeId`).
- **Deviation from spec (Role View):** the spec lists a read-only *monthly cost* on Role View. It is **deferred** here — a current-compensation read is its own query and cost belongs with the later payroll-vs-plan phase (Phase C). Role View ships tasks + tier mix + load% + KPIs. (Recorded so the reviewer treats the absence as intentional.)

---

## File Structure

**Create:**
- `lib/features/workforce_planning/balance_rows.dart` — `BalanceRow`, `kpiCountByEmployee(...)`, `buildBalanceRows(...)` (pure).
- `lib/features/workforce_planning/role_view_rows.dart` — `RoleTaskRow`, `buildRoleTaskRows(...)`, `hoursByTier(...)` (pure).
- `lib/features/workforce_planning/wp_providers.dart` — Riverpod `FutureProvider`s.
- `lib/features/workforce_planning/tabs/balance_tab.dart`
- `lib/features/workforce_planning/tabs/role_view_tab.dart`
- `lib/features/workforce_planning/tabs/structure_tab.dart` (placeholder → Plan 3)
- `lib/features/workforce_planning/tabs/tasks_tab.dart` (placeholder → Plan 2b)
- `lib/features/workforce_planning/tabs/drivers_scenario_tab.dart` (placeholder → Plan 2b)
- `test/features/workforce_planning/balance_rows_test.dart`
- `test/features/workforce_planning/role_view_rows_test.dart`
- `test/features/workforce_planning/balance_tab_test.dart`
- `test/features/workforce_planning/role_view_tab_test.dart`

**Modify:**
- `lib/features/workforce_planning/workforce_planning_screen.dart` — replace `ComingSoonScreen` with the tabbed hub.

---

### Task 1: View-model builders (pure, tested)

**Files:**
- Create: `lib/features/workforce_planning/balance_rows.dart`, `lib/features/workforce_planning/role_view_rows.dart`
- Test: `test/features/workforce_planning/balance_rows_test.dart`, `test/features/workforce_planning/role_view_rows_test.dart`

**Interfaces:**
- Produces:
  - `class BalanceRow { final String employeeId, name; final String? roleTitle; final int tasksOwned; final double capacityHours, hoursScaled, loadScaled; final LoadStatus status; final int kpiCount; }`
  - `Map<String,int> kpiCountByEmployee(Map<String,List<KpiAssignee>> assignedByKpi)`
  - `List<BalanceRow> buildBalanceRows({required List<WpPersonLoad> loads, required Map<String,({String name, String? title})> employeeById, required Map<String,int> kpiCounts, required double multiplier})` — sorted by `loadScaled` desc.
  - `class RoleTaskRow { final String name; final String? nodeName, cadence, skillTier, risk; final double hoursScaled; }`
  - `List<RoleTaskRow> buildRoleTaskRows({required List<WpTask> ownerTasks, required Map<String,WpTaskComputed> computedById, required Map<String,String> nodeNameById, required double multiplier})`
  - `Map<String,double> hoursByTier(List<RoleTaskRow> rows)` — tier→sum hours (null tier → key `'Untiered'`).

- [ ] **Step 1: Write the failing tests**

`test/features/workforce_planning/balance_rows_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';
import 'package:payroll_flutter/features/workforce_planning/balance_rows.dart';
import 'package:payroll_flutter/features/workforce_planning/capacity_math.dart';

void main() {
  test('kpiCountByEmployee counts distinct kpis per employee', () {
    final byKpi = {
      'k1': const [KpiAssignee(employeeId: 'e1', name: 'A'), KpiAssignee(employeeId: 'e2', name: 'B')],
      'k2': const [KpiAssignee(employeeId: 'e1', name: 'A')],
    };
    expect(kpiCountByEmployee(byKpi), {'e1': 2, 'e2': 1});
  });

  test('buildBalanceRows joins, computes scaled load, sorts desc, defaults missing', () {
    final loads = [
      const WpPersonLoad(employeeId: 'e1', companyId: 'c', tasksOwned: 2,
          hoursFixed: 2, hoursGrowingBase: 20, capacityHours: 160, growthMultiplier: 1),
      const WpPersonLoad(employeeId: 'e2', companyId: 'c', tasksOwned: 1,
          hoursFixed: 10, hoursGrowingBase: 0, capacityHours: 160, growthMultiplier: 1),
    ];
    final rows = buildBalanceRows(
      loads: loads,
      employeeById: {'e1': (name: 'Marvin', title: 'Sys')},
      kpiCounts: {'e1': 4},
      multiplier: 2,
    );
    expect(rows.first.employeeId, 'e1'); // higher load first
    expect(rows.first.hoursScaled, 42);  // 2 + 20*2
    expect(rows.first.loadScaled, 42 / 160);
    expect(rows.first.status, LoadStatus.under); // 0.2625
    expect(rows.first.kpiCount, 4);
    final e2 = rows.firstWhere((r) => r.employeeId == 'e2');
    expect(e2.name, 'e2');   // no employee record → id fallback
    expect(e2.roleTitle, isNull);
    expect(e2.kpiCount, 0);
  });
}
```

`test/features/workforce_planning/role_view_rows_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/role_view_rows.dart';

void main() {
  final tasks = [
    const WpTask(id: 't1', companyId: 'c', name: 'SD flash', nodeId: 'n2',
        cadence: 'Per-unit', skillTier: 'Transactional', risk: 'Medium'),
    const WpTask(id: 't2', companyId: 'c', name: 'Vet', nodeId: 'n0',
        cadence: 'Monthly', skillTier: 'Strategic', risk: 'High'),
  ];
  final computed = {
    't1': const WpTaskComputed(taskId: 't1', companyId: 'c', isGrowing: true,
        timesPerMonthBase: 100, minutesEach: 12, hoursPerMonthBase: 20),
    't2': const WpTaskComputed(taskId: 't2', companyId: 'c', isGrowing: false,
        timesPerMonthBase: 4, minutesEach: 30, hoursPerMonthBase: 2),
  };

  test('buildRoleTaskRows scales only growing tasks and names nodes', () {
    final rows = buildRoleTaskRows(
      ownerTasks: tasks, computedById: computed,
      nodeNameById: {'n2': '2. Configure', 'n0': '0. Opportunity gate'},
      multiplier: 2,
    );
    final flash = rows.firstWhere((r) => r.name == 'SD flash');
    expect(flash.nodeName, '2. Configure');
    expect(flash.hoursScaled, 40); // growing: 20 * 2
    final vet = rows.firstWhere((r) => r.name == 'Vet');
    expect(vet.hoursScaled, 2);    // fixed
  });

  test('hoursByTier sums by tier', () {
    final rows = buildRoleTaskRows(
      ownerTasks: tasks, computedById: computed, nodeNameById: const {}, multiplier: 1);
    final byTier = hoursByTier(rows);
    expect(byTier['Transactional'], 20);
    expect(byTier['Strategic'], 2);
  });
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/features/workforce_planning/balance_rows_test.dart test/features/workforce_planning/role_view_rows_test.dart`
Expected: FAIL — undefined `buildBalanceRows` / `buildRoleTaskRows`.

- [ ] **Step 3: Write `balance_rows.dart`**

```dart
import '../../data/models/workforce_planning.dart';
import '../../data/repositories/role_scorecard_repository.dart' show KpiAssignee;
import 'capacity_math.dart';

class BalanceRow {
  final String employeeId;
  final String name;
  final String? roleTitle;
  final int tasksOwned;
  final double capacityHours;
  final double hoursScaled;
  final double loadScaled;
  final LoadStatus status;
  final int kpiCount;
  const BalanceRow({
    required this.employeeId,
    required this.name,
    required this.roleTitle,
    required this.tasksOwned,
    required this.capacityHours,
    required this.hoursScaled,
    required this.loadScaled,
    required this.status,
    required this.kpiCount,
  });
}

/// employeeId -> number of distinct KPIs they are tracked on.
Map<String, int> kpiCountByEmployee(Map<String, List<KpiAssignee>> assignedByKpi) {
  final out = <String, int>{};
  for (final assignees in assignedByKpi.values) {
    for (final a in assignees) {
      out[a.employeeId] = (out[a.employeeId] ?? 0) + 1;
    }
  }
  return out;
}

/// Joins per-person aggregates to display info and projects load at [multiplier].
/// Sorted by scaled load descending (most-loaded first). Missing employee record
/// falls back to the id as name and a null role.
List<BalanceRow> buildBalanceRows({
  required List<WpPersonLoad> loads,
  required Map<String, ({String name, String? title})> employeeById,
  required Map<String, int> kpiCounts,
  required double multiplier,
}) {
  final rows = <BalanceRow>[];
  for (final l in loads) {
    final emp = employeeById[l.employeeId];
    final hours = projectedHours(l.hoursFixed, l.hoursGrowingBase, multiplier);
    final frac = loadFraction(hours, l.capacityHours);
    rows.add(BalanceRow(
      employeeId: l.employeeId,
      name: emp?.name ?? l.employeeId,
      roleTitle: emp?.title,
      tasksOwned: l.tasksOwned,
      capacityHours: l.capacityHours,
      hoursScaled: hours,
      loadScaled: frac,
      status: loadStatus(frac),
      kpiCount: kpiCounts[l.employeeId] ?? 0,
    ));
  }
  rows.sort((a, b) => b.loadScaled.compareTo(a.loadScaled));
  return rows;
}
```

- [ ] **Step 4: Write `role_view_rows.dart`**

```dart
import '../../data/models/workforce_planning.dart';
import 'capacity_math.dart';

class RoleTaskRow {
  final String name;
  final String? nodeName;
  final String? cadence;
  final String? skillTier;
  final String? risk;
  final double hoursScaled;
  const RoleTaskRow({
    required this.name,
    required this.nodeName,
    required this.cadence,
    required this.skillTier,
    required this.risk,
    required this.hoursScaled,
  });
}

/// Builds display rows for one person's owned tasks, projecting hours at
/// [multiplier] (only driver-bound growing tasks scale). Tasks with no computed
/// row (shouldn't happen for owned tasks) fall back to 0 hours.
List<RoleTaskRow> buildRoleTaskRows({
  required List<WpTask> ownerTasks,
  required Map<String, WpTaskComputed> computedById,
  required Map<String, String> nodeNameById,
  required double multiplier,
}) {
  final rows = <RoleTaskRow>[];
  for (final t in ownerTasks) {
    final c = computedById[t.id];
    final base = c?.hoursPerMonthBase ?? 0;
    final growing = c?.isGrowing ?? false;
    final hours = growing ? base * multiplier : base;
    rows.add(RoleTaskRow(
      name: t.name,
      nodeName: t.nodeId == null ? null : nodeNameById[t.nodeId],
      cadence: t.cadence,
      skillTier: t.skillTier,
      risk: t.risk,
      hoursScaled: hours,
    ));
  }
  return rows;
}

/// Sum of scaled hours by skill tier; null tier grouped under 'Untiered'.
Map<String, double> hoursByTier(List<RoleTaskRow> rows) {
  final out = <String, double>{};
  for (final r in rows) {
    final key = r.skillTier ?? 'Untiered';
    out[key] = (out[key] ?? 0) + r.hoursScaled;
  }
  return out;
}
```

- [ ] **Step 5: Run to verify tests pass**

Run: `flutter test test/features/workforce_planning/balance_rows_test.dart test/features/workforce_planning/role_view_rows_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 6: Analyze + commit**

Run: `flutter analyze lib/features/workforce_planning/balance_rows.dart lib/features/workforce_planning/role_view_rows.dart`
Expected: `No issues found!`
```bash
git add lib/features/workforce_planning/balance_rows.dart lib/features/workforce_planning/role_view_rows.dart test/features/workforce_planning/balance_rows_test.dart test/features/workforce_planning/role_view_rows_test.dart
git commit -m "feat(workforce): pure view-model builders for balance + role view"
```

---

### Task 2: Providers

**Files:**
- Create: `lib/features/workforce_planning/wp_providers.dart`

**Interfaces:**
- Consumes: Task 1 (`kpiCountByEmployee`), Plan 1 repo, `employeeListProvider`, `kpiAssignedEmployeesProvider`.
- Produces: `wpPersonLoadsProvider`, `wpNodesProvider`, `wpDriversProvider`, `wpRatesProvider`, `wpConfigProvider`, `wpTasksProvider`, `wpActiveEmployeesProvider` (`FutureProvider<List<Employee>>`), `wpKpiCountByEmployeeProvider` (`FutureProvider<Map<String,int>>`), and `wpGrowthMultiplierProvider` (`Provider<double>` reading `wpConfigProvider`, default 1.0). Thin glue — no unit test (verified by `flutter analyze` + consumed in Tasks 4–5's widget tests).

- [ ] **Step 1: Write `wp_providers.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/employee.dart';
import '../../data/models/workforce_planning.dart';
import '../../data/repositories/employee_repository.dart';
import '../../data/repositories/role_scorecard_repository.dart';
import '../../data/repositories/workforce_planning_repository.dart';
import 'balance_rows.dart';

final wpPersonLoadsProvider = FutureProvider<List<WpPersonLoad>>(
    (ref) => ref.watch(workforcePlanningRepositoryProvider).personLoads());

final wpNodesProvider = FutureProvider<List<WpNode>>(
    (ref) => ref.watch(workforcePlanningRepositoryProvider).nodes());

final wpDriversProvider = FutureProvider<List<WpDriver>>(
    (ref) => ref.watch(workforcePlanningRepositoryProvider).drivers());

final wpRatesProvider = FutureProvider<List<WpRate>>(
    (ref) => ref.watch(workforcePlanningRepositoryProvider).rates());

final wpConfigProvider = FutureProvider<WpConfig?>(
    (ref) => ref.watch(workforcePlanningRepositoryProvider).config());

final wpTasksProvider = FutureProvider<List<WpTask>>(
    (ref) => ref.watch(workforcePlanningRepositoryProvider).tasks());

final wpActiveEmployeesProvider = FutureProvider<List<Employee>>((ref) =>
    ref.watch(employeeListProvider(const EmployeeListQuery()).future));

final wpKpiCountByEmployeeProvider = FutureProvider<Map<String, int>>((ref) async {
  final byKpi = await ref.watch(kpiAssignedEmployeesProvider.future);
  return kpiCountByEmployee(byKpi);
});

/// The stored growth multiplier (default 1.0 when no config row yet). Kept
/// separate so the Balance/Role-View tabs can watch just the number.
final wpGrowthMultiplierProvider = Provider<double>((ref) =>
    ref.watch(wpConfigProvider).asData?.value?.growthMultiplier ?? 1.0);
```

- [ ] **Step 2: Analyze + commit**

Run: `flutter analyze lib/features/workforce_planning/wp_providers.dart`
Expected: `No issues found!`
```bash
git add lib/features/workforce_planning/wp_providers.dart
git commit -m "feat(workforce): riverpod providers for the planning hub"
```

---

### Task 3: Hub scaffold + tab placeholders

**Files:**
- Modify: `lib/features/workforce_planning/workforce_planning_screen.dart`
- Create: `lib/features/workforce_planning/tabs/{balance_tab,role_view_tab,structure_tab,tasks_tab,drivers_scenario_tab}.dart`

**Interfaces:**
- Produces: `WorkforcePlanningScreen` (tabbed hub); `BalanceTab`, `RoleViewTab`, `StructureTab`, `TasksTab`, `DriversScenarioTab` (each `ConsumerWidget`). This task ships all five as simple placeholders; Tasks 4–5 replace Balance/RoleView bodies. Structure/Tasks/Drivers stay placeholders (Plans 2b/3).

- [ ] **Step 1: Write the five placeholder tab widgets**

Each file (substitute the class name + label), e.g. `tabs/balance_tab.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BalanceTab extends ConsumerWidget {
  const BalanceTab({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      const Center(child: Text('Balance'));
}
```
Create the analogous `RoleViewTab` (`role_view_tab.dart`), `TasksTab` (`tasks_tab.dart`, text `'Tasks — available in a later update'`), `DriversScenarioTab` (`drivers_scenario_tab.dart`, text `'Drivers & Scenario — available in a later update'`), and `StructureTab` (`structure_tab.dart`, text `'Structure — available in a later update'`).

- [ ] **Step 2: Rewrite the hub screen**

Replace the entire body of `lib/features/workforce_planning/workforce_planning_screen.dart` with:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/breakpoints.dart';
import '../../app/shell.dart';
import '../auth/profile_provider.dart';
import 'tabs/balance_tab.dart';
import 'tabs/drivers_scenario_tab.dart';
import 'tabs/role_view_tab.dart';
import 'tabs/structure_tab.dart';
import 'tabs/tasks_tab.dart';

/// Workforce Planning hub. HR/Admin-only (route guard in app/router.dart also
/// redirects). Five tabs; Balance + Role View are live, the rest are filled by
/// later plans. See docs/superpowers/specs/2026-07-19-workforce-capacity-planning-design.md.
class WorkforcePlanningScreen extends ConsumerWidget {
  const WorkforcePlanningScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mobile = isMobile(context);
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        drawer: mobile ? const AppDrawer() : null,
        appBar: AppBar(
          title: const Text('Workforce Planning'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Balance'),
              Tab(text: 'Role View'),
              Tab(text: 'Structure'),
              Tab(text: 'Tasks'),
              Tab(text: 'Drivers & Scenario'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            BalanceTab(),
            RoleViewTab(),
            StructureTab(),
            TasksTab(),
            DriversScenarioTab(),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Verify it compiles + full suite**

Run: `flutter analyze lib/features/workforce_planning/ && flutter test`
Expected: analyze clean on the folder; full suite passes (still 763 — no test changes yet).

- [ ] **Step 4: Commit**

```bash
git add lib/features/workforce_planning/workforce_planning_screen.dart lib/features/workforce_planning/tabs/
git commit -m "feat(workforce): tabbed planning hub + tab placeholders"
```

---

### Task 4: Balance tab

**Files:**
- Modify: `lib/features/workforce_planning/tabs/balance_tab.dart`
- Test: `test/features/workforce_planning/balance_tab_test.dart`

**Interfaces:**
- Consumes: `wpPersonLoadsProvider`, `wpActiveEmployeesProvider`, `wpKpiCountByEmployeeProvider`, `wpGrowthMultiplierProvider`, `buildBalanceRows`, `capacity_math.LoadStatus`.
- Produces: the `BalanceTab` load-per-person table.

- [ ] **Step 1: Write the failing widget test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/tabs/balance_tab.dart';
import 'package:payroll_flutter/features/workforce_planning/wp_providers.dart';

Employee _emp(String id, String first, String last, String title) => Employee(
      id: id, companyId: 'c', employeeNumber: id, firstName: first,
      lastName: last, jobTitle: title, employmentType: 'FULL_TIME',
      employmentStatus: 'ACTIVE', hireDate: DateTime(2024, 1, 1),
      isRankAndFile: true, isOtEligible: false, isNdEligible: false,
      isHolidayPayEligible: false, sssEligibilityOverride: false,
      philhealthEligibilityOverride: false, pagibigEligibilityOverride: false,
      taxOnFullEarnings: false);

void main() {
  testWidgets('renders one row per person with an Over chip for >100%', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        wpPersonLoadsProvider.overrideWith((ref) async => const [
          WpPersonLoad(employeeId: 'e1', companyId: 'c', tasksOwned: 6,
              hoursFixed: 210, hoursGrowingBase: 0, capacityHours: 160, growthMultiplier: 1),
        ]),
        wpActiveEmployeesProvider.overrideWith((ref) async => [_emp('e1', 'Marvin', 'Ong', 'Sys')]),
        wpKpiCountByEmployeeProvider.overrideWith((ref) async => {'e1': 4}),
        wpConfigProvider.overrideWith((ref) async => null),
      ],
      child: const MaterialApp(home: Scaffold(body: BalanceTab())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Marvin Ong'), findsOneWidget);
    expect(find.text('Over'), findsOneWidget);   // 210/160 = 131%
    expect(find.text('131%'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/workforce_planning/balance_tab_test.dart`
Expected: FAIL — finds `'Balance'` placeholder, not `'Marvin Ong'`.

- [ ] **Step 3: Implement `balance_tab.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../widgets/responsive_table.dart';
import '../balance_rows.dart';
import '../capacity_math.dart';
import '../wp_providers.dart';

class BalanceTab extends ConsumerWidget {
  const BalanceTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loadsAsync = ref.watch(wpPersonLoadsProvider);
    final empsAsync = ref.watch(wpActiveEmployeesProvider);
    final kpiAsync = ref.watch(wpKpiCountByEmployeeProvider);
    final multiplier = ref.watch(wpGrowthMultiplierProvider);

    if (loadsAsync.isLoading || empsAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final err = loadsAsync.error ?? empsAsync.error;
    if (err != null) {
      return Center(child: Text('Error: $err', style: const TextStyle(color: Colors.red)));
    }
    final employeeById = {
      for (final e in empsAsync.asData!.value)
        e.id: (name: '${e.firstName} ${e.lastName}', title: e.jobTitle),
    };
    final rows = buildBalanceRows(
      loads: loadsAsync.asData!.value,
      employeeById: employeeById,
      kpiCounts: kpiAsync.asData?.value ?? const {},
      multiplier: multiplier,
    );
    if (rows.isEmpty) {
      return const Center(child: Text('No active people to show.'));
    }
    final showProjected = multiplier != 1.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: ResponsiveTable(
        child: DataTable(
          columns: [
            const DataColumn(label: Text('Person')),
            const DataColumn(label: Text('Role')),
            const DataColumn(label: Text('Tasks'), numeric: true),
            const DataColumn(label: Text('Hours/mo'), numeric: true),
            const DataColumn(label: Text('Capacity'), numeric: true),
            DataColumn(label: Text(showProjected ? 'Load (proj.)' : 'Load'), numeric: true),
            const DataColumn(label: Text('Status')),
            const DataColumn(label: Text('KPIs'), numeric: true),
          ],
          rows: [
            for (final r in rows)
              DataRow(cells: [
                DataCell(Text(r.name)),
                DataCell(Text(r.roleTitle ?? '—')),
                DataCell(Text('${r.tasksOwned}', style: AppTheme.mono(context))),
                DataCell(Text(r.hoursScaled.toStringAsFixed(1), style: AppTheme.mono(context))),
                DataCell(Text(r.capacityHours.toStringAsFixed(0), style: AppTheme.mono(context))),
                DataCell(Text('${(r.loadScaled * 100).round()}%', style: AppTheme.mono(context))),
                DataCell(_LoadChip(status: r.status)),
                DataCell(Text('${r.kpiCount}', style: AppTheme.mono(context))),
              ]),
          ],
        ),
      ),
    );
  }
}

/// Tinted status chip (no border) per PRODUCT.md.
class _LoadChip extends StatelessWidget {
  final LoadStatus status;
  const _LoadChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (String label, Color base) = switch (status) {
      LoadStatus.over => ('Over', Colors.red),
      LoadStatus.ok => ('OK', Colors.green),
      LoadStatus.under => ('Under', Colors.orange),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: base.withValues(alpha: dark ? 0.22 : 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: dark ? base.withValues(alpha: 0.95) : base.shade700 as Color?)),
    );
  }
}
```
> Note on the chip text color: `Colors.red`/`green`/`orange` are `MaterialColor`, so `base` above is typed `Color`; to use `.shade700`, keep a `MaterialColor` local instead. Implement the color as: declare `final MaterialColor base` in the switch (the three literals are all `MaterialColor`), and set text color `dark ? base.shade200 : base.shade700`. Adjust the pattern-match binding accordingly so it type-checks under `flutter analyze`.

- [ ] **Step 4: Run the test + analyze**

Run: `flutter test test/features/workforce_planning/balance_tab_test.dart`
Expected: PASS.
Run: `flutter analyze lib/features/workforce_planning/tabs/balance_tab.dart`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/workforce_planning/tabs/balance_tab.dart test/features/workforce_planning/balance_tab_test.dart
git commit -m "feat(workforce): Balance tab — load-per-person table"
```

---

### Task 5: Role View tab

**Files:**
- Modify: `lib/features/workforce_planning/tabs/role_view_tab.dart`
- Test: `test/features/workforce_planning/role_view_tab_test.dart`

**Interfaces:**
- Consumes: `wpActiveEmployeesProvider`, `wpNodesProvider`, `wpPersonLoadsProvider`, `wpGrowthMultiplierProvider`, the repo's `taskComputedForOwner` + `tasks()` (via a small family provider added here), `employeeAssignedKpiIdsProvider`, `roleKpisProvider`/`kpiLibraryProvider` for KPI names, `buildRoleTaskRows`, `hoursByTier`, `personLoad`.
- Produces: `RoleViewTab` — a person picker driving an owned-tasks table + tier summary + load% + KPI chips.

- [ ] **Step 1: Add a per-owner computed provider (top of `role_view_tab.dart`)**

```dart
final _ownerComputedProvider =
    FutureProvider.family<List<WpTaskComputed>, String>((ref, employeeId) =>
        ref.watch(workforcePlanningRepositoryProvider).taskComputedForOwner(employeeId));
```

- [ ] **Step 2: Write the failing widget test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/tabs/role_view_tab.dart';
import 'package:payroll_flutter/features/workforce_planning/wp_providers.dart';

Employee _emp(String id, String first, String last) => Employee(
      id: id, companyId: 'c', employeeNumber: id, firstName: first, lastName: last,
      jobTitle: 'Sys', employmentType: 'FULL_TIME', employmentStatus: 'ACTIVE',
      hireDate: DateTime(2024, 1, 1), isRankAndFile: true, isOtEligible: false,
      isNdEligible: false, isHolidayPayEligible: false, sssEligibilityOverride: false,
      philhealthEligibilityOverride: false, pagibigEligibilityOverride: false,
      taxOnFullEarnings: false);

void main() {
  testWidgets('picking a person shows their owned tasks', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        wpActiveEmployeesProvider.overrideWith((ref) async => [_emp('e1', 'Marvin', 'Ong')]),
        wpNodesProvider.overrideWith((ref) async => const [
          WpNode(id: 'n2', companyId: 'c', code: '2', name: '2. Configure')]),
        wpPersonLoadsProvider.overrideWith((ref) async => const [
          WpPersonLoad(employeeId: 'e1', companyId: 'c', tasksOwned: 1,
              hoursFixed: 0, hoursGrowingBase: 20, capacityHours: 160, growthMultiplier: 1)]),
        wpTasksProvider.overrideWith((ref) async => const [
          WpTask(id: 't1', companyId: 'c', name: 'SD flash', nodeId: 'n2',
              ownerEmployeeId: 'e1', cadence: 'Per-unit', skillTier: 'Transactional')]),
        wpConfigProvider.overrideWith((ref) async => null),
      ],
      child: const MaterialApp(home: Scaffold(body: RoleViewTab())),
    ));
    await tester.pumpAndSettle();
    // Person auto-selected (single person) or via dropdown default:
    expect(find.text('SD flash'), findsOneWidget);
    expect(find.text('2. Configure'), findsOneWidget);
  });
}
```
> The `_ownerComputedProvider` is `family`; override it in the test with `_ownerComputedProvider('e1').overrideWith((ref) async => const [WpTaskComputed(taskId:'t1', companyId:'c', hoursPerMonthBase: 20, isGrowing: true, skillTier:'Transactional')])`. Import it from the tab file (make it non-private or expose a public alias for the test) — simplest: name it `ownerComputedProvider` (public) so the test can override it.

- [ ] **Step 3: Run to verify it fails**

Run: `flutter test test/features/workforce_planning/role_view_tab_test.dart`
Expected: FAIL — placeholder text only.

- [ ] **Step 4: Implement `role_view_tab.dart`**

A `ConsumerStatefulWidget` holding the selected `employeeId` (default: first active employee). Body:
1. `wpActiveEmployeesProvider` → a `DropdownButton<String>` of "First Last".
2. On a selection, watch `ownerComputedProvider(id)` + `wpTasksProvider` (filter `ownerEmployeeId == id`) + `wpNodesProvider` (→ `nodeNameById`) + `wpGrowthMultiplierProvider`; build rows via `buildRoleTaskRows`, and `hoursByTier`.
3. Load %: find the person's `WpPersonLoad` in `wpPersonLoadsProvider` and show `personLoad(load, multiplier: multiplier)` as a percent + a `_LoadChip` (extract `_LoadChip` from `balance_tab.dart` into a shared `tabs/load_chip.dart` and import it in both — do this refactor as part of this task so it isn't duplicated).
4. Owned-tasks `DataTable` in `ResponsiveTable`: Node · Task · Cadence · Hrs/mo · Tier · Risk (mono for hours).
5. Tier summary: a `Wrap` of small chips "Tier: N.N h" from `hoursByTier`.
6. KPIs: `employeeAssignedKpiIdsProvider(id)` intersected with the role, mapped to names via `kpiLibraryProvider`; render as a `Wrap` of `Chip`s, or "No KPIs assigned". (Reuse the exact provider names from `role_scorecard_repository.dart`; if the assigned-ids provider needs the role scorecard id, resolve it from the employee — mirror how `role_tab.dart`'s `EmployeeKpiAssignmentSection` reads them.)

Write the complete widget following the `balance_tab.dart` structure (async `.isLoading`/`.error` guards, `AppTheme.mono` for numbers, 16px padding). Keep the file focused; if it exceeds ~200 lines, that's acceptable for a tab with a picker + three sections, but extract `_LoadChip`/tier-chip helpers to `tabs/load_chip.dart`.

- [ ] **Step 5: Run the test + analyze + full suite**

Run: `flutter test test/features/workforce_planning/role_view_tab_test.dart`
Expected: PASS.
Run: `flutter analyze && flutter test`
Expected: analyze adds no new issues; full suite green (768 = 763 + 4 view-model + 1 balance-tab; adjust for the exact new count).

- [ ] **Step 6: Commit**

```bash
git add lib/features/workforce_planning/tabs/role_view_tab.dart lib/features/workforce_planning/tabs/load_chip.dart test/features/workforce_planning/role_view_tab_test.dart lib/features/workforce_planning/tabs/balance_tab.dart
git commit -m "feat(workforce): Role View tab — owned tasks, tier mix, load, KPIs"
```

---

## Self-Review

**Spec coverage (this plan = Hub + Balance + Role View):**
- Hub with tabs → Task 3 (5 tabs; Structure/Tasks/Drivers placeholders for Plans 2b/3). ✓
- Balance table (person · role · tasks · hours · capacity · load% · status chip · KPI count, sortable-by-load) → Tasks 1+4 (sorted desc in `buildBalanceRows`; projected column when multiplier≠1). ✓
- Role View (owned tasks, tier mix, load%, KPIs) → Tasks 1+5. Monthly cost **deliberately deferred** (documented in Global Constraints). ✓
- Reads real data (employees, KPI assignment, Plan 1 backend) → Task 2 providers. ✓
- Design system (mono numerics, tinted borderless chips, ResponsiveTable, purple CTA) → Tasks 4–5. ✓
- Deferred correctly: Tasks CRUD + Drivers & Scenario (Plan 2b), Structure drag-drop (Plan 3), growth-multiplier control (Plan 2b — until then `wpGrowthMultiplierProvider` reads the stored value / default 1.0, so Balance/Role View already honor a non-1 multiplier if one is set in the DB).

**Placeholder scan:** none. The `_LoadChip` MaterialColor typing caveat and the `ownerComputedProvider` visibility note are called out inline with the exact fix.

**Type consistency:** `BalanceRow`/`RoleTaskRow` fields match their builders and the widget cells; provider names (`wpPersonLoadsProvider`, `wpActiveEmployeesProvider`, `wpKpiCountByEmployeeProvider`, `wpGrowthMultiplierProvider`, `wpNodesProvider`, `wpTasksProvider`, `ownerComputedProvider`) are used identically in Tasks 2/4/5 and their tests. `capacity_math` (`projectedHours`, `loadFraction`, `loadStatus`, `personLoad`, `LoadStatus`) and Plan 1 model field names are used as defined on `main`.

**Open item for the implementer (Task 5):** confirm the exact `employeeAssignedKpiIdsProvider` signature and role-scorecard resolution by reading `role_tab.dart`'s `EmployeeKpiAssignmentSection` before wiring the KPI section — the plan intentionally points at that precedent rather than guessing the family argument.
