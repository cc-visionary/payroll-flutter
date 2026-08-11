# Role Workbench — unifying Workforce Planning, KPIs and Responsibility Cards

**Date:** 2026-08-11
**Status:** Approved design, not yet implemented
**Follow-on:** Spec B — KPI tracking and Employee of the Month (separate document)

## Problem

Three screens edit slices of the same objects with different vocabularies, and
no screen shows the whole role:

| Screen | Can edit | Cannot |
|---|---|---|
| Responsibility Card editor | responsibility text, KPI name/target/frequency | hours, criticality, owner, KPI department/category |
| WP Tasks tab | everything about a task, including its card + area | anything KPI |
| KPI Library | KPI name, department, category, measurement; deactivate | attach to a role or a person |

The storage is already unified — `20260720000002` made a card responsibility a
`wp_tasks` row, and `20260718000001` made a card KPI a `role_scorecard_kpis`
link into a shared `kpis` library. Nothing is duplicated. What is fragmented is
the authoring, and the fragmentation manufactures its own backlog: a
responsibility added on a card lands uncosted ("33 essential responsibilities
uncosted"), and a KPI typed into the card editor silently mints a library row
with no department ("1 KPI with no department", "4 KPIs measuring nobody").

A second problem sits underneath: KPIs are not measurable. `target` is free text
("At least 98%"), nothing records where a number comes from, and nobody counts
it. That blocks the follow-on goal of scoring performance automatically.

## Decisions

1. **Workforce Planning is the workbench.** All role authoring happens there.
2. **The Responsibility Card is an artifact** — view, PDF, and the record hiring
   reads when making an offer. Its editor is deleted outright.
3. **A KPI is an EOS measurable** — it declares how it is counted, from which
   source, at what cadence, against a numeric goal. Raw counts are the proof.
4. **Every scored employee has an explicit set of 3-5 KPIs.** "Empty means all"
   stops meaning anything.
5. **Archive beats delete wherever history exists.**

## Out of scope

KPI logging, peer voting, attendance scoring, the Employee-of-the-Month
leaderboard. Those are Spec B. This spec only guarantees B is buildable without
re-migrating.

## Architecture

### New route

`/workforce-planning/roles/:id` — the role workbench. Reached by clicking a row
in the Roles tab (which keeps its cost/load table as the index) and from "Edit
in Workforce Planning" on the card view. HR/Admin/Super-admin only, matching the
existing `/workforce-planning` guard in `lib/app/router.dart`.

Four panes, one save:

| Pane | Holds | Backed by |
|---|---|---|
| Role details *(collapsed by default)* | mission, required skills, behavioural expectations, department, hiring entity, wage type, pay range, hours/day, days/week, effective date, active | `role_scorecards` |
| Responsibilities | grouped by area; inline hours + criticality + essential; `⋮` opens the full costing dialog (driver/rate/skill tier/risk/owner); Add · Link existing · reorder · remove | `wp_tasks` |
| KPIs | goal (direction · value · unit) + the measurable's definition; Add from library or new; remove | `role_scorecard_kpis`, `kpis` |
| People | holders with load, each with their explicit KPI set ("tracks 4 of 10") | `employees`, `employee_kpis` |

### What is deleted

- `lib/features/responsibility_cards/role_scorecard_form_screen.dart` (1,409 lines)
- Routes `/responsibility-cards/new` and `/responsibility-cards/:id/edit`
- The "New card" entry point on the cards list, replaced by **+ New role** on
  the Roles tab, which creates the card and opens the workbench on it

### What is unchanged

The card view (`role_scorecard_detail_screen.dart`), the card PDF
(`role_card_pdf.dart`), the cards list as a browse-and-print index, employment
contract Annex A, and everything in `lib/features/hiring/` that reads a role
card. They already render from `wp_tasks` and `role_scorecard_kpis`.

Navigation is unchanged: Balance · Roles · Structure · Tasks · Unassigned. The
Unassigned tab is a clustering workspace, not a filtered list, and stays as it
is. The only navigation change is the Roles drill-in.

### Reuse

The workbench composes what exists rather than reimplementing it:

- `tabs/task_form_dialog.dart` — `buildTaskFromForm` / `validateTaskForm`
- `tabs/assignment_panel.dart` — owner and contributor assignment
- `employees/profile/tabs/role_tab.dart` — the per-employee KPI checkbox
  section, `roleKpisProvider`, `employeeAssignedKpiIdsProvider`
- `kpi_library/kpi_form_dialog.dart` — creating a library KPI
- `responsibility_rows.dart` — `diffResponsibilities`, `RespDraft`

New code lives in `lib/features/workforce_planning/role/`: a thin screen shell
plus one file per pane, with decision logic in pure files (following
`tasks_rows.dart` and `kpi_rows.dart`) so it is testable without a widget. No
file in the new directory should approach the size of the editor being deleted.

## Data model

### `kpis` — how the number is produced

| Column | Type | Purpose |
|---|---|---|
| `value_type` | text, default `COUNT`, check `COUNT/RATIO/CURRENCY/PERCENT/DURATION` | shape of the measurable |
| `numerator_label` | text | "Returns received" |
| `numerator_source` | text | "BigSeller" |
| `denominator_label` | text | "Orders shipped" — `RATIO` only |
| `denominator_source` | text | "BigSeller" — `RATIO` only |
| `unit` | text | `%`, orders, days, ₱ |
| `cadence` | text, default `WEEKLY`, check `WEEKLY/MONTHLY/QUARTERLY` | EOS rhythm |
| `proof_type` | text, check `REPORT_EXPORT/SCREENSHOT/SYSTEM_LINK` | what evidence a log must carry |

Sources are free text with autocomplete over values already in use — BigSeller
and Lark today, Shopee or Shopify tomorrow, with no migration to add one.

Cadence lives on the KPI, not the role link: an EOS measurable has one rhythm.
The existing `role_scorecard_kpis.frequency` text is retained and written from
the KPI's cadence so the card PDF and contract templates keep rendering.

Two completeness levels, both computed in Dart rather than stored — a stored
flag would drift from the columns it summarises:

- **Defined** (library level): `value_type`, `unit`, a numerator label and
  source, plus a denominator label and source when `RATIO`.
- **Measurable for a role** (link level): defined, *and* this role's link
  carries a goal.

Adding a KPI to a role therefore requires setting its goal in the same step —
the Add flow asks for the goal before it will save the link.

### `role_scorecard_kpis` — the goal

| Column | Type | Purpose |
|---|---|---|
| `goal_direction` | text, check `GTE/LTE/EQ/BETWEEN` | ≥ · ≤ · = · between |
| `goal_value` | numeric | the number |
| `goal_value_max` | numeric | upper bound, `BETWEEN` only |

The existing free-text `target` column stays and is **written from** the
structured goal on every save (`"≤ 3%"`), so the card PDF, employment-contract
templates and `review_kpi_results` snapshots keep working with no changes.

### Legacy library cleanup

Of the 59 active KPIs, the 55 tracked on somebody survive unchanged and are
flagged "not yet measurable" until upgraded. Of the 4 measuring nobody:

- those linked to **no role card at all** are deleted
- those linked to a card with **no current holder** are deactivated, not deleted

"Measuring nobody" is computed from employees through role links, so a vacant
role's KPIs read as unassigned; deleting them would silently strip a card that
is merely unfilled. The migration prints which KPIs fall in each bucket.

### No new tables

Spec A adds columns only. `kpi_logs`, `eom_votes` and `eom_scores` belong to B.

## Lifecycle

`⋮` offers Edit / Archive / Delete throughout.

**Task.** Delete is enabled only when the task has no `wp_task_assignments`
rows; otherwise Archive, which sets the existing `wp_tasks.status = 'ARCHIVED'`.
Archived tasks leave the load calculation and the card, remain visible under the
Tasks tab's Archived filter, and restore.

Archive buys reversibility and an audit trail, not historical document fidelity.
Saved documents are settings-only and re-render live, so removing a
responsibility — by either route — changes the Annex A of contracts already
issued. That is a pre-existing property of the document model, not something
this change introduces, and it is out of scope here. Worth knowing before a bulk
cleanup of a card whose holders have signed contracts.

**KPI on a role.** Removal deletes the `role_scorecard_kpis` link. Once B adds
`kpi_logs`, a link whose employees have logs archives instead. A cannot enforce
a guard against a table that does not exist, so the rule is recorded here and
implemented in B.

**Library KPI.** Delete only when it is on no role and has no logs; otherwise
Deactivate (`is_active = false`).

## Per-employee KPI sets

`employee_kpis` stops meaning "optional subset" and starts meaning "this
person's measurables". Rules:

- an employee with **no set** is flagged and excluded from scoring — never
  defaulted to their whole role set
- **3-5 is advised, not enforced** — a warning, so a mid-setup new hire with 2
  can still be saved
- only **measurable** KPIs can be added to a set

Editable in two places against one widget: the workbench's People pane and the
employee profile's Role tab.

## Needs attention

Two new chips, both click-through into the workbench:

- **"N people with no KPI set"**
- **"N KPIs not yet measurable"** — missing formula, source or goal

The existing chips (`33 essential responsibilities uncosted`, `4 KPIs measuring
nobody`, `1 KPI with no department`, `3 roles with no department`) become
click-through to the place that fixes them.

## KPI Library after this change

Remains the catalogue and the cleanup surface: create, rename, categorise, set
department, define the measurable, deactivate, merge. It gains a **roles** count
beside the existing people count, and clicking a KPI lists the roles using it
with links into each workbench. It does not gain attach-to-role — that is the
workbench's job.

## Rollout

Four shippable steps, each safe alone:

1. **Schema and rules.** Migration `20260811000001` adds the KPI definition
   columns and the structured goal, and performs the legacy cleanup. Repository
   methods and pure-logic functions with their tests. No UI change.
2. **The workbench.** New route and four panes; Roles gains the drill-in. The
   card editor still exists at this point — both work, nothing is stranded.
3. **Retire the card editor.** Delete the screen and its two routes; card view
   gets "Edit in Workforce Planning"; "New role" moves to the Roles tab. The only
   irreversible step, landing after the workbench has been used for real.
4. **Needs attention.** The two new chips and click-through on the existing ones.

## Failure modes designed against

- **Silent load inflation** — the workbench writes `wp_tasks` directly, so every
  save invalidates the same computed/load providers the card editor invalidates
  today (`wpTasksProvider`, `wpAllTaskComputedProvider`, `ownerComputedProvider`,
  `wpPersonLoadsProvider`, `wpTaskAssignmentsProvider`).
- **A vacant role losing its KPIs** — handled by the split cleanup rule above.
- **Half-specified measurables scoring as perfect** — a KPI cannot join a
  person's set until it is measurable, and a person with no set is excluded from
  scoring rather than defaulted.
- **Contracts drifting** — Annex A renders live from `wp_tasks` in authored
  order, so neither archive nor delete preserves an issued contract's text. The
  workbench warns when removing a responsibility from a card whose holders have
  issued documents.
- **Positional widget reuse** — the panes render repeating rows from drafts. Key
  every row field by draft identity, per the fix in
  `test/features/responsibility_cards/scorecard_row_delete_test.dart`.

## Testing

Pure functions, unit tested:

- goal parse and format (structured ↔ the legacy `target` string)
- attainment and on-track/off-track from raw counts against a goal
- the archive-vs-delete decision for a task and for a KPI
- KPI-set validation (measurable-only, 3-5 advisory, no-set detection)
- EOS completeness — is this KPI measurable, and what is missing

Widget tests, one per pane, on the Supabase-stub harness built in
`scorecard_row_delete_test.dart` and extracted to `test/support/` for reuse:
stub `Supabase.initialize` with a `MockClient`, `EmptyLocalStorage`, an
in-memory PKCE store, and `detectSessionInUri: false`.

## What Spec B inherits

Measurables that know their own formula, source and cadence; goals that are
comparable numbers; an explicit 3-5 set per person; and archive semantics so a
KPI with history cannot be deleted out from under its logs. B adds only
`kpi_logs`, `eom_votes`, `eom_scores`, the Lark sync edge functions, and the
leaderboard.

B's agreed shape, recorded so A does not contradict it: employees submit actuals
and cast votes through **Lark forms**, synced one-way into the app by an edge
function following the `sync-lark-self-evals` pattern. No new app logins. The
Employee-of-the-Month score is 50% performance, 25% peer voting, 25% attendance,
with the weights configurable and attendance and performance both computed.
