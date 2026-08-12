# Spec D — People Analyzer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A quarterly grid that answers EOS's "right person, right seat" — core values rated per person, GWC rated per person per seat, against a bar snapshotted onto each session.

**Architecture:** Four new tables and one screen. The bar evaluation is pure and lives apart from the grid. Access is HR/admins plus managers-for-their-own-reports, with **no** employee-facing surface — and that policy is written deliberately rather than adapted from a neighbour.

**Tech Stack:** Flutter (Material 3, Riverpod), Supabase Postgres, `flutter_test`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-12-people-analyzer-design.md`. Read it first, especially the access-control section.
- **Two verdicts, never merged.** *Below the bar* is about values and blocks Employee of the Month eligibility. *Wrong seat* is about GWC and does not — it says the seat is misassigned, and withholding an award for that punishes someone for a placement decision that was not theirs.
- **No employee-facing surface.** Nothing in this plan renders a person their own rating.
- Nothing carries forward between quarters. Pre-filling turns the exercise into a rubber stamp.
- The repo gates on `flutter analyze` only: 0 errors, 0 warnings; 192 pre-existing `info` lints — add none.
- **Do not run `dart format`.** Match the surrounding style.
- Never claim a test passed or the analyzer was clean without pasting the command output.
- Migrations are applied by the user, never by an implementer.
- Widget tests use `initSupabaseStub()` from `test/support/supabase_stub.dart`.
- Baseline: whatever the tree is when you start. Record it and do not regress it.
- Depends on Spec C's plan having landed: this plan reads seats and holders through it.

## File Structure

| File | Responsibility |
|---|---|
| `supabase/migrations/20260814000001_people_analyzer.sql` (new) | four tables + RLS |
| `lib/data/models/people_analyzer.dart` (new) | `CoreValue`, `AnalyzerSession`, `ValueRating`, `GwcRating` |
| `lib/features/people_analyzer/analyzer_rules.dart` (new) | pure: the two verdicts |
| `lib/data/repositories/people_analyzer_repository.dart` (new) | reads and writes |
| `lib/features/people_analyzer/people_analyzer_screen.dart` (new) | the grid |
| `lib/features/settings/core_values_screen.dart` (new) | authoring the values |

---

### Task 1: The bar, as pure logic

**Files:**
- Create: `lib/features/people_analyzer/analyzer_rules.dart`
- Test: `test/features/people_analyzer/analyzer_rules_test.dart`

**Interfaces:**
- Produces: `enum ValueRating { plus, plusMinus, minus }`; `class Bar { final int maxMinus; final int maxPlusMinus; }`; `class PersonVerdict { final bool belowBar; final bool unrated; final List<String> wrongSeatIds; bool get wrongSeat => wrongSeatIds.isNotEmpty; }`; `PersonVerdict evaluatePerson({required List<ValueRating> values, required Bar bar, required Map<String, ({bool gets, bool wants, bool capacity})> gwcBySeatId})`.

Build this before anything that stores or renders it. The rule is the feature; the tables are how it persists.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/people_analyzer/analyzer_rules.dart';

void main() {
  const eos = Bar(maxMinus: 0, maxPlusMinus: 1);
  const good = (gets: true, wants: true, capacity: true);

  PersonVerdict run(
    List<ValueRating> values, {
    Map<String, ({bool gets, bool wants, bool capacity})> gwc = const {
      's1': good,
    },
    Bar bar = eos,
  }) => evaluatePerson(values: values, bar: bar, gwcBySeatId: gwc);

  group('below the bar', () {
    test('all plus is above the bar', () {
      final v = run([ValueRating.plus, ValueRating.plus, ValueRating.plus]);
      expect(v.belowBar, isFalse);
      expect(v.unrated, isFalse);
    });

    test('exactly one plus-minus is still above — the boundary', () {
      expect(run([ValueRating.plus, ValueRating.plusMinus]).belowBar, isFalse);
    });

    test('two plus-minus breaches the default bar', () {
      expect(
        run([ValueRating.plusMinus, ValueRating.plusMinus]).belowBar,
        isTrue,
      );
    });

    test('a single minus breaches it however good the rest', () {
      expect(run([ValueRating.plus, ValueRating.minus]).belowBar, isTrue);
    });

    test('a looser bar is honoured', () {
      const loose = Bar(maxMinus: 1, maxPlusMinus: 2);
      expect(
        run([ValueRating.minus, ValueRating.plusMinus], bar: loose).belowBar,
        isFalse,
      );
    });
  });

  group('unrated', () {
    test('no ratings is unrated, NOT below the bar', () {
      // A quarter nobody has filled in yet must not read as a verdict on
      // everybody.
      final v = run(const []);
      expect(v.unrated, isTrue);
      expect(v.belowBar, isFalse);
    });
  });

  group('wrong seat is independent of the bar', () {
    test('a failed capacity names that seat and does not touch belowBar', () {
      final v = run(
        [ValueRating.plus, ValueRating.plus],
        gwc: {'s1': good, 's2': (gets: true, wants: true, capacity: false)},
      );
      expect(v.wrongSeat, isTrue);
      expect(v.wrongSeatIds, ['s2']);
      expect(v.belowBar, isFalse);
    });

    test('below the bar and right-seated', () {
      final v = run([ValueRating.minus]);
      expect(v.belowBar, isTrue);
      expect(v.wrongSeat, isFalse);
    });

    test('both at once, reported separately', () {
      final v = run(
        [ValueRating.minus],
        gwc: {'s1': (gets: false, wants: true, capacity: true)},
      );
      expect(v.belowBar, isTrue);
      expect(v.wrongSeatIds, ['s1']);
    });

    test('no seats held is not a wrong seat', () {
      expect(run([ValueRating.plus], gwc: const {}).wrongSeat, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run it, watch it fail. Step 3: Implement. Step 4: Run it, watch it pass.**

- [ ] **Step 5: Analyzer and commit**

```bash
git add -A
git commit -m "feat(people): the People Analyzer bar and its two verdicts"
```

---

### Task 2: The tables and the policy

**Files:**
- Create: `supabase/migrations/20260814000001_people_analyzer.sql`
- Create: `lib/data/models/people_analyzer.dart`
- Test: `test/data/models/people_analyzer_model_test.dart`

**Do not apply the migration.**

**Read this before writing the policy.** The obvious move is to copy `employee_kpis`'s RLS (`20260718000005`):

```sql
auth_is_performance_admin_for_employee(employee_id)
or employee_id = auth_employee_id()
or exists (select 1 from employees e
           where e.id = employee_id and e.reports_to_id = auth_employee_id())
```

**The middle clause must not be copied.** It is right for KPI assignments and a leak here: it would let every employee read their own values rating and below-the-bar verdict. The failure mode is someone discovering they are marked below the bar with no conversation. Write the policy deliberately.

- [ ] **Step 1: Write the migration**

Four tables exactly as the spec's Data model section gives them — `core_values`, `people_analyzer_sessions` (carrying `bar_max_minus` and `bar_max_plus_minus`), `people_analyzer_value_ratings`, `people_analyzer_gwc`. Copy the DDL from the spec; it is complete.

RLS on all four: read and write both gated on `auth_is_performance_admin_for_employee(employee_id)` **or** the requester managing that employee, with **no** self-read clause. `core_values` and `people_analyzer_sessions` have no `employee_id`, so scope those on company plus the HR/admin role, mirroring how `kpis` is scoped in `20260718000001`.

- [ ] **Step 2: Verify the policy has no self-read clause**

```
grep -n "auth_employee_id" supabase/migrations/20260814000001_people_analyzer.sql
```

Every hit must be inside a `reports_to_id` comparison. **A bare `employee_id = auth_employee_id()` is the leak** — if you see one, remove it. Paste the output.

- [ ] **Step 3: Models, failing test first**

`CoreValue`, `AnalyzerSession`, `ValueRating` row and `GwcRating` row, each with `fromRow`. Cover the rating enum's string mapping (`PLUS`/`PLUS_MINUS`/`MINUS`) in both directions, and that the bar is read off the session rather than defaulted.

- [ ] **Step 4: Suite, analyzer, commit, hand over the migration**

```bash
git add -A
git commit -m "feat(people): People Analyzer tables and a policy with no self-read"
```

---

### Task 3: Core values in settings

**Files:**
- Create: `lib/features/settings/core_values_screen.dart`
- Modify: `lib/app/router.dart`, `lib/app/shell.dart`
- Create: `lib/data/repositories/people_analyzer_repository.dart` (values CRUD only; sessions and ratings come in Task 4)
- Test: `test/features/settings/core_values_screen_test.dart`

Ordered list, add/rename/reorder/deactivate. **Deactivating keeps historical ratings readable and drops the value from the next session's columns** — so deactivation, never delete. Follow the KPI Library's deactivate pattern (`kpi_library_screen.dart`) rather than inventing one.

Find the existing settings screens before adding the route and match how they are registered and gated; read `router.dart` rather than assuming.

- [ ] **Step 1: Failing test. Step 2: Run. Step 3: Implement. Step 4: Run. Step 5: Suite, analyzer, commit.**

```bash
git commit -m "feat(people): author core values in settings"
```

---

### Task 4: The grid

**Files:**
- Create: `lib/features/people_analyzer/people_analyzer_screen.dart`
- Modify: `lib/data/repositories/people_analyzer_repository.dart` (sessions, ratings, GWC)
- Modify: `lib/app/router.dart`, `lib/app/shell.dart`
- Test: `test/features/people_analyzer/people_analyzer_screen_test.dart`

**Interfaces:**
- Consumes: `evaluatePerson` and its types; the seat/holder derivation from Spec C's `seat_tree.dart` — **reuse it, do not write a second "which seats does this person hold"**; `initSupabaseStub()` for tests.

**Shape:** one row per person carrying their value ratings, then one indented row per seat they hold carrying that seat's GWC. Columns are the active core values, then G, W, C. The session's bar is shown in the header. Rows flag *below the bar* and *wrong seat* separately, never merged.

The session is created lazily on the first rating of a quarter, and the period is derived from today's date.

- [ ] **Step 1: Write the failing test**

Cover at minimum:
- a person holding two seats renders one value row and two GWC rows
- a person below the bar is flagged, and a person merely wrong-seated is flagged differently
- a deactivated core value does not appear as a column
- **an unrated person is not flagged** — the case that would otherwise damn the whole team on the day a quarter opens

- [ ] **Step 2: Run, watch fail. Step 3: Implement. Step 4: Run.**

- [ ] **Step 5: Suite, analyzer, commit**

```bash
git commit -m "feat(people): the People Analyzer grid"
```

---

## Done when

- Core values are authored in settings and deactivation preserves history.
- The grid rates values per person and GWC per person per seat, against the session's own bar.
- Below the bar and wrong seat are reported separately everywhere they appear.
- An unrated person is not flagged.
- No screen shows an employee their own rating, and the RLS policy has no self-read clause.
- `flutter test` green; `flutter analyze lib test` 0 errors, 0 warnings.
- `20260814000001_people_analyzer.sql` committed and handed over, **not applied**.

## Not in this plan

Employee-of-the-Month eligibility reads the *below the bar* verdict — that check belongs to Spec B, which owns the score. This plan owns the verdict, not its consumer.
