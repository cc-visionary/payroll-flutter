# KPI Library (Phase 1) — Design Spec

> First phase of "easy KPI tracking." Date: 2026-07-18.

## Background & goal

KPIs today live as a JSON array on `role_scorecards.kpis` — each entry is
`{name, measurement, target, frequency}`, defined per role. They only ever get
an actual value at review time: `generate_employee_review` snapshots them into
`review_kpi_results`, and the manager fills `actual_value` / `result_status` /
`manager_rating` during the evaluation. There is no ongoing, per-employee KPI
tracking between reviews, and the JSON blob has no stable identity to track a
KPI over time.

The larger goal (approved direction): employees log KPI actuals each period via
a **Lark form → sync to app → manager approval**, and the Development tab shows
each of an employee's few owned KPIs trending against target. That is a
multi-subsystem effort, decomposed into phases:

1. **KPI library** (this spec) — a first-class KPI table with categories,
   unifying today's role-card KPIs.
2. Per-employee KPI assignment ("responsible for these few").
3. Ongoing log + Lark submission + manager approval.
4. Trend display on the Development tab.

Phase 1 is the foundation: it gives KPIs stable IDs (which Phases 2–4 require)
and the library/grouping to pick from. Each later phase gets its own spec.

## Phase 1 scope

**In:**
- New `kpis` (library) and `role_scorecard_kpis` (link) tables + RLS.
- A lossless migration seeding both from the existing `role_scorecards.kpis`
  JSON, keeping the JSON column in place for rollback.
- Re-pointing the shipped consumers with minimal churn.
- A KPI-library management screen (CRUD + grouping by category).
- The role-card editor's KPI section becomes a library picker.

**Out (later phases / YAGNI):**
- Per-employee KPI assignment, the Lark log, manager approval, trend UI.
- A separate `kpi_categories` table (category is a free-text field for now).
- Dropping the legacy `role_scorecards.kpis` JSON column (a later cleanup
  migration, once the new path is proven).
- Per-employee anything — Phase 1 is purely role/library level.

## Data model

Split "what the KPI is" (library) from "how it applies to a role" (link), so
the same metric can carry different targets on different roles and the migration
loses nothing.

### `kpis` — the library (the *what*)

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `company_id` | uuid not null → companies | company-scoped |
| `name` | text not null | |
| `category` | text | nullable; free-form; grouping key |
| `description` | text | nullable |
| `measurement_unit` | text | nullable (e.g. "%", "orders/day") |
| `is_active` | boolean not null default true | soft-delete |
| `created_at` / `updated_at` | timestamptz | `set_updated_at` trigger |

Unique on `(company_id, lower(name))` so a name is one library entry per company.

### `role_scorecard_kpis` — the link (the *how much / how often, for this role*)

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `role_scorecard_id` | uuid not null → role_scorecards (on delete cascade) | |
| `kpi_id` | uuid not null → kpis (on delete restrict) | restrict: can't delete a library KPI still used by a role |
| `target` | text | nullable; the role's target for this KPI |
| `frequency` | text | nullable; e.g. "Monthly" |
| `sort_order` | integer not null default 0 | preserves display order |
| `created_at` / `updated_at` | timestamptz | |

Unique on `(role_scorecard_id, kpi_id)`. Index on `kpi_id` (FK lookups + the
"which roles use this KPI" query the library screen needs). `target`/`frequency`
are stored as `text` to match the current JSON exactly (targets like "3%" are
free text today; no numeric coercion in Phase 1).

`review_kpi_results` is unchanged — it already snapshots KPI name/target/unit
per review.

## RLS

Match the existing role-card convention (`20260414000014_rls.sql`
`*_company_select` / `*_company_write`):
- **Select:** `company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN'`.
- **Write:** `auth_app_role() in ('SUPER_ADMIN','ADMIN','HR') and (company_id = auth_company_id() or SUPER_ADMIN)`.
- `role_scorecard_kpis` has no `company_id`; scope it via its parent role card
  with an `exists (select 1 from role_scorecards rs where rs.id = role_scorecard_id and (rs.company_id = auth_company_id() or SUPER_ADMIN))` predicate, so the policy subquery is a plain company check (no SECURITY DEFINER helper needed — role_scorecards' own select policy is company-read, which the exists() can see).

## Migration & seeding

A forward migration (never editing the applied ones):
1. Create both tables, enable RLS, add policies, indexes, `updated_at` triggers.
2. Seed: for each `role_scorecards` row, for each element of its `kpis` JSON
   array (with `ordinality` for `sort_order`):
   - `insert into kpis (company_id, name, category, description, measurement_unit) … on conflict (company_id, lower(name)) do nothing` then select the id — find-or-create keyed on `(company_id, lower(trim(name)))`. `measurement_unit`/`description` come from the first occurrence.
   - `insert into role_scorecard_kpis (role_scorecard_id, kpi_id, target, frequency, sort_order)` with the entry's `target`, `frequency`, and array index.
3. **Do not drop `role_scorecards.kpis`.** It stays as read-only legacy for
   rollback; a later cleanup migration removes it.

Empty/blank KPI names are skipped. Whitespace-only `target`/`frequency` become
null.

**Risk:** this runs against live role-card data on prod, and re-points
`generate_employee_review` (a SECURITY DEFINER function reviews depend on). It
must be validated against an isolated local replica first — replay the full
migration chain, seed a two-company fixture, and assert losslessness and that
review generation still snapshots identically — before `supabase db push`.

## Consumer re-pointing (minimize churn)

Keep `RoleScorecard.kpis` as `List<KpiItem>` in the Dart model; the
**repository** populates it from the join (`role_scorecard_kpis` ⨝ `kpis`,
ordered by `sort_order`, mapping to `KpiItem{name, measurement, target,
frequency}`). Then the read-only consumers change nothing:
- **Role-card PDF** (`roleCardBlocks`) — reads `card.kpis`. Unchanged.
- **Employment-contract template** — reads `card.kpis`. Unchanged.
- **Role-card detail screen** — reads `card.kpis`. Unchanged.

Two consumers genuinely change:
1. **Role-card editor** (`role_scorecard_form_screen.dart`): the KPI section
   becomes a library picker — choose an existing `kpis` row (autocomplete by
   name, grouped by category) or create one inline, then set this role's
   `target` + `frequency`. On save, upsert `role_scorecard_kpis` rows for the
   card (insert new links, update changed target/frequency, delete removed
   ones) instead of writing the JSON blob. The legacy JSON column is left
   as-is (not written) post-migration.
2. **`generate_employee_review`** (SQL, forward migration): read the role's KPIs
   from `role_scorecard_kpis ⨝ kpis` (ordered by `sort_order`) instead of
   `v_card.kpis`, snapshotting the same `kpi_name` / `measurement_unit` /
   `target_value` into `review_kpi_results`. Behaviour identical; source changed.

## KPI library management screen

New screen, HR/admin-gated (same redirect guard as `/responsibility-cards`),
sibling to Responsibility Cards in the nav:
- Lists library KPIs **grouped by category**.
- Create / edit `name`, `category`, `measurement_unit`, `description`.
- Delete is a **soft delete** (`is_active = false`) — a KPI referenced by any
  role card (FK `on delete restrict`) can't be hard-deleted, and soft-delete
  preserves it for history and for Phases 2–4.
- Category input is free text with existing categories offered as suggestions.

## Testing

- **Migration (isolated replica):** total `role_scorecard_kpis` rows == total
  KPI entries across all role cards (lossless); every `target`/`frequency`
  preserved; `kpis` row count == distinct `lower(name)` per company (dedup).
- **Repository:** `RoleScorecard.kpis` returns the joined KPIs in `sort_order`;
  existing role-card PDF / contract / detail tests pass unchanged.
- **`generate_employee_review`:** on a seeded role card + employee, snapshots
  the same rows into `review_kpi_results` as before.
- **Editor:** unit-test the payload builder that diffs picked KPIs + targets
  into `role_scorecard_kpis` insert/update/delete sets.
- `flutter analyze` clean; full suite green.

## Design system

The library screen and editor picker follow `PRODUCT.md`: single Luxium purple
CTA, 6px radius, tinted status chips, tables wrapped in `responsive_table.dart`.
No new colors or packages.
