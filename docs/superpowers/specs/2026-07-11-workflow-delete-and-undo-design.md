# Delete cancelled / undo completed workflows — design

**Date:** 2026-07-11
**Status:** Approved (pending spec review)

## Problem

The workflow detail screen (`/workflows/:id`) offers **Cancel workflow** only while a
workflow is `DRAFT`/`IN_PROGRESS`. Once a workflow reaches a terminal state there is no
way to act on it from that screen:

- A **CANCELLED** workflow (e.g. the salary-adjustment notice in the screenshot, cancelled
  because its compensation change was cancelled) is dead weight with no way to remove it.
- A **COMPLETED** workflow that was completed *by mistake* cannot be reopened.

Deletion of a compensation change already exists on the employee profile / compensation
history side and, via the `delete_compensation_change` RPC, also deletes the linked
workflow. The reverse direction — deleting from the workflow screen — does not exist, so
the relationship is asymmetric.

## Goals

1. **Delete a CANCELLED workflow** from the workflow detail screen.
   - For comp-linked workflows this must also delete the linked compensation history
     (symmetry with the existing profile-side delete, which already deletes the workflow).
2. **Undo a COMPLETED workflow** — reopen it to `IN_PROGRESS` to recover from a mistaken
   completion.

## Non-goals

- No delete/undo for `DRAFT`/`IN_PROGRESS` (they already have **Cancel**).
- Undo does **not** un-apply a compensation change or un-issue a generated document — it is
  a workflow-status revert only. Reversing an actual pay change stays a profile-side delete.
- Deleting a standalone (SEPARATION/HIRING) workflow does **not** delete the documents or
  employment events it references — those are independent HR records with their own
  lifecycle (Documents hub). The workflow is only a task-tracker for them.

## Background — what the code/schema already guarantees

- `workflow_steps.workflow_instance_id references workflow_instances(id) on delete cascade`
  — deleting an instance removes its steps automatically (cascade bypasses RLS).
- `compensation_changes.workflow_id references workflow_instances(id)` with **no `on delete`
  clause** (= `NO ACTION`/restrict). A raw `delete from workflow_instances` therefore **fails**
  when a comp change points at it. Only `workflow_steps` and `compensation_changes` reference
  `workflow_instances`.
- `delete_compensation_change(p_change_id)` (migration `20260710000001`) already deletes,
  atomically and in FK order: the change → its workflow (steps cascade) → its notice document
  → its timeline event; reverts the scorecard pointer for an APPLIED role change; guards
  against released payroll; and raises `DELETE_FORBIDDEN` when RLS filters the delete to zero
  rows. `security invoker`, so RLS applies.
- `workflow_instances` RLS: SELECT = same company or SUPER_ADMIN; WRITE = same company AND
  role in (SUPER_ADMIN, ADMIN, HR). A same-company non-HR user can SELECT but not DELETE, so a
  DELETE can be silently filtered to zero rows → the `DELETE_FORBIDDEN` row-count guard is
  warranted, mirroring the comp RPC.
- The workflow detail screen already gates on `profile.isHrOrAdmin`.

## Design

### 1. Status-driven action on the workflow detail screen

Replace the single "Cancel workflow" trailing action with a status switch:

| `w.status`          | Trailing action     | Handler                     |
|---------------------|---------------------|-----------------------------|
| `DRAFT` / `IN_PROGRESS` | Cancel workflow (existing) | `_cancelWorkflow` (unchanged) |
| `CANCELLED`         | **Delete workflow** | `_deleteWorkflow` (new)     |
| `COMPLETED`         | **Undo (reopen)**   | `_reopenWorkflow` (new)     |

Buttons use the existing error-tinted `OutlinedButton.icon` idiom (delete) and a neutral
button (undo). Only one appears at a time.

### 2. Delete (CANCELLED only)

**Routing** — determined by whether a compensation change is linked, read from the already-
cached `compensationChangeByWorkflowProvider(w.id).future`:

- **Comp-linked** (a change exists → SALARY_CHANGE / ROLE_CHANGE): call
  `compensationChangeRepository.deleteChange(change.id)` — the existing atomic RPC. This
  removes the change **and** the workflow + notice + event. Symmetric with the profile side.
- **Standalone** (no linked change → SEPARATION / HIRING / other): call the new
  `workflowRepository.deleteWorkflow(w.id)`.

**New RPC — `delete_workflow(p_instance_id uuid) returns void`, `security invoker`:**

```
select status into v_status from workflow_instances where id = p_instance_id;
if not found then raise exception 'WORKFLOW_NOT_FOUND'; end if;
if v_status <> 'CANCELLED' then raise exception 'WORKFLOW_NOT_CANCELLED'; end if;

-- Comp-linked workflows must go through delete_compensation_change so the change +
-- notice + event are cleaned up together; refuse here rather than emit a raw FK error.
if exists (select 1 from compensation_changes where workflow_id = p_instance_id)
then raise exception 'WORKFLOW_HAS_COMPENSATION_CHANGE'; end if;

delete from workflow_instances where id = p_instance_id;   -- steps cascade
get diagnostics v_deleted = row_count;
if v_deleted = 0 then raise exception 'DELETE_FORBIDDEN'; end if;
```

`revoke execute ... from public; grant execute ... to authenticated;` (mirrors the comp RPC).

**Released-payroll guard: PROPOSED, THEN REJECTED AS UNSAFE — do not reintroduce.**

An earlier draft of this design proposed "refining" `delete_compensation_change` so its
released-payroll guard ran only when `applied_at is not null`, on the premise that *a change
that never materialized cannot have produced a payslip*. **That premise is false.** It was
implemented, caught in final review, and reverted. The guard stays exactly as it is in
`20260710000001` — unconditional.

Why the premise is false:

- `effective_compensation.dart:17` resolves the change in force by
  `status IN ('SCHEDULED','APPLIED')` and `effective_date <= asOf`. **`applied_at` plays no
  part in whether a change drives pay.**
- `compute_service.dart:672` resolves the rate at `payPeriod.endDate`, while `applyDue`
  (`compute_service.dart:90`) clamps its `asOf` to **today**. So on an *ahead-dated* run
  (`period_end` in the future — routine when a run is released a day or two early to cut bank
  files), a SCHEDULED change effective in `(today, period_end]` is never materialized
  (`applied_at` stays null) yet is still picked by the resolver and **pays the released
  payslip**.

Consequence: gating the guard on `applied_at` would let a change that a RELEASED payslip
actually paid at be hard-deleted, leaving that payslip's rate unexplainable — silent,
irreversible loss of payroll money history. There is also no safe narrower carve-out: a
*now-CANCELLED* change could equally have paid while it was SCHEDULED under an ahead-dated
release, so keying the skip on `status = 'CANCELLED'` is unsafe for the same reason.

Accepted trade-off: deleting a comp-linked CANCELLED workflow is refused (`RELEASED_PAYROLL`)
whenever a RELEASED run's period covers the change's effective date. That is the correct,
conservative behaviour — that money may genuinely have been paid. Standalone (SEPARATION /
HIRING) workflow deletion and the undo/reopen action are unaffected by this guard.

### 3. Undo / reopen (COMPLETED only)

**New repository method — `reopenInstance(String instanceId)`** (client-side, mirroring
`cancelInstance`; no RPC — no cascade or cross-table integrity to protect):

1. Find the most-recently-finished step: `workflow_steps` for the instance with status in
   (`COMPLETED`, `SKIPPED`), ordered by `completed_at desc, step_index desc`, limit 1.
2. If found, revert it to `PENDING`, clearing `completed_by_id`, `completed_at`, `remarks`.
   Keep `input_data`, `generated_document_id`, `output_data` (so the linked document and
   "Generate now" reuse survive).
3. Update the instance → `status = 'IN_PROGRESS'`, `completed_at = null`, filtered by
   `.eq('status', 'COMPLETED')` for idempotency.

Order (step first, then instance) avoids any transient auto-complete; no
`maybeCompleteInstance` call is made. After reopening, the reopened step's actions reappear
and re-completing it re-fires `maybeCompleteInstance` normally.

### 4. UI handlers

`_deleteWorkflow`:
- Read the linked change (`compensationChangeByWorkflowProvider(w.id).future`) to tailor copy.
- Confirm dialog naming what dies (comp-linked: "…and the linked compensation change"; else
  "…and its steps"). Error-styled confirm button.
- Comp-linked → `deleteChange`; catch `ReleasedPayrollException` and `DeleteForbiddenException`
  with the same snackbar copy as `runDeleteCompensationChange`. Standalone → `deleteWorkflow`;
  catch `DeleteForbiddenException`.
- On success: `context.go('/workflows')` (the entity is gone), snackbar, and invalidate:
  `workflowListProvider`; and for comp-linked additionally `compensationChangeByWorkflowProvider`,
  `pendingCompensationChangesProvider(employeeId)`, `employeeByIdProvider(employeeId)`.

`_reopenWorkflow`:
- Light confirm ("Reopen this workflow? It returns to in-progress and reopens the last
  completed step.").
- `reopenInstance(w.id)`; invalidate `workflowStepsProvider(w.id)`, `workflowByIdProvider(w.id)`,
  `workflowListProvider`. Stay on the screen (it now shows IN_PROGRESS). Snackbar.

Reuse `DeleteForbiddenException` / `deleteForbiddenFrom` (currently in
`compensation_change_repository.dart`) from `workflow_repository.dart` via import — no new
error module unless a cleaner shared location is trivial during implementation.

## Files

- `supabase/migrations/20260711000001_delete_workflow.sql` — new `delete_workflow` RPC **only**.
  `delete_compensation_change` is deliberately left untouched (see the rejected refinement above).
- `lib/data/repositories/workflow_repository.dart` — `deleteWorkflow()`, `reopenInstance()`.
- `lib/features/workflows/workflow_detail_screen.dart` — status-switched trailing action +
  `_deleteWorkflow` / `_reopenWorkflow` handlers.

## Testing

- `deno test supabase/tests/delete_workflow_test.ts`:
  - standalone CANCELLED workflow → deleted, steps gone;
  - comp-linked workflow → `WORKFLOW_HAS_COMPENSATION_CHANGE`;
  - non-cancelled workflow → `WORKFLOW_NOT_CANCELLED`;
  - missing id → `WORKFLOW_NOT_FOUND`.
  (The `DELETE_FORBIDDEN` path needs a non-HR caller; the Deno tests run as the postgres
  superuser, which bypasses RLS, so that path is verified manually.)
- `flutter analyze` clean. Manual smoke: delete a cancelled comp workflow (verify the change is
  gone from the employee's compensation history, documents hub, and timeline **in the same
  session**, without a restart), delete a cancelled separation workflow (its documents remain),
  undo a completed workflow and re-complete it.

## Risks

- **Comp-linked delete is refused under released payroll.** Because the guard stays
  unconditional, deleting a comp-linked CANCELLED workflow fails with `RELEASED_PAYROLL`
  whenever a RELEASED run covers the change's effective date. This is correct (the money may
  have been paid) but the copy says "Cancel the change instead", which reads oddly for an
  already-cancelled change. Cosmetic; revisit the message if it bites.
- **Cross-surface staleness.** The comp-linked delete must invalidate the same provider set as
  the profile-side `runDeleteCompensationChange` (compensation history, documents hub, timeline,
  employee). These are non-autoDispose families, so a missed invalidation shows deleted data
  until restart. Keep the two call sites' invalidation lists in sync.
- **RLS parity** — `delete_workflow` relies on `workflow_instances` write policy = HR/ADMIN/
  SUPER_ADMIN. If that policy is ever narrowed, the `DELETE_FORBIDDEN` guard still fails safe.
