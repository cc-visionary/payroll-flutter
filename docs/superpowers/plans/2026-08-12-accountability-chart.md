# Spec C — Accountability Chart Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render Luxium's EOS Accountability Chart — one box per person-in-a-seat, arranged by a hierarchy of functions — and rename the Responsibility Card to the Seat.

**Architecture:** The chart is a rendering over data that already exists plus one new column. Boxes come from seats and their holders, roles from responsibility areas, and the tree from a new `role_scorecards.parent_id`. The cycle guard is reused, not rewritten.

**Tech Stack:** Flutter (Material 3, Riverpod, GoRouter), Supabase Postgres, `flutter_test`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-12-accountability-chart-design.md`. Read it first.
- **`role_scorecards` keeps its table name.** The rename is UI vocabulary only. Routes keep their paths.
- **`employees.reports_to_id` and the Structure tab are not touched.** Two trees is the design, not an oversight.
- Holders are filtered `employment_status == 'ACTIVE' && deletedAt == null` — the filter `people_pane.dart` uses. **Not** `wpActiveEmployeesProvider`, which despite its name filters only `deleted_at`.
- The repo gates on `flutter analyze` only: 0 errors, 0 warnings; 192 pre-existing `info` lints — add none.
- **Do not run `dart format`.** Match the surrounding style of each file.
- Never claim a test passed or the analyzer was clean without pasting the command output.
- Migrations are applied by the user, never by an implementer. Three from Spec A are still unapplied (`20260811000001`, `20260811000002`, `20260812000001`); this plan's migration makes four, and they all go together.
- Widget tests use `initSupabaseStub()` from `test/support/supabase_stub.dart`, with a tall `tester.view.physicalSize`.
- Baseline: **1353 passing, 1 skipped**, analyzer clean.

## What already exists — reuse, do not rewrite

- **`wouldCreateCycle`** (`lib/features/workforce_planning/org_tree.dart:51`) is already generic: it takes `List<({String id, String? parentId})>`, not employees. It works for seats verbatim. `descendantsOf` beside it likewise.
- **`reportingDropError`** (`lib/features/workforce_planning/structure_rows.dart:6`) wraps it with people-specific *messages* only. The seat version is the same shape with different wording.
- **`OrgChartView`** (`lib/features/workforce_planning/org_chart_view.dart:19`) takes `people` and `empById` and renders employee-shaped nodes. Its node renderer is not reusable for seats. Its `_ElbowPainter` (`:220`) and layout may be — judge that when you get there and say what you concluded.
- The Needs-attention machinery: `AttentionItem`, `AttentionCategory`, `AttentionSeverity`, `AttentionTarget` and the zero-suppressing `add()` helper, all in `needs_attention.dart`.

## File Structure

| File | Responsibility |
|---|---|
| `supabase/migrations/20260813000001_seat_parent.sql` (new) | `parent_id` + index + cycle trigger |
| `lib/features/workforce_planning/seat_tree.dart` (new) | pure: boxes from seats+holders, roles from areas, seat drop guard |
| `lib/features/workforce_planning/accountability_chart_screen.dart` (new) | the chart |
| `lib/features/workforce_planning/needs_attention.dart` (modify) | two new findings |
| ~10 files (modify) | the Seat rename |

---

### Task 1: Rename the Responsibility Card to the Seat

**Files:** the ten occurrences listed below. **Test:** none new — this task changes no behaviour, and a test asserting a label is a change-detector. Say so in your report rather than adding one.

**Interfaces:** Consumes nothing. Produces no API change.

Grep finds ten occurrences of "Responsibility Card" in `lib/`. Eight are user-visible strings:

- `lib/app/shell.dart:101` — the nav item
- `lib/features/responsibility_cards/role_scorecard_detail_screen.dart:29` — screen title
- `lib/features/responsibility_cards/responsibility_cards_screen.dart:27` — screen title
- `lib/features/employees/profile/tabs/performance_tab.dart:127` — label
- `lib/features/performance/performance_dashboard.dart:111` — label
- `lib/features/performance/employee_review_detail_screen.dart:135` — label
- `lib/features/performance/employee_review_detail_screen.dart:153` — subtitle
- `lib/features/responsibility_cards/review_eligibility.dart:8` — a message shown to the user

Two are doc comments, reworded in the same pass so the code stops using a name the UI no longer does:

- `lib/data/repositories/review_cycle_repository.dart:222`
- `lib/features/workforce_planning/role/role_workbench_screen.dart:13`

- [ ] **Step 1: Confirm the list is still exact**

```
grep -rni "responsibility card" lib
```

**Case-insensitive, deliberately.** An earlier draft of this plan specified a
case-sensitive grep and treated its ten Title Case hits as the whole set; it
misses two lowercase plurals — the empty-state message six lines below the
title being renamed (`responsibility_cards_screen.dart:34`) and the hint in
`role_title_field.dart:77`, a widget embedded in six document forms.

Expected: twelve hits — the ten listed above plus those two. **If it differs,
stop and report.**

- [ ] **Step 2: Rename**

"Responsibility Cards" → "Seats" (plural, nav and list title). "Responsibility Card" → "Seat" elsewhere. Read each line in context: `review_eligibility.dart:8` returns `'No Responsibility Card assigned'`, which becomes `'No seat assigned'` — lower case mid-sentence, and it reads as prose, not a label.

Do **not** touch route paths, table names, class names, or file names.

- [ ] **Step 3: Verify nothing else moved**

```
grep -rni "responsibility card" lib test
flutter test
flutter analyze lib test
```

Expected: no hits in `lib`; suite unchanged at 1353 passing, 1 skipped; 0 errors, 0 warnings. A test failing here means it asserted on a label — fix the test, and note in your report which one, because that tells us where the vocabulary is load-bearing.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor(wp): the responsibility card is the seat"
```

---

### Task 2: The seat's parent

**Files:**
- Create: `supabase/migrations/20260813000001_seat_parent.sql`
- Modify: `lib/data/models/role_scorecard.dart` (add `parentId`)
- Modify: `lib/data/repositories/role_scorecard_repository.dart` (persist it)
- Test: `test/data/models/role_scorecard_parent_test.dart`

**Interfaces:**
- Produces: `RoleScorecard.parentId` (`String?`), read by `fromRow`, written by `toUpsertPayload`.

**Do not apply the migration.**

- [ ] **Step 1: Write the migration**

```sql
-- The Accountability Chart is a tree of SEATS, not of people. employees
-- .reports_to_id cannot express it: a person can hold two seats in different
-- branches (Clinton holds Visionary and Sourcing), and reports_to_id is one
-- value per person.
alter table role_scorecards
  add column if not exists parent_id uuid references role_scorecards(id);
create index if not exists role_scorecards_parent on role_scorecards (parent_id);

comment on column role_scorecards.parent_id is
  'Parent SEAT in the Accountability Chart. Independent of employees.reports_to_id '
  'by design — the two trees answer different questions. Null means a root seat.';

-- A seat must not be its own ancestor. The Dart guard protects the drag-and-drop
-- path; this protects every other path.
create or replace function assert_no_seat_cycle() returns trigger
language plpgsql as $$
declare
  cur uuid := new.parent_id;
  hops int := 0;
begin
  while cur is not null loop
    if cur = new.id then
      raise exception 'seat % cannot be its own ancestor', new.id;
    end if;
    hops := hops + 1;
    if hops > 100 then
      raise exception 'seat parent chain exceeded 100 hops; data is already cyclic';
    end if;
    select parent_id into cur from role_scorecards where id = cur;
  end loop;
  return new;
end $$;

drop trigger if exists _role_scorecards_no_cycle on role_scorecards;
create trigger _role_scorecards_no_cycle
  before insert or update of parent_id on role_scorecards
  for each row when (new.parent_id is not null)
  execute function assert_no_seat_cycle();
```

Note the hop cap: without it, a cycle that somehow already exists turns the guard itself into an infinite loop.

- [ ] **Step 2: Write the failing model test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';

void main() {
  test('reads and writes the seat parent', () {
    final card = RoleScorecard.fromRow({
      'id': 'seat-1',
      'company_id': 'co-1',
      'job_title': 'Sourcing',
      'mission_statement': '',
      'wage_type': 'MONTHLY',
      'work_hours_per_day': 8,
      'work_days_per_week': 'Monday to Saturday',
      'is_active': true,
      'effective_date': '2026-01-01',
      'parent_id': 'seat-root',
    });
    expect(card.parentId, 'seat-root');
    expect(card.toUpsertPayload()['parent_id'], 'seat-root');
  });

  test('a root seat has no parent, and null round-trips', () {
    final card = RoleScorecard.fromRow({
      'id': 'seat-1',
      'company_id': 'co-1',
      'job_title': 'Visionary',
      'mission_statement': '',
      'wage_type': 'MONTHLY',
      'work_hours_per_day': 8,
      'work_days_per_week': 'Monday to Saturday',
      'is_active': true,
      'effective_date': '2026-01-01',
    });
    expect(card.parentId, isNull);
    expect(card.toUpsertPayload().containsKey('parent_id'), isTrue);
    expect(card.toUpsertPayload()['parent_id'], isNull);
  });
}
```

These fixtures are complete: `fromRow` (`role_scorecard.dart:263`) reads
`key_responsibilities`, `kpis`, `required_skills`, `behavioral_expectations`
and `wp_tasks` defensively and branches on null, and `version` falls back to 1
via `(r['version'] as num?)?.toInt() ?? 1`. The only hard requirements are
`id`, `company_id`, `job_title` and a parseable `effective_date` string, all of
which are present.

- [ ] **Step 3: Run it, watch it fail, implement, run again**

```
flutter test test/data/models/role_scorecard_parent_test.dart
```

Add `parentId` to the constructor (optional, defaulting null), `fromRow` and `toUpsertPayload`. Follow how `hiringEntityId` is threaded — it is the closest existing analogue.

- [ ] **Step 4: Suite, analyzer, commit**

```
flutter test
flutter analyze lib test
```

```bash
git add -A
git commit -m "feat(wp): a seat can have a parent seat"
```

- [ ] **Step 5: Hand the migration over**

Report, do not run: `20260813000001_seat_parent.sql` is ready and joins the three unapplied Spec A migrations. All four go together.

---

### Task 3: Seat-tree pure logic

**Files:**
- Create: `lib/features/workforce_planning/seat_tree.dart`
- Test: `test/features/workforce_planning/seat_tree_test.dart`

**Interfaces:**
- Consumes: `wouldCreateCycle` from `org_tree.dart`; `RoleScorecard`; `Employee`.
- Produces: `class SeatBox { final String seatId; final String function; final String? holderName; final String? holderId; final List<String> roles; bool get isOpen => holderId == null; }`; `List<SeatBox> seatBoxes({required List<RoleScorecard> seats, required List<Employee> employees, required Map<String, List<String>> areasBySeat})`; `String? seatDropError({required String movingSeatId, required String newParentId, required List<({String id, String? parentId})> seats})`.

**The expansion rule:** a seat with N active holders yields N boxes; a seat with none yields exactly one box with `holderId == null`. That one-for-none case is EOS's open seat and is the point of the whole tool — it must not collapse to zero boxes.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/workforce_planning/seat_tree.dart';

void main() {
  group('seatBoxes', () {
    test('one box per active holder', () {
      final boxes = seatBoxes(
        seats: [seat('s1', 'Brand Handling')],
        employees: [emp('e1', 'Christian', 's1'), emp('e2', 'Evander', 's1')],
        areasBySeat: const {'s1': ['Packing', 'Customer service']},
      );
      expect(boxes, hasLength(2));
      expect(boxes.map((b) => b.holderName), ['Christian', 'Evander']);
      expect(boxes.every((b) => b.function == 'Brand Handling'), isTrue);
      expect(boxes.first.roles, ['Packing', 'Customer service']);
    });

    test('a seat with no holder yields ONE open box, not zero', () {
      // EOS's open seat. Collapsing it to nothing hides the finding the chart
      // exists to surface.
      final boxes = seatBoxes(
        seats: [seat('s1', 'Marketing')],
        employees: const [],
        areasBySeat: const {'s1': ['Campaigns']},
      );
      expect(boxes, hasLength(1));
      expect(boxes.single.isOpen, isTrue);
      expect(boxes.single.holderName, isNull);
      expect(boxes.single.function, 'Marketing');
    });

    test('ignores separated and deleted holders', () {
      final boxes = seatBoxes(
        seats: [seat('s1', 'Ops')],
        employees: [
          emp('e1', 'Live', 's1'),
          emp('e2', 'Resigned', 's1', status: 'RESIGNED'),
          emp('e3', 'Deleted', 's1', deleted: true),
        ],
        areasBySeat: const {},
      );
      expect(boxes, hasLength(1));
      expect(boxes.single.holderName, 'Live');
    });

    test('a seat with no areas has no roles, and does not throw', () {
      final boxes = seatBoxes(
        seats: [seat('s1', 'Ops')],
        employees: [emp('e1', 'Live', 's1')],
        areasBySeat: const {},
      );
      expect(boxes.single.roles, isEmpty);
    });
  });

  group('seatDropError', () {
    const seats = [
      (id: 'a', parentId: null),
      (id: 'b', parentId: 'a'),
      (id: 'c', parentId: 'b'),
    ];

    test('a seat cannot parent itself', () {
      expect(seatDropError(movingSeatId: 'a', newParentId: 'a', seats: seats),
          isNotNull);
    });

    test('a seat cannot move under its own descendant', () {
      expect(seatDropError(movingSeatId: 'a', newParentId: 'c', seats: seats),
          isNotNull);
    });

    test('a legal move returns null', () {
      expect(seatDropError(movingSeatId: 'c', newParentId: 'a', seats: seats),
          isNull);
    });
  });
}
```

You need `seat()` and `emp()` helpers. Copy `_emp` from `test/features/workforce_planning/role_lens_test.dart:27` — it compiles against the current `Employee` and takes `(id, name, cardId)`; extend it with optional status and deleted overrides. Build `seat()` against the real `RoleScorecard` constructor.

- [ ] **Step 2: Run it, watch it fail**

```
flutter test test/features/workforce_planning/seat_tree_test.dart
```

Expected: compile failure — `seat_tree.dart` does not exist.

- [ ] **Step 3: Implement**

`seatDropError` delegates to `wouldCreateCycle` and supplies seat-worded messages — the same shape as `reportingDropError` (`structure_rows.dart:6`). Read that first and mirror it; do not reimplement the cycle walk.

- [ ] **Step 4: Run, suite, analyzer, commit**

```bash
git add -A
git commit -m "feat(wp): seat boxes and the seat drop guard"
```

---

### Task 4: The chart screen

**Files:**
- Create: `lib/features/workforce_planning/accountability_chart_screen.dart`
- Modify: `lib/app/router.dart` (route `/accountability-chart`)
- Modify: `lib/app/shell.dart` (nav item under Work & Performance)
- Test: `test/features/workforce_planning/accountability_chart_screen_test.dart`

**Interfaces:**
- Consumes: `seatBoxes`, `seatDropError`; `roleScorecardListProvider`; `wpActiveEmployeesProvider` **filtered as the constraint above requires**; `wpTasksProvider` for the areas.
- Produces: `class AccountabilityChartScreen extends ConsumerWidget`.

**Behaviour:** boxes laid out as a tree by `parent_id`, roots being seats with no parent. Each box shows function, name (or OPEN SEAT), and its roles. Dragging a box onto another re-parents the seat, refused by `seatDropError`, saved immediately — matching the Structure tab's established behaviour, which its own `TabIntro` already documents as "changes here save immediately".

Decide whether `OrgChartView`'s layout and `_ElbowPainter` can be reused or whether a seat-shaped renderer is cleaner, and **say which you chose and why** — its node renderer is employee-shaped, so at minimum that part is new.

**The chart's own copy must say what it is.** Someone expecting an org chart will read it as broken. One line under the title: this maps functions and who owns them, not who reports to whom — for reporting lines, see Workforce Planning ▸ Structure.

- [ ] **Step 1: Write the failing test**

Cover: a seat with two holders renders two boxes; a seat with no holder renders one reading OPEN SEAT; a child seat renders beneath its parent; and the explanatory line is present. Use `initSupabaseStub()` and a tall surface.

- [ ] **Step 2: Run it, watch it fail. Step 3: Implement. Step 4: Run again.**

- [ ] **Step 5: Route and nav**

Route `/accountability-chart`, gated the same way `/workforce-planning` is — read `router.dart`'s redirect and confirm the guard covers the new path rather than assuming it.

- [ ] **Step 6: Suite, analyzer, commit**

```bash
git add -A
git commit -m "feat(wp): the accountability chart"
```

---

### Task 5: Two findings

**Files:**
- Modify: `lib/features/workforce_planning/needs_attention.dart`
- Modify: `lib/features/workforce_planning/tabs/needs_attention_strip.dart`
- Test: `test/features/workforce_planning/needs_attention_test.dart`

**Interfaces:**
- Produces: `buildNeedsAttention` gains `Map<String, int> areaCountBySeat = const {}` and `Map<String, int> holderCountBySeat = const {}`, both defaulted.

Two signals, both EOS prescriptions:

- **"N seats with more than five roles"** — EOS's answer is consolidate. `AttentionCategory.structure`, target `roles`.
- **"N open seats"** — a function nobody owns. `AttentionCategory.structure`, target `roles`.

**Read the file's conventions first.** Every case goes through a `_run({...})` wrapper, and it has its own `_card`, `_kpi`, `_load` and `_t` helpers with signatures that differ from other test files'. Extend `_run` with the two new parameters before adding cases.

**Both parameters are defaulted, so the strip compiles before it is wired — and a chip that always reads zero is worse than no chip.** Verify the wiring produces a real count and say how you verified it. Equally: `needs_attention.dart` guards its nullable map parameters by treating absent as "skip the signal" rather than as empty, because empty yields the wrong extreme. Follow that established pattern if your inputs can be absent.

- [ ] **Step 1: Write the failing tests. Step 2: Run, watch fail. Step 3: Implement. Step 4: Run.**

- [ ] **Step 5: Suite, analyzer, commit**

```bash
git add -A
git commit -m "feat(wp): flag oversized and open seats"
```

---

## Done when

- The app says Seat, and `grep -rn "Responsibility Card" lib` is empty.
- `/accountability-chart` renders one box per holder, OPEN SEAT for vacancies, roles from areas, arranged by `parent_id`.
- Re-parenting works and refuses cycles, in Dart and in the database.
- Both findings appear only when non-zero.
- `flutter test` green; `flutter analyze lib test` 0 errors, 0 warnings.
- `20260813000001_seat_parent.sql` committed and handed over, **not applied**.

## Next plan

**Spec D — the People Analyzer** (`2026-08-12-people-analyzer-design.md`). Its per-seat GWC rows depend on this plan's Seat vocabulary and on `seatBoxes`' notion of which seats a person holds.
