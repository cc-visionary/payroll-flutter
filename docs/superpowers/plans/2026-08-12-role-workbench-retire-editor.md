# Role Workbench — Plan 3: Retire the Card Editor

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Responsibility Card a pure artifact — view, PDF, and the record hiring reads — by routing every edit entry point at the workbench and deleting `role_scorecard_form_screen.dart` and its two routes.

**Architecture:** Repoint the two navigation entry points first, add the one capability the workbench still lacks (creating a role), and only then delete the old screen. Deleting last means every step before it is independently revertible and nothing is stranded mid-plan.

**Tech Stack:** Flutter (Material 3, Riverpod, GoRouter), Supabase Postgres, `flutter_test`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-11-role-workbench-design.md`. Plans 1 and 2 are merged at `053aa07`; their Global Constraints still bind.
- **Deletion is the LAST code task.** Until Task 4 runs, both editors work. Do not disable, gut, or partially delete the old screen earlier — a half-deleted editor is worse than either state.
- The card **view** (`role_scorecard_detail_screen.dart`), the **PDF** (`role_card_pdf.dart`, `/responsibility-cards/:id/pdf`), the **list** as a browse index, and everything in `lib/features/hiring/` that reads a role card all keep working unchanged. Only editing moves.
- The repo gates on `flutter analyze` only: 0 errors, 0 warnings; 192 pre-existing `info` lints — add none.
- **Do not run `dart format`.** Match the surrounding style of each file.
- Never claim a test passed or the analyzer was clean without pasting the command output.
- Baseline: **1338 passing, 1 skipped**, analyzer clean.
- Widget tests use `initSupabaseStub()` from `test/support/supabase_stub.dart`, and need a tall `tester.view.physicalSize` or content below the fold never mounts.
- Three migrations remain unapplied (`20260811000001`, `20260811000002`, `20260812000001`). This plan adds none and depends on none.

## File Structure

| File | Responsibility |
|---|---|
| `lib/features/responsibility_cards/role_scorecard_detail_screen.dart` (modify) | Edit button → workbench |
| `lib/features/responsibility_cards/responsibility_cards_screen.dart` (modify) | row Edit → workbench; "New card" button removed |
| `lib/features/workforce_planning/role/new_role_dialog.dart` (new) | collects the minimum a card needs, creates it, returns its id |
| `lib/features/workforce_planning/tabs/role_view_tab.dart` (modify) | "+ New role" action |
| `lib/features/responsibility_cards/role_scorecard_form_screen.dart` (DELETE) | the old editor |
| `lib/app/router.dart` (modify) | delete `/responsibility-cards/new` and `/:id/edit` |
| `lib/features/workforce_planning/role/responsibilities_pane.dart` (modify) | the resync Plan 2 deferred |

---

### Task 1: Both Edit entry points open the workbench

**Files:**
- Modify: `lib/features/responsibility_cards/role_scorecard_detail_screen.dart:40-56`
- Modify: `lib/features/responsibility_cards/responsibility_cards_screen.dart:66-69`
- Test: `test/features/responsibility_cards/edit_routes_to_workbench_test.dart`

**Interfaces:**
- Consumes: the route `/workforce-planning/roles/:id`, live since Plan 2.
- Produces: nothing new; two call sites change target.

**Three** call sites push `/responsibility-cards/$cardId/edit`, not two:

- the card view's Edit button (`role_scorecard_detail_screen.dart:47,52`),
- the list row's `onEdit` (`responsibility_cards_screen.dart:68`),
- and `unassigned_tab.dart:366`, where "Propose role" drafts an INACTIVE card
  from a cluster and lands HR on it to finish it.

All three become `/workforce-planning/roles/$cardId`. The third is the one that
would otherwise become a dead link when Task 4 removes the route. It is safe to
repoint: `RoleScorecardRepository.byId` (`:87-101`) has no `is_active` filter,
so the workbench opens a draft, and its header already renders "· inactive".

Relabel the card view's button from **Edit** to **Edit in Workforce Planning** on desktop (the tooltip likewise on mobile). The destination is a different screen in a different section; a button still saying "Edit" would read as a bug the first time it navigates away.

- [ ] **Step 1: Write the failing test**

Create `test/features/responsibility_cards/edit_routes_to_workbench_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/features/documents/providers.dart';
import 'package:payroll_flutter/features/responsibility_cards/role_scorecard_detail_screen.dart';

import '../../support/supabase_stub.dart';

RoleScorecard _card() => RoleScorecard(
  id: 'card-1',
  companyId: 'co-1',
  jobTitle: 'Kiosk Sales Representative',
  missionStatement: 'Sell through the kiosk.',
  responsibilities: const [],
  kpis: const [],
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

  testWidgets('the card view sends Edit to the workbench, not the old editor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final pushed = <String>[];
    final router = GoRouter(
      initialLocation: '/responsibility-cards/card-1',
      routes: [
        GoRoute(
          path: '/responsibility-cards/:id',
          builder: (c, s) =>
              RoleScorecardDetailScreen(cardId: s.pathParameters['id']!),
        ),
        // Catch every destination the button could reach, so a push to the
        // retired /edit route fails loudly here rather than silently 404ing.
        GoRoute(
          path: '/workforce-planning/roles/:id',
          builder: (c, s) {
            pushed.add('/workforce-planning/roles/${s.pathParameters['id']}');
            return const Scaffold(body: Text('workbench'));
          },
        ),
        GoRoute(
          path: '/responsibility-cards/:id/edit',
          builder: (c, s) {
            pushed.add('/responsibility-cards/${s.pathParameters['id']}/edit');
            return const Scaffold(body: Text('old editor'));
          },
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roleScorecardByIdProvider('card-1').overrideWith((ref) async => _card()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    final edit = find.textContaining('Edit');
    expect(edit, findsWidgets, reason: 'the card view should offer an edit affordance');
    await tester.tap(edit.first);
    await tester.pumpAndSettle();

    expect(pushed, ['/workforce-planning/roles/card-1']);
  });
}
```

If the detail screen gates its Edit button on a role/permission provider, override that provider so the button renders — read the screen before writing, and say in your report what you had to override.

- [ ] **Step 2: Run it and watch it fail**

```
flutter test test/features/responsibility_cards/edit_routes_to_workbench_test.dart
```

Expected: FAIL — `pushed` contains `/responsibility-cards/card-1/edit`.

- [ ] **Step 3: Repoint both call sites**

In `role_scorecard_detail_screen.dart`, both branches of the Edit action:

```dart
                  ? IconButton(
                      tooltip: 'Edit in Workforce Planning',
                      onPressed: () =>
                          context.push('/workforce-planning/roles/$cardId'),
                      icon: const Icon(Icons.edit),
                    )
                  : FilledButton.icon(
                      onPressed: () =>
                          context.push('/workforce-planning/roles/$cardId'),
                      icon: const Icon(Icons.edit),
                      label: const Text('Edit in Workforce Planning'),
                    ),
```

In `responsibility_cards_screen.dart:68`:

```dart
                  onEdit: () =>
                      context.push('/workforce-planning/roles/${rows[i].id}'),
```

- [ ] **Step 4: Run it and watch it pass, then the suite**

```
flutter test test/features/responsibility_cards/edit_routes_to_workbench_test.dart
flutter test
flutter analyze lib test
```

Expected: focused green; suite ≥ 1339 passing, 1 skipped; 0 errors, 0 warnings.

- [ ] **Step 5: Commit**

```bash
git add lib/features/responsibility_cards/role_scorecard_detail_screen.dart lib/features/responsibility_cards/responsibility_cards_screen.dart test/features/responsibility_cards/edit_routes_to_workbench_test.dart
git commit -m "feat(wp): card Edit opens the workbench, not the old editor"
```

---

### Task 2: Creating a role moves to the Roles tab

**Files:**
- Create: `lib/features/workforce_planning/role/new_role_dialog.dart`
- Modify: `lib/features/workforce_planning/tabs/role_view_tab.dart`
- Modify: `lib/features/responsibility_cards/responsibility_cards_screen.dart:30-47` (remove the "New card" action)
- Test: `test/features/workforce_planning/role/new_role_dialog_test.dart`

**Interfaces:**
- Consumes: `RoleScorecardRepository.upsert` via `roleScorecardRepositoryProvider`; `userProfileProvider` for `companyId`; `_uuid()`'s equivalent — read how `role_scorecard_form_screen.dart` generates a new card id before it is deleted, and reuse that approach.
- Produces: `Future<String?> showNewRoleDialog(BuildContext context, WidgetRef ref)` returning the new card's id, or null if cancelled.

**The minimum a card needs.** `RoleScorecard`'s constructor requires `jobTitle`, `missionStatement`, `wageType`, `workHoursPerDay`, `workDaysPerWeek`, `isActive` and `effectiveDate`. The dialog collects **job title and mission** — both of which the old editor validated as required — and defaults the rest exactly as the old editor's new-card mode did: `MONTHLY`, `8`, `Monday to Saturday`, active, effective today. Everything else is edited in the workbench's Role details pane immediately afterwards.

Do not put the whole details form in this dialog. The point of the workbench is that a role is authored in one place; a second full form would recreate the problem this project exists to remove.

- [ ] **Step 1: Write the failing test**

Create `test/features/workforce_planning/role/new_role_dialog_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/workforce_planning/role/new_role_dialog.dart';

import '../../../support/supabase_stub.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initSupabaseStub();
  });

  /// Pumps a host whose only job is to open the dialog under test.
  Future<void> openDialog(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () => showNewRoleDialog(context, ref),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('refuses to create a role with no job title', (tester) async {
    await openDialog(tester);

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    // Still open, with a complaint — never a card with a blank title.
    expect(find.text('Create'), findsOneWidget);
    expect(find.textContaining('title'), findsWidgets);
  });

  testWidgets('refuses to create a role with no mission', (tester) async {
    await openDialog(tester);

    await tester.enterText(find.byType(TextFormField).first, 'Kiosk Rep');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('Create'), findsOneWidget);
    expect(find.textContaining('ission'), findsWidgets);
  });
}
```

These two cases pin the validation only. Creating a card for real needs a repository, and this repo has no established fake for `roleScorecardRepositoryProvider`; if you can override that provider with a recording fake as cheaply as `test/data/repositories/role_scorecard_kpi_links_test.dart` does for its client, add a third case asserting the created card carries the defaults above. If you cannot do it cleanly, say so in your report rather than contorting the test — the two validation cases are the required part.

- [ ] **Step 2: Run it and watch it fail**

```
flutter test test/features/workforce_planning/role/new_role_dialog_test.dart
```

Expected: compile failure — `new_role_dialog.dart` does not exist.

- [ ] **Step 3: Implement the dialog**

Create `lib/features/workforce_planning/role/new_role_dialog.dart` with `showNewRoleDialog`. An `AlertDialog` with two `TextFormField`s in a `Form`, Cancel and Create. On Create: validate, build the `RoleScorecard` with the defaults above, `upsert` it, invalidate `roleScorecardListProvider`, and `Navigator.pop` the new id.

- [ ] **Step 4: Wire it into the Roles tab**

Add a **+ New role** action to `role_view_tab.dart`'s header, visible on the same permission the tab already requires. On success, `context.push('/workforce-planning/roles/$id')` so the manager lands in the workbench with the role open.

- [ ] **Step 5: Remove the cards list's New card button**

Delete the `actions:` block at `responsibility_cards_screen.dart:30-47`. The list becomes a browse-and-print index. Leave `canManage` in place if the row actions still use it; remove it only if it becomes genuinely unused, and let the analyzer tell you which.

- [ ] **Step 6: Run everything**

```
flutter test test/features/workforce_planning/role/new_role_dialog_test.dart
flutter test
flutter analyze lib test
```

Expected: green; 0 errors, 0 warnings.

- [ ] **Step 7: Commit**

```bash
git add lib/features/workforce_planning/role/new_role_dialog.dart lib/features/workforce_planning/tabs/role_view_tab.dart lib/features/responsibility_cards/responsibility_cards_screen.dart test/features/workforce_planning/role/new_role_dialog_test.dart
git commit -m "feat(wp): create a role from the Roles tab"
```

---

### Task 3: The Responsibilities pane gets its resync

**Files:**
- Modify: `lib/features/workforce_planning/role/responsibilities_pane.dart`
- Test: `test/features/workforce_planning/role/responsibilities_pane_test.dart`

**Interfaces:**
- Consumes: the pattern already shipped in `kpis_pane.dart` — `_isDirty` comparing drafts against a baseline captured in `_captureFrom`, and `_resync()` behind a confirm dialog when dirty, silent when pristine.
- Produces: nothing new.

Plan 2 deferred this. The pane holds a capture-once snapshot of
`_areas`/`_existingRows` that only refreshes on its own mutations, so another
screen invalidating `wpTasksProvider` leaves it showing stale names and order
beside live hours. It matters more here than in the KPIs pane: **this pane's
order is what the role-card PDF and contract Annex A render.**

**Do NOT port the dirty check.** An earlier draft of this task said to mirror
`kpis_pane.dart` wholesale, including `_isDirty` and a confirm dialog. That was
wrong. `KpisPane` stages edits in `TextEditingController`s behind its own Save
button, so it has genuine unsaved state to protect. This pane has none: every
mutation path (`_addArea`, `_linkExisting`, `_addTask`, `_editTask`) persists
immediately from a dialog, names render as plain `Text`, and there is no Save
button. A dirty check here would always be false — the "worse than none" case.

Fix the staleness itself. Prefer **deleting the `_captured` gate** and deriving
the drafts from the provider each build, which removes the bug class rather
than giving the user a manual workaround. Before doing that, check whether
anything in the pane keys off draft identity or otherwise needs those draft
objects stable across builds; if it does, keep the gate and add a
silent-always refresh `IconButton` instead. Either way there is no confirm
dialog — copy claiming to discard typing would be a lie.

Document the divergence from `kpis_pane.dart` in the code, not only in a
report: the next reader will see two panes on one screen behaving differently
and needs the reason without re-deriving it.

- [ ] **Step 1: Write the failing test**

Add to `test/features/workforce_planning/role/responsibilities_pane_test.dart` one case: an external change to what `wpTasksProvider` returns surfaces in the pane. Whether that means "after tapping refresh" or "on the next build" depends on which fix the check above led you to.

Write only tests that correspond to reachable behaviour. There is no dirty state and no confirm dialog here, so there is nothing to test for either — do not manufacture a scenario to fill the shape of the KPIs pane's test list.

- [ ] **Step 2: Run it and watch it fail**

```
flutter test test/features/workforce_planning/role/responsibilities_pane_test.dart
```

Expected: FAIL — no refresh control exists.

- [ ] **Step 3: Implement**

Apply whichever fix the identity-key check indicated: drop the `_captured` gate, or keep it behind a silent refresh control. No `_isDirty`, no `_baseline`, no confirm dialog.

- [ ] **Step 4: Run everything**

```
flutter test test/features/workforce_planning/role/responsibilities_pane_test.dart
flutter test
flutter analyze lib test
```

- [ ] **Step 5: Commit**

```bash
git add lib/features/workforce_planning/role/responsibilities_pane.dart test/features/workforce_planning/role/responsibilities_pane_test.dart
git commit -m "feat(wp): dirty-checked resync on the responsibilities pane"
```

---

### Task 4: Delete the card editor

**Files:**
- Delete: `lib/features/responsibility_cards/role_scorecard_form_screen.dart`
- Delete: `test/features/responsibility_cards/scorecard_row_delete_test.dart`
- Modify: `lib/app/router.dart` — remove the routes at `:161-164` and `:175-179`, and the now-unused import

**This is the irreversible step. Do not start it until Tasks 1-3 are committed and green.**

The editor is 1,409 lines and its only remaining referents are the two routes and one test. `scorecard_row_delete_test.dart` exists solely to guard that screen's keyed-row bug (`6ae6c9b`); with the screen gone it has nothing to test. Its lesson lives on in the panes' own keyed-row tests, so delete it rather than porting it.

**Deleting this file also closes a real latent defect** recorded during Plan 2: `role_scorecard_form_screen.dart:586,625` pass `initialValue` to `DropdownButtonFormField` with no `_present` guard, so a card pointing at a deleted department would assert and crash that editor on open. It was left alone precisely because this task removes it.

- [ ] **Step 1: Confirm nothing else references it**

```
grep -rn "RoleScorecardFormScreen\|role_scorecard_form_screen" lib test
```

Expected: exactly three hits — two in `lib/app/router.dart`, one in `test/features/responsibility_cards/scorecard_row_delete_test.dart`. **If there are others, stop and report them** rather than deleting; something referenced it that this plan did not account for.

- [ ] **Step 2: Delete**

```bash
git rm lib/features/responsibility_cards/role_scorecard_form_screen.dart test/features/responsibility_cards/scorecard_row_delete_test.dart
```

Then remove from `lib/app/router.dart`: the `/responsibility-cards/new` route, the `/responsibility-cards/:id/edit` route, and the `role_scorecard_form_screen.dart` import.

Leave the redirect guard at `:97-104` alone — it still governs `/responsibility-cards` and the PDF exemption, both of which survive.

- [ ] **Step 3: Run everything**

```
flutter analyze lib test
flutter test
```

Expected: 0 errors, 0 warnings. The suite drops by the four cases in the deleted test file — that is the expected count change, not a regression. State the new number in your report.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor(wp): delete the responsibility-card editor

Workforce Planning is now the only place a role is authored. The card view,
its PDF, the list index and everything hiring reads are unchanged.

Also removes a latent crash: the editor passed initialValue to its department
and hiring-entity dropdowns with no _present guard, so a card pointing at a
deleted department asserted on open."
```

---

### Task 5: Small deferred cleanups

**Files:**
- Modify: `lib/features/employees/profile/tabs/role_tab.dart` (duplicate copy)
- Modify: `lib/data/models/kpi.dart:126-129` (stale doc)
- Modify: `lib/features/workforce_planning/role/role_workbench_screen.dart` (pane keys)

Three items recorded across Plan 2's reviews, none worth its own plan:

1. **Duplicate empty-set copy.** With a validator supplied and zero boxes ticked, `role_tab.dart`'s unconditional "No KPIs selected yet…" and `kpi_set_rules.dart`'s "Pick at least one KPI…" both render. Keep one. The validator's message is the one that disappears when the problem is fixed, so prefer it and make the static line conditional on there being no validator.
2. **`writeGoal` doc drift.** `kpi.dart:126-129` still says the repository writes the derived `target` as NULL. Since `053aa07` that is true only when the caller supplies no free text. Correct the comment — it is the doc a future reader consults before deleting `hadStoredGoal`.
3. **Pane keys.** All four panes in `role_workbench_screen.dart` carry an identical `ValueKey(cardId)`, which buys nothing since `cardId` is fixed for the route instance. Either give each pane a distinct key or drop them; a key that cannot discriminate is misleading. Say which you chose and why.

- [ ] **Step 1: Make the changes**

- [ ] **Step 2: Run everything**

```
flutter test
flutter analyze lib test
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "chore(wp): deferred cleanups from the workbench reviews"
```

---

## Done when

- Every Edit entry point opens `/workforce-planning/roles/:id`.
- A role can be created from the Roles tab and lands you in its workbench.
- `role_scorecard_form_screen.dart` and its two routes no longer exist.
- The card view, its PDF, the list index and hiring all still work.
- `flutter test` green; `flutter analyze lib test` 0 errors, 0 warnings.

## Next plan

**Plan 4 — Needs attention.** Two new chips and the KPI Library's roles count. Independent of this plan; either order works.
