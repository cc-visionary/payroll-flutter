# Workflows MVP — Case-Management for HR Processes

**Date:** 2026-05-31
**Status:** Draft, pending user review
**Owner:** payroll-flutter

## Summary

Activate the dormant `workflow_instances` + `workflow_steps` schema (shipped 2026-04-14) as a **case-management** surface for HR processes — not a generic rule engine. Each `workflow_instance` represents one HR process per employee (a SEPARATION case, a HIRING case, a DISCIPLINARY case, etc.); each `workflow_step` is a discrete action within that case (a document to generate, an approval to obtain, a status to update). The MVP captures workflow data on existing trigger points (separation confirmation, applicant OFFER_ACCEPTED) and gives Brixter a `/workflows` inbox to see "what's mid-flight" plus a "Generate now" button per DOCUMENT_GENERATION step to actually render the PDF.

## Motivation

Today HR processes live in scattered Lark threads and Brixter's personal spreadsheet:

- **Separations**: when an employee is separated, the system creates DRAFT `employee_documents` placeholders (Quitclaim/COE/NTE) but never renders the PDFs. Brixter has to manually navigate to `/documents`, re-pick the employee, and generate each one. Every leaver.
- **Hires**: after `OFFER_ACCEPTED → Convert-to-Employee` (just shipped), there's no system record of the post-conversion onboarding work (IT setup, equipment, day-1 orientation). Brixter tracks it manually.
- **No central inbox**: HR has no single screen showing "what multi-step processes are currently in-flight, what's overdue, what's done."

The schema is already in place. This MVP wires it to the existing trigger points and surfaces it in the UI.

## Decisions locked from brainstorm

1. **Interpretation**: case-management (use shipped schema). The "visual rule builder" tagline on the current ComingSoonScreen gets rewritten.
2. **Auto-fire scope**: **data capture + "Generate now" button**. No edge-function PDF rendering, no auto-fire on event. When a trigger event happens, the system inserts a `workflow_instance` + N `workflow_steps`. Each DOCUMENT_GENERATION step has a "Generate now" button on the workflow detail screen that calls the existing template renderer. Cleaner ship; no Deno PDF runtime needed.
3. **Cross-feature handoff in MVP**: yes — when an applicant moves to `OFFER_ACCEPTED`, also insert a HIRING `workflow_instance` with onboarding steps. Connects Hiring → Workflows visibly.
4. **Onboarding/Offboarding stub consolidation**: yes — remove those nav items; `/workflows` shows all `workflow_instances` with filter chips per `workflow_type` (HIRING, SEPARATION, REGULARIZATION, etc.).

## Scope (in)

1. `WorkflowInstance` + `WorkflowStep` Dart models mirroring the shipped tables.
2. `WorkflowRepository` (list / byId / insertWithSteps / updateStepStatus / completeInstance / cancelInstance).
3. `/workflows` list screen — filterable by `workflow_type` + `status`, sorted newest-first.
4. `/workflows/:id` detail screen — step-by-step timeline; each step shows status, assignee, completed-at; DOCUMENT_GENERATION steps have a "Generate now" button.
5. **Separation kickoff** — modify `profile_header.dart`'s separation confirmation handler (around line 332) to ALSO insert a SEPARATION `workflow_instance` + N DOCUMENT_GENERATION steps (one per selected document). The existing `employee_documents` DRAFT placeholders stay (linked to the steps via `workflow_steps.generated_document_id` once rendered).
6. **Hiring kickoff** — modify `convert_action.dart`'s `markConverted` flow (or `applicantRepository.markConverted`) so that on HIRED, the system also inserts a HIRING `workflow_instance` with a default set of onboarding steps (IT setup, equipment, day-1, 30-day check-in — all `STATUS_UPDATE`-type steps that HR manually completes).
7. **"Generate now" action** — on a DOCUMENT_GENERATION step's detail, button calls the existing template renderer (Quitclaim / COE / NTE), saves the PDF bytes to `employee_documents.file_data` (or wherever the existing pipeline persists them), updates the step's `output_data` with the document id, sets `generated_document_id`, and flips the step to COMPLETED.
8. **Manual step completion** — STATUS_UPDATE / DATA_ENTRY / REVIEW step types get a "Mark complete" button with an optional remarks field.
9. **Workflow lifecycle** — when all steps are COMPLETED (or SKIPPED), auto-complete the `workflow_instance` (`status = COMPLETED`, `completed_at = now()`). Manual "Cancel" button on the detail screen with a reason field.
10. **Nav cleanup** — remove `/onboarding` and `/offboarding` nav items + their stub screens. Update `lib/app/shell.dart`. Unhide `/workflows` (currently `comingSoon: true`).

## Scope (out — v2 or later)

- **Generic rule engine** (when X then Y triggers/conditions/actions) — the placeholder tagline gets rewritten away from this.
- **APPROVAL step type via Lark webhook** — the schema has `step_type = 'APPROVAL'` but v1 doesn't pause-and-wait on Lark. Approvals stay manual ("Mark complete after Lark approves").
- **Visual drag-drop step builder** per workflow_type.
- **SLA tracking + overdue escalation** — no due dates on steps in v1.
- **Auto-fire-on-event via edge function** — kickoff happens client-side in the existing event handlers.
- **Other workflow types** — REGULARIZATION, SALARY_CHANGE, ROLE_CHANGE, DISCIPLINARY, REPAYMENT_AGREEMENT are out of scope (the schema enum includes them; only SEPARATION + HIRING are wired in v1).

## Integration principle (carry-over from Hiring spec)

Same hard rule: **reuse, do not duplicate.**

- `workflow_instances.employee_id` is an FK — the workflow row never copies employee data.
- `workflow_steps.generated_document_id` points at `employee_documents` — the workflow tracks WHICH document was generated, not a copy of its bytes.
- DOCUMENT_GENERATION steps' `input_data` carries only the template id + minimal kickoff context (e.g. `{"template_id": "quitclaim", "document_id": "<existing employee_documents row id>"}`). Autofill resolves the rest from the same employee/scorecard/entity FKs the documents feature uses today.
- HIRING workflow_instances reference the converted Employee via `employee_id`. No reference to the applicant — that's already in `employees.converted_from_applicant_id` (… wait, the field is `applicants.converted_to_employee_id` from Hiring MVP — verify at plan time which direction the FK lives; the workflow only needs `employee_id`).

## Data model (already shipped — verify-only)

**`workflow_instances`** (`supabase/migrations/20260414000013_workflows.sql`):
- `id`, `company_id`, `employee_id` (FK → employees), `workflow_type` (enum), `status` (enum, default DRAFT)
- `title`, `context` (jsonb), `result` (jsonb)
- `initiated_by_id` (FK → users), `completed_at`, `cancelled_at`, `cancel_reason`
- audit: `created_at`, `updated_at`

**`workflow_steps`**:
- `id`, `workflow_instance_id` (FK with `on delete cascade`)
- `step_index` (int, unique per instance), `step_type` (enum), `name`, `description`
- `status` (enum, default PENDING)
- `assigned_to_id` (FK → users, nullable)
- `input_data` / `output_data` (jsonb)
- `completed_by_id`, `completed_at`, `remarks`
- `generated_document_id` (FK → employee_documents, nullable)

**Enums**:
- `workflow_type`: HIRING, REGULARIZATION, SALARY_CHANGE, ROLE_CHANGE, DISCIPLINARY, SEPARATION, REPAYMENT_AGREEMENT
- `workflow_status`: DRAFT, IN_PROGRESS, COMPLETED, CANCELLED
- `workflow_step_type`: DATA_ENTRY, APPROVAL, DOCUMENT_GENERATION, STATUS_UPDATE, REVIEW
- `workflow_step_status`: PENDING, IN_PROGRESS, COMPLETED, SKIPPED, REJECTED

## Architecture

### Models — `lib/data/models/workflow_instance.dart` + `lib/data/models/workflow_step.dart`
Standard `fromRow` factories, immutable, mirror the columns. No `copyWith` needed yet.

### Repository — `lib/data/repositories/workflow_repository.dart`
Mirrors `applicant_repository.dart`:
- `WorkflowListQuery({statuses, types, employeeId, ...})` value class with `==`/`hashCode`.
- `list(WorkflowListQuery)` → `Future<List<WorkflowInstance>>`, ordered by `created_at desc`.
- `byId(String id)` → `Future<WorkflowInstance?>`, single instance.
- `stepsForInstance(String id)` → `Future<List<WorkflowStep>>`, ordered by `step_index`.
- `insertWithSteps({...})` — atomic-ish: insert instance, get id, insert all steps with the right `step_index` + `workflow_instance_id`. Returns the new instance id. Used by the SEPARATION and HIRING kickoff handlers.
- `markStepInProgress(stepId)`, `markStepCompleted({stepId, completedById, outputData?, generatedDocumentId?, remarks?})`, `markStepSkipped({stepId, completedById, remarks})`.
- `maybeCompleteInstance(instanceId)` — checks all steps; if all are COMPLETED or SKIPPED, flips instance status to COMPLETED + stamps `completed_at`. Called after every step status change.
- `cancelInstance({instanceId, cancelReason, cancelledById})` — sets `status = CANCELLED`, `cancelled_at = now()`.

Providers: `workflowListProvider(WorkflowListQuery)`, `workflowByIdProvider(String)`, `workflowStepsProvider(String)`.

### Workflow seeding — `lib/features/workflows/seeders.dart`
Pure functions that return a `(WorkflowInstanceInput, List<WorkflowStepInput>)` ready for `insertWithSteps`. One seeder per supported workflow type:

- `seedSeparationWorkflow({employee, documentTypes, eventId, ...})` → SEPARATION instance + one DOCUMENT_GENERATION step per `documentTypes` entry (Quitclaim, COE, NTE — matching whatever the separation dialog selected). Each step's `input_data` is `{"template_id": "<id>", "employee_document_id": "<id from the DRAFT placeholder>"}`.
- `seedHiringWorkflow({employee, applicantId, ...})` → HIRING instance + 4 default STATUS_UPDATE steps: "IT setup", "Equipment provisioning", "Day-1 orientation", "30-day check-in". HR can manually mark each complete.

These seeders are PURE — they don't write to the DB. The kickoff handlers in `profile_header.dart` and `convert_action.dart` call the seeder then call `workflowRepository.insertWithSteps(...)`.

### List screen — `lib/features/workflows/workflows_screen.dart`
Replace the existing ComingSoonScreen stub. ConsumerStatefulWidget:

- Permission gate: `profile.isHrOrAdmin` (same as Hiring).
- AppBar: title "Workflows". No "New workflow" button — workflows are only created via kickoff events (separation confirmation, applicant conversion) in v1. Future v2 may add a manual-create button.
- Top filter bar (`Wrap` of chips/dropdowns):
  - Workflow type — multi-select from the 7 enum values (default: all).
  - Status — multi-select from DRAFT/IN_PROGRESS/COMPLETED/CANCELLED (default: not CANCELLED).
  - Employee — autocomplete from `employeeListProvider`.
- Body: a `ResponsiveTable` (the project's existing 1100-px-wrap helper) showing:
  - Title (link)
  - Employee name (resolved)
  - Type (chip)
  - Status (chip)
  - Steps: "X/Y complete"
  - Initiated by (user email)
  - Created at (relative date)
- Click row → push `/workflows/:id`.

### Detail screen — `lib/features/workflows/workflow_detail_screen.dart`
- Header: title, employee name, workflow_type chip, status chip, initiated_by, created_at.
- Below header: progress bar / "X of Y steps complete".
- Steps timeline (vertical, like the existing `timeline_tab.dart`):
  - Each step is a card:
    - Step index circle (e.g. "1", "2") + step_type icon (file for DOCUMENT_GENERATION, checkmark for STATUS_UPDATE, etc.)
    - Step name + description
    - Status chip (PENDING / IN_PROGRESS / COMPLETED / SKIPPED / REJECTED)
    - Action button (varies by step_type and status):
      - DOCUMENT_GENERATION + PENDING/IN_PROGRESS → **"Generate now"** button. Reads `input_data.template_id`, opens the existing `/documents/generate/<template>` flow with the employee pre-selected (or renders directly via the existing render pipeline + saves to the linked `employee_documents` row), then on success calls `markStepCompleted` with `generatedDocumentId`.
      - STATUS_UPDATE / DATA_ENTRY / REVIEW + PENDING/IN_PROGRESS → **"Mark complete"** button (opens a small dialog with an optional remarks field).
      - APPROVAL + PENDING/IN_PROGRESS → **"Mark approved"** / **"Mark rejected"** buttons (manual; Lark integration deferred to v2).
      - COMPLETED → shows completed_at + remarks + (for DOCUMENT_GENERATION) a "View document" link → `/documents` filtered by the doc id.
    - "Skip" overflow action — calls `markStepSkipped`.
- Bottom of detail: **"Cancel workflow"** button (opens reason dialog → `cancelInstance`).
- Auto-complete: after any step status change, the screen calls `maybeCompleteInstance`; if instance flipped to COMPLETED, show a small green banner at the top.

### "Generate now" wiring — the trickiest piece
For a DOCUMENT_GENERATION step on the Quitclaim/COE/NTE templates:

1. Step's `input_data` is `{"template_id": "quitclaim", "employee_document_id": "<draft row id>"}`.
2. Click "Generate now" → resolve the template via `findTemplateById(templateId)` from the existing `template_registry.dart`.
3. Run the template's autofill against the employee + their hiring entity (existing providers).
4. Build the PDF via existing `buildDocumentPdf(blocks, theme)`.
5. UPDATE the linked `employee_documents` row with the PDF bytes (existing column `file_data` or whatever the documents feature uses). Flip its status from DRAFT to ISSUED.
6. Call `markStepCompleted(stepId, generatedDocumentId: <that doc row id>, output_data: {...})`.
7. Call `maybeCompleteInstance`.

The user wanted to AVOID a separate edge-function PDF runtime. Client-side render-on-click is exactly what this is — runs in the desktop Flutter app on Brixter's session. No Deno.

**Adaptation point**: if the existing documents feature does NOT persist PDF bytes to `employee_documents.file_data` (e.g. it only renders ephemerally), the "Generate now" action will need to either (a) start persisting them, or (b) just open the existing `/documents/generate/<template>` flow with the employee pre-selected and let HR click the existing "Save" button (which is already wired up). Plan-time: check what `generate_screen.dart` does on save.

### Separation kickoff modification
In `lib/features/employees/profile/widgets/profile_header.dart` around line 330-345, AFTER the existing `await client.from('employee_documents').insert(docs);`:

```dart
if (result.documents.isNotEmpty) {
  // Insert workflow_instance + steps for HR to track this separation case.
  // Reads back the inserted document ids so each DOCUMENT_GENERATION step
  // can link to its placeholder row via input_data.
  final insertedDocs = await client
      .from('employee_documents')
      .select('id, document_type')
      .eq('generated_from_event_id', eventId);
  final docIdByType = {
    for (final d in (insertedDocs as List))
      (d as Map)['document_type'] as String: d['id'] as String,
  };
  await ref.read(workflowRepositoryProvider).insertWithSteps(
        instance: seedSeparationWorkflow(
          employee: employee,
          documentTypes: result.documents,
          eventId: eventId,
          docIdByType: docIdByType,
          initiatedById: actorId!,
        ),
      );
}
```

(Adjust to match the actual `insert` return shape — the SDK call above may need `.select()` chaining.)

### Hiring kickoff modification
In `lib/features/hiring/convert_action.dart`'s `onCreatedFromApplicant` callback, AFTER the successful `markConverted` call:

```dart
await ref.read(workflowRepositoryProvider).insertWithSteps(
      instance: seedHiringWorkflow(
        employee: <the new employee>,
        applicantId: a.id,
        initiatedById: <current user id>,
      ),
    );
```

This needs the new Employee row (id at minimum). The existing convert flow has the new `employeeId` from `onCreatedFromApplicant` — we have it.

### Routes — `lib/app/router.dart`
- Keep `/workflows` (currently points at the ComingSoon stub) — repoint at the real `WorkflowsScreen`.
- Add `/workflows/:id` → `WorkflowDetailScreen(instanceId: id)`.
- **Delete** `/onboarding` and `/offboarding` routes + their stub imports.

### Nav — `lib/app/shell.dart`
- Hiring nav item: already unhidden in Hiring MVP.
- Workflows nav item: remove `comingSoon: true` flag.
- Onboarding nav item: **DELETE** (the line and its stub screen file).
- Offboarding nav item: **DELETE** (same).
- Update the tagline/description on the `ComingSoonScreen` if Workflows ever falls back to it (e.g. for non-HR users).

### Permissions
Same gate as Hiring/Compliance: `profile.isHrOrAdmin`. RLS already configured on the workflow tables.

## Step-type-specific UX detail

| step_type | Trigger button | What it does |
|---|---|---|
| DOCUMENT_GENERATION | "Generate now" | Renders the PDF via existing template, saves to linked `employee_documents` row, marks step COMPLETED with `generated_document_id` |
| STATUS_UPDATE | "Mark complete" | Marks step COMPLETED with optional remarks. Used for "IT setup done", "Day-1 orientation done", etc. |
| DATA_ENTRY | "Mark complete" + (future v2: a JSON form for `output_data`) | Currently same as STATUS_UPDATE; v2 may add per-step form rendering |
| REVIEW | "Mark complete" with optional remarks | Same as STATUS_UPDATE; semantic differentiation only |
| APPROVAL | "Approve" / "Reject" buttons | Sets step COMPLETED (approve) or REJECTED (reject) with remarks. Lark routing deferred to v2 |

All step types: "Skip" overflow option that sets status SKIPPED.

## Workflow type seeds (initial templates baked into seeders.dart)

### SEPARATION
Default steps (created by `seedSeparationWorkflow`):
- Step 1: DOCUMENT_GENERATION — Quitclaim (only if `result.documents` contains it)
- Step 2: DOCUMENT_GENERATION — COE (only if included)
- Step 3: DOCUMENT_GENERATION — NTE (only if included)
- (Future: STATUS_UPDATE "Final pay disbursed", STATUS_UPDATE "Equipment returned", STATUS_UPDATE "Access revoked")

Title: `"Separation — {employee.fullName}"`.

### HIRING
Default steps (created by `seedHiringWorkflow`):
- Step 1: STATUS_UPDATE — "IT account & email setup"
- Step 2: STATUS_UPDATE — "Equipment provisioning (laptop, peripherals)"
- Step 3: STATUS_UPDATE — "Day-1 orientation completed"
- Step 4: STATUS_UPDATE — "30-day check-in completed"

Title: `"Hiring — {employee.fullName}"`. Context: `{"applicant_id": "<id>"}`.

## Data flow recap

1. **Separation**: Brixter confirms separation → existing employee row updated + employment_events row + DRAFT employee_documents rows. NEW: also insert a SEPARATION `workflow_instance` + DOCUMENT_GENERATION steps linked to the DRAFTs.
2. **Hiring**: Applicant converts to Employee → existing `markConverted` stamps the conversion. NEW: also insert a HIRING `workflow_instance` + onboarding STATUS_UPDATE steps.
3. **Brixter visits `/workflows`** → sees both SEPARATION and HIRING cases in-flight, filterable by type/status/employee.
4. **Clicks a SEPARATION row** → sees 3 DOCUMENT_GENERATION steps. Clicks "Generate now" on Step 1 → Quitclaim PDF renders, saves to the linked `employee_documents` row, step flips to COMPLETED. Repeats for Steps 2-3. Workflow auto-completes when all steps done.
5. **Clicks a HIRING row** → sees 4 STATUS_UPDATE steps. Marks each "complete" as IT/equipment/orientation gets done. Workflow auto-completes.

## Testing

- **Models**: `WorkflowInstance.fromRow` + `WorkflowStep.fromRow` round-trip tests.
- **Repository**: focused tests for `insertWithSteps` (creates instance + N steps with correct step_index), `markStepCompleted` (sets fields, doesn't touch other steps), `maybeCompleteInstance` (no-op if any step is still PENDING; flips when last step completes).
- **Seeders**: `seedSeparationWorkflow` with various `documentTypes` lists produces the right step count + titles. `seedHiringWorkflow` produces 4 default steps.
- **List screen**: smoke render with mocked rows; filter chips toggle correctly.
- **Detail screen**: step-type rendering smoke (each of the 5 step types renders the right action button).
- **"Generate now"** integration test: not feasible without real Supabase fixtures; covered by manual smoke after merge.

## Phases (for the implementation plan that follows)

1. **Models + Repository** — small, mechanical. WorkflowInstance + WorkflowStep + WorkflowRepository + tests.
2. **Seeders** — `seedSeparationWorkflow` + `seedHiringWorkflow` (pure functions). Tests for step counts/titles.
3. **Workflows list screen** — replace ComingSoon stub, build the filterable table, nav unhide, route wiring.
4. **Workflow detail screen** — header, steps timeline, action buttons per step type.
5. **"Generate now" action** — wire the Quitclaim/COE/NTE template renderer to the step, persist the doc, mark step complete.
6. **Step lifecycle actions** — Mark complete dialog, Skip, Cancel workflow.
7. **Separation kickoff hook** — modify `profile_header.dart` to insert workflow after the existing doc placeholders.
8. **Hiring kickoff hook** — modify `convert_action.dart`'s `onCreatedFromApplicant` to insert the HIRING workflow.
9. **Onboarding/Offboarding stub cleanup** — delete the two screens + nav items + route entries.
10. **Final green-bar verification** — full test suite, manual smoke of both kickoff paths.

Estimated 2-3 sessions of subagent-driven work.

## Open questions (resolve at plan time, not now)

1. **Persistent PDF storage**: does the current documents feature persist PDF bytes to `employee_documents.file_data` on a "Save" action? If yes, "Generate now" can write straight to it. If no (current behavior may be ephemeral preview-only), "Generate now" needs to add persistence — verify at plan time, may bump scope by 1 task.
2. **`workflows_screen.dart`'s "no new workflow" UX**: should the screen mention "Workflows are created automatically when you confirm a separation or convert an applicant" as an inline hint, so HR doesn't wonder where the create button is? Likely yes — small banner above the table.
3. **Auto-cancel on employee deletion**: if an employee row is soft-deleted (separation with `archive: true`), should the workflow_instance auto-cancel? The schema has `on delete cascade` on workflow_steps but not on workflow_instances. v1: leave it alone (instances persist; the audit trail is the point). v2: revisit.

## Risks

- **`employee_documents` persistence assumption**: the "Generate now" UX hinges on whether the document feature already saves PDF bytes. If not, the scope expands.
- **Concurrent step completion**: two HR users on the same workflow could complete different steps simultaneously. `maybeCompleteInstance` re-reads all step statuses before flipping the instance, so the race is benign — last writer wins on instance status, but both step COMPLETIONs persist. Acceptable for MVP.
- **Step ordering**: `step_index` is locked at insert time. Reordering steps post-creation is not supported (no "drag steps" UI in v1).
- **`workflow_steps.assigned_to_id`**: v1 doesn't populate this (no per-step assignment UI). Steps are implicitly assigned to the workflow's `initiated_by_id` (Brixter). v2 may add per-step assignment + Lark notifications.

## What this unblocks (downstream)

- **Performance MVP (Weeks 5-6)**: 30-day check-in step in the HIRING workflow can later trigger a Performance review row. Currently a STATUS_UPDATE; can evolve into a step that links to a check-in record.
- **REGULARIZATION workflows**: probationary → regular regularization is the natural next workflow_type to add — schema already supports it.
- **Lark APPROVAL routing**: v2 can extend the APPROVAL step type to pause the workflow and resume on `lark-approval-webhook` callback. Schema is ready; just needs wiring.
- **SLA tracking**: v2 can add `due_at` columns to `workflow_steps` and an overdue indicator on the list/detail.
