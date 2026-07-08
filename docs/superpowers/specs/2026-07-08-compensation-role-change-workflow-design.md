# Compensation & Role Change Workflow — Design

**Date:** 2026-07-08
**Status:** Draft, pending user review
**Owner:** payroll-flutter

## Summary

Add a first-class HR action that performs a **compensation or role change** against an
employee and auto-generates the matching notice as a byproduct — the same way
confirming a separation already writes the data change, drafts documents, and spins up
a workflow. Five change types are covered: **salary increase**, **salary decrease**,
**promotion** (role + pay), **lateral transfer** (role/dept, same pay), and
**demotion** (role down and/or pay down). Each writes an effective-dated
`compensation_changes` row, appends an `employment_events` timeline entry, drafts the
notice, and opens a `SALARY_CHANGE`/`ROLE_CHANGE` workflow whose one step renders the
PDF via the existing "Generate now" affordance.

The core enabler is a new **`compensation_changes`** table that becomes the
effective-dated source of truth for an individual's pay and role. `role_scorecards`
stays as the shared role definition (mission, KPIs, responsibilities, salary band) but
its `base_salary` stops being the per-person pay truth — it becomes the role's
reference/default. This finally gives the "Coming Soon" Compensation module a real
backbone.

## Motivation

Documents already exist — `SalaryAdjustmentTemplate` even ships two modes (salary
adjustment, promotion). But nothing *performs* the change:

- Today the Role tab's "Change Role" button deep-links to the employee edit form. It
  records no history, no effective date, no reason, and produces no notice.
- Salary lives on the **shared, role-level** `role_scorecards.base_salary`, which
  payroll reads as the person's pay (`compute_service.dart:620` — "Role scorecard is
  ALWAYS the basis for actual payroll earnings"). Editing it to raise one person moves
  **everyone** on that role.
- The `workflow_instances.workflow_type` enum already includes `SALARY_CHANGE` and
  `ROLE_CHANGE`, but no seeder or kickoff ever creates them — only `SEPARATION` and
  `HIRING` are wired.

The gap the user named: *"we already have documents, but they aren't integrated into
the role scorecard."* This spec closes it by separating an individual's pay/role from
the role definition, and by driving the change → timeline → notice → workflow chain off
a single confirm action.

## Decisions locked from brainstorm

1. **Change types (all four buckets, five enum values):** salary increase, salary
   decrease, promotion, lateral transfer, demotion. One unified action that branches by
   type; each branch emits its matching notice.
2. **Salary storage → per-employee comp record.** A new `compensation_changes` table is
   the source of truth for an individual's pay; payroll resolves the current effective
   row and falls back to `role_scorecards.base_salary`. Scorecard `base_salary` becomes
   the role reference/band. (Chosen over forking a scorecard per change, and over a
   sharing-dependent hybrid.)
3. **Confirm behavior → mirror separation.** Write the change → append an
   `employment_events` row → draft the notice (`DRAFT employee_documents`) → create a
   `SALARY_CHANGE`/`ROLE_CHANGE` workflow with a `DOCUMENT_GENERATION` step. HR clicks
   "Generate now" on `/workflows/:id` to render the PDF.
4. **Effective date → future-dated, auto-applies.** HR sets an `effective_date`
   (defaults to the 1st of next month). Payroll picks the comp row whose
   `effective_date <= period` so a queued raise simply doesn't affect runs until it
   lands. Role reassignment is gated to the effective date too.
5. **No cron, no auto-gen-on-open.** Future-dated changes sit `SCHEDULED`; payroll
   always resolves correctly at compute time. The stored `employees.role_scorecard_id`
   is materialized to the new role by an "apply due changes" routine run at the **start
   of a payroll compute**, plus a manual **"Apply now"** button on the workflow for
   off-cycle needs. No background scheduler. (Consistent with the existing performance
   check-in preference: no cron, no auto-gen on open.)
6. **Notice templates → extend, don't multiply.** Extend `SalaryAdjustmentType` with
   `lateral` and `demotion`; salary increase/decrease reuse the pay-only wording. One
   block-based template, N modes — matching the pattern already in the file.

## Data model

### New table: `compensation_changes`

One row = one change event. Effective-dated source of truth for an individual's pay and
role.

```
compensation_changes
  id                uuid pk
  company_id        uuid  not null  fk companies
  employee_id       uuid  not null  fk employees
  change_type       enum  not null  -- SALARY_INCREASE | SALARY_DECREASE
                                     -- | PROMOTION | LATERAL_TRANSFER | DEMOTION
  status            enum  not null default 'SCHEDULED'  -- SCHEDULED | APPLIED | CANCELLED
  effective_date    date  not null
  prev_base_salary  numeric        -- snapshot at confirm (from comp row or scorecard)
  new_base_salary   numeric        -- equals prev for LATERAL_TRANSFER
  prev_wage_type    text           -- MONTHLY | DAILY | HOURLY
  new_wage_type     text
  prev_scorecard_id uuid  fk role_scorecards   -- null/equal when role unchanged
  new_scorecard_id  uuid  fk role_scorecards   -- new role for role changes
  reason            text
  workflow_id       uuid  fk workflow_instances
  document_id       uuid  fk employee_documents
  initiated_by_id   uuid  fk users
  applied_at        timestamptz
  created_at        timestamptz default now()
  deleted_at        timestamptz    -- soft-delete convention, matches other tables
```

- **Pay-only** (increase/decrease): `new_scorecard_id = prev_scorecard_id`.
- **Role** (promotion/lateral/demotion): `new_scorecard_id` points at the new role.
  Lateral has `new_base_salary = prev_base_salary`.
- Indexes: `(employee_id, effective_date)` for the payroll resolver; `(status)` for the
  "apply due" sweep; `(workflow_id)`.
- RLS + audit trigger mirroring the existing `employee_documents` / `role_scorecards`
  tables.

### `document_type` enum additions

Add `PROMOTION`, `LATERAL_TRANSFER`, `DEMOTION`. Pay-only notices keep the existing
`SALARY_ADJUSTMENT`. This lets each notice file cleanly in the employee's document
history and prevents a later notice from superseding an unrelated earlier one.
`kDocumentTypeByTemplateId` (in `document_type_mapping.dart`) is a per-mode lookup, so
the one template maps to the right code per mode.

### Unchanged

`role_scorecards` schema is untouched. `employees.declared_wage_override` (statutory/tax
lever) is untouched. `employees.role_scorecard_id` remains the "current role" pointer
read by the org chart / Role tab / hiring — it's just now materialized on/after the
effective date rather than at confirm for future-dated role moves.

## Payroll resolution (the one core-engine touch)

In `lib/features/payroll/runs/compute/compute_service.dart`, the wage resolution around
line 619–635 changes from reading `roleCard['base_salary']` directly to:

> For the pay period, select the latest `compensation_changes` row for this employee
> with `effective_date <= period` and `status IN (SCHEDULED, APPLIED)` and
> `deleted_at IS NULL`. Use its `new_base_salary`, `new_wage_type`, and
> `new_scorecard_id` (the scorecard supplies `work_hours_per_day`,
> `work_days_per_week`, department). **Fall back to `roleCard['base_salary']` /
> `roleCard['wage_type']`** when no such row exists.

Consequences:

- Future-dated changes **auto-apply** the moment a run's period reaches the effective
  date — no cron, no manual re-apply for the money math.
- The `declared_wage_override` statutory path is unchanged; it still layers on top as
  `StatutoryOverride` exactly as today.
- A pure resolver function `effectiveCompensation(rows, asOf)` is factored out so it is
  unit-testable in isolation (no Supabase dependency), the way `wage_calculator` and the
  seeders already are.

## Applying the change (no cron)

- **Immediate** (`effective_date == today`): on confirm, flip
  `employees.role_scorecard_id` to `new_scorecard_id` (role changes only) and set the
  row `status = APPLIED`, `applied_at = now()`.
- **Future-dated:** the row stays `SCHEDULED`. Payroll resolves pay/role correctly via
  the resolver above. The stored `employees.role_scorecard_id` (what the org chart /
  Role tab read) is materialized by an **`applyDueCompensationChanges(companyId, asOf)`**
  routine invoked at the **start of a payroll compute**: for every `SCHEDULED` row with
  `effective_date <= asOf`, repoint `role_scorecard_id` and mark `APPLIED`.
- **Manual "Apply now"** button on the workflow detail lets HR materialize a due change
  off-cycle without waiting for a payroll run.
- **Cancel:** a `SCHEDULED` row can be cancelled from the workflow (sets
  `status = CANCELLED`); the resolver and sweep both ignore cancelled rows.

## Entry point & UX

The employee profile **Role tab** (`lib/features/employees/profile/tabs/role_tab.dart`)
gets the real action, replacing the current deep-link:

- The "Current Role" section's trailing button becomes **"Adjust Compensation / Change
  Role"**, opening a dialog.
- **Dialog** (`compensation_change_dialog.dart`):
  - Change-type selector (increase / decrease / promotion / lateral / demotion). Field
    visibility follows the type:
    - Pay-only: new salary + wage type.
    - Role changes: pick the **new role scorecard** (autofills its band as a hint) +
      optional new salary (required for promotion/demotion; locked to current for
      lateral).
  - Effective date (defaults to 1st of next month), reason (free text).
  - Client-side validation: increase must be > current, decrease/demotion < current,
    lateral pay == current, promotion role must differ, effective date not in the past.
- A **"Pending changes"** strip appears on the Role tab whenever a `SCHEDULED` row
  exists — shows change type, new value, effective date, and a link to its workflow.

Out of scope for v1: the "Coming Soon" **Compensation screen** becoming the org-wide
list/history of comp changes (follow-on §Follow-ons).

## Confirm → the automatic chain (mirrors separation)

Implemented as a single handler (parallel to the separation handler in
`profile_header.dart`), executing in sequence:

1. Insert the `compensation_changes` row (`SCHEDULED`, or `APPLIED` + repoint scorecard
   when immediate).
2. Append an `employment_events` row — `COMPENSATION_CHANGE` for pay-only,
   `ROLE_CHANGE` for role moves — capturing old/new values + reason for audit; capture
   the event id.
3. Insert a **`DRAFT employee_documents`** row for the notice (correct `document_type`
   per mode), `generated_from_event_id = eventId`.
4. Seed a workflow via a new **`seedCompensationChangeWorkflow()`** in
   `lib/features/workflows/seeders.dart`: `workflow_type = SALARY_CHANGE` (pay-only) or
   `ROLE_CHANGE` (role moved), one `DOCUMENT_GENERATION` step whose `input_data` carries
   `{template_id: 'salary_adjustment', mode, employee_document_id}` and
   `generated_document_id = <draft id>`. Back-fill `compensation_changes.workflow_id`
   and `.document_id`.
5. `insertWithSteps(...)`, invalidate the workflow + employee + timeline + documents
   providers.
6. HR opens `/workflows/:id`, clicks **"Generate now"**, and the notice renders from
   settings (no stored PDF — re-renderable, matching the documents-settings-only model).

## Notice templates

Extend `SalaryAdjustmentType` in `salary_adjustment_inputs.dart` from
`{salaryAdjustment, promotion}` to add **`lateral`** and **`demotion`**. In
`salary_adjustment_template.dart`:

- Subject/body per mode:
  - `salaryAdjustment` (increase & decrease): existing pay-only wording. Decrease uses a
    neutral "your {period} will be adjusted from X to Y" (no "pleased to inform").
  - `promotion`: existing role + pay wording.
  - `lateral`: "you are being transferred from {oldPosition} to {newPosition}, effective
    …; your {period} remains unchanged."
  - `demotion`: role and/or pay reduction wording, neutral tone.
- `autofill(ctx)` sources `oldSalary`/`oldPosition`/`salaryPeriod` from the **current
  effective `compensation_changes` row if present, else the scorecard** (small tweak to
  the existing autofill, which already reads the scorecard). New role fields
  (`newPosition`, `newSalary`, `newRoleScorecardId`) come from the workflow step's
  `input_data` / the comp row.
- `validate(...)` extended for the new modes (require new role for lateral/demotion role
  moves; require decrease for demotion pay).
- Register the template modes in `kDocumentTypeByTemplateId` so each mode resolves to
  its `document_type`.

## Scope (in)

1. Migration: `compensation_changes` table (+ its `change_type`/`status` enums, indexes,
   RLS, audit trigger), `document_type` enum additions (`PROMOTION`,
   `LATERAL_TRANSFER`, `DEMOTION`), and any `employment_events.event_type` additions
   needed (`COMPENSATION_CHANGE`; `ROLE_CHANGE` reused if already present).
2. `CompensationChange` Dart model + `CompensationChangeRepository` (insert, list by
   employee, pending-by-employee, cancel, `applyDue`).
3. Pure `effectiveCompensation(rows, asOf)` resolver + wiring into `compute_service`
   wage resolution, with `applyDueCompensationChanges` called at compute start.
4. `compensation_change_dialog.dart` + Role tab action + "Pending changes" strip.
5. Confirm handler (change → event → draft doc → workflow) +
   `seedCompensationChangeWorkflow()`.
6. `SalaryAdjustmentType` `lateral`/`demotion` modes + template subject/body/validate/
   autofill updates + document-type mapping.
7. "Apply now" / "Cancel" affordances on the workflow detail for a scheduled comp change.
8. Tests (see below).

## Scope (out / follow-ons)

- Org-wide **Compensation screen** (list/history/analytics of all comp changes; replaces
  the Coming Soon stub). v1 surfaces changes only per-employee on the Role tab + in
  Workflows.
- Bulk / annual comp-review cycles with budget envelopes (a Compensation-module feature).
- Approval gating on comp changes (extra `APPROVAL` workflow step) — v1 is a single HR
  action, matching separation. Can be added as a step later.
- Back-filling historical comp for existing employees — v1 relies on the scorecard
  fallback, so untouched employees keep computing exactly as today.

## Testing

- **`effectiveCompensation` resolver** (Dart unit): empty → null (scorecard fallback);
  future-dated row skipped before its date; latest-of-multiple chosen on `effective_date`;
  cancelled rows ignored; tie-break by `created_at`.
- **`seedCompensationChangeWorkflow`** (Dart unit, pure like existing `seeders.dart`
  tests): correct `workflow_type` per pay-only vs role move; one step with correct
  `input_data`/`generated_document_id`.
- **Payroll engine** test: a `SCHEDULED` raise does not change a run whose period ends
  before `effective_date`, and does for the next period; statutory override still layers
  on top unchanged.
- **Validation** unit tests for the dialog rules (increase>current, lateral==current,
  demotion<current, promotion role differs, no past effective date).
- `flutter analyze` clean. (Repo gates on analyze, not `dart format`; match each file's
  surrounding formatting style.)

## Files (anticipated)

**New**
- `supabase/migrations/<ts>_compensation_changes.sql`
- `lib/data/models/compensation_change.dart`
- `lib/data/repositories/compensation_change_repository.dart`
- `lib/features/payroll/engine/effective_compensation.dart` (pure resolver)
- `lib/features/employees/profile/widgets/compensation_change_dialog.dart`
- `supabase/tests/…` / `test/…` as above

**Modified**
- `lib/features/payroll/runs/compute/compute_service.dart` (wage resolution + applyDue)
- `lib/features/workflows/seeders.dart` (+ `seedCompensationChangeWorkflow`, template map)
- `lib/features/employees/profile/tabs/role_tab.dart` (action + pending strip)
- `lib/features/employees/profile/widgets/profile_header.dart` (shared confirm-handler
  pattern, if extracted)
- `lib/features/documents/templates/salary_adjustment_inputs.dart` (+ 2 enum modes)
- `lib/features/documents/templates/salary_adjustment_template.dart` (modes)
- `lib/features/documents/templates/salary_adjustment_validate.dart`
- `lib/features/documents/document_type_mapping.dart`
- `lib/features/workflows/workflow_detail_screen.dart` ("Apply now"/"Cancel")

## Concurrency note

Multiple Claude sessions share this working dir. Implementation must happen on an
isolated git worktree/branch (per repo convention), and the new migration timestamp must
not collide with `20260630000002` or any other pending prod-deploy-gate migration.
