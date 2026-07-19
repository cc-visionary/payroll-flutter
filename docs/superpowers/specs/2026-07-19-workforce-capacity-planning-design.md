# Workforce Capacity Planning (Phase A + B) — Design Spec

> Date: 2026-07-19. First slice of the "integrate workforce planning with
> responsibilities and loads, and integrate KPI" initiative. Turns the
> `/workforce-planning` *Coming Soon* stub into a working, driver-based capacity
> model, seeded once from the user's `luxium_capacity_model.xlsx`.

## Background & goal

The user maintains a capacity model in a spreadsheet (`~/Downloads/luxium_capacity_model.xlsx`)
that computes, for every task the business does, how many hours per month it
costs, who owns it, and therefore how **loaded** each person is. The chain is:

```
business drivers × growth multiplier
  → task times/month × minutes each
  → task hours/month
  → Σ hours per owner ÷ capacity
  → load % per person
```

Chosen goal (from brainstorming): **workload balance** — see who owns which
responsibilities, how loaded they are (over/under capacity), and which KPIs they
track, so work can be rebalanced. "Load" is measured as **manual effort in hours**
(cadence × frequency × minutes-per-unit), not a t-shirt size — matching the
spreadsheet, which the user pointed to as the source of truth.

This is the first of four phases (A–D). This spec covers **A (task inventory +
load) + B (drivers + growth multiplier)**, chosen as the first build slice so the
numbers self-update and scenarios work from day one.

## Scope

**In:**
- New `wp_*` table namespace: value-chain nodes, drivers, rates, tasks, capacity
  overrides, config.
- Postgres views that compute per-task hours and per-person load (base at ×1 and
  scaled at the stored growth multiplier).
- A one-time **idempotent data migration** seeding the model from the xlsx.
- The Workforce Planning screen rebuilt as a hub with five tabs: **Balance**,
  **Role View**, **Structure**, **Tasks**, **Drivers & Scenario**.
- A **Structure** tab: a draggable org tree (people arranged by reporting line)
  where you can **drag a responsibility (task) from one person onto another** to
  reassign its owner, and **drag a person under a different manager** to restructure
  reporting. Both are the natural way to act on the load numbers.
- Each person's assigned KPIs surfaced **read-only** (reusing the Phase-1/2 KPI
  library + assignment layer).
- RLS mirroring `kpis` / `role_scorecards`.

**Out (later phases / YAGNI):**
- **Phase C** — open/proposed role slots, orphan/high-risk-unowned work, tier-leak
  report, work-per-value-chain-node rollup, payroll now-vs-proposed, hiring-trigger
  verdicts (the spreadsheet's Dashboard sheet).
- **Phase D** — tying KPIs to nodes/tasks so a node's health = load + KPI
  performance.
- A **formula engine** for derived drivers (see Simplifications).
- **Multiple named scenarios** (see Simplifications).
- An in-app xlsx file-picker / importer UI (the seed is a one-time migration).
- Per-task or per-person target/frequency overrides beyond what the model holds.
- A **graphical/canvas org chart** with connector lines — the Structure tab is an
  **indented, expandable tree** (simpler, responsive, testable) for v1.
- **Powering the separate `/org-chart` route** — it stays a stub for now; the tree
  is built as a reusable widget so `/org-chart` can adopt a read-only/export version
  later.
- **Bulk / historical org changes** — drags apply immediately to the live record;
  no effective-dating or reorg drafts.

## Simplifications (deliberate fidelity trade-offs)

These are the only two places we trade spreadsheet fidelity for a much smaller
build. Both were surfaced and approved during brainstorming.

1. **Flat drivers, no formula engine.** The sheet derives some drivers from others
   (e.g. `units needing config = total units × 80%`). We do **not** replicate
   arbitrary formulas. Every driver is a flat input value; the growth multiplier
   scales any driver flagged `grows = true`. A 2× scenario therefore doubles all
   volume drivers together, but the exact "80% of total" linkage is collapsed — HR
   maintains any derived driver as its own input row (and flags it `grows` so it
   scales).
2. **One global growth multiplier**, not multiple named scenarios. The sheet's
   "current vs proposed" columns become **base** (×1) vs **scaled** (×multiplier)
   columns off a single `growth_multiplier` in `wp_config`.

## Data model

All tables are company-scoped (`company_id uuid not null`), have
`created_at timestamptz not null default now()`, and (where mutable in-app)
`updated_at`. New namespace prefix: `wp_`.

### `wp_value_chain_nodes`
The organizing spine ("0. Opportunity gate" … "12. People", "W. Wholesale lane",
"S. Physical store"). Editable, ordered.
```
id uuid pk, company_id, code text not null, name text not null,
sort_order int not null default 0
unique (company_id, lower(trim(code)))
```

### `wp_drivers`
Business volumes.
```
id uuid pk, company_id, name text not null, value numeric not null default 0,
grows boolean not null default false, note text, sort_order int not null default 0
```
`scaled_value = grows ? value × growth_multiplier : value`.

### `wp_rates`
Minutes-per-unit productivity library.
```
id uuid pk, company_id, name text not null, minutes_each numeric not null default 0,
note text
```

### `wp_tasks`
The costed task inventory (~160 rows after import).
```
id uuid pk, company_id,
node_id uuid null → wp_value_chain_nodes on delete set null,
name text not null,
brand_scope text null,                 -- 'Shared' | 'GameCove' | 'OGKILS' | ...
cadence text null,                     -- descriptive label (Monthly/Weekly/Per-unit/Ad-hoc/...)
times_source text not null default 'manual' check (times_source in ('manual','driver')),
times_manual numeric null,             -- when times_source='manual'
driver_id uuid null → wp_drivers on delete set null,   -- when times_source='driver'
driver_factor numeric not null default 1,
minutes_source text not null default 'manual' check (minutes_source in ('manual','rate')),
minutes_manual numeric null,           -- when minutes_source='manual'
rate_id uuid null → wp_rates on delete set null,        -- when minutes_source='rate'
skill_tier text null check (skill_tier is null or skill_tier in
    ('Transactional','Operational','Managerial','Strategic')),
risk text null check (risk is null or risk in ('Low','Medium','High')),
capability text null,
owner_employee_id uuid null → employees on delete set null,  -- null = orphan/unassigned
role_scorecard_id uuid null → role_scorecards on delete set null,
responsibility_area text null,         -- imported label of the card area this task came from (informational)
notes text,
external_ref text null,                -- e.g. 'T017'; import idempotency key
updated_at timestamptz not null default now()
unique (company_id, external_ref)      -- partial: where external_ref is not null
```
Owner, driver, rate, node, and card all `on delete set null` — deleting an
employee/driver/etc. degrades the task to unassigned/manual rather than deleting
work. (This is a Phase-C concern too: an orphaned owner shows as unowned work.)

### `wp_capacity_overrides`
```
employee_id uuid pk → employees on delete cascade,
capacity_hours numeric not null
```
Absence ⇒ `wp_config.default_capacity_hours` (160). Cascade on employee delete.

### `wp_config`
Single row per company.
```
company_id uuid pk, growth_multiplier numeric not null default 1.0,
default_capacity_hours numeric not null default 160
```

### Views (the canonical math — the app reads these, never recomputes)

**`wp_task_computed`** — one row per task, joining `wp_config`, `wp_drivers`,
`wp_rates`:
```
task_id, company_id, owner_employee_id, node_id, skill_tier, risk,
times_per_month_base,   -- driver.value (unscaled) × driver_factor, or times_manual
times_per_month_scaled, -- driver.scaled_value × driver_factor, or times_manual
minutes_each,           -- rate.minutes_each or minutes_manual
hours_per_month_base    = times_per_month_base   × minutes_each / 60,
hours_per_month_scaled  = times_per_month_scaled × minutes_each / 60
```
(`times_manual` tasks are identical in base and scaled — only `grows` drivers move.)

**`wp_person_load`** — one row per employee that owns ≥1 task (LEFT-joined against
all active employees so zero-task people still appear at 0%):
```
employee_id, company_id, tasks_owned int,
hours_base, hours_scaled,
capacity_hours,                       -- override or config default
load_base   = hours_base   / capacity_hours,
load_scaled = hours_scaled / capacity_hours
```

Views are `security_invoker` so RLS on the base tables governs visibility.

## KPI integration (read-only)

Role View shows each person's assigned KPIs. Reuse the existing
`employeeAssignedKpiIdsProvider` + role-KPI fallback ("no rows = full role set")
from Phase 2 — no new tables, no writes. Balance tab shows a KPI **count** per
person from the same source. Deeper KPI↔node/task wiring is Phase D.

## UI

Rebuild `lib/features/workforce_planning/workforce_planning_screen.dart` (today a
`ComingSoonScreen`) as a tabbed hub. Route and HR/Admin guard unchanged
(`/workforce-planning`, `profile.isHrOrAdmin`). Follow `PRODUCT.md`: single Luxium
purple CTA, 6px radius, tinted status chips (no colored borders), Geist Mono for
the numbers (hours, %, currency), tabular data via `responsive_table.dart`.

1. **Balance** (default tab) — the load-per-person table, reading `wp_person_load`:
   person · role (job title) · tasks owned · hours/mo · capacity · **load %**
   (base and, when multiplier ≠ 1, projected) · a status chip
   (**Over** > 100%, **OK** 80–100%, **Under** < 80%) · KPI count. Sortable by
   load. This is the primary deliverable.
2. **Role View** — a person picker → owned tasks (node · task · cadence · times/mo
   · mins · hrs · tier · risk from `wp_task_computed`), an hours-by-skill-tier
   summary, load %, monthly cost (read-only, from the same source payroll uses —
   `compensation_changes` with role-scorecard base as fallback), and the person's KPIs.
3. **Structure** — the draggable org tree (see next section).
4. **Tasks** — inventory CRUD: create/edit/delete a task; set node, cadence,
   times (manual value or a driver + factor), minutes (manual or a rate), tier,
   risk, capability, owner (employee), and optional responsibility-card link. Filter
   by node/owner/brand.
5. **Drivers & Scenario** — edit drivers (value, `grows`), edit rates
   (minutes_each), and a **growth-multiplier** control (writes
   `wp_config.growth_multiplier`) that re-projects the Balance and Role View tabs.

## Structure tab (org tree + drag-and-drop)

An **indented, expandable tree** of employees built from `employees.reports_to_id`
(roots = employees with no manager). Each node shows: name · job title · **load %**
chip (from `wp_person_load`, Over/OK/Under) · expand caret. Expanding a node lists
that person's **owned responsibilities** (their `wp_tasks`, each an hours-labelled
chip). Two drag interactions, both writing immediately to the live record
(HR/Admin only):

1. **Transfer a responsibility** — drag a task chip from person A's node and drop
   it on person B's node ⇒ `update wp_tasks set owner_employee_id = B`. Both
   people's load chips recompute (re-read `wp_person_load`).
2. **Restructure reporting** — drag a person node and drop it on another person ⇒
   `update employees set reports_to_id = target`. **Cycle guard:** reject the drop
   when the target is the dragged node itself or any of its descendants (would
   orphan a subtree / create a loop); reject a no-op (same manager). A pure helper
   `wouldCreateCycle(tree, movingId, newParentId)` decides, unit-tested; the UI only
   offers valid drop targets and surfaces a SnackBar on an invalid attempt.

Implemented with Flutter `Draggable` / `DragTarget`. Task chips and person nodes are
distinct draggable types so a task can't be dropped as a manager and vice-versa.
No connector-line canvas (that's Out); the indented layout wraps in
`responsive_table.dart`-style constraints and scrolls.

**Dependency to verify in the plan:** the `employees` table's RLS must permit
HR/Admin to update `reports_to_id`. If the existing update policy is narrower, the
plan adds a migration widening it (HR/Admin, company-scoped) — the reporting drag is
blocked without it.

## Import (one-time bootstrap)

A generated **idempotent data migration** seeds the model from the xlsx (parsed at
implementation time), not an in-app importer:

- `wp_value_chain_nodes` ← the Lists "Value chain node" column.
- `wp_drivers` ← the Drivers "Block 1 — Volumes" rows (name, value, `grows` from
  the "Grows?" flag). `wp_rates` ← the Drivers "Block 2 — Rates" rows.
- `wp_tasks` ← the Tasks sheet (~160 rows), keyed on the sheet's `ID` as
  `external_ref` for idempotency. **Times:** best-effort driver bind — a
  volume/per-unit task whose frequency uniquely matches one driver's value binds to
  that `driver_id` (so the multiplier moves it day one); otherwise `times_manual`
  holds the sheet's exact figure. **Minutes:** always `minutes_manual` (the exact
  sheet value, preserving hours); rates are imported as a **library** for HR to bind
  in-app later, not auto-bound.
- **Owner matching:** `Current owner` name → `employees` by
  `lower(trim(first_name || ' ' || last_name))`; unmatched → null. **Card linking**
  (`role_scorecard_id`) is **not** attempted at seed time (the xlsx has no reliable
  card key) — left null for in-app linking (Plan 2). The migration must not fail on
  a missing name; unmatched owners are reported after import for cleanup.
- The migration re-runs safely: tasks upsert on `(company_id, external_ref)`;
  nodes/drivers/rates are find-or-insert by name. Because the tasks unique index is
  **partial** (`where external_ref is not null`), PostgREST/`ON CONFLICT` can't
  target it blindly — the importer does find-then-update-or-insert keyed on
  `external_ref` (same lesson as the KPI functional index in Phase 1).

The match rate (owners found, cards linked) will be reported when the importer is
built, so HR knows how much manual owner assignment remains.

## RLS

Mirror `kpis` exactly (`20260718000001`): company read, HR/Admin/Super-admin write,
using the existing `auth_company_id()` and `auth_app_role()` helpers.

```sql
-- for each wp_* table (nodes, drivers, rates, tasks, capacity_overrides, config):
alter table wp_x enable row level security;
create policy wp_x_select on wp_x for select
  using (company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN');
create policy wp_x_write on wp_x for all
  using (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR')
    and (company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN'))
  with check (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR')
    and (company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN'));
```
`wp_capacity_overrides` is keyed by `employee_id`; its policies resolve
`company_id` through `employees`. Views are `security_invoker = true`.

**`employees.reports_to_id` writes** (Structure tab reporting drag) go through the
`employees` table's own RLS, not a `wp_*` policy. The plan must confirm HR/Admin can
update `reports_to_id`; if the current policy is narrower, add a migration widening
it (HR/Admin, company-scoped, `reports_to_id` only where practical).

## Testing

- **Migrations** — validated on a throwaway Postgres, then the isolated 643xx
  replica (seed splice before `20260418000002`) before any prod push. Assert:
  tables + RLS apply; `wp_task_computed` returns correct hours for (a) a manual
  task, (b) a driver-bound task with `grows=true` at multiplier 1 and 2, (c) a
  rate-bound task; `wp_person_load` sums a multi-task owner and shows 0% for a
  zero-task employee; the seed migration is re-runnable (no duplicate rows).
- **Dart unit tests** — a pure hours/load calculator mirroring the views (manual /
  driver / rate combinations; grows-only scaling; capacity override vs default);
  the Balance status-chip thresholds (Over/OK/Under boundaries at exactly 80% and
  100%); `wouldCreateCycle` (self, direct descendant, deep descendant, valid move,
  same-manager no-op) and the tree-building helper (roots, nesting).
- **Widget tests** — Balance renders and flags over/under; Role View lists owned
  tasks + KPIs; Tasks CRUD builds the right insert/update payload; the
  growth-multiplier control re-projects the Balance figures; the Structure tab
  renders the tree, a task drop builds the `owner_employee_id` update, a person drop
  builds the `reports_to_id` update, and an invalid (cycle/self) drop is rejected
  with no write.
- `flutter analyze` clean; full suite green. (Repo gates on `flutter analyze`
  only — do **not** run `dart format`.)

## Design system

Per `PRODUCT.md` and `CLAUDE.md`: light + dark, single purple CTA `#635BFF` /
`#7F7DFC`, Satoshi + Geist Mono (mono for all numeric columns), 6px radius, 4px
spacing grid, tinted status chips without colored borders, tables wrapped in
`responsive_table.dart`. No new packages.
