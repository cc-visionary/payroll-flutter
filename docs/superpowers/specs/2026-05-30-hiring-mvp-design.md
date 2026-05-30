# Hiring (Applicant Tracking) — MVP Design

**Date:** 2026-05-30
**Status:** Draft, pending user review
**Owner:** payroll-flutter

## Summary

Activate the `applicants` + `interviews` schema that's been in the database since 2026-04-14 with zero Dart consumers. Ship a Brixter-grade applicant tracker that funnels candidates from intake through interview to a fully converted Employee, generating the offer letter directly from the existing `EmploymentContractTemplate`. MVP is ~80% UI assembly over already-built infrastructure; no new migrations, no new templates.

## Motivation

Brixter manages every candidate in Lark threads + an ad-hoc spreadsheet, then re-types the entire candidate record into the Employee form on hire. There is no system record of who interviewed whom, who rejected whom, or what salary was offered. The system already has:

- **Full schema** in `supabase/migrations/20260414000006_applicants.sql` (applicants + interviews tables, RLS, indexes, triggers)
- **Conversion target**: `EmployeeFormScreen` ships every field a HIRED applicant needs to become an employee
- **Offer letter target**: `EmploymentContractTemplate` (already `supportsBulk: true`) renders against a `RoleScorecard` + person shape — meaning the offer letter is essentially free once we can hand it an applicant-shaped person

…all sitting dormant. This spec wires it together.

## Decisions locked from brainstorm

1. **Build order**: Hiring → Workflows → Performance (data recommendation).
2. **Workflows model (forward-affecting)**: case-management on the existing schema (rule-engine tagline gets rewritten when Workflows ships).
3. **Offer letter timing**: PDF generated BEFORE conversion at the OFFER stage. The `EmploymentContractTemplate` will be refactored to accept either an Employee or an Applicant via a thin person-shape adapter, so the candidate sees the contract before accepting.
4. **Net-new role UX**: hard gate — Brixter must create the Role Scorecard first. Rationale (per user): the offer letter renders against scorecard data (KPIs, base salary, work hours, responsibilities), so without a scorecard the offer letter can't autofill. The `applicants.custom_job_title` column stays unused in v1.

## Scope (in)

1. `Applicant` model (Dart) + `ApplicantRepository`
2. `lib/features/hiring/hiring_screen.dart` — Kanban-by-status with search/filter
3. `lib/features/hiring/applicant_form_screen.dart` — Add/Edit applicant
4. Status pipeline transitions (incl. rejection_reason + withdrawal_reason capture)
5. **Refactor**: `EmploymentContractTemplate` accepts an Applicant-shape person (via a thin adapter), so the offer letter renders directly from an applicant
6. "Generate Offer Letter" action on the applicant detail
7. "Convert to Employee" action on OFFER_ACCEPTED applicants → prefills `EmployeeFormScreen` → stamps `converted_to_employee_id` + `converted_at` on save → flips status to HIRED
8. Flip `Hiring` sidebar nav item from `comingSoon: true` to false
9. Route wiring: `/hiring` (list), `/hiring/new`, `/hiring/:id` (detail)
10. Permissions: gated behind `profile.isHrOrAdmin` (matches Employees/Compliance)

## Scope (out — v2 or later)

- `interviews` table consumption (scheduling, interviewer ratings, recommendations) — the table stays unused in v1
- Supabase storage buckets for `resume_path`, `cover_letter_path`, `offer_letter_path` — file uploads deferred; the columns stay nullable and unused
- Lark candidate-source ingestion / Lark approval routing for offers
- `custom_job_title` free-text fallback (deliberately ruled out)
- Referral bonus auto-creation from `referred_by_id`
- Hiring funnel analytics (time-in-stage, conversion, source effectiveness)
- Drag-drop Kanban (status changes via dropdown on detail screen instead)

## Data model (already shipped — verify-only)

**`applicants` table** (`supabase/migrations/20260414000006_applicants.sql`):

Identity: `id`, `company_id`, `first_name`, `middle_name`, `last_name`, `suffix`, `email`, `phone_number`, `mobile_number`
Role: `role_scorecard_id` (FK, nullable in schema but **required at app level**), `custom_job_title` (ignored), `department_id`, `hiring_entity_id`
Sourcing: `source`, `referred_by_id` (→ employees.id), `linkedin_url`, `portfolio_url`
Files: `resume_path`, `resume_file_name`, `cover_letter_path`, `offer_letter_path` (all unused v1)
Offer: `expected_salary_min`, `expected_salary_max`, `expected_start_date`
Status: `status` (enum, default NEW), `status_changed_at`, `status_changed_by_id`, `rejection_reason`, `withdrawal_reason`
Conversion: `converted_to_employee_id` (UNIQUE FK → employees.id), `converted_at`
Audit: `applied_at`, `created_by_id`, `created_at`, `updated_at`, `deleted_at`

**Enum `applicant_status`** (9 members): `NEW`, `SCREENING`, `INTERVIEW`, `ASSESSMENT`, `OFFER`, `OFFER_ACCEPTED`, `HIRED`, `REJECTED`, `WITHDRAWN`

## Architecture

### 1. Model — `lib/data/models/applicant.dart`
Mirrors `employee.dart` conventions: immutable class, `fromRow(Map)`, `toJson()`, `copyWith({...})`. Decimal for the salary range (consistent with employee `declaredWageOverride`). DateTimes for dates. Derived getter `fullName = [first, middle, last, suffix].whereNonEmpty.join(' ')`.

### 2. Repository — `lib/data/repositories/applicant_repository.dart`
Mirrors `employee_repository.dart`:

- `applicantListProvider({ApplicantListQuery})` — company-scoped, status filter, search (name/email), role_scorecard filter, hiring_entity filter, sort by applied_at desc
- `applicantByIdProvider(String id)`
- `applicantsCountByStatusProvider` — for Kanban column counts
- `upsert({...})` — insert-or-update. On status change: stamps `status_changed_at = now()` + `status_changed_by_id = currentUserId`. If new status is REJECTED, `rejection_reason` is required (validated at form layer). If WITHDRAWN, `withdrawal_reason` required.
- `markConverted({applicantId, employeeId})` — atomic: sets `converted_to_employee_id`, `converted_at = now()`, `status = HIRED`. Called from the convert flow after the new Employee row commits.

RLS already gates writes to HR/Admin (per the shipped policies); no policy changes needed.

### 3. Screen — `lib/features/hiring/hiring_screen.dart`
Kanban-by-status (Brixter-friendly visual pipeline). Columns left-to-right: NEW, SCREENING, INTERVIEW, ASSESSMENT, OFFER, OFFER_ACCEPTED, HIRED. Two "tray" sections below or right-side: REJECTED, WITHDRAWN.

Each card shows: full name, role (`role_scorecard.job_title`), hiring entity (badge), source, applied_at relative date.

Top bar:
- Search field (name / email)
- Role filter (multi-select from `roleScorecardListProvider`)
- Hiring entity filter
- "+ New Applicant" FilledButton.icon (right-aligned)

Click a card → push `/hiring/:id` detail screen.

No drag-drop in v1 — status changes happen via dropdown on the detail screen.

Mobile/narrow: degrade Kanban to a status-filtered list (use existing `isMobile(context)` from `lib/app/breakpoints.dart` — same pattern as `payroll_runs_screen.dart`).

### 4. Add/Edit form — `lib/features/hiring/applicant_form_screen.dart`
Mirrors `employee_form_screen.dart` section structure:

- **Identity**: first, middle, last, suffix, email, phone, mobile
- **Role** (REQUIRED block):
  - Role Scorecard picker (`roleScorecardListProvider`). Empty-state CTA "Create a Role Scorecard" → links to existing `/role-scorecards/new`. Form blocks submission while this is null.
  - Hiring Entity picker
  - Department (optional)
- **Sourcing**: source (free text or chip from common values: Lark Careers, Referral, LinkedIn, Walk-in, Other), referred_by employee picker (when source = Referral), linkedin_url, portfolio_url
- **Offer**: expected_salary_min, expected_salary_max, expected_start_date
- **Status**: NEW for new applicants (initial); edit form shows current status as read-only here — status changes happen on the detail screen, not in the edit form, to enforce the status-transition rules
- **Notes**: text area

Save: calls `upsert(...)`, on success routes to `/hiring/:id` detail.

### 5. Detail screen — `lib/features/hiring/applicant_detail_screen.dart`
Header: name, status chip, current role + hiring entity, applied_at.

Tabs (mirror `employee_profile_screen.dart` tab pattern):

- **Overview** — read-only field summary + status change history (timeline of `status_changed_at`/`status_changed_by_id` reads, sourced from a future `audit_logs` query if available; for v1 just show current state). Edit button.
- **Actions** (always-visible row):
  - Status dropdown (with transition validation, see below)
  - Generate Offer Letter (enabled only when status ≥ OFFER)
  - Convert to Employee (enabled only when status = OFFER_ACCEPTED)

### 6. Status pipeline transitions
Enforce in repository + UI:

| From | Allowed next | Notes |
|---|---|---|
| NEW | SCREENING, REJECTED, WITHDRAWN | |
| SCREENING | INTERVIEW, REJECTED, WITHDRAWN | |
| INTERVIEW | ASSESSMENT, OFFER, REJECTED, WITHDRAWN | skip ASSESSMENT if no test needed |
| ASSESSMENT | OFFER, REJECTED, WITHDRAWN | |
| OFFER | OFFER_ACCEPTED, REJECTED, WITHDRAWN | |
| OFFER_ACCEPTED | HIRED (via Convert), WITHDRAWN | HIRED only set automatically by markConverted |
| HIRED | (terminal) | |
| REJECTED | NEW (re-engage) | |
| WITHDRAWN | NEW (re-engage) | |

Rejection dialog when moving to REJECTED: required `rejection_reason` text field, "Reject" / "Cancel" buttons. Same pattern for WITHDRAWN with `withdrawal_reason`.

### 7. Offer letter — refactor `EmploymentContractTemplate`
**Approach**: introduce a thin person-shape adapter that both Employee and Applicant can produce, rather than parameterizing the template on two distinct ID types. Smallest, least-invasive refactor.

New helper file: `lib/features/documents/templates/contract_person.dart`
```dart
class ContractPerson {
  final String fullName;
  final String? gender;
  final String homeAddress;
  // …only what the template actually reads…
  final RoleScorecard? scorecard;
  final HiringEntity? entity;

  static ContractPerson fromEmployee(Employee e, HiringEntity? co, RoleScorecard? sc) { ... }
  static ContractPerson fromApplicant(Applicant a, HiringEntity? co, RoleScorecard? sc) { ... }
}
```

Refactor `EmploymentContractInputs.employeeId` to also accept `applicantId` (one nullable each, exactly one populated). Refactor `EmploymentContractTemplate.autofill(ctx)` to branch on which is set, build a `ContractPerson`, then continue with the existing block-tree generation against that shape.

**Offer letter trigger**: `applicant_detail_screen.dart` "Generate Offer Letter" button calls a new `lib/features/hiring/offer_letter_action.dart` that:
1. Builds `EmploymentContractInputs(applicantId: ...)` via autofill against the applicant
2. Calls existing `buildDocumentPdf` directly (skip the generate screen UI — we have all the data)
3. Opens a preview screen with Print / Save / Email actions (reuse the `PdfPreviewScaffold` from generate_screen.dart's last step)
4. Optionally stamps the rendered PDF path into `applicants.offer_letter_path` — DEFERRED to v2 (storage buckets out of scope)

**Side benefit**: this refactor also unblocks generating the Employment Contract for any future "render contract from a candidate-like shape" need (e.g. NDA-at-offer-time, contractor agreement templates).

### 8. Convert to Employee — `lib/features/hiring/convert_action.dart`
Triggered on OFFER_ACCEPTED applicants. Opens existing `EmployeeFormScreen` in "new employee" mode with these fields pre-filled from the applicant:

- name parts (first / middle / last / suffix)
- email, phone_number, mobile_number
- role_scorecard_id
- hiring_entity_id, department_id
- referred_by_id
- `hireDate = expected_start_date ?? today`
- `declaredWageOverride` left empty (HR fills final on conversion)

On save (existing flow returns the new employeeId): call `applicantRepository.markConverted(applicantId, employeeId)`. Snackbar: "Hired — converted to {Employee#}". Navigate back to `/hiring/:id` showing the now-HIRED status with a "View employee" link to `/employees/:id`.

### 9. Nav + routing

- `lib/app/shell.dart` line ~96 (Hiring nav item): change `comingSoon: true` → false; keep `_always` predicate; remains under People group
- `lib/app/router.dart`: add routes `/hiring`, `/hiring/new`, `/hiring/:id`; remove the existing placeholder
- Update placeholder file `lib/features/hiring/hiring_screen.dart` (currently 1-file stub from `ComingSoonScreen`) to the real screen

## Data flow recap

1. Brixter clicks "+ New Applicant" → fills form → blocked until a Role Scorecard is chosen → save → status = NEW
2. As candidate progresses, Brixter changes status on detail screen — each transition stamps `status_changed_at` + `status_changed_by_id`
3. At OFFER stage: Brixter clicks "Generate Offer Letter" → PDF renders against the Applicant + their RoleScorecard + HiringEntity → preview screen → Print/Save/Email
4. Candidate accepts: Brixter sets status to OFFER_ACCEPTED on the detail screen
5. Brixter clicks "Convert to Employee" → `EmployeeFormScreen` opens prefilled → on save: `markConverted` writes converted_to_employee_id + converted_at, flips status to HIRED
6. Applicant card moves to the HIRED column with a "View employee" link

## Permissions

Same gate as Employees/Compliance: `profile.isHrOrAdmin`. RLS at the table layer (already shipped) is the security backstop; UI gate avoids showing the nav item / screens to non-HR users. Audit trail rides on the existing `audit_logs` triggers (already capturing INSERT/UPDATE on applicants).

## Testing

- **Model**: `fromRow` round-trip — including null middle_name, null suffix, null role_scorecard, full enum coverage
- **Repository**: list with each filter combo; upsert (create + update); status transition validation rejects illegal moves; markConverted is atomic
- **Status pipeline**: unit test of the transition matrix (allowed/disallowed)
- **Form**: validation — required fields including role_scorecard_id hard gate; rejection/withdrawal reason required when status moves to terminal-reject states
- **Offer letter render**: `EmploymentContractTemplate` invoked from an Applicant produces a `%PDF` with the candidate's name + the scorecard's job_title + the entity's signatory present. Add to `test/features/documents/templates/` alongside the existing employment_contract tests.
- **Smoke**: Kanban renders 0/1/many cards per column without overflow; mobile degrades to filtered list

## Phases (for the implementation plan that follows)

1. **Schema verification + Model + Repository + tests** (sizing: small — schema is fixed, model is well-precedented by Employee)
2. **Hiring Kanban screen (read-only)** + nav unhide + permission gate (sizing: small — list-over-existing-schema like audit_log_screen)
3. **Applicant form (add/edit)** + role-scorecard hard gate + transition-aware status display (sizing: medium — mirrors employee_form_screen patterns)
4. **Detail screen + status transitions + rejection/withdrawal dialogs** (sizing: small)
5. **EmploymentContractTemplate refactor** (ContractPerson adapter) + offer letter action + render preview (sizing: medium — touches a shipped template; tests must stay green)
6. **Convert-to-Employee flow** (prefill EmployeeFormScreen + markConverted) (sizing: small — wiring on top of an existing form)

Total: estimated 2 weeks of session work.

## Open questions (resolve at plan time, not now)

1. **Audit trail surfacing**: status_changed history — do we read from `audit_logs` (already populated by triggers) or from a separate `applicant_status_history` table? Verify which is cheaper to query in plan-time. Default: lazy-read from `audit_logs` filtered on entity_type='applicant'.
2. **Department picker**: `applicants.department_id` exists in schema. The employees feature has departments but it's unclear how routinely they're populated. Confirm in plan-time whether the form shows this field at all in v1 or hides it.
3. **EmploymentContractTemplate test impact**: when the ContractPerson refactor lands, the existing `employment_contract_*_test.dart` files need to be re-targeted (they build against employeeId; will need to verify they still pass against the new shape). Plan must include a migration of those tests, not a deletion.

## Risks

- **EmploymentContractTemplate refactor blast radius**: this is a production-shipped template with golden tests. The ContractPerson adapter approach minimizes blast radius but the refactor must keep all existing tests green.
- **Hard gate UX friction**: forcing scorecard creation before applicant entry will frustrate Brixter for net-new roles. Mitigation: the "Create a Role Scorecard" CTA on the form's role block jumps directly to the scorecard form and returns on save (use GoRouter `pop` with return value).
- **Status transition discipline**: without enforcement, the Kanban turns into a free-for-all. Both repository and UI must validate transitions.
- **`interviews` table left unused**: someone may try to write to it ad-hoc. Add a doc comment in `applicant_repository.dart` noting it's deliberately deferred and the v2 spec should consume it.

## What this unblocks (downstream)

- **Workflows MVP (Weeks 3-4)**: `OFFER_ACCEPTED → HIRING workflow_instance` is the natural Workflow kickoff point. The applicant → employee conversion becomes a tracked `workflow_steps` chain (offer letter → background check → IT setup → equipment → day-1 onboarding). Hiring landing first means Workflows has real data to track.
- **Performance MVP (Weeks 5-6)**: applicants who get HIRED via this flow already have a `role_scorecard_id`. Performance reviews then auto-prefill KPIs from that scorecard — the "review the role they were hired into" loop closes naturally.
- **Onboarding stub** (later): becomes a filtered view over `workflow_instances` of type HIRING — no extra schema needed.
