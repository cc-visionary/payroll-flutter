# Accountability Model — Design Spec

> Date: 2026-07-23. Integrates the proven HRCI / accountability concepts from
> `[07] Projects/workforce-accountability-planning/docs` into this app's
> workforce planning and KPI library. Supersedes the "one responsibility, one
> card" shape established by `2026-07-20-responsibility-task-unification-design.md`.

## Background & the problems

Two concrete pains, both tracing to a single root (a third, related need
follows):

1. **Making a new role creates duplicates.** When HR builds a new role card,
   "Add responsibility" is a blank text box. There is no view of what already
   exists, so a manager retypes "Pack and dispatch orders" when Sales & Ops
   already has "Pack, label, check, and dispatch online orders". Now there are
   two rows, each with its own hours, double-counting the same work.

2. **Adjusting workload is too complex.** To change a task's hours you enter
   "Cost tasks" mode and set four things — times source, times value, minutes
   source, minutes value. Most people just want to say "this takes about ten
   hours a month."

**The root cause is the same for both.** Today a responsibility (`wp_tasks`
row) is glued to exactly **one** role card via `role_scorecard_id`. So the same
real-world work done by two roles *cannot* be one object — it is forced to be
two rows. That is why re-authoring duplicates, and it is why editing hours in
one place never propagates.

The HRCI docs solve this with a first-class **Accountability** that is assigned
to one or more **positions** (`AccountabilityAssignment`), with one PRIMARY
(Accountable) and any number of CONTRIBUTORs (Responsible). We adopt that model.

A third, related need falls out of the same shape: **seeing which work is
unassigned and deciding what to do with it** — archive it if it is no longer
needed, or, when several unowned tasks form a coherent job, design a new role
around them. The current system can show "unattributed hours" but gives no way
to act. Once work is a first-class accountability with an owner (or none), that
becomes a first-class workflow — see "Unassigned work" below.

## Decisions locked in brainstorming

| Question | Decision |
|---|---|
| Same work done by several roles | **One shared accountability**, not copies. Duplicates become structurally impossible. |
| How shared hours land on people | **Per-role allocation %**, with per-person numbers derived. Editable in one place, with bulk simplifiers. |
| RACI roles | Keep **PRIMARY (Accountable) + CONTRIBUTOR (Responsible)** — HRCI's core. Orthogonal to the %: role says who answers, % says who carries hours. |
| Default workload input | **Direct hours/month** (HRCI's `estimatedHours`). Driver × rate demoted to an "Advanced: scales with volume" toggle. |
| Editing the split | **On the accountability**, never by drilling into each person's profile. One-click simplifiers. |
| Unassigned work | **Track it, then decide** — archive if not needed, assign if it is, or cluster similar unowned items and **propose a new role** from them. |
| Framework | **Follow HRCI as far as it fits.** Skip its enterprise scaffolding (below). |

## The model

### Accountability (the renamed, unglued `wp_tasks`)

`wp_tasks` **loses** its single-card identity as the source of truth and gains a
plain workload figure. Concretely:

- **Add** `hours_per_month numeric` — the direct figure. Present ⇒ it wins.
  Absent ⇒ fall back to the existing `times × minutes / 60` driver calc (the
  "advanced" path). This keeps every already-costed row working untouched while
  making the simple field the default.
- **Add** `criticality text check (in 'LOW','MEDIUM','HIGH','CRITICAL')` —
  HRCI's prioritiser. `skill_tier` and `risk` stay; criticality answers the
  distinct question "does the business stop if this fails".
- **Add** `status text default 'ACTIVE' check (in 'ACTIVE','ARCHIVED')` —
  HRCI's `AccountabilityStatus`. Work that is **no longer needed** is
  **archived**, not deleted: it drops out of load, the queues and the needs-
  attention strip, but stays for reference and can be restored. Deleting an
  accountability that carries history is the wrong tool; archiving is the right
  one. Archived work is also excluded from the duplicate check, so retiring the
  old "Blindbox packing" does not block re-using the name later.
- `role_scorecard_id` / `responsibility_area` / `area_sort` / `task_sort`
  **stay** but describe the accountability's *home* card (where it was authored,
  and the card whose Annex A it still appears on). Sharing is expressed by
  assignments, below — not by moving this column.
- `owner_employee_id` is **superseded** by assignments (migration backfills it
  as a PRIMARY assignment, then the column is retained NOT NULL-free for
  rollback but no longer read — same play as `key_responsibilities`).

### Assignment (new) — who does it, in what role, for what share

```sql
create table wp_task_assignments (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null references companies(id) on delete cascade,
  task_id           uuid not null references wp_tasks(id) on delete cascade,
  -- Target: a role card (the HRCI "position"), OR a specific person as an
  -- exception. Exactly one is set.
  role_scorecard_id uuid references role_scorecards(id) on delete cascade,
  employee_id       uuid references employees(id) on delete cascade,
  assignment_role   text not null default 'CONTRIBUTOR'
                    check (assignment_role in ('PRIMARY','CONTRIBUTOR')),
  allocation_pct    numeric not null default 0
                    check (allocation_pct >= 0 and allocation_pct <= 100),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint one_target check ((role_scorecard_id is null) != (employee_id is null))
);
create unique index wp_task_assignments_card
  on wp_task_assignments (task_id, role_scorecard_id) where role_scorecard_id is not null;
create unique index wp_task_assignments_person
  on wp_task_assignments (task_id, employee_id) where employee_id is not null;
-- At most one PRIMARY per task, enforced in app + a partial unique index:
create unique index wp_task_assignments_one_primary
  on wp_task_assignments (task_id) where assignment_role = 'PRIMARY';
```

**Why target a card, not only a person.** HRCI assigns to positions, and it
handles three things a person-only model cannot: vacant roles still show their
work; a new holder inherits the role's accountabilities automatically; and the
contract annex (a role document) stays coherent. A **per-person** assignment
exists as the *exception* — when one kiosk rep genuinely does more than the
other — mirroring today's explicit-owner override.

### How the per-person numbers come out (the split)

This is an **extension of the existing `wp_person_load` mechanic**, not a
rewrite. For each accountability:

1. Its monthly hours = `hours_per_month` if set, else the driver calc (scaled by
   the growth multiplier only when driver-linked and growing — unchanged).
2. Each **card assignment** takes `allocation_pct` of those hours, then divides
   that share **evenly across the card's ACTIVE, non-deleted holders** — exactly
   the split the current system already does for derived owners.
3. Each **person assignment** takes its `allocation_pct` off the top for that one
   person (the override).
4. Anything left unallocated (Σ% < 100) is **unattributed** and surfaced, never
   silently dropped.

Worked example — Packing, 65.8 h/mo, `Sales & Ops PRIMARY 60%`,
`Kiosk CONTRIBUTOR 40%`; Sales & Ops has 1 holder (Evander), Kiosk has 2:

- Evander → 60% = **39.5h**
- each Kiosk rep → 40% ÷ 2 = 20% = **13.2h**

which is precisely the per-person breakdown the user asked for — produced from
two editable knobs (60 / 40), not three per-person figures.

## Editing — the whole point

### Authoring a role: assign, don't retype

On the role-card editor, **"Add responsibility" becomes "Assign accountability"**:

- A searchable picker over **every existing accountability**, not just the
  unlinked pool the current "Link existing task" shows.
- Typing a name that fuzzy-matches an existing one raises an inline
  *"Looks like 'Packing' (Sales & Ops) — assign that instead of creating a
  duplicate?"*
- **Create new** stays available, one tap, for genuinely new work.

Assigning a card to an accountability = inserting a `wp_task_assignments` row.
The card's responsibility list = accountabilities where this card is assigned
(PRIMARY or CONTRIBUTOR) **plus** those still authored on it directly.

### Setting workload: one field

The accountability editor leads with **`Workload: [ 65.8 ] hours / month`** and
nothing else. Because there is one accountability, this is set once and is right
everywhere it appears. **▸ Advanced: scales with volume** reveals the existing
driver/rate controls for the volume work that needs them.

### The assignment panel + simplifiers

Right on the accountability, a compact panel:

```
Assigned                                   = 100% ✓
  Sales & Ops Assistant   [PRIMARY ▾]  [ 60 ]%   → Evander 39.5h
  Kiosk Sales Rep         [CONTRIB ▾]  [ 40 ]%   → 2 people, 13.2h each

  [ Split equally ]  [ Owner majority 60/40 ]  [ Clear ]
```

- The **`= 100%` / `⚠ 92%`** check is live.
- Simplifiers write every row at once: *Split equally* sets each to 100/N;
  *Owner majority* gives PRIMARY 60 and splits 40 across the rest; *Clear* zeros.
- Per-person hours shown inline are **derived**, read-only here — you edit two
  knobs, not six numbers, and never leave this panel.

## Unassigned work — decide, don't let it rot

An accountability with **no PRIMARY** is work nobody is answerable for. The
current system surfaces "unattributed hours" but offers no way to *act* on them.
There are two very different reasons a thing is unassigned, and they need
opposite actions — this is HRCI's "Reviewing Unassigned Work" plus its role-gap
concept (roadmap 3.4.4 / 3.4.5):

1. **Not needed anymore** → **Archive** it. One tap, reversible, keeps history.
2. **Needed, but no role does it yet** → it should belong to *someone*. Either
   assign it to an existing role, or — when several unassigned items form a
   coherent job — **propose a new role** from the group.

### The "Unassigned" workspace

A dedicated view (its own tab section, and fed into needs-attention) listing
every ACTIVE accountability with no PRIMARY, with per-row actions
**Assign ▾ · Archive · Add to proposed role**, and, above them, **grouping
that makes the "design a new role" case visible**:

- Group unassigned work by **responsibility area / node**, and by **name
  similarity** (the same fuzzy match the duplicate check uses), so
  "these six unassigned finance tasks" cluster together on screen instead of
  scattering across a flat list.
- Each cluster shows its **total hours** and a **`Propose role from these`**
  action: it drafts a new (inactive) role card seeded with the selected
  accountabilities as PRIMARY assignments, named from the cluster, ready for HR
  to finish — turning "here is a pile of unowned work" into "here is the role we
  need to hire for," with the hours already totalled to justify it.

Nothing is auto-created or auto-archived — every action is a human decision,
because "not needed" and "needs a new hire" are judgements, not derivations.
The system only *surfaces and clusters*; the person *decides*.

## "Needs attention" — changes surface themselves

The model now knows ownership, %, criticality and load, so the HRCI **Problems**
idea becomes free: a derived strip (no new table) at the top of Balance and on a
small dashboard, ranked by severity, each row deep-linking to its fix:

- 🔴 a person **over 100%**
- 🔴 a **CRITICAL** accountability with **no PRIMARY**
- 🟡 **unassigned** accountabilities — with the **Assign / Archive / Propose
  role** actions from the Unassigned workspace inline
- 🟡 an accountability whose shares **don't total 100%**
- 🟡 **uncosted** accountabilities (real work, no hours)
- 🟡 a role card or KPI with **no department**
- 🟡 a **KPI measuring nobody**

This is the direct answer to "easily see what changes need to be done."

### KPI library alignment

Small, same spirit: the library already groups department → category. Add the
same **needs-attention** signals it can compute (measuring-nobody, no-department,
no-measurement) into the shared strip, so KPI gaps and workload gaps read in one
place instead of two.

## HRCI alignment

| HRCI concept | Here |
|---|---|
| Accountability (first-class) | the unglued `wp_tasks` |
| AccountabilityAssignment + positionId | `wp_task_assignments` → role card |
| RACI: PRIMARY / CONTRIBUTOR | `assignment_role` |
| Workload allocation %, warn ≠ 100% (fn 2.3.3) | `allocation_pct` + live check |
| `estimatedHours` as the simple default | `hours_per_month` |
| Criticality LOW→CRITICAL | `criticality` |
| `AccountabilityStatus` ACTIVE/ARCHIVED | `status` |
| Problems / gap detection | derived needs-attention strip |
| Reviewing Unassigned Work; Role Gaps (3.4.4/3.4.5) | Unassigned workspace + Propose role |
| Capacity utilization | existing load %, unchanged |
| Capacity rules (RATIO) | your existing drivers (advanced path) |

## Out of scope (their enterprise scaffolding, not on this goal)

Multi-tenant, scenarios-as-tables, groups / group types, dotted-line matrix,
time-based allocation tables (seasonal), forecasting sheets, comments /
@mentions, approval workflows, SOC 2, CSV import. Each is revisitable when a
concrete need appears; none serves "edit efficiently / see what changes" today.

## Risks

1. **Core-model change on live prod data.** 282 tasks, their owners, the derived
   split, and contract Annex A all sit on the current shape. Mitigation:
   sequence it (below) so each step ships working; backfill the single owner as a
   PRIMARY assignment; keep `owner_employee_id` for rollback.
2. **Annex A / role-card order.** Sharing must not reorder or reword a card's
   authored responsibilities. The accountability keeps its home card +
   `area_sort`/`task_sort`; only *additional* assignments are new. A regression
   test pins Annex A before/after.
3. **Two split paths (card vs person) diverging.** One pure function computes the
   split; both the person view and the role view route through it, as
   `rebalance.dart` already does. No second implementation.
4. **`hours_per_month` vs the driver calc disagreeing.** Direct hours wins when
   present; the rule is explicit and unit-tested, and the "Advanced" toggle makes
   which path is active visible.
5. **Σ% < 100 hiding work.** Unallocated hours are surfaced as unattributed, not
   dropped — same principle as today's orphan handling.

## Testing

- Pure: the split (card-share ÷ holders, person override, Σ%<100 → unattributed);
  direct-hours-wins-over-driver; the simplifiers (equal, owner-majority, clear);
  the ≠100% check; fuzzy duplicate match.
- Migration on throwaway Postgres: every current owner becomes exactly one
  PRIMARY assignment; totals unchanged; idempotent.
- Widget: assignment panel edits + simplifiers; authoring picker + duplicate
  warning; needs-attention rows link correctly; Annex A regression; archive
  removes an accountability from load/queues but keeps it restorable; "propose
  role from cluster" drafts an inactive card seeded with the selected items.
- `flutter analyze` clean; full suite green.

## Sequencing (so nothing breaks midway)

1. **Direct-hours workload** — `hours_per_month` column + the one-field editor +
   the wins-over-driver rule. Immediate relief on problem 2, no sharing yet.
2. **Criticality + status** — two columns; the criticality chip; **Archive**
   replaces hard-delete for "not needed anymore". Feeds needs-attention ranking.
3. **Needs-attention strip + Unassigned workspace** — pure derivation over
   current data (Assign / Archive / cluster / Propose role); ships value before
   the big migration. Note: until step 4, "unassigned" means the *current*
   notion — no `owner_employee_id` and no staffed home card (the existing
   orphan/unattributed logic). Once assignments land, the same view's criterion
   becomes the literal "no PRIMARY assignment"; the UI does not change, only what
   feeds it.
4. **Assignments table + backfill** — owners → PRIMARY assignments; the split
   function extended; nothing user-visible changes yet.
5. **Assignment panel + %** + simplifiers on the accountability editor.
6. **Assign-from-library authoring** + duplicate warning.

Each step is its own plan, reviewed and merged before the next.

## Design system

Per `PRODUCT.md`: mono for hours/percentages; tinted borderless status chips
(criticality, PRIMARY/CONTRIBUTOR, "= 100%"); `ResponsiveTable`; single purple
CTA; the `TabIntro` pattern to explain the new vocabulary in place.
