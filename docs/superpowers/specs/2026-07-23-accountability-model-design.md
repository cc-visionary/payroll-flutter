# Accountability Model — Design Spec

> Date: 2026-07-23. Integrates the proven HRCI / accountability concepts from
> `[07] Projects/workforce-accountability-planning/docs`, grounded in the HRCI
> *Human Resource Body of Knowledge* (2017), into this app's workforce planning
> and KPI library. This app is the **manager's** planning surface; employees
> interact via **Lark**. Supersedes the "one responsibility, one card" shape
> established by `2026-07-20-responsibility-task-unification-design.md`.

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
| Audience | **This app is for MANAGERS** — planning, deciding, seeing gaps. **Employees interact through Lark** — forms and notifications, not this UI. |
| Framework | **Follow HRCI + the HRBoK as far as they fit.** Skip the enterprise scaffolding and the rest of the HRBoK (below). |

## The model

### Accountability (the renamed, unglued `wp_tasks`)

`wp_tasks` **loses** its single-card identity as the source of truth and gains a
plain workload figure. Concretely:

- **Add** `hours_per_month numeric` — the direct figure. Present ⇒ it wins.
  Absent ⇒ fall back to the existing `times × minutes / 60` driver calc (the
  "advanced" path). This keeps every already-costed row working untouched while
  making the simple field the default.
- **Add** `criticality text check (in 'LOW','MEDIUM','HIGH','CRITICAL')` —
  HRCI's prioritiser and the "importance" leg of the ADA essential-function test
  (see HRBoK grounding). `skill_tier` and `risk` stay; criticality answers the
  distinct question "does the business stop if this fails".
- **Add** `is_essential boolean default true` — the ADA essential-function flag
  (p123): work that is a reason the role exists, as opposed to a catch-all. An
  **expectation** (`is_expectation`) is by definition **non-essential**; the two
  are kept consistent (an essential item must have importance and hours; a
  non-essential catch-all need not).
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

The model now knows ownership, %, criticality, essential-status and load, so the
HRCI **Problems** idea becomes free: a derived strip (no new table) at the top of
Balance and on a small dashboard, ranked by severity, each row deep-linking to
its fix. Grouped by the **HRBoK gap categories — People / Process / Structure /
Tools** (p52):

**People**
- 🔴 a person **over 100%**
- 🔴 a **CRITICAL** accountability with **no PRIMARY**
- 🔴 **key-person risk** — a CRITICAL, essential accountability held by exactly
  **one** active person with **no CONTRIBUTOR** (tribal knowledge, no backup)
- 🟡 **unassigned** accountabilities — with the **Assign / Archive / Propose
  role** actions from the Unassigned workspace inline

**Process**
- 🟡 an accountability whose shares **don't total 100%**
- 🟡 **uncosted** essential accountabilities (real, essential work with no hours)
- 🟡 a **KPI measuring nobody** or with **no measurement defined** (not yet a
  job-related, evidence-based measure)

**Structure**
- 🟡 an **unstaffed** role card carrying CRITICAL work
- 🟡 a role card or KPI with **no department**

**Tools** — reserved; no signals today (kept so the taxonomy is complete).

This is the direct answer to "easily see what changes need to be done," in the
profession's own gap-analysis shape.

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
| **HRBoK** TDR job analysis (p121) | area ≈ duty; accountability ≈ task/responsibility |
| **HRBoK** ADA essential-function test (p144) | criticality × cadence × hours; `is_essential` |
| **HRBoK** job-related, measurable KPIs (p122, p204) | KPI ↔ responsibility link; measurement required |
| **HRBoK** gap analysis People/Process/Structure/Tools (p52) | needs-attention grouping |
| **HRBoK** tribal-knowledge / succession risk (p200, p150) | key-person needs-attention signal |
| **HRBoK** span of control, FTE, cost-per-FTE (p70, p180) | additive Roles-view metrics |

## Two audiences: managers plan here, employees answer via Lark

**This app is a manager's tool.** Managers author accountabilities, set
workload, own the split, and read the needs-attention strip. Employees do **not**
work in this UI — they interact through **Lark** (the org's chat, already wired
for HR data sync and approvals): short forms and notifications, in the tool they
already live in.

This split turns out to *solve* the workload problem rather than complicate it,
and it is textbook HRBoK: **job analysis is done by surveying the workers who do
the job** about "the types of tasks they do, the frequency of the efforts, and
to whom they are dependent" (p121). The manager should not have to guess a task's
hours — the person doing it knows. So:

- **Workload confirmation (job analysis by questionnaire).** For an uncosted
  accountability, the manager sends a one-tap **Lark micro-form** to the owner:
  *"Roughly how many hours a month does 'Pack and dispatch orders' take you?"*
  The reply populates `hours_per_month`. This is the direct-hours model (the
  simple default) fed by the one person who actually knows — and it is exactly
  the HRBoK job-analysis method, not a workaround.
- **Assignment / allocation change → notify + acknowledge.** When a manager
  assigns work or changes someone's %, the affected employee gets a Lark
  notification and can acknowledge or flag *"that's not what I do"* — closing the
  accuracy loop the HRBoK's periodic job-analysis review calls for (p123).
- **KPI check-ins** already point at Lark (self-review + Lark wiring is a known
  pending item). The library's job-related, measurable KPIs are what those
  check-ins ask about.

**Design principle for every new surface:** if it needs an *employee* to do
something, it is a **Lark form/notification**, and this app only shows the
*manager* the request's status. The app never becomes an employee portal.

Concretely, this rides the **existing Lark integration** (edge functions +
secrets already in the repo for attendance/leave/approval sync); the new pieces
are message templates and a small "sent / answered" status column, not a new
channel. Full employee-facing Lark flows are their own spec once the
manager-side model lands — noted here so the model leaves room for them (an
accountability carries the fields a Lark form needs: name, current hours, owner).

## Grounding in the HRBoK (HRCI, 2017)

The *Guide to the Human Resource Body of Knowledge* is a 609-page reference for
the whole HR profession. Most of it — employment law, benefits, labor
relations, recruiting, compensation structures, ethics — is **not** this
feature's concern and is deliberately not pulled in (see Out of scope). But its
**job-analysis and workforce-planning doctrine is exactly what this model is,
and it sharpens several decisions.** The concepts below are integrated; page
references are to that book.

### An accountability *is* a job-analysis unit (TDR)

The HRBoK defines the hierarchy of work through **task-based (TDR) analysis**
(p121): a **task** is the most fundamental activity; a **duty** is several
tasks; a **responsibility** is the *obligation to complete the tasks and duties*
plus wider organizational requirements. Our model already mirrors this —
responsibility **area** ≈ duty, the accountability ≈ task/responsibility. We
adopt the vocabulary explicitly so the app speaks the profession's language.

Job-analysis questionnaires survey "the types of tasks they do, **the frequency
of the efforts, and to whom they are dependent for task completion**" (p121) —
i.e. **cadence** and **contributors/dependencies**. That is precisely the
assignment model above, which is reassuring: the design was reconstructing job
analysis, and now says so.

### The ADA essential-function test = our three knobs (p144)

The single most useful import. Under the ADA, an **essential function** is a
task "that is the reason for the job's existence," and is determined by three
factors:

1. **Percentage of time spent** on it → our **allocation % / hours**.
2. **The frequency** of the task → our **cadence**.
3. **How important** it is to the overall purpose → our **criticality**.

So the fields we chose are not arbitrary — they are the legally-grounded test
for whether work is essential. Two concrete consequences:

- **Add `is_essential boolean default true`.** An essential function is the
  reason a role exists; the HRBoK is explicit that vague catch-alls like *"other
  duties as assigned"* are **not** essential because they fail the importance /
  frequency / reason test (p123). This is the *same distinction* the existing
  `is_expectation` flag draws — behavioural catch-alls that are not costable
  workload. We align the two: an **expectation is a non-essential item**; an
  **essential function must have importance (criticality) and time (hours)**.
  The needs-attention strip flags a CRITICAL item with no owner or no hours as a
  contradiction (essential by criticality, unstaffed or unmeasured in practice).
- The Roles view and any exported role document can now legitimately label its
  costed, owned, CRITICAL responsibilities as the role's **essential functions**
  — which is what a defensible job description requires.

### KPIs must be job-related and measurable (Griggs v. Duke Power, Title VII; p122, p204)

The HRBoK is emphatic: performance criteria "must be **job related**" and
evidence-based, tying objectives "to tasks, duties, and responsibilities"
(p204); criteria not tied to the job are legally indefensible (*Griggs v. Duke
Power*, p122). This directly hardens the KPI library:

- A KPI should **link to the responsibility/essential function it measures**, not
  float free. (Groundwork exists — KPIs already attach to role cards.)
- A KPI with **no measurement defined** (the four we already flagged) or **tracked
  on nobody** is, in HRBoK terms, not yet a job-related, evidence-based measure.
  The needs-attention strip already surfaces both; we now frame *why* it matters.

### Gap analysis has four categories: People / Process / Structure / Tools (p52, p84)

The HRBoK frames organizational gaps in exactly these four buckets (and the
sibling project's `ProblemCategory` enum — `PEOPLE, PROCESS, STRUCTURE, TOOLS` —
is lifted straight from this). The needs-attention strip adopts them as its
**grouping**, so "what needs doing" reads in the profession's standard shape:

- **People** — over-capacity, unowned work, key-person risk (below).
- **Process** — uncosted work, shares ≠ 100%, KPI measuring nobody.
- **Structure** — role/KPI with no department, an unstaffed CRITICAL role.
- **Tools** — reserved (no signals today; kept so the taxonomy is complete).

### Key-person / tribal-knowledge risk (p200, p224; succession p150)

The HRBoK names **tribal knowledge** — work only one person can do — as "a form
of risk that HR must manage," addressed through succession and cross-training.
The model can now *detect* it: a **CRITICAL, essential accountability held by
exactly one active person, with no CONTRIBUTOR** is a bus-factor-of-one. This
becomes a **People** needs-attention signal — "only Marvin can do device
flashing; no backup" — which is the succession-planning cue the book calls for,
computed for free from criticality + assignments.

### Workforce metrics (span of control p70; FTE / cost-per-FTE p180, p306)

The Roles view already reports holders, hours, load and cost. The HRBoK's
standard workforce metrics slot in with no new data: **span of control**
(direct reports per manager, from `reports_to_id`), **FTE** and **cost per FTE**
(from capacity + base salary). These are additive to the existing Roles table,
not a new screen.

## Out of scope (enterprise scaffolding + the rest of the HRBoK)

**From the sibling app:** multi-tenant, scenarios-as-tables, groups / group
types, dotted-line matrix, time-based allocation tables (seasonal), forecasting
sheets, comments / @mentions, approval workflows, SOC 2, CSV import.

**From the HRBoK:** everything that is not job analysis, workforce planning,
competency/gap, performance-measurement job-relatedness, or workforce metrics —
i.e. employment law and EEO detail (kept only as the *rationale* for
job-relatedness), recruiting and employer branding, total-rewards / benefits
design, labor relations, HR ethics, global mobility, learning-program design.
This app is a workforce-planning tool, not an HRIS; the book grounds the model,
it does not expand its scope.

Each is revisitable when a concrete need appears; none serves "edit efficiently /
see what changes" today.

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
  the ≠100% check; fuzzy duplicate match; each needs-attention signal incl.
  key-person risk (CRITICAL + essential + one holder + no contributor) and its
  People/Process/Structure/Tools grouping; `is_essential`/`is_expectation`
  consistency.
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
2. **Criticality + essential + status** — three columns; the criticality/
   essential chips (the ADA test made visible); **Archive** replaces hard-delete
   for "not needed anymore". Feeds needs-attention ranking.
3. **Needs-attention strip + Unassigned workspace** — pure derivation over
   current data, grouped People/Process/Structure/Tools, incl. key-person risk
   (Assign / Archive / cluster / Propose role); ships value before the big
   migration. Note: until step 4, "unassigned" means the *current* notion — no
   `owner_employee_id` and no staffed home card (the existing orphan/unattributed
   logic). Once assignments land, the same view's criterion becomes the literal
   "no PRIMARY assignment"; the UI does not change, only what feeds it.
4. **Assignments table + backfill** — owners → PRIMARY assignments; the split
   function extended; nothing user-visible changes yet.
5. **Assignment panel + %** + simplifiers on the accountability editor.
6. **Assign-from-library authoring** + duplicate warning.
7. **Lark workload confirmation** — a "ask the owner" action on an uncosted
   accountability that sends a Lark micro-form and shows sent/answered status;
   the reply fills `hours_per_month`. Rides the existing Lark integration; its
   own spec once 1–6 land, but the model already carries the fields it needs.

Each step is its own plan, reviewed and merged before the next. Steps 1–3 need
no core migration and ship immediate value (simpler workload editing, the
needs-attention/gap view); steps 4–6 are the shared-accountability change; step
7 closes the manager↔employee loop via Lark.

## Design system

Per `PRODUCT.md`: mono for hours/percentages; tinted borderless status chips
(criticality, PRIMARY/CONTRIBUTOR, "= 100%"); `ResponsiveTable`; single purple
CTA; the `TabIntro` pattern to explain the new vocabulary in place.
