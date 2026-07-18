# Per-Employee KPI Assignment (Phase 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let HR assign each employee a subset of their role card's KPIs; reviews snapshot that subset, falling back to the full role set when un-curated.

**Architecture:** New `employee_kpis` join (employee_id, kpi_id). `generate_employee_review` re-pointed to snapshot the assigned subset when the employee has one, else the full role set. An assignment checklist on the employee profile's role tab. "No rows = full role set" keeps every un-curated employee on their whole role, so nothing regresses.

**Tech Stack:** Supabase Postgres (forward migrations), Flutter + Riverpod + GoRouter, `supabase_flutter` PostgREST client.

## Global Constraints

- Gate on `flutter analyze` only — mixed formatter styles; do NOT run `dart format`. Match surrounding style.
- Migrations are forward-only; the applied `20260718000001..000004` must not be edited.
- `employee_kpis` has NO target/frequency — those stay on `role_scorecard_kpis` (the role card). Assignment is strictly a **subset of the employee's role card KPIs**.
- **No rows = full role set.** An employee with zero `employee_kpis` rows is tracked on their whole role card. A non-empty set means exactly those.
- The assigned set is always **intersected with the role's current KPIs** at read time (a KPI removed from the role, or left over after a role change, drops out; empty intersection → full role set).
- RLS reuses `auth_is_performance_admin_for_employee(uuid)` (from `20260717000009`): read by HR/admin + the employee + their direct manager; write by HR/admin.
- Test any prod-bound migration on a throwaway Postgres + isolated replica before `supabase db push`. Prod push is controller-run after review.
- Design system per `PRODUCT.md`: single Luxium purple CTA, 6px radius, tables via `lib/widgets/responsive_table.dart` where tabular; no new packages.

---

### Task 1: `employee_kpis` table + RLS

**Files:**
- Create: `supabase/migrations/20260718000005_employee_kpis.sql`

**Interfaces:**
- Produces: table `employee_kpis(id, employee_id, kpi_id, created_at)` with RLS. Consumed by Tasks 2–4.

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260718000005_employee_kpis.sql`:

```sql
-- Phase 2 of KPI tracking: per-employee subset of their role card's KPIs.
-- No target/frequency here — those live on role_scorecard_kpis. Zero rows for an
-- employee means "tracked on the full role set" (see generate_employee_review).

create table employee_kpis (
  id           uuid primary key default gen_random_uuid(),
  employee_id  uuid not null references employees(id) on delete cascade,
  kpi_id       uuid not null references kpis(id) on delete cascade,
  created_at   timestamptz not null default now(),
  unique (employee_id, kpi_id)
);
create index employee_kpis_employee on employee_kpis (employee_id);
create index employee_kpis_kpi on employee_kpis (kpi_id);

alter table employee_kpis enable row level security;
create policy employee_kpis_read on employee_kpis for select using (
  auth_is_performance_admin_for_employee(employee_id)
  or employee_id = auth_employee_id()
  or exists (
    select 1 from employees e
    where e.id = employee_id and e.reports_to_id = auth_employee_id()
  )
);
create policy employee_kpis_write on employee_kpis for all
  using (auth_is_performance_admin_for_employee(employee_id))
  with check (auth_is_performance_admin_for_employee(employee_id));
```

- [ ] **Step 2: Validate on a throwaway Postgres**

Stand up a scratch Postgres, stub `employees(id uuid pk, reports_to_id uuid)`, `kpis(id uuid pk)`, and the functions `auth_is_performance_admin_for_employee(uuid) returns boolean` (return true), `auth_employee_id() returns uuid` (return null). Run the migration. Assert: `employee_kpis` exists; inserting a row works; the unique `(employee_id, kpi_id)` rejects a duplicate; RLS is enabled (`select relrowsecurity from pg_class where relname='employee_kpis'` → t). (Full replica RLS behavior is verified by the controller before prod push.)

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260718000005_employee_kpis.sql
git commit -m "feat(kpi): employee_kpis table (per-employee subset of role KPIs) + RLS"
```

---

### Task 2: Re-point `generate_employee_review` to the assigned subset

**Files:**
- Create: `supabase/migrations/20260718000006_review_from_employee_kpis.sql`

**Interfaces:**
- Consumes: `employee_kpis` (Task 1).
- Produces: `generate_employee_review` snapshots the employee's assigned subset (∩ current role), else the full role set.

- [ ] **Step 1: Extract the current function**

Run: `sed -n '/create or replace function generate_employee_review/,/^\$\$;/p' supabase/migrations/20260718000002_generate_review_from_kpi_link.sql`
This is the authoritative body to copy forward. You will copy it verbatim and change only: (a) add one declared variable, (b) add one SELECT before the KPI loop, (c) add one AND-clause in the KPI loop's WHERE.

- [ ] **Step 2: Write the forward migration**

Create `supabase/migrations/20260718000006_review_from_employee_kpis.sql` as `create or replace function generate_employee_review(...) ... $$;`, byte-identical to the Step 1 output EXCEPT:

1. In the `declare` block, add alongside the existing declarations:
```sql
  v_has_assignment boolean;
```

2. Immediately BEFORE the KPI loop's `v_index := 0;` line, add:
```sql
  select exists (
    select 1
    from employee_kpis ek
      join role_scorecard_kpis rsk
        on rsk.kpi_id = ek.kpi_id and rsk.role_scorecard_id = v_card.id
    where ek.employee_id = v_employee.id
  ) into v_has_assignment;
```

3. Change the KPI loop's source query (the `for v_item in select jsonb_build_object(...) ... loop`) so its WHERE gains the assignment filter. The loop becomes exactly:
```sql
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
      and (
        not v_has_assignment
        or exists (
          select 1 from employee_kpis ek
          where ek.employee_id = v_employee.id and ek.kpi_id = rsk.kpi_id
        )
      )
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
```

Preserve the ENTIRE rest of the function verbatim (the responsibility snapshot, the two skills loops, status transitions) by copying from Step 1's output — do NOT retype it. `v_item` stays jsonb (shared with the skills loops).

- [ ] **Step 3: Verify only the intended changes**

Run: `diff <(sed -n '/create or replace function generate_employee_review/,/^\$\$;/p' supabase/migrations/20260718000002_generate_review_from_kpi_link.sql) <(sed -n '/create or replace function generate_employee_review/,/^\$\$;/p' supabase/migrations/20260718000006_review_from_employee_kpis.sql)`
Expected: exactly three hunks — the added `v_has_assignment` declaration, the added `select ... into v_has_assignment`, and the added `and (not v_has_assignment or exists(...))` in the KPI loop WHERE. Nothing else differs.

- [ ] **Step 4: Validate the three scenarios on a throwaway Postgres**

Stub the tables the function touches (employees, role_scorecards, role_scorecard_kpis, kpis, employee_reviews, review_kpi_results, review_skill_ratings, employee_kpis) and the `auth_*`/`set_updated_at` helpers, seed a role card with 3 KPIs and an employee on it, then:
- (a) employee has employee_kpis rows for 2 of the 3 role KPIs → generate a review → `review_kpi_results` has exactly those 2.
- (b) employee has zero employee_kpis rows → review has all 3.
- (c) employee has one employee_kpis row referencing a KPI NOT on the role → `v_has_assignment` false → review has all 3.
(If fully stubbing the function's other tables is impractical, at minimum confirm the function's body parses/creates, and prove the KPI-selection logic with a standalone query mirroring the loop's WHERE against the seeded rows.)

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260718000006_review_from_employee_kpis.sql
git commit -m "feat(kpi): generate_employee_review snapshots the employee's assigned KPI subset"
```

---

### Task 3: Model, repository methods + providers, and the pure selection helpers

**Files:**
- Create: `lib/data/models/role_kpi.dart`
- Modify: `lib/data/repositories/role_scorecard_repository.dart`
- Test: `test/data/repositories/employee_kpi_selection_test.dart`

**Interfaces:**
- Consumes: `employee_kpis`, `role_scorecard_kpis`, `kpis` (Tasks 1, Phase 1).
- Produces (consumed by Task 4):
  - `class RoleKpi { final String kpiId; final String name; final String? target; final String? frequency; }`
  - `RoleScorecardRepository.roleKpis(String roleScorecardId) -> Future<List<RoleKpi>>` (from `role_scorecard_kpis ⨝ kpis`, ordered by `sort_order`).
  - `RoleScorecardRepository.employeeAssignedKpiIds(String employeeId) -> Future<Set<String>>`.
  - `RoleScorecardRepository.saveEmployeeKpis(String employeeId, List<String> kpiIds) -> Future<void>` (replace-all: delete the employee's rows, insert `kpiIds`; empty list clears → default-all).
  - Providers `roleKpisProvider(String)` and `employeeAssignedKpiIdsProvider(String)`.
  - Pure helpers `initialCheckedKpiIds(Set<String> assigned, List<String> roleKpiIds) -> Set<String>` and `kpiIdsToPersist(Set<String> checked, List<String> roleKpiIds) -> List<String>`.

- [ ] **Step 1: Write the failing test for the pure helpers**

Create `test/data/repositories/employee_kpi_selection_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';

void main() {
  group('initialCheckedKpiIds', () {
    test('no assignment -> all role KPIs checked (default all)', () {
      expect(
        initialCheckedKpiIds(<String>{}, ['a', 'b', 'c']),
        {'a', 'b', 'c'},
      );
    });
    test('with assignment -> only assigned that are on the role', () {
      expect(
        initialCheckedKpiIds({'a', 'z'}, ['a', 'b', 'c']),
        {'a'}, // 'z' not on the role is ignored
      );
    });
  });

  group('kpiIdsToPersist', () {
    test('all role KPIs checked -> persist none (default all)', () {
      expect(kpiIdsToPersist({'a', 'b', 'c'}, ['a', 'b', 'c']), isEmpty);
    });
    test('a subset checked -> persist that subset', () {
      expect(kpiIdsToPersist({'a', 'c'}, ['a', 'b', 'c']), ['a', 'c']);
    });
    test('none checked -> persist none (falls back to default all)', () {
      expect(kpiIdsToPersist(<String>{}, ['a', 'b', 'c']), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/data/repositories/employee_kpi_selection_test.dart`
Expected: FAIL — the helpers don't exist.

- [ ] **Step 3: Add the model**

Create `lib/data/models/role_kpi.dart`:

```dart
/// One KPI on a role card, with its stable library id — used by the per-employee
/// assignment UI (which keys on kpi_id) rather than the display-only KpiItem.
class RoleKpi {
  final String kpiId;
  final String name;
  final String? target;
  final String? frequency;
  const RoleKpi({
    required this.kpiId,
    required this.name,
    this.target,
    this.frequency,
  });

  factory RoleKpi.fromRow(Map<String, dynamic> r) => RoleKpi(
    kpiId: r['kpi_id'] as String,
    name: (r['kpis'] as Map?)?['name'] as String? ?? '',
    target: r['target'] as String?,
    frequency: r['frequency'] as String?,
  );
}
```

- [ ] **Step 4: Add the helpers + repo methods + providers**

In `lib/data/repositories/role_scorecard_repository.dart`:

Add the import at the top with the other model imports:
```dart
import '../models/role_kpi.dart';
```

Add these pure top-level helpers (outside the class):
```dart
/// The checkbox state to show when the assignment section opens: if the employee
/// has no assignment, all role KPIs are checked (they're tracked on the full
/// set by default); otherwise only the assigned KPIs that are still on the role.
Set<String> initialCheckedKpiIds(Set<String> assigned, List<String> roleKpiIds) {
  if (assigned.isEmpty) return roleKpiIds.toSet();
  return roleKpiIds.where(assigned.contains).toSet();
}

/// What to persist for [checked] out of [roleKpiIds]: nothing when all (or none)
/// are checked — both mean "default: full role set" — otherwise the subset in
/// role order.
List<String> kpiIdsToPersist(Set<String> checked, List<String> roleKpiIds) {
  if (checked.isEmpty || checked.length == roleKpiIds.length) return const [];
  return roleKpiIds.where(checked.contains).toList();
}
```

Add these methods to `RoleScorecardRepository`:
```dart
  Future<List<RoleKpi>> roleKpis(String roleScorecardId) async {
    final rows = await _client
        .from('role_scorecard_kpis')
        .select('kpi_id, target, frequency, sort_order, kpis(name)')
        .eq('role_scorecard_id', roleScorecardId)
        .order('sort_order');
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(RoleKpi.fromRow)
        .toList();
  }

  Future<Set<String>> employeeAssignedKpiIds(String employeeId) async {
    final rows = await _client
        .from('employee_kpis')
        .select('kpi_id')
        .eq('employee_id', employeeId);
    return {
      for (final r in (rows as List).cast<Map<String, dynamic>>())
        r['kpi_id'] as String,
    };
  }

  /// Replace the employee's KPI assignment with [kpiIds]. Empty clears it
  /// (employee falls back to the full role set).
  Future<void> saveEmployeeKpis(String employeeId, List<String> kpiIds) async {
    await _client.from('employee_kpis').delete().eq('employee_id', employeeId);
    if (kpiIds.isNotEmpty) {
      await _client.from('employee_kpis').insert([
        for (final id in kpiIds) {'employee_id': employeeId, 'kpi_id': id},
      ]);
    }
  }
```

Add these providers near the other KPI providers:
```dart
final roleKpisProvider =
    FutureProvider.family<List<RoleKpi>, String>((ref, roleScorecardId) {
  return ref.watch(roleScorecardRepositoryProvider).roleKpis(roleScorecardId);
});

final employeeAssignedKpiIdsProvider =
    FutureProvider.family<Set<String>, String>((ref, employeeId) {
  return ref.watch(roleScorecardRepositoryProvider).employeeAssignedKpiIds(employeeId);
});
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/data/repositories/employee_kpi_selection_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 6: Verify analyze + full suite**

Run: `flutter analyze lib/data/models/role_kpi.dart lib/data/repositories/role_scorecard_repository.dart test/data/repositories/employee_kpi_selection_test.dart`
Expected: no errors.
Run: `flutter test`
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add lib/data/models/role_kpi.dart lib/data/repositories/role_scorecard_repository.dart test/data/repositories/employee_kpi_selection_test.dart
git commit -m "feat(kpi): employee_kpis repo methods, RoleKpi model, and selection helpers"
```

---

### Task 4: Assignment section on the role tab

**Files:**
- Modify: `lib/features/employees/profile/tabs/role_tab.dart` (add a section inside `_RoleDetail`)
- Test: `test/features/employees/employee_kpi_assignment_section_test.dart`

**Interfaces:**
- Consumes: `roleKpisProvider`, `employeeAssignedKpiIdsProvider`, `initialCheckedKpiIds`, `kpiIdsToPersist`, `RoleScorecardRepository.saveEmployeeKpis`, `roleScorecardRepositoryProvider` (Task 3); `userProfileProvider` (for `canManageEmployees`).
- Produces: the assignment UI. No downstream consumers.

- [ ] **Step 1: Write a widget test for the default-all render**

Create `test/features/employees/employee_kpi_assignment_section_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/role_kpi.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';
import 'package:payroll_flutter/features/employees/profile/tabs/role_tab.dart';

void main() {
  testWidgets('shows the role KPIs, all checked when un-curated', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        roleKpisProvider('role-1').overrideWith((ref) async => const [
          RoleKpi(kpiId: 'a', name: 'Order Accuracy'),
          RoleKpi(kpiId: 'b', name: 'On-Time Dispatch'),
        ]),
        employeeAssignedKpiIdsProvider('emp-1').overrideWith((ref) async => <String>{}),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: EmployeeKpiAssignmentSection(
            employeeId: 'emp-1',
            roleScorecardId: 'role-1',
            canManage: true,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Order Accuracy'), findsOneWidget);
    expect(find.text('On-Time Dispatch'), findsOneWidget);
    // Un-curated: both boxes checked (default = full role set).
    final boxes = tester.widgetList<CheckboxListTile>(find.byType(CheckboxListTile));
    expect(boxes.length, 2);
    expect(boxes.every((b) => b.value == true), isTrue);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/employees/employee_kpi_assignment_section_test.dart`
Expected: FAIL — `EmployeeKpiAssignmentSection` doesn't exist.

- [ ] **Step 3: Implement the section**

In `lib/features/employees/profile/tabs/role_tab.dart`, add the import if missing:
```dart
import '../../../../data/models/role_kpi.dart';
```
Add this public widget at the end of the file (it is referenced by the test and rendered inside `_RoleDetail`):

```dart
/// HR-facing checklist of the role's KPIs; ticked ones are the KPIs this
/// employee is tracked/reviewed on. Un-curated (no rows) shows all ticked —
/// "tracking the full role set." Saving all (or none) clears to the default.
class EmployeeKpiAssignmentSection extends ConsumerStatefulWidget {
  final String employeeId;
  final String roleScorecardId;
  final bool canManage;
  const EmployeeKpiAssignmentSection({
    super.key,
    required this.employeeId,
    required this.roleScorecardId,
    required this.canManage,
  });

  @override
  ConsumerState<EmployeeKpiAssignmentSection> createState() =>
      _EmployeeKpiAssignmentSectionState();
}

class _EmployeeKpiAssignmentSectionState
    extends ConsumerState<EmployeeKpiAssignmentSection> {
  Set<String>? _checked; // null until loaded
  List<RoleKpi> _roleKpis = const [];
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final roleKpis = ref.watch(roleKpisProvider(widget.roleScorecardId));
    final assigned = ref.watch(employeeAssignedKpiIdsProvider(widget.employeeId));
    return roleKpis.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Could not load KPIs: $e'),
      ),
      data: (kpis) => assigned.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Could not load assignment: $e'),
        ),
        data: (assignedIds) {
          _roleKpis = kpis;
          _checked ??= initialCheckedKpiIds(
            assignedIds,
            [for (final k in kpis) k.kpiId],
          );
          final checked = _checked!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('KPIs this employee is tracked on',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              if (assignedIds.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text('Tracking all role KPIs (default). Untick any that '
                      "can't be realistically measured for this person."),
                ),
              for (final k in kpis)
                CheckboxListTile(
                  value: checked.contains(k.kpiId),
                  title: Text(k.name),
                  subtitle: k.target == null ? null : Text('Target: ${k.target}'),
                  onChanged: widget.canManage && !_saving
                      ? (v) => setState(() {
                          if (v == true) {
                            checked.add(k.kpiId);
                          } else {
                            checked.remove(k.kpiId);
                          }
                        })
                      : null,
                ),
              if (widget.canManage)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Saving...' : 'Save KPI selection'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(roleScorecardRepositoryProvider).saveEmployeeKpis(
            widget.employeeId,
            kpiIdsToPersist(_checked!, [for (final k in _roleKpis) k.kpiId]),
          );
      ref.invalidate(employeeAssignedKpiIdsProvider(widget.employeeId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('KPI selection saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
```

- [ ] **Step 4: Render it inside `_RoleDetail`**

In `_RoleDetail`'s `build` (the widget that already has `employee` and `card`), add the section where the KPI list is shown (after the existing role/KPI content). Insert:
```dart
          EmployeeKpiAssignmentSection(
            employeeId: employee.id,
            roleScorecardId: card.id,
            canManage: canManage,
          ),
```
Place it within the existing scrolling column/list of `_RoleDetail` (follow the surrounding widget structure — it renders sections in a `ListView`/`Column`).

- [ ] **Step 5: Run the widget test to verify it passes**

Run: `flutter test test/features/employees/employee_kpi_assignment_section_test.dart`
Expected: PASS.

- [ ] **Step 6: Verify analyze + full suite; manual smoke pending**

Run: `flutter analyze lib/features/employees/profile/tabs/role_tab.dart`
Expected: no errors.
Run: `flutter test`
Expected: all pass.
Manual (coordinator; no headless GUI): open an employee's Role tab → the KPI section lists the role KPIs, all ticked for an un-curated employee → untick one, Save → reopen shows the subset; a review generated for that employee snapshots only the ticked KPIs.

- [ ] **Step 7: Commit**

```bash
git add lib/features/employees/profile/tabs/role_tab.dart test/features/employees/employee_kpi_assignment_section_test.dart
git commit -m "feat(kpi): per-employee KPI assignment section on the role tab"
```

---

## After all tasks: prod migration

Once reviewed and the throwaway-Postgres/replica checks pass, `supabase db push` applies `20260718000005` + `20260718000006`. Confirm `supabase migration list` shows both on Remote, then smoke-test an assignment save + a review generation on prod.

## Notes for the implementer

- `card.kpis` (KpiItem) has no kpi_id — that's why the section uses `roleKpisProvider` (RoleKpi, with kpi_id), not `card.kpis`.
- `saveEmployeeKpis` is replace-all (delete then insert), not a diff — simpler and correct for this small per-employee set.
- Do not add target/frequency to `employee_kpis` — they belong to the role card.
