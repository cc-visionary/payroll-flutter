# Role Workbench — Plan 2: The Workbench

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `/workforce-planning/roles/:id` — the one place a role is authored: details, responsibilities, KPIs, load and holders — reached by clicking a row in the Roles tab.

**Architecture:** A thin screen shell plus one file per pane under `lib/features/workforce_planning/role/`, composing widgets that already exist (`task_form_dialog`, `EmployeeKpiAssignmentSection`, `kpi_form_dialog`) and the pure logic Plan 1 landed. Each pane owns its own save; there is no single giant form. Before any pane is built, one migration makes an employee's stored KPI set mean exactly what it says.

**Tech Stack:** Flutter (Material 3, Riverpod, GoRouter), Supabase Postgres, `flutter_test`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-11-role-workbench-design.md`. Plan 1 (`2026-08-11-role-workbench-foundation.md`) is merged at `e2de3b3`; read its Global Constraints too, they still bind.
- **The card editor stays live and untouched.** `role_scorecard_form_screen.dart` and its two routes are retired in Plan 3, not here. Until then both editors work; do not delete or disable either.
- The repo gates on `flutter analyze` only: 0 errors, 0 warnings. It carries 192 pre-existing `info` lints — add none.
- **Do not run `dart format`.** Match the surrounding style of each file.
- Never claim a test passed or the analyzer was clean without pasting the command output.
- Migrations are applied by the user with `supabase db push`, never by an implementer.
- **`role_scorecard_kpis.target` and `.frequency` stay derived**, never hand-typed — `goalColumns` writes `target`, `frequencyLabelFromCadence` writes `frequency`. They are rendered into role-card PDFs and employment-contract Annex A.
- Every mutation must invalidate the same provider set `tasks_tab.dart:1426` (`_invalidateAfterTaskChange`) does, plus `roleScorecardByIdProvider(cardId)`. A save that skips one leaves Balance or the card view reading stale numbers until restart.
- Repeating rows rendered from drafts must key every field by draft identity — see `test/features/responsibility_cards/scorecard_row_delete_test.dart` and commit `6ae6c9b` for what happens otherwise.
- Widget tests use `initSupabaseStub()` from `test/support/supabase_stub.dart`. Set a tall `tester.view.physicalSize` or content below the fold never mounts.
- Vocabularies live in `lib/features/kpi_library/kpi_measurable.dart` (`kKpiValueTypes`, `kKpiCadences`, `kKpiProofTypes`) and must not be re-declared.

## File Structure

| File | Responsibility |
|---|---|
| `supabase/migrations/20260811000002_explicit_employee_kpi_sets.sql` (new) | backfill so a stored KPI set means what it says |
| `lib/data/repositories/role_scorecard_repository.dart` (modify) | `initialCheckedKpiIds` / `kpiIdsToPersist` semantics; `distinctKpiSources()`; `roleWorkbenchProvider` |
| `lib/features/workforce_planning/role/role_workbench_screen.dart` (new) | route target: header, error/loading, hosts the four panes |
| `lib/features/workforce_planning/role/role_details_pane.dart` (new) | mission, skills, expectations, department, entity, pay, schedule |
| `lib/features/workforce_planning/role/responsibilities_pane.dart` (new) | areas + tasks, inline hours/criticality, add/link/remove |
| `lib/features/workforce_planning/role/kpis_pane.dart` (new) | role→KPI links: goal, cadence, live preview, add/remove |
| `lib/features/workforce_planning/role/people_pane.dart` (new) | holders, load, per-employee KPI set |
| `lib/features/kpi_library/kpi_definition_form.dart` (new) | the measurable definition fields, shared by the library dialog and the KPIs pane |
| `lib/features/workforce_planning/tabs/role_view_tab.dart` (modify) | row drill-in |

---

### Task 1: An employee's stored KPI set means what it says

**Files:**
- Create: `supabase/migrations/20260811000002_explicit_employee_kpi_sets.sql`
- Modify: `lib/data/repositories/role_scorecard_repository.dart:13-33`
- Test: `test/data/repositories/kpi_set_persistence_test.dart`

**Interfaces:**
- Consumes: nothing from later tasks.
- Produces: `initialCheckedKpiIds(Set<String> assigned, List<String> roleKpiIds)` and `kpiIdsToPersist(Set<String> checked, List<String> roleKpiIds)` with changed semantics — same signatures, so no call site changes shape.

**Why this is first.** Today `kpiIdsToPersist` collapses "everything checked" to `const []`, and `initialCheckedKpiIds` reads `[]` back as "everything". The stored set and the effective set are therefore different things, and `employeeNeedsKpiSet` (Plan 1) already disagrees with that. Building the People pane on the old rule would cement it, and Plan 4's "N people with no KPI set" chip would flag every correctly-configured employee. The backfill materialises today's effective set for everyone, so no person's tracked KPIs change on the day it runs.

**Deliberately NOT changed:** the `employee_kpis`-empty fallbacks inside `generate_employee_review` (`20260718000006`) and `employeesByKpi`. After the backfill they fire only for someone with a genuinely absent set, where falling back is the same behaviour as today and strictly safer than generating an empty review. Spec B decides whether to remove them.

- [ ] **Step 1: Write the failing test**

Create `test/data/repositories/kpi_set_persistence_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';

void main() {
  const role = ['a', 'b', 'c'];

  group('initialCheckedKpiIds', () {
    test('an absent set stays absent — it no longer means "all of them"', () {
      // The backfill in 20260811000002 gave everyone who had an effective set
      // an explicit one, so empty now means nobody has chosen.
      expect(initialCheckedKpiIds(const {}, role), isEmpty);
    });

    test('a stored set is shown exactly as stored', () {
      expect(initialCheckedKpiIds({'a', 'c'}, role), {'a', 'c'});
    });

    test('drops ids that are no longer on the role', () {
      // Survives an employee being moved to a different role card.
      expect(initialCheckedKpiIds({'a', 'z'}, role), {'a'});
    });

    test('a stored set that is entirely off-role reads as absent', () {
      expect(initialCheckedKpiIds({'y', 'z'}, role), isEmpty);
    });
  });

  group('kpiIdsToPersist', () {
    test('persists every checked id, including when all are checked', () {
      // The old rule collapsed this to [] and lost the distinction between
      // "tracks all three" and "nobody has chosen".
      expect(kpiIdsToPersist({'a', 'b', 'c'}, role), ['a', 'b', 'c']);
    });

    test('persists a partial selection in role order', () {
      expect(kpiIdsToPersist({'c', 'a'}, role), ['a', 'c']);
    });

    test('drops checked ids that are not on the role', () {
      expect(kpiIdsToPersist({'a', 'z'}, role), ['a']);
    });

    test('an empty selection persists as empty', () {
      expect(kpiIdsToPersist(const {}, role), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

```
flutter test test/data/repositories/kpi_set_persistence_test.dart
```

Expected: FAIL on the first and fifth cases — `initialCheckedKpiIds(const {}, role)` currently returns `{'a','b','c'}`, and `kpiIdsToPersist({'a','b','c'}, role)` currently returns `[]`.

- [ ] **Step 3: Change the two helpers**

In `lib/data/repositories/role_scorecard_repository.dart`, replace both functions (lines 13-33) with:

```dart
/// Which boxes to tick for an employee whose stored set is [assigned].
///
/// The stored set IS the set. An empty result means nobody has chosen yet —
/// a gap to close, not "tracks everything". That changed in 20260811000002,
/// which backfilled an explicit set for everyone who had an effective one.
/// Ids no longer on the role are dropped: an employee can be moved to a
/// different card, leaving rows that point at the old role's KPIs.
Set<String> initialCheckedKpiIds(
  Set<String> assigned,
  List<String> roleKpiIds,
) => roleKpiIds.where(assigned.contains).toSet();

/// What to store for [checked], in role order so the rows read predictably.
///
/// Unlike the pre-20260811000002 rule this never collapses a full selection to
/// the empty list — "tracks all three" and "nobody has chosen" are different
/// states and scoring has to tell them apart.
List<String> kpiIdsToPersist(Set<String> checked, List<String> roleKpiIds) =>
    roleKpiIds.where(checked.contains).toList();
```

- [ ] **Step 4: Run it and watch it pass**

```
flutter test test/data/repositories/kpi_set_persistence_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 5: Run the whole suite**

```
flutter test
```

Expected: `All tests passed!`, at least 1279 passing. `employee_kpi_assignment_section_test.dart` asserts the OLD behaviour ("shows the role KPIs, all checked when un-curated"). It will fail. That test encodes the rule this task deliberately reverses — update its expectation to "none checked when un-curated" and rename it accordingly. Do not change the widget to make the old assertion pass.

- [ ] **Step 6: Write the backfill migration**

Create `supabase/migrations/20260811000002_explicit_employee_kpi_sets.sql`:

```sql
-- An employee's stored KPI set becomes the set. Before this, zero rows in
-- employee_kpis meant "tracks the full role set" (see 20260718000005/06), so
-- the stored set and the effective set were different things — and scoring
-- cannot tell "tracks all ten" from "nobody has chosen".
--
-- Materialise today's effective set for everyone who has one, so no person's
-- tracked KPIs change on the day this runs. After it, an empty set genuinely
-- means nobody has chosen, which is what the app now flags as a gap.
--
-- The empty-set fallbacks in generate_employee_review (20260718000006) and in
-- employeesByKpi are DELIBERATELY left in place. Post-backfill they fire only
-- for a genuinely absent set, where falling back is both unchanged from today
-- and safer than generating a review with no KPIs at all.
do $$
declare v_rows int;
begin
  insert into employee_kpis (employee_id, kpi_id)
  select e.id, l.kpi_id
  from employees e
    join role_scorecard_kpis l on l.role_scorecard_id = e.role_scorecard_id
  where e.deleted_at is null
    and e.employment_status = 'ACTIVE'
    and e.role_scorecard_id is not null
    and not exists (
      select 1 from employee_kpis ek where ek.employee_id = e.id
    )
  on conflict (employee_id, kpi_id) do nothing;

  get diagnostics v_rows = row_count;
  raise notice 'explicit KPI sets: % employee_kpis rows materialised', v_rows;
end $$;
```

- [ ] **Step 7: Verify the migration reads correctly**

```
grep -c "not exists" supabase/migrations/20260811000002_explicit_employee_kpi_sets.sql
grep -n "on conflict" supabase/migrations/20260811000002_explicit_employee_kpi_sets.sql
```

Expected: `1`, and one `on conflict (employee_id, kpi_id) do nothing` line — that unique constraint exists (`20260718000005`), and the guard makes a replay a no-op. Confirm by reading that the `not exists` subquery keys on `employee_id` alone, so an employee with a partial set is left exactly as they are.

- [ ] **Step 8: Analyze and commit**

```
flutter analyze lib test
```

```bash
git add lib/data/repositories/role_scorecard_repository.dart supabase/migrations/20260811000002_explicit_employee_kpi_sets.sql test/data/repositories/kpi_set_persistence_test.dart test/features/employees/employee_kpi_assignment_section_test.dart
git commit -m "feat(kpi): an employee's stored KPI set means what it says"
```

- [ ] **Step 9: Hand the migration to the user**

Report, do not run:

> `20260811000002_explicit_employee_kpi_sets.sql` is ready and must be applied **with** `20260811000001`. It prints how many rows it materialised. Until it runs, everyone reads as having no KPI set.

---

### Task 2: The route, the shell, and the drill-in

**Files:**
- Create: `lib/features/workforce_planning/role/role_workbench_screen.dart`
- Modify: `lib/app/router.dart` (beside the other `/workforce-planning` route, ~line 254)
- Modify: `lib/features/workforce_planning/tabs/role_view_tab.dart` (the `DataRow` at ~line 194)
- Test: `test/features/workforce_planning/role/role_workbench_screen_test.dart`

**Interfaces:**
- Consumes: `RoleRollupRow.cardId` (`lib/features/workforce_planning/role_rollup.dart:31`); `roleScorecardByIdProvider(String)` from `lib/features/documents/providers.dart`.
- Produces: `class RoleWorkbenchScreen extends ConsumerWidget { const RoleWorkbenchScreen({super.key, required this.cardId}); final String cardId; }` at route `/workforce-planning/roles/:id`. Tasks 3-7 add panes to its body in the order: details, responsibilities, KPIs, people.

- [ ] **Step 1: Write the failing test**

Create `test/features/workforce_planning/role/role_workbench_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/features/documents/providers.dart';
import 'package:payroll_flutter/features/workforce_planning/role/role_workbench_screen.dart';

import '../../../support/supabase_stub.dart';

RoleScorecard _card() => RoleScorecard(
  id: 'card-1',
  companyId: 'co-1',
  jobTitle: 'Technical Product & Purchasing Specialist',
  missionStatement: 'Build a predictable wholesale revenue engine.',
  responsibilities: const [],
  kpis: const [],
  requiredSkills: const [],
  behavioralExpectations: const [],
  version: 2,
  wageType: 'DAILY',
  workHoursPerDay: 8,
  workDaysPerWeek: 'Monday to Saturday',
  isActive: true,
  effectiveDate: DateTime(2025, 1, 1),
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initSupabaseStub();
  });

  Future<void> pump(WidgetTester tester, {RoleScorecard? card}) async {
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roleScorecardByIdProvider(
            'card-1',
          ).overrideWith((ref) async => card),
        ],
        child: const MaterialApp(
          home: RoleWorkbenchScreen(cardId: 'card-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the role title and version in the header', (tester) async {
    await pump(tester, card: _card());
    expect(
      find.text('Technical Product & Purchasing Specialist'),
      findsOneWidget,
    );
    expect(find.textContaining('Version 2'), findsOneWidget);
  });

  testWidgets('says so plainly when the card is missing', (tester) async {
    await pump(tester, card: null);
    expect(find.textContaining('not found'), findsOneWidget);
    // Never a bare spinner forever, and never an empty scaffold that reads as
    // a role with nothing in it.
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

```
flutter test test/features/workforce_planning/role/role_workbench_screen_test.dart
```

Expected: compile failure — `role_workbench_screen.dart` does not exist.

- [ ] **Step 3: Write the shell**

Create `lib/features/workforce_planning/role/role_workbench_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/breakpoints.dart';
import '../../documents/providers.dart';

/// The one place a role is authored: details, responsibilities, KPIs and the
/// people holding it. Reached from the Roles tab; the Responsibility Card
/// screen is the read-only artifact this produces.
///
/// Each pane owns its own save. There is deliberately no single form key
/// spanning them — a manager fixing one responsibility's hours should not be
/// blocked by an unrelated empty field three panes away.
class RoleWorkbenchScreen extends ConsumerWidget {
  const RoleWorkbenchScreen({super.key, required this.cardId});

  final String cardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardAsync = ref.watch(roleScorecardByIdProvider(cardId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Role'),
        actions: [
          IconButton(
            tooltip: 'View card',
            icon: const Icon(Icons.description_outlined),
            onPressed: () => context.push('/responsibility-cards/$cardId'),
          ),
          IconButton(
            tooltip: 'PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () => context.push('/responsibility-cards/$cardId/pdf'),
          ),
        ],
      ),
      body: cardAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load this role: $e')),
        data: (card) {
          if (card == null) {
            return const Center(child: Text('This role card was not found.'));
          }
          return ListView(
            padding: EdgeInsets.all(isMobile(context) ? 16 : 24),
            children: [
              Text(
                card.jobTitle,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Version ${card.version}'
                '${card.isActive ? '' : ' · inactive'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              // Panes are added here by later tasks, in this order:
              // details, responsibilities, KPIs, people.
            ],
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 4: Run it and watch it pass**

```
flutter test test/features/workforce_planning/role/role_workbench_screen_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 5: Add the route**

In `lib/app/router.dart`, directly after the `/workforce-planning` route (~line 254), add:

```dart
          GoRoute(
            path: '/workforce-planning/roles/:id',
            builder: (c, s) =>
                RoleWorkbenchScreen(cardId: s.pathParameters['id']!),
          ),
```

and the import beside the other workforce-planning import (~line 53):

```dart
import '../features/workforce_planning/role/role_workbench_screen.dart';
```

The existing guard at line 108 already covers this path: it tests `loc.startsWith('/workforce-planning')`, so the workbench is HR/Admin-only with no extra work. Verify that line still reads that way rather than assuming it.

- [ ] **Step 6: Add the drill-in**

In `lib/features/workforce_planning/tabs/role_view_tab.dart`, the `DataRow` built per `RoleRollupRow` (~line 194) gains a tap target. `_RoleLens` is a `ConsumerWidget`, so use the `context` already in scope:

```dart
            DataRow(
              // The Roles table is now the front door to the workbench: this
              // row is the only place that knows the card id.
              onSelectChanged: (_) =>
                  context.push('/workforce-planning/roles/${r.cardId}'),
              cells: [
```

Add `import 'package:go_router/go_router.dart';` to that file if it is not already imported.

`onSelectChanged` gives keyboard and screen-reader affordance for free, which a bare `InkWell` around the first cell would not.

**It also requires `showCheckboxColumn: false` on the `DataTable` at ~line 182.**
`showCheckboxColumn` defaults to `true`, and Flutter computes
`displayCheckboxColumn = showCheckboxColumn && anyRowSelectable` — so setting
`onSelectChanged` on any row silently materialises a checkbox column, a
select-all header checkbox, and disabled styling on the unselectable `Total`
row. The select-all then calls every row's `onSelectChanged` in one pass, which
with a navigating callback means one click pushes a workbench screen per role.
Suppressing the column keeps the tap, keyboard and screen-reader semantics and
drops the rest:

```dart
      child: DataTable(
        showCheckboxColumn: false,
        columnSpacing: 24,
```

Add a test asserting `find.byType(Checkbox)` finds nothing in this table —
`test/features/workforce_planning/role_lens_test.dart` already stands the tab
up with the provider overrides needed.

- [ ] **Step 7: Run the suite and the analyzer**

```
flutter test
flutter analyze lib test
```

Expected: `All tests passed!` with the two new cases added; 0 errors, 0 warnings. `role_lens_test.dart` and `tab_intro_test.dart` exercise this tab — if either breaks, the row structure changed in a way it asserts on; fix the code, not the test.

- [ ] **Step 8: Commit**

```bash
git add lib/features/workforce_planning/role/role_workbench_screen.dart lib/app/router.dart lib/features/workforce_planning/tabs/role_view_tab.dart test/features/workforce_planning/role/role_workbench_screen_test.dart
git commit -m "feat(wp): role workbench route and Roles-tab drill-in"
```

---

### Task 3: Role details pane

**Files:**
- Create: `lib/features/workforce_planning/role/role_details_pane.dart`
- Modify: `lib/features/workforce_planning/role/role_workbench_screen.dart` (mount the pane)
- Test: `test/features/workforce_planning/role/role_details_pane_test.dart`

**Interfaces:**
- Consumes: `RoleScorecard` (`lib/data/models/role_scorecard.dart`); `RoleScorecardRepository.upsert` via `roleScorecardRepositoryProvider`; `hiringEntityListProvider` (`lib/data/repositories/hiring_entity_repository.dart:154`); `resolveScorecardBaseSalaryOnSave` (`lib/features/responsibility_cards/scorecard_base_salary.dart`).
- Produces: `class RoleDetailsPane extends ConsumerStatefulWidget { const RoleDetailsPane({super.key, required this.card}); final RoleScorecard card; }`.

**Field set, taken from the card editor** (`role_scorecard_form_screen.dart`): job title, department, hiring entity, mission statement, required skills (name + description, repeating), behavioural expectations (name + observable standard, repeating), wage type, base salary, salary range min/max, hours per day, days per week, effective date, active.

**Two rules carried over from the editor, both load-bearing:**
1. Base salary is immutable on an existing card — `resolveScorecardBaseSalaryOnSave` enforces it. Editing it would silently reprice every employee on the role who has no `compensation_changes` record. Render it read-only with that reason as helper text.
2. Repeating skill and expectation rows must key each field by `identityHashCode` of its draft — see `role_scorecard_form_screen.dart:683-700` for the shape and `6ae6c9b` for the bug that keying prevents.

- [ ] **Step 1: Write the failing test**

Create `test/features/workforce_planning/role/role_details_pane_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/features/workforce_planning/role/role_details_pane.dart';

import '../../../support/supabase_stub.dart';

RoleScorecard _card() => RoleScorecard(
  id: 'card-1',
  companyId: 'co-1',
  jobTitle: 'Kiosk Sales Representative',
  missionStatement: 'Sell through the kiosk.',
  responsibilities: const [],
  kpis: const [],
  requiredSkills: const [
    RequiredSkill(name: 'Product knowledge', description: 'Knows the range'),
    RequiredSkill(name: 'Cash handling', description: 'Accurate float'),
    RequiredSkill(name: 'Upselling', description: 'Suggests add-ons'),
  ],
  behavioralExpectations: const [],
  version: 1,
  wageType: 'DAILY',
  workHoursPerDay: 8,
  workDaysPerWeek: 'Monday to Saturday',
  isActive: true,
  effectiveDate: DateTime(2025, 1, 1),
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initSupabaseStub();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RoleDetailsPane(card: _card()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder fieldsLabelled(String label) => find.ancestor(
    of: find.text(label),
    matching: find.byType(TextFormField),
  );

  testWidgets('removing a skill drops that row, not the last one', (
    tester,
  ) async {
    // The card editor shipped this bug for months (fixed in 6ae6c9b): unkeyed
    // fields are matched positionally, so the surviving rows kept the text of
    // the rows before them and the LAST row appeared to vanish.
    await pump(tester);
    await tester.tap(find.text('Role details'));
    await tester.pumpAndSettle();

    expect(fieldsLabelled('Skill name'), findsNWidgets(3));
    await tester.tap(
      find.widgetWithIcon(IconButton, Icons.delete_outline).first,
    );
    await tester.pumpAndSettle();

    expect(fieldsLabelled('Skill name'), findsNWidgets(2));
    expect(find.text('Product knowledge'), findsNothing);
    expect(find.text('Cash handling'), findsOneWidget);
    expect(find.text('Upselling'), findsOneWidget);
  });

  testWidgets('base salary is read-only on an existing card', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Role details'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextFormField>(
      fieldsLabelled('Base salary').first,
    );
    expect(field.enabled, isFalse);
    expect(find.textContaining('compensation'), findsOneWidget);
  });

  testWidgets('starts collapsed so the panes below are reachable', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Role details'), findsOneWidget);
    expect(fieldsLabelled('Skill name'), findsNothing);
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

```
flutter test test/features/workforce_planning/role/role_details_pane_test.dart
```

Expected: compile failure — `role_details_pane.dart` does not exist.

- [ ] **Step 3: Implement the pane**

Create `lib/features/workforce_planning/role/role_details_pane.dart`. Build it as an `ExpansionTile` titled `Role details`, `initiallyExpanded: false`, containing the field set above and a Save button that calls `roleScorecardRepositoryProvider.upsert` with a `RoleScorecard` rebuilt from the controllers.

Port the field widgets from `role_scorecard_form_screen.dart` — the same labels, the same `_responsiveRow` two-column behaviour, the same validators. Two required departures from that source:

```dart
// Skills and expectations: key every field by draft identity, never by index.
// Unkeyed fields are matched positionally, so removing row i leaves the
// survivors showing the text of the rows before it (fixed in 6ae6c9b).
TextFormField(
  key: ValueKey('skill-name-${identityHashCode(_skills[i])}'),
  initialValue: _skills[i].name,
  onChanged: (v) => _skills[i].name = v,
  // ...
),
```

```dart
// Base salary is immutable on an existing card. Changing it would silently
// reprice every employee on this role who has no compensation_changes row —
// see resolveScorecardBaseSalaryOnSave, which enforces this on save too.
TextFormField(
  controller: _baseSalary,
  enabled: false,
  decoration: const InputDecoration(
    labelText: 'Base salary',
    helperText: 'Set per employee under compensation, not on the role.',
    border: OutlineInputBorder(),
  ),
),
```

On save, invalidate `roleScorecardByIdProvider(card.id)` and `roleScorecardListProvider`.

- [ ] **Step 4: Run it and watch it pass**

```
flutter test test/features/workforce_planning/role/role_details_pane_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 5: Mount it**

In `role_workbench_screen.dart`, replace the panes comment with `RoleDetailsPane(card: card)`.

- [ ] **Step 6: Suite, analyzer, commit**

```
flutter test
flutter analyze lib test
```

```bash
git add lib/features/workforce_planning/role/role_details_pane.dart lib/features/workforce_planning/role/role_workbench_screen.dart test/features/workforce_planning/role/role_details_pane_test.dart
git commit -m "feat(wp): role details pane on the workbench"
```

---

### Task 4: Responsibilities pane

**Files:**
- Create: `lib/features/workforce_planning/role/responsibilities_pane.dart`
- Modify: `lib/features/workforce_planning/role/role_workbench_screen.dart`
- Test: `test/features/workforce_planning/role/responsibilities_pane_test.dart`

**Interfaces:**
- Consumes: `wpTasksProvider`, `wpAllTaskComputedProvider` (`lib/features/workforce_planning/wp_providers.dart`); `showTaskFormDialog` / `buildTaskFromForm` (`lib/features/workforce_planning/tabs/task_form_dialog.dart`); `removalActionForTask` and `RemovalAction` (`lib/features/workforce_planning/removal_lifecycle.dart`); `diffResponsibilities` and `RespDraft` (`lib/features/responsibility_cards/responsibility_rows.dart`); `WorkforcePlanningRepository.saveTask`.
- Produces: `class ResponsibilitiesPane extends ConsumerStatefulWidget { const ResponsibilitiesPane({super.key, required this.cardId, required this.companyId}); }`.

**Behaviour:** rows grouped by `responsibility_area` in `area_sort`/`task_sort` order; each row shows the task name (editable inline), its hours/month, its criticality, and a `⋮` menu with Edit (opens the existing task dialog for the full costing model), Archive and Delete. `removalActionForTask` decides which of Archive/Delete is offered — Delete only when the task has no `wp_task_assignments` rows. Add and "Link existing" reuse the Tasks tab's flows.

- [ ] **Step 1: Write the failing test**

Create `test/features/workforce_planning/role/responsibilities_pane_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/features/workforce_planning/role/responsibilities_pane.dart';
import 'package:payroll_flutter/features/workforce_planning/wp_providers.dart';

import '../../../support/supabase_stub.dart';

WpTask _task({
  required String id,
  required String name,
  required String area,
  int areaSort = 0,
  int taskSort = 0,
}) => WpTask(
  id: id,
  companyId: 'co-1',
  name: name,
  roleScorecardId: 'card-1',
  responsibilityArea: area,
  areaSort: areaSort,
  taskSort: taskSort,
  timesSource: 'manual',
  minutesSource: 'manual',
  driverFactor: 1,
  isEssential: true,
  isExpectation: false,
  status: 'ACTIVE',
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initSupabaseStub();
  });

  Future<void> pump(WidgetTester tester, List<WpTask> tasks) async {
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wpTasksProvider.overrideWith((ref) async => tasks),
          wpAllTaskComputedProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ResponsibilitiesPane(cardId: 'card-1', companyId: 'co-1'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('groups by area in authored order, not alphabetically', (
    tester,
  ) async {
    // The card PDF and contract Annex A render in authored order; a pane that
    // sorted by name would show a different order than the document.
    await pump(tester, [
      _task(id: 't1', name: 'Zebra task', area: 'Setup', taskSort: 0),
      _task(id: 't2', name: 'Apple task', area: 'Setup', taskSort: 1),
      _task(id: 't3', name: 'Only one', area: 'Research', areaSort: 1),
    ]);

    final areas = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    expect(areas.indexOf('Setup'), lessThan(areas.indexOf('Research')));
    expect(areas.indexOf('Zebra task'), lessThan(areas.indexOf('Apple task')));
  });

  testWidgets('an uncosted responsibility reads as a dash, never as zero', (
    tester,
  ) async {
    // 0.0h would read as "this takes no time"; unknown and idle differ.
    await pump(tester, [_task(id: 't1', name: 'Uncosted work', area: 'Setup')]);
    expect(find.text('0.0'), findsNothing);
    expect(find.text('—'), findsWidgets);
  });

  testWidgets('shows only the card\'s own responsibilities', (tester) async {
    await pump(tester, [
      _task(id: 't1', name: 'Mine', area: 'Setup'),
      WpTask(
        id: 't9',
        companyId: 'co-1',
        name: 'Someone else\'s',
        roleScorecardId: 'card-2',
        responsibilityArea: 'Other',
        timesSource: 'manual',
        minutesSource: 'manual',
        driverFactor: 1,
        isEssential: true,
        isExpectation: false,
        status: 'ACTIVE',
      ),
    ]);
    expect(find.text('Mine'), findsOneWidget);
    expect(find.text('Someone else\'s'), findsNothing);
  });

  testWidgets('hides archived responsibilities', (tester) async {
    await pump(tester, [
      _task(id: 't1', name: 'Live work', area: 'Setup'),
      WpTask(
        id: 't2',
        companyId: 'co-1',
        name: 'Retired work',
        roleScorecardId: 'card-1',
        responsibilityArea: 'Setup',
        timesSource: 'manual',
        minutesSource: 'manual',
        driverFactor: 1,
        isEssential: true,
        isExpectation: false,
        status: 'ARCHIVED',
      ),
    ]);
    expect(find.text('Live work'), findsOneWidget);
    expect(find.text('Retired work'), findsNothing);
  });
}
```

These parameter names are verified against `lib/data/models/workforce_planning.dart:142-171`: `areaSort`, `taskSort`, `isEssential`, `isExpectation`, `status`, `responsibilityArea`, `timesSource`, `minutesSource` and `driverFactor` all exist with those spellings, and every one except `id`/`companyId`/`name` carries a default — so the helper above can drop any argument it does not care about.

- [ ] **Step 2: Run it and watch it fail**

```
flutter test test/features/workforce_planning/role/responsibilities_pane_test.dart
```

Expected: compile failure — `responsibilities_pane.dart` does not exist.

- [ ] **Step 3: Implement the pane**

Create `lib/features/workforce_planning/role/responsibilities_pane.dart`. Filter `wpTasksProvider` to `roleScorecardId == cardId && status == 'ACTIVE'`, group by `responsibilityArea` ordered by `areaSort` then `taskSort`, and render each area as a header with its rows beneath.

Per row: the name in a keyed `TextFormField`, the hours from `wpAllTaskComputedProvider` rendered `'—'` when absent, a criticality chip, and a `PopupMenuButton` offering Edit / Archive / Delete. Gate the last two:

```dart
// A task with assignments carries history that costing and load attribution
// hang off — archive keeps the row addressable instead of destroying it.
final action = removalActionForTask(assignmentCount: assignmentsFor(t.id));
```

Save via `diffResponsibilities` + `WorkforcePlanningRepository.saveResponsibilities`, exactly as the card editor does at `role_scorecard_form_screen.dart:492-520` — read that block before writing this one; it diffs against the raw rows captured on load, never against the upsert's return.

After every mutation call the same invalidation set as `tasks_tab.dart:1426`, plus `roleScorecardByIdProvider(cardId)`.

- [ ] **Step 4: Run it and watch it pass**

```
flutter test test/features/workforce_planning/role/responsibilities_pane_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 5: Mount, suite, analyzer, commit**

Mount below `RoleDetailsPane` in the workbench.

```
flutter test
flutter analyze lib test
```

```bash
git add lib/features/workforce_planning/role/responsibilities_pane.dart lib/features/workforce_planning/role/role_workbench_screen.dart test/features/workforce_planning/role/responsibilities_pane_test.dart
git commit -m "feat(wp): responsibilities pane on the workbench"
```

---

### Task 5: The measurable definition form and its source autocomplete

**Files:**
- Create: `lib/features/kpi_library/kpi_definition_form.dart`
- Modify: `lib/data/repositories/role_scorecard_repository.dart` (add `distinctKpiSources`)
- Modify: `lib/features/kpi_library/kpi_form_dialog.dart` (host the new form)
- Modify: `lib/features/kpi_library/kpi_library_screen.dart` (pass `writeDefinition: true`)
- Test: `test/features/kpi_library/kpi_definition_form_test.dart`

**Interfaces:**
- Consumes: `kKpiValueTypes`, `kKpiCadences`, `kKpiProofTypes`, `kpiDefinitionGaps` (`lib/features/kpi_library/kpi_measurable.dart`); `Kpi` (`lib/data/models/kpi.dart`).
- Produces: `class KpiDefinitionForm extends StatefulWidget` exposing its current values through a `ValueChanged<KpiDefinitionDraft> onChanged`; `class KpiDefinitionDraft { String valueType; String? numeratorLabel, numeratorSource, denominatorLabel, denominatorSource, unit, proofType; String cadence; }`; `Future<List<String>> RoleScorecardRepository.distinctKpiSources()` and `kpiSourcesProvider`.

**Behaviour:** the denominator fields appear only when `valueType == 'RATIO'`. Source fields are `Autocomplete<String>` over `distinctKpiSources()` — free text, suggestions only, so a new channel needs no migration. A live "still needed: unit, source" line renders `kpiDefinitionGaps`.

**Also fix here** (carried from Plan 1's final review): `saveLibraryKpi`'s `writeDefinition` currently defaults false and the library screen never passes it, so the definition cannot be saved at all. Pass `writeDefinition: true` from the library screen now that the dialog collects the fields.

- [ ] **Step 1: Write the failing test**

Create `test/features/kpi_library/kpi_definition_form_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/kpi_library/kpi_definition_form.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    KpiDefinitionDraft? initial,
    List<String> sources = const ['BigSeller', 'Lark'],
  }) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: KpiDefinitionForm(
              initial: initial,
              knownSources: sources,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a COUNT hides the denominator fields', (tester) async {
    await pump(tester, initial: KpiDefinitionDraft(valueType: 'COUNT'));
    expect(find.text('Counted against'), findsNothing);
  });

  testWidgets('a RATIO reveals them', (tester) async {
    await pump(tester, initial: KpiDefinitionDraft(valueType: 'RATIO'));
    expect(find.text('Counted against'), findsOneWidget);
  });

  testWidgets('names what is still missing', (tester) async {
    await pump(tester, initial: KpiDefinitionDraft(valueType: 'COUNT'));
    expect(find.textContaining('unit'), findsWidgets);
    expect(find.textContaining('what is counted'), findsWidgets);
  });

  testWidgets('suggests sources already in use without forcing them', (
    tester,
  ) async {
    await pump(tester, initial: KpiDefinitionDraft(valueType: 'COUNT'));
    final source = find.ancestor(
      of: find.text('Source'),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(source.first, 'Big');
    await tester.pumpAndSettle();
    expect(find.text('BigSeller'), findsWidgets);

    // Free text must still be accepted — a new channel should not need a
    // migration or a code change.
    await tester.enterText(source.first, 'Temu');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

```
flutter test test/features/kpi_library/kpi_definition_form_test.dart
```

Expected: compile failure — `kpi_definition_form.dart` does not exist.

- [ ] **Step 3: Add the repository method and provider**

In `lib/data/repositories/role_scorecard_repository.dart`:

```dart
  /// Source systems already named on some KPI, for the definition form's
  /// autocomplete. Suggestions only — the columns are free text so a new
  /// channel (Shopee, Shopify, Temu) needs neither a migration nor a release.
  Future<List<String>> distinctKpiSources() async {
    final rows = await _client
        .from('kpis')
        .select('numerator_source, denominator_source');
    final out = <String>{};
    for (final r in (rows as List).cast<Map<String, dynamic>>()) {
      for (final key in ['numerator_source', 'denominator_source']) {
        final v = (r[key] as String?)?.trim();
        if (v != null && v.isNotEmpty) out.add(v);
      }
    }
    final list = out.toList()..sort();
    return list;
  }
```

and beside the other providers:

```dart
final kpiSourcesProvider = FutureProvider<List<String>>(
  (ref) => ref.watch(roleScorecardRepositoryProvider).distinctKpiSources(),
);
```

- [ ] **Step 4: Implement the form, wire the dialog**

Create `lib/features/kpi_library/kpi_definition_form.dart` with `KpiDefinitionDraft` and `KpiDefinitionForm` as specified above. Host it inside `KpiFormDialog` below the existing name/category/description fields, and in `kpi_library_screen.dart` pass the draft's values plus `writeDefinition: true` into `saveLibraryKpi`.

- [ ] **Step 5: Run the focused tests, then the suite**

```
flutter test test/features/kpi_library/kpi_definition_form_test.dart
flutter test test/features/kpi_library/kpi_library_screen_test.dart
flutter test
flutter analyze lib test
```

Expected: all pass, 0 errors, 0 warnings.

- [ ] **Step 6: Commit**

```bash
git add lib/features/kpi_library/kpi_definition_form.dart lib/features/kpi_library/kpi_form_dialog.dart lib/features/kpi_library/kpi_library_screen.dart lib/data/repositories/role_scorecard_repository.dart test/features/kpi_library/kpi_definition_form_test.dart
git commit -m "feat(kpi): measurable definition form with source autocomplete"
```

---

### Task 6: KPIs pane

**Files:**
- Create: `lib/features/workforce_planning/role/kpis_pane.dart`
- Modify: `lib/features/workforce_planning/role/role_workbench_screen.dart`
- Modify: `lib/data/repositories/role_scorecard_repository.dart` (`saveRoleScorecardKpis` caller-supplied cadence)
- Test: `test/features/workforce_planning/role/kpis_pane_test.dart`

**Interfaces:**
- Consumes: `roleKpisProvider(cardId)`, `kpiLibraryProvider`, `saveRoleScorecardKpis`, `KpiLinkInput`; `KpiGoal`, `GoalDirection`, `formatGoal`, `parseLegacyTarget` (`lib/data/models/kpi_goal.dart`); `computeReadingValue`, `isOnTrack` (`lib/features/kpi_library/kpi_reading.dart`); `isKpiDefined`, `isMeasurableForRole` (`lib/features/kpi_library/kpi_measurable.dart`); `KpiDefinitionForm` (Task 5).
- Produces: `class KpisPane extends ConsumerStatefulWidget { const KpisPane({super.key, required this.cardId, required this.companyId}); }`.

**Behaviour:** one row per `role_scorecard_kpis` link showing name, goal (direction dropdown + value + the KPI's unit), cadence and whether it is measurable. Add offers the library (`Autocomplete`) or a new KPI via `KpiDefinitionForm`. A live preview renders `computeReadingValue` + `isOnTrack` against sample counts as the manager types the goal. Removing a link deletes it (Plan 1's `removalActionForKpiLink`; `hasLogs` is false until Spec B).

**Two carried fixes, both required here:**
1. When a link's goal is absent but its legacy `target` text is not, offer `parseLegacyTarget`'s reading as a pre-filled suggestion the manager confirms. Never apply it silently — a bare "98%" carries no direction, which is why the parser returns null for it.
2. **`KpiLinkInput.cadence` must be supplied for every link this pane saves.** Plan 1 deliberately removed the repository's `cadence ??= kpi.cadence` fallback because it silently rewrote every frequency to "Weekly"; the workbench is the caller that now has to pass the real value. Also seed a NEW library KPI's `cadence` from the form rather than the bare `'WEEKLY'` default — the migration's one-shot backfill cannot reach rows created after it ran.

- [ ] **Step 1: Write the failing test**

Create `test/features/workforce_planning/role/kpis_pane_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/kpi_goal.dart';
import 'package:payroll_flutter/data/models/role_kpi.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';
import 'package:payroll_flutter/features/workforce_planning/role/kpis_pane.dart';

import '../../../support/supabase_stub.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initSupabaseStub();
  });

  Future<void> pump(WidgetTester tester, List<RoleKpi> kpis) async {
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roleKpisProvider('card-1').overrideWith((ref) async => kpis),
          kpiLibraryProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: KpisPane(cardId: 'card-1', companyId: 'co-1'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders a structured goal with its unit', (tester) async {
    await pump(tester, const [
      RoleKpi(
        kpiId: 'k1',
        name: 'Return Rate',
        goal: KpiGoal(direction: GoalDirection.lte, value: 3),
        unit: '%',
        cadence: 'WEEKLY',
      ),
    ]);
    expect(find.text('Return Rate'), findsOneWidget);
    expect(find.textContaining('≤ 3%'), findsWidgets);
  });

  testWidgets('flags a link with no goal as not measurable', (tester) async {
    await pump(tester, const [
      RoleKpi(kpiId: 'k1', name: 'Setup Accuracy', target: 'At least 98%'),
    ]);
    expect(find.textContaining('not measurable'), findsWidgets);
  });

  testWidgets('offers the legacy target as a suggestion, not a fact', (
    tester,
  ) async {
    // "At least 98%" is readable; the manager still confirms it, because a
    // bare "98%" is not and we must never guess a direction.
    await pump(tester, const [
      RoleKpi(kpiId: 'k1', name: 'Setup Accuracy', target: 'At least 98%'),
    ]);
    expect(find.textContaining('98'), findsWidgets);
    expect(find.textContaining('Suggested'), findsWidgets);
  });

  testWidgets('says nothing is measured yet when the role has no KPIs', (
    tester,
  ) async {
    await pump(tester, const []);
    expect(find.textContaining('No KPIs'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

```
flutter test test/features/workforce_planning/role/kpis_pane_test.dart
```

Expected: compile failure — `kpis_pane.dart` does not exist.

- [ ] **Step 3: Implement the pane**

Create `lib/features/workforce_planning/role/kpis_pane.dart` per the behaviour above. Every `KpiLinkInput` it constructs must carry `goal`, `unit` AND `cadence`:

```dart
        KpiLinkInput(
          kpiId: draft.kpiId,
          name: draft.name,
          target: draft.legacyTarget,
          frequency: draft.legacyFrequency,
          goal: draft.goal,
          unit: draft.unit,
          // Required. Plan 1 removed the repository's `cadence ??= kpi.cadence`
          // fallback because it silently rewrote every link's frequency to
          // "Weekly"; this pane is the caller that must supply the real value.
          cadence: draft.cadence,
        ),
```

- [ ] **Step 4: Run it and watch it pass**

```
flutter test test/features/workforce_planning/role/kpis_pane_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 5: Mount, suite, analyzer, commit**

```
flutter test
flutter analyze lib test
```

```bash
git add lib/features/workforce_planning/role/kpis_pane.dart lib/features/workforce_planning/role/role_workbench_screen.dart test/features/workforce_planning/role/kpis_pane_test.dart
git commit -m "feat(wp): KPIs pane with structured goals on the workbench"
```

---

### Task 7: People pane

**Files:**
- Create: `lib/features/workforce_planning/role/people_pane.dart`
- Modify: `lib/features/workforce_planning/role/role_workbench_screen.dart`
- Test: `test/features/workforce_planning/role/people_pane_test.dart`

**Interfaces:**
- Consumes: `wpActiveEmployeesProvider`, `wpPersonLoadsProvider` (`lib/features/workforce_planning/wp_providers.dart`); `EmployeeKpiAssignmentSection` (`lib/features/employees/profile/tabs/role_tab.dart:583`); `validateKpiSet`, `KpiSetVerdict`, `employeeNeedsKpiSet` (`lib/features/kpi_library/kpi_set_rules.dart`); `roleKpisProvider`, `employeeAssignedKpiIdsProvider`.
- Produces: `class PeoplePane extends ConsumerWidget { const PeoplePane({super.key, required this.cardId}); }`.

**Behaviour:** one row per ACTIVE non-deleted holder, with their load percentage and `tracks N of M`, or a warning chip when `employeeNeedsKpiSet` is true. Tapping a holder expands `EmployeeKpiAssignmentSection` for them, with `validateKpiSet`'s problems blocking save and its warnings shown but not blocking.

- [ ] **Step 1: Write the failing test**

Create `test/features/workforce_planning/role/people_pane_test.dart`. The
`Employee` and `WpPersonLoad` helpers below are lifted from
`test/features/workforce_planning/role_lens_test.dart`, which is this repo's
established way of standing up these providers:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/role_kpi.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';
import 'package:payroll_flutter/data/repositories/role_scorecard_repository.dart';
import 'package:payroll_flutter/features/workforce_planning/role/people_pane.dart';
import 'package:payroll_flutter/features/workforce_planning/wp_providers.dart';

import '../../../support/supabase_stub.dart';

Employee _emp(String id, String name) => Employee(
  id: id,
  companyId: 'co-1',
  employeeNumber: id,
  firstName: name,
  lastName: 'X',
  roleScorecardId: 'card-1',
  employmentType: 'FULL_TIME',
  employmentStatus: 'ACTIVE',
  hireDate: DateTime(2024, 1, 1),
  isRankAndFile: true,
  isOtEligible: false,
  isNdEligible: false,
  isHolidayPayEligible: false,
  sssEligibilityOverride: false,
  philhealthEligibilityOverride: false,
  pagibigEligibilityOverride: false,
  taxOnFullEarnings: false,
);

WpPersonLoad _load(String id) => WpPersonLoad(
  employeeId: id,
  companyId: 'co-1',
  capacityHours: 160,
  growthMultiplier: 1,
);

const _roleKpis = [
  RoleKpi(kpiId: 'k1', name: 'Return Rate'),
  RoleKpi(kpiId: 'k2', name: 'Setup Accuracy'),
  RoleKpi(kpiId: 'k3', name: 'On-Time Dispatch'),
];

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initSupabaseStub();
  });

  Future<void> pump(
    WidgetTester tester, {
    required Set<String> assigned,
  }) async {
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wpActiveEmployeesProvider.overrideWith(
            (ref) async => [_emp('e1', 'Marvin')],
          ),
          wpPersonLoadsProvider.overrideWith((ref) async => [_load('e1')]),
          roleKpisProvider('card-1').overrideWith((ref) async => _roleKpis),
          employeeAssignedKpiIdsProvider(
            'e1',
          ).overrideWith((ref) async => assigned),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PeoplePane(cardId: 'card-1'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a holder with no stored set is flagged, not shown as full', (
    tester,
  ) async {
    // Before 20260811000002 an empty set meant "tracks everything", so this
    // person would have read as tracking all three. Under scoring that is the
    // difference between measured-on-three and measured-on-ten.
    await pump(tester, assigned: const {});
    expect(find.textContaining('No KPI set'), findsOneWidget);
    expect(find.textContaining('tracks 3 of 3'), findsNothing);
  });

  testWidgets("shows how many of the role's KPIs a holder tracks", (
    tester,
  ) async {
    await pump(tester, assigned: {'k1', 'k2'});
    expect(find.textContaining('tracks 2 of 3'), findsOneWidget);
    expect(find.textContaining('No KPI set'), findsNothing);
  });

  testWidgets('names the holder and their load', (tester) async {
    await pump(tester, assigned: {'k1'});
    expect(find.textContaining('Marvin'), findsOneWidget);
  });
}
```

If `Employee`'s constructor has gained or lost a required field since
`role_lens_test.dart` was written, follow that file rather than this listing —
it is compiled against the current model and this is a copy.

- [ ] **Step 2: Run it and watch it fail**

```
flutter test test/features/workforce_planning/role/people_pane_test.dart
```

Expected: compile failure — `people_pane.dart` does not exist.

- [ ] **Step 3: Implement the pane**

Create `lib/features/workforce_planning/role/people_pane.dart` per the behaviour above.

```dart
// An employee with no stored set is a gap to close, not somebody tracked on
// everything — see 20260811000002. Rendering them as "tracks 3 of 3" is the
// exact misreading the migration exists to prevent.
if (employeeNeedsKpiSet(assigned)) ... // warning chip
```

- [ ] **Step 4: Run it and watch it pass**

```
flutter test test/features/workforce_planning/role/people_pane_test.dart
```

Expected: `All tests passed!` with `+2`, no skips.

- [ ] **Step 5: Mount, suite, analyzer, commit**

```
flutter test
flutter analyze lib test
```

```bash
git add lib/features/workforce_planning/role/people_pane.dart lib/features/workforce_planning/role/role_workbench_screen.dart test/features/workforce_planning/role/people_pane_test.dart
git commit -m "feat(wp): people pane with per-employee KPI sets"
```

---

## Done when

- `/workforce-planning/roles/:id` shows all four panes and each saves independently.
- Clicking a Roles-tab row opens it.
- `flutter test` green; `flutter analyze lib test` 0 errors, 0 warnings.
- `20260811000002_explicit_employee_kpi_sets.sql` committed and handed to the user, **not applied**.
- The card editor still works, untouched.

## Next plans

- **Plan 3 — retire the card editor.** Delete `role_scorecard_form_screen.dart` and the `/responsibility-cards/new` and `/:id/edit` routes; card view gains "Edit in Workforce Planning"; "New role" moves to the Roles tab. Written once this plan lands, against its real files.
- **Plan 4 — Needs attention.** The "N people with no KPI set" and "N KPIs not yet measurable" chips, plus click-through on the existing ones.
