# Simple task allocation — role first

Date: 2026-09-28 · Status: DRAFT, awaiting owner review

## Why

HR uses Workforce Planning for two jobs equally: entering work (who does this
task, how long) and rebalancing (who is overloaded). Today both are hard:

- A task form carries ~20 fields. Skill tier, risk, capability and brand scope
  are saved but read by nothing downstream except the form and costing view.
- "Who does it" can be said three ways at once — `owner_employee_id`, the
  task's `role_scorecard_id`, and `%` rows in `wp_task_assignments` (role or
  person, PRIMARY/CONTRIBUTOR, must total 100%). HR must understand all three
  before assigning anything, and they can disagree.
- Effort has three input modes (direct hours; times × minutes; driver × rate).
- Answering "how many people are on this task, how long is it" means opening
  the task. Five tabs split the picture.

Success = HR can add a task with three inputs and, on one screen, see which
role is short-staffed and why.

## Decisions (owner-approved in brainstorming)

1. **Role first, one role per task.** Every task belongs to exactly one role
   card. Its hours split across the role's active holders. Work shared by two
   roles is described as two tasks.
2. **One role, many holders is normal** (e.g. three Sales Kiosk
   Representatives). The role, not the person, is the unit of load; an
   overloaded role is fixed by adding a holder, moving a task to another
   role, or shrinking a task.
3. **Oversight follows RACI and is a label.** "Checked by" is derived from the
   holders' `employees.reports_to_id` → that manager's role. It carries 0
   hours. Each manager role gets one ordinary task, "Supervise team", whose
   hours HR sets once. No per-task review hours (no double counting).
4. **Capability lives on roles and people, not tasks.** Per-task skill tier,
   risk, capability, brand scope, value-chain node, criticality and the
   essential flag move into a collapsed "More details" section. Person ↔ role
   fit is a gap-analysis concern (reviews / development), out of scope here.
5. **Effort = how often × how long.** Frequency presets, duration per
   occurrence, the app shows ≈ h/mo.
6. **Front door is a Role board.** Five tabs become three.
7. **Existing data converts automatically**, ambiguous cases are listed for
   review, nothing is deleted.

## The model

### Effort

| Frequency | Stored `times_manual` (per month) | Notes |
|---|---|---|
| Daily | 26 | Same 26-working-day convention payroll uses |
| Weekly | 52 / 12 ≈ 4.33 | |
| Monthly | 1 | |
| Quarterly | 1 / 3 | |
| Per order | driver volume | `times_source = 'driver'`, picks the existing orders driver |

Duration is `minutes_manual`. `cadence` stores the preset token (`DAILY`,
`WEEKLY`, `MONTHLY`, `QUARTERLY`, `PER_ORDER`) so the form can reopen on the
right preset; a legacy free-text cadence or a direct-hours task opens as
"Custom" (hours/month field). `wp_task_computed` is unchanged — it already
computes `times × minutes / 60` and lets `hours_per_month` win.

### Who

- A task's role is `wp_tasks.role_scorecard_id` — the only "who" the app
  reads after this change.
- A holder is an employee with that `role_scorecard_id`, `employment_status =
  'ACTIVE'`, not soft-deleted (same filter as `holderCountByRole`).
- **Split is capacity-weighted**, not flat: holder share = holder capacity ÷
  sum of holders' capacities. With equal capacity this is the current even
  split; a part-timer (`wp_capacity_overrides`) gets a proportionally smaller
  share, so every holder of a role shows the same load %. *(Changes
  `wp_person_load`; flag for owner review.)*
- Role figures: `work = Σ task hours`, `capacity = Σ holder capacity`,
  `load = work ÷ capacity`, `needs = work ÷ default_capacity_hours` people,
  `short = needs − holders` when positive.
- Checked by: the distinct roles of the holders' `reports_to_id` managers.
  Zero or several are both shown as-is (e.g. "checked by —", "checked by Ops
  Manager, CEO").

### Load bands

Unchanged: Under < 80%, OK 80–100%, Over > 100%.

## Screens

Workforce Planning tabs: **Roles · Organization · All tasks** (was Balance,
Roles, Organization, Responsibilities, Unassigned). Drivers/rates/scenario
dialog stays behind the tune icon.

### Roles (front door)

Top to bottom:

1. **People load strip** — every active person as a compact chip with load %,
   sorted high → low. Tapping one scrolls to their role card.
2. **No role yet (N)** — tasks with no role. Collapsible; drag a task onto a
   role card to give it one. Replaces the Unassigned tab.
3. **Check these (N)** — tasks the conversion flagged (see Migration). Each
   shows what it used to be ("was: Jeremy 60%, Marvin 40%") and a "Looks
   right" dismiss.
4. **Role cards**, over-loaded first, then by load descending:

```
┌ Sales Kiosk Representative ─────── checked by Marketing & Retail Mgr ┐
│ Work 540 h/mo · Has 3 people · Needs 3.4 people   ⚠ short 0.4         │
│ Ana 113% ⚠   Ben 113% ⚠   Cris 113% ⚠                                  │
│ ─ Man the LCT kiosk          Daily · 6 h        ≈ 156h                  │
│ ─ Restock & display          Daily · 1 h        ≈ 26h                   │
│ … 5 more                                                                │
│ [+ Add task]  [+ Add holder]                                            │
└─────────────────────────────────────────────────────────────────────────┘
```

- **Drag a task onto another role card** = move it to that role. Moves are
  drafts (reuse `MoveDrafts` / `HoverPreview` from `balance_tab.dart`): while
  hovering, both cards show before → after load; an Apply / Reset bar commits
  or discards. Nothing writes until Apply.
- **+ Add holder** opens a picker of active employees; choosing one sets that
  employee's `role_scorecard_id` (confirm dialog names their current role,
  since it is a real role change). It does not create compensation changes.
- A role with zero holders shows "Nobody holds this role" and its work counts
  toward "needs" only.
- Clicking a task opens the task form. Clicking the role title opens the
  existing Role workbench.

### Organization

Unchanged.

### All tasks

The Responsibilities table simplified to a searchable list: Name · Frequency ·
Duration · ≈ h/mo · Role · Checked by. Filters: role, "no role", "flagged".
Row actions: edit, archive, change role. Keeps bulk "Fill area" and delete-all
behaviour where they exist today. The costing columns (Times/mo, Minutes each,
Node) move into the task form's More details.

### Task form

Required: **Name · How often · How long · Role** with a live "≈ N h/mo · split
across M people" line under the role. More details (collapsed): responsibility
area, notes, expectation flag, criticality, essential, skill tier, risk,
capability, brand scope, value-chain node, and the "scales with volume"
driver/rate controls for non-order drivers.

Removed from the form: owner picker and `AssignmentPanel`.

## Migration (one SQL migration, non-destructive)

For each ACTIVE `wp_tasks` row, in order:

1. Has `role_scorecard_id` and no assignment rows → unchanged.
2. Has assignment rows → role = the PRIMARY row's role; if the PRIMARY row is
   a person, that person's role; if no PRIMARY, the largest-% row resolved the
   same way. Flag it when more than one assignment row existed or the
   resolved role differs from the existing `role_scorecard_id`.
3. No role, has `owner_employee_id` → role = the owner's role. Flag it when the
   owner has no role (task stays in "No role yet").
4. Otherwise → stays roleless ("No role yet"), not flagged.

Flags are stored in a new nullable `wp_tasks.allocation_review_note text` (the
"was: …" text) cleared by "Looks right". `owner_employee_id` and every
`wp_task_assignments` row are kept untouched; `wp_person_load` simply stops
reading them. Rollback = restore the previous view definition.

`wp_person_load` is redefined: attribution comes only from `wp_tasks.
role_scorecard_id` × holders, capacity-weighted.

## Knock-on changes

- **Contract Annex A** currently appends an employee's owned off-card tasks.
  With no person-level ownership read, it lists the role's tasks only.
- **Role-card PDF** "shared responsibilities" (`_withSharedResponsibilities`)
  no longer has sources; the section drops out.
- **Needs attention** rules become: task with no role; role with no holders;
  role over 100%; flagged task.
- Balance tab, Roles (role_view) tab, Unassigned tab, `assignment_panel.dart`
  and `allocation.dart` are removed once nothing imports them.

## Out of scope

- Person ↔ role skill-gap view.
- People holding more than one role.
- Role families / templates for similar roles.
- Pushing any of this to Lark.

## Testing

- Unit: frequency preset → `times_manual`; round-trip (form reopens on the
  preset); role figures (work, needs, short, capacity-weighted shares
  including a part-timer and a zero-holder role); checked-by derivation.
- Migration: run against an isolated local Supabase copy (643xx, see the
  local RLS testing note) seeded with each conversion case; assert roles and
  review notes, and that assignment rows survive.
- Widget: Role board ordering and short-staffed banner; drag preview shows
  before/after for both roles; Apply writes, Reset doesn't; 3-input form
  saves and reopens.
- `flutter analyze` clean; existing WP tests updated or removed with the
  screens they cover.
