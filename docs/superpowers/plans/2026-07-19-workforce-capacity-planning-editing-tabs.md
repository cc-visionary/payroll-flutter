# Workforce Capacity Planning — Editing Tabs (Plan 2b of 4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Fill the two editing tabs of the Workforce Planning hub — **Tasks** (task inventory CRUD, incl. owner assignment) and **Drivers & Scenario** (drivers/rates CRUD + the growth-multiplier control) — so the load numbers become editable and the mostly-unowned seed can be assigned in-app.

**Architecture:** A reusable stateful `TaskFormDialog` (fed dropdown data by its caller, returns a `WpTask`) drives create/edit; the Tasks tab lists/filters/deletes and persists via the Plan 1 repository; the Drivers & Scenario tab manages drivers/rates via small dialogs plus a multiplier control writing `wp_config`. Every write invalidates the read providers so the Balance/Role View tabs never show stale data. Validation logic is a pure, unit-tested function.

**Tech Stack:** Flutter (Material 3, Riverpod), the Plan 1 `workforce_planning_repository` + models, Plan 2's `wp_providers`, `AppTheme.mono`, `ResponsiveTable`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-19-workforce-capacity-planning-design.md`. Plan 2b of 4: **Plans 1 (backend) + 2 (hub + read tabs) are merged**; Plan 3 = Structure drag-drop.
- **Design system (`PRODUCT.md`):** single Luxium purple CTA (`FilledButton` defaults, no cyan/sky); `AppTheme.mono(context)` for every number/hour/percent; 6px radius; `ResponsiveTable` for tables; tinted borderless chips (reuse `StatusChip` if a chip is needed).
- Repo gates on **`flutter analyze` only** — no `dart format`; match surrounding style (`kpi_form_dialog.dart` for dialogs, `kpi_library_screen.dart` for list+CRUD+SnackBar, `attendance_edit_dialog.dart` for `DropdownButtonFormField<String?>`).
- **Plan 1 repo writes** (on `main`): `saveTask(WpTask)` (insert when `id==''`, else update by id — `toUpsert` already nulls the unused times/minutes source field), `deleteTask(String id)`, `saveDriver(WpDriver)`, `saveRate(WpRate)`, `setGrowthMultiplier(String companyId, double m)`. Models in `lib/data/models/workforce_planning.dart`.
- **Plan 2 providers** (on `main`, `lib/features/workforce_planning/wp_providers.dart`): `wpTasksProvider`, `wpNodesProvider`, `wpDriversProvider`, `wpRatesProvider`, `wpConfigProvider`, `wpActiveEmployeesProvider`, `wpPersonLoadsProvider`, `wpGrowthMultiplierProvider`. `ownerComputedProvider` is a PUBLIC family in `lib/features/workforce_planning/tabs/role_view_tab.dart`.
- **STALE-DATA OBLIGATION (from Plan 2's final review):** these providers are NOT autoDispose. After ANY write you MUST `ref.invalidate`:
  - after `saveTask`/`deleteTask`: `wpTasksProvider`, `wpPersonLoadsProvider`, `ownerComputedProvider` (whole family).
  - after `saveDriver`/`saveRate`/`setGrowthMultiplier`: the matching list provider (`wpDriversProvider`/`wpRatesProvider`/`wpConfigProvider`) AND `wpPersonLoadsProvider` + `ownerComputedProvider` (hours depend on drivers/rates/config through the views).
- `companyId` for new rows: `ref.watch(userProfileProvider).asData?.value?.companyId` (pattern in `kpi_library_screen.dart:26`). HR/Admin gate is the existing route guard — no inline check needed.
- These tabs replace the placeholder bodies of `tasks_tab.dart` / `drivers_scenario_tab.dart` (created in Plan 2); the hub already wires them.

---

## File Structure

**Create:**
- `lib/features/workforce_planning/tabs/task_form_dialog.dart` — `TaskFormDialog` + pure `validateTaskForm(...)`.
- `test/features/workforce_planning/task_form_dialog_test.dart`
- `test/features/workforce_planning/tasks_tab_test.dart`
- `test/features/workforce_planning/drivers_scenario_tab_test.dart`

**Modify:**
- `lib/features/workforce_planning/tabs/tasks_tab.dart` — placeholder → list + CRUD.
- `lib/features/workforce_planning/tabs/drivers_scenario_tab.dart` — placeholder → drivers/rates CRUD + multiplier.

---

### Task 1: Task form dialog + validation

**Files:**
- Create: `lib/features/workforce_planning/tabs/task_form_dialog.dart`
- Test: `test/features/workforce_planning/task_form_dialog_test.dart`

**Interfaces:**
- Produces:
  - `String? validateTaskForm({required String name, required String timesSource, String? driverId, required String minutesSource, String? rateId})` — returns an error string or null.
  - `class TaskFormDialog extends StatefulWidget` — constructor `TaskFormDialog({WpTask? existing, required String companyId, required List<WpNode> nodes, required List<WpDriver> drivers, required List<WpRate> rates, required List<Employee> employees})`; returns a `WpTask?` via `Navigator.pop`.

- [ ] **Step 1: Write the failing tests**

`test/features/workforce_planning/task_form_dialog_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/tabs/task_form_dialog.dart';

void main() {
  test('validateTaskForm requires a name', () {
    expect(validateTaskForm(name: '', timesSource: 'manual', minutesSource: 'manual'),
        'Name is required.');
  });
  test('validateTaskForm requires a driver when times source is driver', () {
    expect(
        validateTaskForm(name: 'x', timesSource: 'driver', driverId: null, minutesSource: 'manual'),
        'Pick a driver (or switch Times to Manual).');
  });
  test('validateTaskForm requires a rate when minutes source is rate', () {
    expect(
        validateTaskForm(name: 'x', timesSource: 'manual', minutesSource: 'rate', rateId: null),
        'Pick a rate (or switch Minutes to Manual).');
  });
  test('validateTaskForm passes when complete', () {
    expect(
        validateTaskForm(name: 'x', timesSource: 'driver', driverId: 'd1', minutesSource: 'rate', rateId: 'r1'),
        isNull);
  });

  testWidgets('dialog shows the name-required error on empty Save', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () => showDialog<WpTask>(
            context: context,
            builder: (_) => const TaskFormDialog(
                companyId: 'c', nodes: [], drivers: [], rates: [], employees: []),
          ),
          child: const Text('open'),
        );
      })),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Name is required.'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/features/workforce_planning/task_form_dialog_test.dart`
Expected: FAIL — undefined `validateTaskForm` / `TaskFormDialog`.

- [ ] **Step 3: Implement `task_form_dialog.dart`**

```dart
import 'package:flutter/material.dart';

import '../../../data/models/employee.dart';
import '../../../data/models/workforce_planning.dart';

const _tiers = ['Transactional', 'Operational', 'Managerial', 'Strategic'];
const _risks = ['Low', 'Medium', 'High'];

/// Validates the task form. Returns an error message, or null when OK.
String? validateTaskForm({
  required String name,
  required String timesSource,
  String? driverId,
  required String minutesSource,
  String? rateId,
}) {
  if (name.trim().isEmpty) return 'Name is required.';
  if (timesSource == 'driver' && (driverId == null || driverId.isEmpty)) {
    return 'Pick a driver (or switch Times to Manual).';
  }
  if (minutesSource == 'rate' && (rateId == null || rateId.isEmpty)) {
    return 'Pick a rate (or switch Minutes to Manual).';
  }
  return null;
}

/// Create/edit dialog for a `wp_tasks` row. Caller supplies the dropdown data
/// (nodes/drivers/rates/employees) and persists the returned [WpTask] via
/// `WorkforcePlanningRepository.saveTask`, then invalidates the read providers.
class TaskFormDialog extends StatefulWidget {
  final WpTask? existing;
  final String companyId;
  final List<WpNode> nodes;
  final List<WpDriver> drivers;
  final List<WpRate> rates;
  final List<Employee> employees;
  const TaskFormDialog({
    super.key,
    this.existing,
    required this.companyId,
    required this.nodes,
    required this.drivers,
    required this.rates,
    required this.employees,
  });

  @override
  State<TaskFormDialog> createState() => _TaskFormDialogState();
}

class _TaskFormDialogState extends State<TaskFormDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _brand = TextEditingController(text: widget.existing?.brandScope ?? '');
  late final _cadence = TextEditingController(text: widget.existing?.cadence ?? '');
  late final _capability = TextEditingController(text: widget.existing?.capability ?? '');
  late final _timesManual = TextEditingController(
      text: widget.existing?.timesManual?.toString() ?? '');
  late final _driverFactor = TextEditingController(
      text: (widget.existing?.driverFactor ?? 1).toString());
  late final _minutesManual = TextEditingController(
      text: widget.existing?.minutesManual?.toString() ?? '');

  late String _timesSource = widget.existing?.timesSource ?? 'manual';
  late String _minutesSource = widget.existing?.minutesSource ?? 'manual';
  late String? _nodeId = widget.existing?.nodeId;
  late String? _driverId = widget.existing?.driverId;
  late String? _rateId = widget.existing?.rateId;
  late String? _tier = widget.existing?.skillTier;
  late String? _risk = widget.existing?.risk;
  late String? _ownerId = widget.existing?.ownerEmployeeId;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _brand, _cadence, _capability, _timesManual, _driverFactor, _minutesManual]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final err = validateTaskForm(
      name: _name.text,
      timesSource: _timesSource,
      driverId: _driverId,
      minutesSource: _minutesSource,
      rateId: _rateId,
    );
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    final task = WpTask(
      id: widget.existing?.id ?? '',
      companyId: widget.existing?.companyId ?? widget.companyId,
      name: _name.text.trim(),
      nodeId: _nodeId,
      brandScope: _brand.text.trim().isEmpty ? null : _brand.text.trim(),
      cadence: _cadence.text.trim().isEmpty ? null : _cadence.text.trim(),
      timesSource: _timesSource,
      timesManual: _timesSource == 'manual' ? double.tryParse(_timesManual.text.trim()) : null,
      driverId: _timesSource == 'driver' ? _driverId : null,
      driverFactor: double.tryParse(_driverFactor.text.trim()) ?? 1,
      minutesSource: _minutesSource,
      minutesManual: _minutesSource == 'manual' ? double.tryParse(_minutesManual.text.trim()) : null,
      rateId: _minutesSource == 'rate' ? _rateId : null,
      skillTier: _tier,
      risk: _risk,
      capability: _capability.text.trim().isEmpty ? null : _capability.text.trim(),
      ownerEmployeeId: _ownerId,
      externalRef: widget.existing?.externalRef,
    );
    Navigator.pop(context, task);
  }

  InputDecoration _dec(String label) =>
      InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'New task' : 'Edit task'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: _name, autofocus: true, decoration: _dec('Name')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _nodeId,
              decoration: _dec('Value-chain node'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('— None —')),
                ...widget.nodes.map((n) => DropdownMenuItem<String?>(value: n.id, child: Text(n.name))),
              ],
              onChanged: (v) => setState(() => _nodeId = v),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: _brand, decoration: _dec('Brand / scope'))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _cadence, decoration: _dec('Cadence (label)'))),
            ]),
            const SizedBox(height: 16),
            // Times source
            Text('Times per month', style: Theme.of(context).textTheme.labelLarge),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'manual', label: Text('Manual')),
                ButtonSegment(value: 'driver', label: Text('Driver')),
              ],
              selected: {_timesSource},
              onSelectionChanged: (s) => setState(() => _timesSource = s.first),
            ),
            const SizedBox(height: 8),
            if (_timesSource == 'manual')
              TextField(controller: _timesManual, keyboardType: TextInputType.number, decoration: _dec('Times / month'))
            else
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: _driverId,
                    decoration: _dec('Driver'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('— Pick —')),
                      ...widget.drivers.map((d) => DropdownMenuItem<String?>(value: d.id, child: Text(d.name))),
                    ],
                    onChanged: (v) => setState(() => _driverId = v),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(width: 110, child: TextField(controller: _driverFactor, keyboardType: TextInputType.number, decoration: _dec('× factor'))),
              ]),
            const SizedBox(height: 16),
            // Minutes source
            Text('Minutes each', style: Theme.of(context).textTheme.labelLarge),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'manual', label: Text('Manual')),
                ButtonSegment(value: 'rate', label: Text('Rate')),
              ],
              selected: {_minutesSource},
              onSelectionChanged: (s) => setState(() => _minutesSource = s.first),
            ),
            const SizedBox(height: 8),
            if (_minutesSource == 'manual')
              TextField(controller: _minutesManual, keyboardType: TextInputType.number, decoration: _dec('Minutes each'))
            else
              DropdownButtonFormField<String?>(
                initialValue: _rateId,
                decoration: _dec('Rate'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('— Pick —')),
                  ...widget.rates.map((r) => DropdownMenuItem<String?>(value: r.id, child: Text(r.name))),
                ],
                onChanged: (v) => setState(() => _rateId = v),
              ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _tier,
                  decoration: _dec('Skill tier'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('— None —')),
                    ..._tiers.map((t) => DropdownMenuItem<String?>(value: t, child: Text(t))),
                  ],
                  onChanged: (v) => setState(() => _tier = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _risk,
                  decoration: _dec('Risk'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('— None —')),
                    ..._risks.map((r) => DropdownMenuItem<String?>(value: r, child: Text(r))),
                  ],
                  onChanged: (v) => setState(() => _risk = v),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(controller: _capability, decoration: _dec('Capability requirement')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _ownerId,
              decoration: _dec('Owner'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('— Unassigned —')),
                ...widget.employees.map((e) =>
                    DropdownMenuItem<String?>(value: e.id, child: Text('${e.firstName} ${e.lastName}'))),
              ],
              onChanged: (v) => setState(() => _ownerId = v),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
```

- [ ] **Step 4: Run tests + analyze**

Run: `flutter test test/features/workforce_planning/task_form_dialog_test.dart`
Expected: PASS (4 unit + 1 widget).
Run: `flutter analyze lib/features/workforce_planning/tabs/task_form_dialog.dart test/features/workforce_planning/task_form_dialog_test.dart`
Expected: `No issues found!` (if `SegmentedButton` or `initialValue` flags on this Flutter version, adjust: `initialValue`→`value` for `DropdownButtonFormField` if needed — match what `attendance_edit_dialog.dart` uses, which is `initialValue`).

- [ ] **Step 5: Commit**

```bash
git add lib/features/workforce_planning/tabs/task_form_dialog.dart test/features/workforce_planning/task_form_dialog_test.dart
git commit -m "feat(workforce): task create/edit form dialog + validation"
```

---

### Task 2: Tasks tab (list + CRUD)

**Files:**
- Modify: `lib/features/workforce_planning/tabs/tasks_tab.dart`
- Test: `test/features/workforce_planning/tasks_tab_test.dart`

**Interfaces:**
- Consumes: `wpTasksProvider`, `wpNodesProvider`, `wpDriversProvider`, `wpRatesProvider`, `wpActiveEmployeesProvider`, `userProfileProvider`, `TaskFormDialog`, `workforcePlanningRepositoryProvider`, `ownerComputedProvider` (imported from `role_view_tab.dart` for invalidation).
- Produces: `TasksTab` — a task list with New/Edit/Delete.

- [ ] **Step 1: Write the failing widget test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/tabs/tasks_tab.dart';
import 'package:payroll_flutter/features/workforce_planning/wp_providers.dart';

void main() {
  testWidgets('lists tasks with owner name and node', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        wpTasksProvider.overrideWith((ref) async => const [
          WpTask(id: 't1', companyId: 'c', name: 'SD flash', nodeId: 'n2',
              ownerEmployeeId: 'e1'),
        ]),
        wpNodesProvider.overrideWith((ref) async => const [
          WpNode(id: 'n2', companyId: 'c', code: '2', name: '2. Configure')]),
        wpDriversProvider.overrideWith((ref) async => const []),
        wpRatesProvider.overrideWith((ref) async => const []),
        wpActiveEmployeesProvider.overrideWith((ref) async => const []),
      ],
      child: const MaterialApp(home: Scaffold(body: TasksTab())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('SD flash'), findsOneWidget);
    expect(find.text('2. Configure'), findsWidgets);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/workforce_planning/tasks_tab_test.dart`
Expected: FAIL — placeholder text.

- [ ] **Step 3: Implement `tasks_tab.dart`**

A `ConsumerWidget` that:
1. Watches `wpTasksProvider` + `wpNodesProvider` (+ drivers/rates/employees for the dialog). `.isLoading`/`.error` gates like `balance_tab.dart`.
2. Renders a `DataTable` in `ResponsiveTable`: Task · Node · Owner · Cadence · (edit / delete icon buttons per row). Node name from a `{nodeId: name}` map; owner name from an employees map (or "Unassigned").
3. An AppBar-less "New task" `FilledButton.icon` at the top of the tab body (a `Padding` + `Align(topRight)`).
4. New/Edit → `showDialog<WpTask>(context, builder: (_) => TaskFormDialog(existing: …, companyId: companyId, nodes: …, drivers: …, rates: …, employees: …))`. On non-null result: `await ref.read(workforcePlanningRepositoryProvider).saveTask(result)` inside try/catch → on error `ScaffoldMessenger` SnackBar → on success invalidate `wpTasksProvider`, `wpPersonLoadsProvider`, and `ownerComputedProvider`.
5. Delete → an `AlertDialog` confirm (mirror `kpi_library_screen._confirmDeactivate`) → `repo.deleteTask(id)` → same three invalidations.
6. `companyId` via `userProfileProvider`; disable "New task" when null.

Write the complete widget following `kpi_library_screen.dart`'s structure (async `.when` or `.isLoading`/`.error`, SnackBar error handling, `ref.invalidate`). Import `ownerComputedProvider` from `'role_view_tab.dart'`. Use `AppTheme.mono` for any numeric column shown.

- [ ] **Step 4: Run the test + analyze + full suite**

Run: `flutter test test/features/workforce_planning/tasks_tab_test.dart` → PASS.
Run: `flutter analyze lib/features/workforce_planning/tabs/tasks_tab.dart test/features/workforce_planning/tasks_tab_test.dart` → clean.
Run: `flutter test` → full suite green.

- [ ] **Step 5: Commit**

```bash
git add lib/features/workforce_planning/tabs/tasks_tab.dart test/features/workforce_planning/tasks_tab_test.dart
git commit -m "feat(workforce): Tasks tab — inventory CRUD + owner assignment"
```

---

### Task 3: Drivers & Scenario tab

**Files:**
- Modify: `lib/features/workforce_planning/tabs/drivers_scenario_tab.dart`
- Test: `test/features/workforce_planning/drivers_scenario_tab_test.dart`

**Interfaces:**
- Consumes: `wpDriversProvider`, `wpRatesProvider`, `wpConfigProvider`, `wpGrowthMultiplierProvider`, `userProfileProvider`, `workforcePlanningRepositoryProvider`, `wpPersonLoadsProvider` + `ownerComputedProvider` (for invalidation).
- Produces: `DriversScenarioTab` — drivers list + rates list (each CRUD) + a growth-multiplier control.

- [ ] **Step 1: Write the failing widget test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/tabs/drivers_scenario_tab.dart';
import 'package:payroll_flutter/features/workforce_planning/wp_providers.dart';

void main() {
  testWidgets('renders drivers, rates, and the current multiplier', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        wpDriversProvider.overrideWith((ref) async => const [
          WpDriver(id: 'd1', companyId: 'c', name: 'Shopee orders', value: 120, grows: true)]),
        wpRatesProvider.overrideWith((ref) async => const [
          WpRate(id: 'r1', companyId: 'c', name: 'SD flash', minutesEach: 12)]),
        wpConfigProvider.overrideWith((ref) async =>
            const WpConfig(companyId: 'c', growthMultiplier: 2, defaultCapacityHours: 160)),
      ],
      child: const MaterialApp(home: Scaffold(body: DriversScenarioTab())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Shopee orders'), findsOneWidget);
    expect(find.text('SD flash'), findsOneWidget);
    expect(find.textContaining('2'), findsWidgets); // multiplier shown
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/workforce_planning/drivers_scenario_tab_test.dart`
Expected: FAIL — placeholder text.

- [ ] **Step 3: Implement `drivers_scenario_tab.dart`**

A `ConsumerWidget` (`.isLoading`/`.error` gates on drivers+rates+config) rendering a scrollable `Column` with three sections:
1. **Scenario** — a card showing the current growth multiplier via `AppTheme.mono`, with a stepper/slider or a small "Set multiplier" button opening an `AlertDialog` with a numeric field. On save: `repo.setGrowthMultiplier(companyId, value)` → invalidate `wpConfigProvider`, `wpPersonLoadsProvider`, `ownerComputedProvider`. (A `Slider` from 0.5–5.0 step 0.5 is fine; label with `AppTheme.mono`.)
2. **Drivers** — a `DataTable`/list (name · value · grows toggle) with New/Edit (a small `_DriverDialog` with name + value + a `SwitchListTile` grows) and delete. Save → `repo.saveDriver(WpDriver(...))` → invalidate `wpDriversProvider`, `wpPersonLoadsProvider`, `ownerComputedProvider`. (No `deleteDriver` in the Plan 1 repo — OMIT driver/rate delete; the model FKs are `on delete set null` but there's no repo delete method, so support only create/edit here and note delete as a follow-up.)
3. **Rates** — same shape (name · minutes) with a `_RateDialog` (name + minutes). Save → `repo.saveRate(...)` → invalidate `wpRatesProvider`, `wpPersonLoadsProvider`, `ownerComputedProvider`.

Follow `kpi_library_screen.dart` for list-row + dialog + SnackBar + invalidation patterns. `companyId` via `userProfileProvider`; disable writes when null. Use `AppTheme.mono` for the multiplier, driver values, and rate minutes.

- [ ] **Step 4: Run the test + analyze + full suite**

Run: `flutter test test/features/workforce_planning/drivers_scenario_tab_test.dart` → PASS.
Run: `flutter analyze && flutter test` → analyze adds no new issues; full suite green.

- [ ] **Step 5: Commit**

```bash
git add lib/features/workforce_planning/tabs/drivers_scenario_tab.dart test/features/workforce_planning/drivers_scenario_tab_test.dart
git commit -m "feat(workforce): Drivers & Scenario tab — drivers/rates + growth multiplier"
```

---

## Self-Review

**Spec coverage (this plan = Tasks CRUD + Drivers & Scenario):**
- Tasks tab: inventory CRUD, node/cadence/times/minutes/tier/risk/owner, filter → Tasks 1+2. Owner assignment (the seed's ~111 unowned) is now possible. ✓
- Drivers & Scenario: drivers (value, grows) + rates (minutes) + growth-multiplier control writing `wp_config` → Task 3. ✓
- Every write invalidates the read providers (stale-data obligation from Plan 2's review) → Tasks 2+3. ✓
- Design system (mono numerics, purple CTA, ResponsiveTable, dialogs mirroring `kpi_form_dialog`) → all tasks. ✓
- Deferred/omitted (documented): **driver/rate DELETE** — the Plan 1 repo has no `deleteDriver`/`deleteRate` (FKs are `on delete set null`); create/edit only here, delete is a follow-up. Per-employee **capacity override** editing (`setCapacityOverride` exists) is NOT surfaced in this plan — capacity stays the config default; add later if needed. Structure drag-drop is Plan 3.

**Placeholder scan:** none — full dialog + validation code given; the `initialValue` vs `value` `DropdownButtonFormField` caveat and the `SegmentedButton` availability are called out with the fallback.

**Type consistency:** `validateTaskForm`/`TaskFormDialog` signatures match their tests and the Task 2 caller; `WpTask`/`WpDriver`/`WpRate`/`WpConfig`/`WpNode`/`Employee` field names match `main`; repo methods (`saveTask`/`deleteTask`/`saveDriver`/`saveRate`/`setGrowthMultiplier`) and provider names match Plan 1/2 exactly; `ownerComputedProvider` imported from `role_view_tab.dart` (public) for invalidation.

**Open item for implementers:** confirm on this Flutter version whether `DropdownButtonFormField` takes `initialValue` (as `attendance_edit_dialog.dart` uses) or `value`, and whether `SegmentedButton` is available; use whatever analyzes clean (a `SegmentedButton` fallback is two `ChoiceChip`s or a `ToggleButtons`). These are the only version-sensitive spots.
