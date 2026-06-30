# Employee brand allocation (company) — design

**Date:** 2026-06-30
**Status:** Approved (verbal) — pending plan
**Area:** `lib/features/employees` (employee form), `lib/features/responsibility_cards` (role scorecard form), `lib/data` (employee + role_scorecard repos/models), Supabase migration

## Problem

Employees added via the Edit Employee form never get a **brand allocation** (`employees.hiring_entity_id`) — the column that drives the displayed company (profile header `profile_header.dart:44`), Documents company resolution, payroll grouping, and disbursement. Concretely:

- `EmployeeRepository.upsert` (`employee_repository.dart:138-200`) has **no `hiring_entity_id` parameter and never writes it**.
- The employee form has **no brand/company picker** — its only hiring-entity control is "Statutory Employer of Record," which writes a *different* column, `statutory_entity_id` (a statutory-remittance-only override; NULL = inherit from `hiring_entity_id`).
- Applicant→employee conversion **drops** the applicant's brand: `_applyApplicantSeed` (`employee_form_screen.dart:163-165`) intentionally skips `hiringEntityId` ("HR can set them after save") but no UI exists to set it.

Result: every form-created employee (manual or converted) has `hiring_entity_id = NULL`, so their company shows missing/null everywhere. Seeded employees look fine only because the seed script wrote the column directly. (The "choose a brand" picker the user remembers is on the **Applicant/Listing** screens — `_HiringEntityPicker`, "Hiring Entity (brand)" — which save correctly there.)

## Decision (confirmed with stakeholder)

Add a **required** brand-allocation control to the Edit Employee form with two modes — **derive from role scorecard** or **set manually** — and persist it. Role scorecards gain an optional company so derive-mode has a source. HR/Admin editable.

## Architecture

### 1. Schema — `role_scorecards.hiring_entity_id`
- Migration: `alter table role_scorecards add column hiring_entity_id uuid references hiring_entities(id) on delete restrict;` (nullable; no backfill).
- A scorecard MAY define a default brand; this is the source for employee derive-mode.

### 2. Role scorecard model + repo
- `RoleScorecard` gains `hiringEntityId` (`String?`), mapped from `r['hiring_entity_id']`.
- `RoleScorecardRepository.upsert` gains a `hiringEntityId` param written to the payload.

### 3. Role scorecard form (`role_scorecard_form_screen.dart`)
- Add a "Company (brand)" hiring-entity dropdown (optional) so HR can set the scorecard's default entity. Mirror the existing entity-picker pattern.

### 4. Employee form (`employee_form_screen.dart`) — new required "Company (brand)" control
Placed in the Employment section, above "Statutory Employer of Record". HR/Admin editable (`isHrOrAdmin`). State: `_brandMode` (`derive` | `manual`), `_hiringEntityId` (manual selection).
- **Mode toggle** (SegmentedButton): "From role scorecard" (default) / "Set manually".
- **Derive mode:** resolved brand = selected scorecard's `hiringEntityId`, shown read-only. If the selected scorecard has no brand, the field shows a prompt to switch to manual (cannot save in derive-mode with no resolved brand).
- **Manual mode:** explicit hiring-entity dropdown bound to `_hiringEntityId`.
- **Resolved value on save:** `effectiveHiringEntityId = (mode==derive) ? scorecard.hiringEntityId : _hiringEntityId`.
- **Validation:** save blocked (with an inline message) until `effectiveHiringEntityId != null` — enforces non-nullable at the form layer (DB column stays nullable so existing rows don't break).
- On load (edit): if `employee.hiringEntityId` matches the scorecard's entity → default to derive mode; else manual mode pre-set to `employee.hiringEntityId`.

### 5. Persistence — the core bug fix
`EmployeeRepository.upsert` gains `String? hiringEntityId` (always written, since required) → `payload['hiring_entity_id'] = hiringEntityId`. The employee form passes `effectiveHiringEntityId`.

### 6. Applicant→employee conversion
`_applyApplicantSeed` applies the seed's `hiringEntityId`: set manual mode with `_hiringEntityId = seed.hiringEntityId` (falls back to derive if the seed brand equals the scorecard's). It now persists via upsert.

### 7. Existing employees with null brand
No bulk backfill. The required control forces a valid brand on the next edit/save. (Optional future: a list of null-brand employees for cleanup.)

### 8. Display / downstream
Unchanged — profile header, Documents (`generate_screen._contextFor`), payroll grouping, and disbursement already read `hiring_entity_id`; they render correctly once it's set. "Statutory Employer of Record" is untouched; its "inherit from brand allocation" now inherits a real value.

## Testing
- Migration column present (review).
- `RoleScorecard.fromRow` maps `hiring_entity_id`; repo upsert writes it.
- `EmployeeRepository.upsert` writes `hiring_entity_id` (param present in payload).
- Employee form: derive mode resolves the scorecard's entity; manual mode uses the picker; save is blocked when neither resolves; applicant seed pre-fills the brand.
- Widget-level form tests where feasible without heavy platform mocking; otherwise unit-test the pure `effectiveHiringEntityId`/validation helper + manual smoke.

## Risks / notes
- Role scorecards without a company can't power derive-mode → the form must fall back to manual and block save until set; surfaced with a clear message.
- DB column nullable (no NOT NULL constraint) to avoid breaking existing null-brand rows; non-nullability enforced in the form only.
- `on delete restrict` on the FK prevents deleting a hiring entity still referenced by a scorecard.
