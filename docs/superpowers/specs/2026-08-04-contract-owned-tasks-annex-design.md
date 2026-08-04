# Employment Contract Annex A — Personally-Owned Tasks — Design

**Date:** 2026-08-04
**Status:** Approved (pending user review of this doc)

## Problem

The employment contract's Annex A ("Duties and Responsibilities") renders the role card's responsibility list: duties **authored on the card** (from `wp_tasks` rows with `role_scorecard_id = card`) plus accountabilities **shared to the card** via assignments (appended as trailing areas by `RoleScorecardRepository._withSharedResponsibilities`).

Tasks an employee **personally owns** (`wp_tasks.owner_employee_id = employee`) that live on another card — or on no card — never appear in their contract, even though the People view counts them as that person's real work.

## Goal

Employee-mode contracts append the employee's personally-owned, off-card, ACTIVE tasks to Annex A as trailing responsibility areas — without altering the card-authored duty list in any way.

## Decisions made during brainstorming

| Decision | Choice |
|----------|--------|
| Source model | Approach A: **append** owned off-card tasks; never remove or reorder card-authored duties (a colleague owning a card task does not shrink this person's contract) |
| Person-scoped list (Approach B) | Rejected — under-scopes the legal document and breaks the authored-order invariant ("Risk #2", protected by the Annex A gate in `role_scorecard_responsibilities_test`) |
| Applicant mode | Unchanged — no employee exists, card list only |
| Saved contracts | Unchanged — responsibilities are snapshotted into `generation_options` at generation; only new generations pick up the richer list |

## 1. Pure model function — reuse, don't duplicate

`responsibilitiesFromAssignedTasks(cardId, tasks)` in `lib/data/models/role_scorecard.dart` already implements exactly the needed semantics: skip tasks authored on `cardId`, skip blank names, group by `responsibility_area` (min `area_sort`, ties by name; tasks by `task_sort`, ties by id), bucket area-less tasks.

Generalize its no-area bucket label with an optional parameter (default preserves current behavior):

```dart
List<ResponsibilityArea> responsibilitiesFromAssignedTasks(
  String cardId,
  List<WpTask> assignedToCard, {
  String fallbackArea = 'Shared',
})
```

The owned-task append calls it with `fallbackArea: 'Additional Responsibilities'` (an area-less personally-owned task is not "Shared" — it is extra duty).

## 2. Repository fetch

`RoleScorecardRepository` gains:

```dart
/// ACTIVE tasks personally owned by [employeeId], for the employment
/// contract's Annex A append. Archived work is excluded; authored-on-own-card
/// filtering happens in responsibilitiesFromAssignedTasks.
Future<List<WpTask>> activeTasksOwnedBy(String employeeId)
```

— a single `wp_tasks` select: `.eq('owner_employee_id', employeeId).eq('status', 'ACTIVE')`. (Task counts per person are small — tens, not thousands — no paging needed.)

## 3. Contract autofill wiring (employee mode only)

In `EmploymentContractTemplate.autofill`'s employee path, after the scorecard loads:

1. Fetch `activeTasksOwnedBy(emp.id)` wrapped in try/catch → empty list on failure (contract generation must never break on a workforce-planning read; consistent with the feature family's other degradations).
2. Compute `extra = responsibilitiesFromAssignedTasks(cardId, ownedTasks, fallbackArea: 'Additional Responsibilities')` where `cardId` is the employee's `roleScorecardId` (`''` when they have no card — then nothing is treated as authored and all owned tasks append).
3. **Name-dedup:** drop any appended task whose trimmed, case-insensitive name already appears anywhere in the assembled list (card-authored + card-shared). This handles the overlap where a task is both shared to the card and owned by this employee. An area left empty by dedup is dropped entirely. (Dedup is by name because `ResponsibilityArea` carries rendered names, not task ids — and an identical name would render as a duplicate line regardless of id.)
4. Append the surviving areas AFTER the scorecard's responsibilities when mapping into `ContractResponsibility`.

The applicant path and `_onPickerCompanyChanged` are untouched (employee re-selection already re-runs autofill).

## 4. Ordering and fallbacks

Final Annex A order: card-authored areas (authored order) → card-shared areas (existing trailing append) → owned-task areas (new trailing append, same internal sort rules). No card at all → owned-task areas alone (after the empty list). No owned tasks / fetch failure → today's output, byte-identical.

## 5. Testing

- Unit tests for the generalized function: `fallbackArea` default stays `'Shared'` (existing tests must pass unchanged); custom label lands area-less tasks in `'Additional Responsibilities'`.
- Unit tests for the dedup helper: case-insensitive name collision dropped; empty area pruned; non-colliding tasks survive; ordering preserved.
- The existing Annex A gate in `role_scorecard_responsibilities_test` must stay green (authored output untouched).
- No DB-dependent tests (no local Supabase); repository fetch is a thin select verified by `flutter analyze` + GUI smoke (generate a contract for an employee who owns an off-card task).

## Out of scope

- Person-scoped removal of colleague-owned card tasks (Approach B).
- Any change to the role-card PDF, applicant contracts, or other document templates.
- Refresh affordances in the contract form.
- Rendering task metadata (notes, criticality, expectation flags) in Annex A.
