# Responsibility ↔ Task Unification — Design Spec

> Date: 2026-07-20. Follows the 4-plan Workforce Capacity Planning feature
> (`2026-07-19-workforce-capacity-planning-design.md`). Makes a role card's
> **responsibility** and a workforce-planning **task** the same object.

## Background & goal

Today there are two parallel lists describing the same work:

| List | Where | Size (prod) | Has hours? | Has owner? |
|---|---|---|---|---|
| Card responsibilities | `role_scorecards.key_responsibilities` JSON (`{area, tasks[]}`) | 7 cards, **42 areas, 164 task strings** | no | no |
| Costed tasks | `wp_tasks` (seeded from `luxium_capacity_model.xlsx`) | **118**, all unlinked, all unowned | yes | no |

They overlap in meaning but not in wording, so they can't be auto-matched. The
user's ask: **"task = responsibilities so that we can easily organize and fix the
load."** Plus an explicit constraint: **it must be realistic to manage — not
time-consuming for HR.**

Those two goals conflict under a naive unification (hand-deduping ~282 rows and
costing 164 responsibilities before load means anything). This design reaches
"task = responsibility" while keeping HR's ongoing job to what it already is:
**edit responsibilities on the role card.** Everything else derives.

## The three burden-killers (the core of this design)

1. **Owner is DERIVED from the role.** A responsibility on the *HR Manager* card
   is owned by whoever holds that role. No mass owner-assignment. An explicit
   per-task owner override remains for exceptions.
2. **Costing is OPTIONAL and incremental.** An uncosted responsibility contributes
   0 hours and renders as "not costed." HR costs the big rocks first; load
   sharpens over time instead of demanding 164 estimates up front.
3. **No 282-row reconciliation.** The 164 card responsibilities become the real
   list. The 118 spreadsheet rows land in a labelled *"from capacity model"*
   bucket that can be bulk-deleted or cherry-picked. Nobody pairs up 282 rows.

## Scope

**In:**
- Promote the 164 card responsibilities into `wp_tasks` (ordered, linked to
  card + area).
- Ordering columns so the card's authored order survives (`area_sort`, `task_sort`).
- `wp_person_load` rewritten to attribute **derived-owner** hours (split across
  role holders) alongside explicit owners.
- `RoleScorecard.responsibilities` backfilled from the task rows so the detail
  screen, role-card PDF, employee role tab, and employment-contract prefill keep
  working unchanged.
- Role-card editor writes responsibility rows instead of the JSON blob.
- Tasks tab regrouped: card → area → tasks, with the legacy bucket and
  "not costed" markers.

**Out (deliberately):**
- Deduping the 118 against the 164 (bucket + delete instead).
- Forcing costing on every responsibility.
- Many-to-many (a task belongs to exactly one card + area — confirmed with user).
- Re-sourcing already-saved employment contracts (they snapshot — see Risk 1).
- Dropping the legacy `key_responsibilities` column (kept for rollback).

## Data model

`wp_tasks` already has `role_scorecard_id` (FK) and `responsibility_area` (text).
**Add two ordering columns** (migration):

```sql
alter table wp_tasks
  add column area_sort int not null default 0,
  add column task_sort int not null default 0;
```

Ordering matters because the role-card PDF and the employment-contract prefill
render responsibilities in the card's authored order; sorting by name would
silently reword those documents.

**Why text + sort rather than a first-class `wp_responsibility_areas` table:**
fewer moving parts for the editor and the migration, and an area with zero
responsibilities carries no meaning anyway (it simply isn't persisted). Renaming
an area is a single `update wp_tasks set responsibility_area = :new where
role_scorecard_id = :card and responsibility_area = :old`.

**Task identity:** a responsibility row is `(role_scorecard_id, responsibility_area,
name)`. Promotion is idempotent on that triple.

**Legacy rows:** the 118 seeded tasks are exactly those with `external_ref is not
null` and `role_scorecard_id is null` — no new column needed to identify the bucket.

## Derived owner + the load rewrite

The rule, in priority order, for attributing a task's hours:

1. `owner_employee_id` set → that person carries **all** the hours (explicit override).
2. else `role_scorecard_id` set → split evenly across **active employees holding
   that role** (`employees.role_scorecard_id = task.role_scorecard_id`,
   `employment_status='ACTIVE' and deleted_at is null`). N holders → `hours / N` each.
3. else → **unattributed** (the orphan bucket; surfaced, not silently dropped).

`wp_person_load` is rewritten to union the explicit and derived attributions. A
role with **zero** holders contributes nothing to anyone but must still be visible
as unattributed work (that's a staffing gap signal, and matches the existing
"orphan work" idea).

`wp_task_computed` is unchanged (per-task hours); only the attribution layer moves.

## Backfill (how the card keeps working)

Exactly the pattern proven in the KPI unification: `RoleScorecard.responsibilities`
stays a model field, but `fromRow` builds it from the embedded task rows —
grouped by `responsibility_area`, ordered by `area_sort` then `task_sort` — instead
of parsing `key_responsibilities`. The repository's `list()`/`byId()` selects gain a
`wp_tasks(...)` embed.

Every downstream consumer then keeps working untouched: role-card detail screen,
`role_card_pdf.dart`, employee `role_tab.dart`, and the employment-contract
prefill in `employment_contract_form.dart`.

**`key_responsibilities` is kept** (NOT NULL) for rollback and written as `[]` by
`toUpsert` — omitting the key causes a `23502` insert failure. This is a recorded
lesson from the KPI work; do not remove the key.

## Editor

The role-card form's responsibilities section keeps its current UX (areas, each
with a list of responsibility lines) but persists to task rows: diff the edited
tree against the existing rows and insert / update / delete, assigning
`area_sort` / `task_sort` from list position. Costing fields are **not** exposed
here — HR edits *what* the responsibility is; *how long it takes* is set on the
Tasks tab. That separation is what keeps card editing as fast as it is today.

## Tasks tab

Regrouped from a flat list to: **role card → responsibility area → responsibilities**,
in authored order, showing per row: name · hours (or **"not costed"**) · effective
owner (with a *derived* hint when it comes from the role) · cadence.

Plus two buckets, both collapsible:
- **From capacity model (118)** — the legacy seeded rows, with a bulk-delete and
  the option to link one into an area if it's genuinely a distinct responsibility.
- **Unattributed** — tasks whose role has no holder, or with neither owner nor card.

## Migration plan

One forward migration:
1. `alter table wp_tasks add column area_sort/task_sort`.
2. Promote: for each active role card, for each area (index → `area_sort`), for each
   task string (index → `task_sort`), insert a `wp_tasks` row (`name` = the string,
   `role_scorecard_id`, `responsibility_area`, uncosted: `times_manual`/`minutes_manual`
   null, `times_source`/`minutes_source` = `'manual'`). Idempotent: skip when a row
   with the same `(role_scorecard_id, responsibility_area, lower(trim(name)))` exists.
3. `create or replace view wp_person_load` with the derived-owner attribution.

Validated on a throwaway Postgres before any prod push (the established pattern);
the prod push is the user's call.

## Risks

1. **Employment contract (Annex A).** Verified: the contract **snapshots** —
   `employment_contract_form` prefills from the card into the document input, which
   serializes `responsibilities` via `toJson`/`fromJson`. Already-saved contracts
   keep their own copy and are unaffected; only *new* contract prefill reads the
   card. Mitigation: a regression test asserting the prefill produces the same
   `(area, tasks[])` structure and order before/after the switch.
2. **Order drift** in the PDF/contract if `area_sort`/`task_sort` are wrong →
   covered by the ordering columns + a test on the backfill grouping.
3. **`key_responsibilities` NOT NULL** → `toUpsert` must keep writing `[]` (23502).
4. **Split-hours surprise:** two holders of one role each show half the hours. This
   is deliberate (capacity, not accountability) and must be labelled in the UI.
5. **Editor regression** is the largest UI surface; the diff-and-persist logic gets
   pure unit tests.

## Testing

- Migration on throwaway Postgres: columns added; promotion inserts 164 rows with
  correct ordering and is idempotent on re-run; `wp_person_load` attributes
  explicit-owner, derived-split (N=1, N=2, N=0), and unattributed cases correctly.
- Pure Dart: the backfill grouping (rows → ordered `ResponsibilityArea` list); the
  editor's diff (insert/update/delete + sort assignment); effective-owner resolution.
- Widget: card detail + role tab render responsibilities identically post-switch;
  Tasks tab grouping incl. both buckets; contract-prefill regression.
- `flutter analyze` clean; full suite green.

## Design system

Per `PRODUCT.md`: mono for hours/percentages, tinted borderless chips ("not
costed", "derived"), `ResponsiveTable` for tabular areas, single purple CTA.
