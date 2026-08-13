> **SUPERSEDED — 2026-08-13.** Luxium is no longer adopting EOS, so the
> vocabulary and the standalone chart this spec describes are gone. The
> chart's content survives: Workforce Planning's Structure tab became
> **Organization**, where each person's box now lists what their role owns.
> "Seat" reads "Role" everywhere, and `role_scorecards.parent_id` was removed
> along with its never-applied migration, because the Organization tab uses
> `employees.reports_to_id` instead of a separate role tree. Kept for the
> reasoning, not as a description of the app.

# Spec C — The Accountability Chart

**Date:** 2026-08-12
**Status:** Approved design, not yet implemented
**Depends on:** Spec A (`2026-08-11-role-workbench-design.md`), complete and merged at `2b44ede`
**Sibling:** Spec D — the People Analyzer (`2026-08-12-people-analyzer-design.md`), built after this one

## Why

Luxium is adopting EOS (Gino Wickman, *Traction*). Two of its tools need a home in the app. This spec covers the Accountability Chart; the People Analyzer is Spec D.

An EOS Accountability Chart is **not** an org chart. Each box is a *seat* — a function, the one person accountable for it, and the handful of roles that seat owns. It is drawn by function, and its central rule is one seat, one name.

The app is close to this already. A role card carries a job title, a mission, and responsibilities grouped into areas. What it lacks is the seat framing, a hierarchy of functions, and the one-name rule.

## Decisions

1. **The card *becomes* the Seat.** A vocabulary change, not a new entity beside it.
2. **One box per holder.** A seat with two holders renders as two boxes; a seat with none renders as an OPEN SEAT.
3. **A seat's parent is a seat.** New `role_scorecards.parent_id`. The chart is a tree of functions, independent of who reports to whom.
4. **Box roles are the seat's responsibility areas**, derived, never authored twice.
5. **The job title is the function label.** No new field.

## Out of scope

The People Analyzer (Spec D). KPI logging and Employee of the Month (Spec B, unwritten). Any change to `employees.reports_to_id` or the Structure tab.

## The rename

"Responsibility Card" → "Seat" across the UI. Grep finds ten occurrences in `lib/`: **eight user-visible strings** — `shell.dart:101` (nav), `role_scorecard_detail_screen.dart:29` (title), `responsibility_cards_screen.dart:27` (title), `performance_tab.dart:127` (label), `performance_dashboard.dart:111` (label), `employee_review_detail_screen.dart:135` (label) and `:153` (subtitle), `review_eligibility.dart:8` (a message shown to the user) — plus **two doc comments**, `review_cycle_repository.dart:222` and `role_workbench_screen.dart:13`, which should be reworded in the same pass so the code stops using a name the UI no longer does.

**The `role_scorecards` table keeps its name.** Renaming it would touch three unapplied migrations, every document template, the payroll compute path and 71 unpushed commits, to change a word. The table name is not user-visible; the label is.

**No document or contract template mentions the term** — verified by grep over `lib/features/documents/`. Nothing printed on a signed page changes.

Routes keep their paths for the same reason. `/responsibility-cards/:id` stays; only its title changes.

## The chart

### Boxes

| Box element | Source |
|---|---|
| Function | the seat's `job_title` |
| Name | the seat's ACTIVE, non-deleted holder |
| Roles | the seat's responsibility **areas**, in `area_sort` order |

**One box per holder.** Holders come from `employees.role_scorecard_id`, filtered `employment_status = 'ACTIVE' and deleted_at is null` — the same filter the workbench's People pane uses (`people_pane.dart`), not `wpActiveEmployeesProvider`, which despite its name filters only `deleted_at`.

A seat with no holder renders **one** box reading OPEN SEAT. A seat with three holders renders three boxes, identical but for the name. This is EOS's shape: the chart's value comes from every box having exactly one name in it.

### The tree

New nullable `role_scorecards.parent_id` referencing `role_scorecards(id)`. Roots are seats with no parent.

`employees.reports_to_id` is **not** used and **not** changed. The two trees answer different questions and EOS is explicit that conflating them is the mistake: the Structure tab keeps answering "who does this person report to", the chart answers "who owns this function". Keeping them separate is also what makes the one-person-two-seats case representable — Clinton holds Visionary and Sourcing in different branches, which a single `reports_to_id` cannot express.

**A cycle guard is required.** A seat must not be its own ancestor. A drag-and-drop chart makes that trivial to do by accident, and a cycle renders as an infinite tree. Enforce it in Dart before the write (walk the ancestor chain) and with a database trigger, because the Dart guard protects the UI path and the trigger protects every other path.

### Findings

Two, both EOS prescriptions rather than invented rules, both belonging on the Needs-attention strip beside the chips Spec A's Plan 4 added:

- **"N seats with more than five roles"** — EOS's answer is consolidate. Derived from the count of distinct `responsibility_area` values per seat.
- **"N open seats"** — a function nobody owns.

Both follow the existing `AttentionItem` shape and the `add()` helper that suppresses zero counts. `AttentionTarget` needs no new value if both point at `roles`; add one only if the chart gets its own route.

## Data model

```sql
alter table role_scorecards
  add column if not exists parent_id uuid references role_scorecards(id);
create index if not exists role_scorecards_parent on role_scorecards (parent_id);
```

Plus a trigger rejecting a cycle on insert or update of `parent_id`.

Nothing else. Boxes, names and roles are all derived from rows that already exist.

## Testing

Pure and unit-testable without a widget:

- ancestor-walk cycle detection, including self-parent and a three-seat loop
- the seat-to-boxes expansion: nought holders → one OPEN SEAT box, three holders → three boxes
- role derivation from areas, preserving `area_sort` and de-duplicating
- the two findings' counts, including that each is silent at zero

Widget-level, on the `test/support/supabase_stub.dart` harness:

- a seat with no holder renders OPEN SEAT, not an empty name
- a seat with two holders renders two boxes
- a seat with six areas is flagged

## Risks

- **Authoring `parent_id` for ~10 seats is a manual pass** with no safe default. Deriving it from `reports_to_id` as a starting point would be wrong for exactly the seats that matter — the ones where a person's manager and a function's owner differ, which is the case the tree exists to express. Leave it null and let the chart show unparented seats as roots until someone places them.
- **Two trees can drift** — a seat can report to a function whose holder is not the manager of this seat's holder. That is legal in EOS and often deliberate, so it is not a finding. It will look like a bug to anyone expecting an org chart, so the chart's own copy should say what it is.
