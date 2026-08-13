# Spec — The KPI Cascade: definitions and results

**Date:** 2026-08-13
**Status:** Approved design, not yet implemented
**Source material:** `Luxium_People_Workforce_KPI_App_Update_Spec.docx` (owner, 2026-08-13) and the owner's framing message the same day
**Supersedes:** the never-written "Spec B" (KPI logging + Employee of the Month)
**Builds on:** Spec A — the role workbench (`2026-08-11-role-workbench-design.md`)

## Why

The app can say what work exists, which role owns it, and who holds that role.
It cannot say whether any of it is going well.

The framework is a **lightweight cascading Balanced Scorecard plus strategic
workforce planning, with EOS-inspired accountability** — not an EOS
implementation. Internally: Integrated Performance & Workforce Planning.

Two things are missing. First, a layer between work and measurement: today a
KPI hangs off a role with nothing saying what it is supposed to prove, which is
how you get one KPI per responsibility instead of the two to four that matter.
Second, results — the KPI Library defines rules that nothing ever evaluates.

## Scope

This spec covers **definitions and results**. Explicitly deferred, each to its
own spec:

| Deferred | Why it is separate |
|---|---|
| Issues (red → owner + due date) | Real, and named in the owner's design principles, but the dashboard is useful before it exists. Several draft KPIs measure issue aging, so that spec depends on this one. |
| External data integrations | Cashflow, commerce/order systems, Payroll-external. This spec builds the socket; that spec wires the plug. |
| Capacity simplification | `Capacity Tracked?`, `Workload Method`, Estimated Load vs Workload Coverage, and removing the "everything must be costed" warnings. Independent of the KPI work. |

## Decisions

Each of these was chosen against a real alternative. Do not re-litigate them
without new information.

1. **A person's KPIs are their role's KPIs. Pure inheritance, no per-employee
   exceptions.** A new hire is measurable the day they are assigned a role, and
   a role change moves measurement automatically. Two costs, both accepted:
   two people in one role cannot be measured differently, so a trainee carries
   the veteran's target; and `employee_kpis` is a LIVE table on production, so
   removing it is a destructive migration that also rewrites a live SQL
   function — see "Removing `employee_kpis`" below, which corrects an earlier
   draft of this spec that wrongly called it unapplied.
2. **Desired Outcomes hang off a role's accountability areas**, not off the
   role as a whole and not off the KPI. Area → outcome → KPI is the authoring
   order, and modelling it this way is what makes both gaps visible: an area
   with responsibilities and no outcome, and an outcome nothing measures.
3. **Department and Company results are recomputed from source over a wider
   population, never aggregated from children.** Averaging children's
   percentages is wrong the moment two people handle different volumes.
4. **No Data is not Red.** Red means data exists and the target was missed.
   This is a rule about honesty: a red square that only means "nobody entered
   anything" teaches people to ignore red squares.
5. **Where manual input is CAPTURED is deliberately still open**, and the
   design must not force it. The owner is weighing an in-app surface (staff
   would install the app) against Lark forms (the source docx §4 puts exception
   capture in Lark; the existing division of labour agrees). This spec
   therefore defines the **ingestion boundary**, not the collection surface —
   see "The ingestion boundary" below. Choosing Lark later must be a wiring
   change, not a schema rewrite.
6. **Only confirmed exceptions count.** Every KPI in the owner's draft says
   *confirmed* fulfillment errors, *confirmed preventable* purchasing errors.
   Whoever saw it records it; a manager or HR confirms it; the KPI counts the
   confirmed ones. An unconfirmed record is a claim, and a metric that moves on
   unverified claims is a metric people will learn to game or resent.

## Data model

### Configuration

**`kpis` gains four columns.** Measurement and Source A/B are already covered by
the unapplied `20260811000001` (`value_type`, `numerator_label`,
`numerator_source`, `denominator_label`, `denominator_source`, `unit`,
`cadence`, `proof_type`), and **`department_id` already exists** — added by the
applied `20260723000002_kpi_departments.sql` and already on the `Kpi` model.

| Column | Values | Note |
|---|---|---|
| `level` | `PERSONAL` / `DEPARTMENT` / `COMPANY` | Which scope this KPI is designed for |
| `parent_kpi_id` | → `kpis` | The higher-level KPI this one serves |
| `rollup_type` | `DIRECT` / `SHARED` / `ALIGNED` / `INDEPENDENT` | Governs whether the engine computes upper scopes |
| `data_method` | `AUTOMATIC` / `HYBRID` / `MANUAL_EXCEPTION` / `MANUAL_PERIODIC` | Governs where inputs come from |

**Targets move up.** A Department or Company KPI has no role to hang a target
on, so `kpis` carries `target_direction` and `target_value` as the default.
`role_scorecard_kpis.goal_*` (also from `20260811000001`) stays as a per-role
override — the KPI's own target is what a non-personal scope uses.

**`role_outcomes`** — new. `(id, company_id, role_scorecard_id,
responsibility_area, text, sort_order)`. The area is the text name used by
`wp_tasks.responsibility_area`, matching how `areasByRole` already groups them.

**`role_scorecard_kpis.outcome_id`** — new, nullable, → `role_outcomes`. Reads
as "this role's KPI proves this role's outcome". It lives on the link rather
than on `kpis` because an outcome belongs to a role, and a Company KPI has no
role.

**Removing `employee_kpis` is a live schema change, not a file deletion.** An
earlier draft of this spec said it had never been applied. That was wrong, and
the correction changes the cost of decision 1:

- `employee_kpis` was created by `20260718000005` and **is applied on
  production**. Migrations `20260719000001-3` are confirmed applied, and
  `supabase db push` applies in filename order, so everything before them is
  too. The table holds real per-employee curation.
- `20260718000006` defines `generate_employee_review`, a **live SQL function**
  that reads `employee_kpis` — intersecting an employee's subset with their
  role's KPIs, and falling back to the full role set when the subset is empty.
  Dropping the table without rewriting that function breaks review generation.
- Only `20260811000002` and `20260812000001` are genuinely unapplied files that
  can simply be deleted.

So the work is: rewrite `generate_employee_review` to read the role's KPIs
directly, then drop the table in the same migration. Because "no rows" already
means "the whole role set", every employee with no curated subset is unaffected
by definition; only employees with a deliberately narrowed subset change
behaviour, and they change to measuring their full role set — which is what
pure inheritance means.

### Results

**`kpi_results`** — one row per KPI × period × scope.

| Column | Note |
|---|---|
| `period` | `'2026-08'` — monthly |
| `scope` | `PERSONAL` / `DEPARTMENT` / `COMPANY` |
| `employee_id`, `department_id` | Populated per scope; both null at company scope |
| `numerator`, `denominator` | **Stored, not just the computed value** — a ratio cannot be re-aggregated or audited from a percentage alone |
| `value` | Derived; stored so a historical row survives a formula change |
| `target_snapshot`, `direction_snapshot` | What the target WAS in that period. Raising a target must not silently reclassify closed months |
| `status` | `ON_TRACK` / `OFF_TRACK` / `NO_DATA` |
| `source_completeness` | `COMPLETE` / `MISSING_SOURCE` |

Unique on `(kpi_id, period, scope, employee_id, department_id)`.

**`kpi_exceptions`** — `(id, company_id, kpi_id, employee_id, department_id,
occurred_on, quantity, note, reported_by, reported_via, confirmed_at,
confirmed_by, external_ref)`. One row per occurrence. Confirmed rows aggregate
by month into the numerator of a `MANUAL_EXCEPTION` KPI.

`reported_via` records the collection surface (`APP` / `LARK`) and
`external_ref` the originating record's id, so a Lark-sourced row is
recognisable and idempotent on re-sync. Both exist from day one even if only
one surface is built, because retrofitting provenance onto rows already
collected is not possible.

## How results are produced

Three input paths, all landing in the same `kpi_results` row:

1. **Automatic sources.** A registry maps a source key to a function returning
   `(numerator, denominator)` for a scope and period. The first four come from
   data the app already owns: attendance, review completion, critical vacancy
   aging, employee documentation completeness. That makes the HR Manager's
   whole KPI set automatic on day one — which matters because it exercises the
   engine end to end rather than only on paper.
2. **Confirmed exceptions**, aggregated per month, for `MANUAL_EXCEPTION`.
   Purchasing errors, confirmed fulfillment errors, technical rework.
3. **Period readings**, for `MANUAL_PERIODIC` and the manual half of `HYBRID`:
   a numerator and denominator recorded for a scope and period. This is the
   path for "campaigns done on time = 8 of 10 this month" — a metric someone
   counts periodically, not an incident that happens.

External sources (Cashflow, commerce, order systems) drop into slot 1 in the
integrations spec without changing anything here. That is the point of the
registry.

## The ingestion boundary

Paths 2 and 3 are **records with a shape, not screens**. An exception is
`(kpi, subject, occurred_on, quantity, note)`. A period reading is
`(kpi, scope, period, numerator, denominator, note)`. Both are written through
a repository method that validates and stamps provenance.

Whether a human produces those records by opening this app or by filling a
Lark form that a sync job replays is **an unmade decision**, and the boundary
is drawn here specifically so it stays unmade without blocking the build:

- Nothing above the repository knows which surface produced a record.
- A Lark sync would be a caller of the same methods, matching the existing
  `sync-lark-self-evals` pattern, using `external_ref` for idempotency.
- Building the in-app surface first does not foreclose Lark, and vice versa.

**What the choice does change**, and why it must be made before the surface is
built rather than after: this app's navigation is HR/admin-gated today. An
in-app surface makes ordinary employees a new class of user, needing routes
outside that gate and RLS written deliberately rather than adapted from a
neighbouring policy. A Lark surface needs none of that — the sync job runs as a
service role and no employee ever signs in.

The implementation plan should therefore build the boundary and the automatic
sources first, and treat the manual surface as its own late task, by which
point the decision will have been made.

## Pure logic, tested apart from the UI

These carry the correctness and belong in plain Dart files with unit tests:

- **Status.** Given numerator, denominator, target and direction → `ON_TRACK` /
  `OFF_TRACK` / `NO_DATA`. Tests must pin: missing denominator is `NO_DATA` not
  `OFF_TRACK`; a zero denominator is `NO_DATA`, not a division error; exactly
  meeting the target is on track for both directions; and a zero numerator with
  a real denominator is a genuine result, not missing data.
- **Population resolution.** Given a KPI, a scope and a period → whose data to
  include. A person's department comes from their role, so **a person with no
  role has no department and falls out of Department scope entirely** — that
  must be a pinned test, not a discovery.
- **Exception aggregation.** Confirmed only; by `occurred_on` month, not by
  recorded-at or confirmed-at month, so a late-confirmed exception lands in the
  month it actually happened.
- **Roll-up eligibility.** `DIRECT` computes upper scopes; `SHARED` computes
  department and company but never personal; `ALIGNED` and `INDEPENDENT`
  compute only their own level.

## Screens

- **KPI Library** gains the five new fields, and a level filter. Authoring
  order is company-first, then department, then role.
- **Role workbench** gains an Outcomes pane beside Responsibilities, and the
  KPI pane gains "proves which outcome".
- **KPI Results** — a monthly view per scope: what the number is, where it came
  from, and what is missing.
- **Dashboard** — Company and Department for the month, off-track first.
- **Exception recording and period readings** — a confirmation queue for
  managers and HR either way. The surface that COLLECTS them is deferred until
  the app-versus-Lark decision is made; see "The ingestion boundary".
- Personal history feeds the existing quarterly check-in rather than a new
  surface.

## Risks

- **The cascade only pays off if company KPIs are authored first.** Nothing in
  the schema enforces the order, and starting from roles reproduces the KPI
  bloat this is meant to end. This is a process risk, not a code one; the
  Library's level filter is the only nudge the app offers.
- **An in-app manual surface widens who uses the app.** Today it is an HR and
  admin tool. Ordinary employees recording exceptions would be a new class of
  user, needing routes outside the HR gate and RLS written deliberately rather
  than adapted from a neighbouring policy — the same trap the People Analyzer
  spec flagged before it was cancelled. Routing capture through Lark avoids
  this entirely. The decision is open; the cost of getting it wrong lands here.
- **Confirmation is a bottleneck by design.** If nobody confirms,
  `MANUAL_EXCEPTION` KPIs read as zero exceptions rather than as unknown. The
  results view must distinguish "none happened" from "none confirmed yet".
- **A KPI whose definition changes mid-period** produces a row computed one way
  and a target snapshotted another. Closed periods stay stable; the current
  period recomputes. Reopening a closed period is out of scope.

## Done when

- A KPI carries level, department, parent, roll-up type and data method, and
  the Library can filter by level.
- A role's accountability areas carry desired outcomes, and a KPI can name the
  outcome it proves.
- A person's KPIs come from their role with no per-employee setup;
  `generate_employee_review` reads the role's KPIs directly, and
  `employee_kpis` is dropped in the same migration.
- A month's results exist at all three scopes, with department and company
  recomputed from source rather than averaged from children.
- No Data renders visibly differently from Off Track.
- The four in-app automatic sources compute without anyone entering a number.
- An exception reaches `kpi_exceptions` through the repository boundary,
  carrying the surface it came from, and only confirmed ones move a KPI. The
  confirmation queue exists regardless of which surface collected the record.
- A period reading ("8 of 10 campaigns on time") can be recorded for a scope
  and period through that same boundary.
- **Open until the owner decides:** whether the collecting surface is in-app or
  a Lark form. The build order puts that task last so the decision is not
  forced early; the boundary above is what makes waiting safe.
- `flutter test` green; `flutter analyze lib test` 0 errors, 0 warnings.
- Migrations committed and handed over, **not applied**.
