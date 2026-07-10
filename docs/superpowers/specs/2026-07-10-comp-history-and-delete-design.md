# Compensation History + Hard Delete — Design

**Date:** 2026-07-10
**Status:** Draft, pending user review
**Owner:** payroll-flutter

## Summary

Give HR a visible **compensation history** per employee, and a **hard delete** that removes a
mistaken compensation change together with everything it spawned: its workflow, its notice document,
and its timeline event. Delete is **blocked** once a released payroll run has already paid at that
rate — at that point the honest action is "Cancel change", not erasure.

Delete runs as a single Postgres RPC so a seven-step, four-table destructive cascade is atomic.

A prerequisite fix ships first: today a compensation change's notice **cannot be found**, because
"Generate now" mints a second, unlinked `employee_documents` row instead of updating the DRAFT
placeholder the change points at. Without that fix, a cascade delete would remove the placeholder
and leave the real, issued notice behind.

## Motivation

- `compensation_changes` rows already accumulate but are **never displayed as history**. The only
  surfaces are the "Pending changes" strip (SCHEDULED only) and the Timeline event.
- There is no way to undo a mis-entered change. `cancel(...)` exists but only flips status to
  `CANCELLED`; it does **not** void the notice and does **not** revert `employees.role_scorecard_id`
  when `applyDue` already repointed it. So even cancelling leaves the employee in the wrong role.
- A mistaken change silently changes pay: `compute_service` resolves `compensation_changes` before
  falling back to the scorecard.

## Decisions locked from brainstorm

1. **Hard delete**, not soft delete. Rows are physically removed — "as if it never happened".
2. **Blocked when a RELEASED payroll run has used it.** Refuse, explain, and point at "Cancel
   change". Delete exists to undo a mistake *before* money moves.
3. **The timeline `employment_events` row is deleted too** — no phantom "Salary Change" pointing at
   nothing.
4. **History lives as a section on the employee's Role tab**, under Current Role.
5. **Atomicity via a Postgres RPC** (`delete_compensation_change`), `SECURITY INVOKER` so RLS still
   applies. The guard lives server-side and cannot be skipped by a future caller.
6. **Prerequisite:** fix the document linkage so one change owns exactly one `employee_documents`
   row.

## Verified facts (checked, not assumed)

- **RLS permits DELETE.** `compensation_changes` has `..._company_write ... for all`
  (20260708000001). `workflow_instances` gets `..._company_write ... for all` from the DO-block at
  `20260414000014_rls.sql:96-113`. `employee_documents` and `employment_events` get
  `..._admin_write ... for all` from the DO-block at `:154-173`. `for all` covers DELETE for
  `SUPER_ADMIN/ADMIN/HR`. **No RLS migration is required.**
- **The FK graph dictates the delete order:**
  - `workflow_steps.workflow_instance_id → workflow_instances` is `ON DELETE CASCADE`.
  - `workflow_steps.generated_document_id → employee_documents` has **no** cascade — a document
    cannot be deleted while a step references it.
  - `employee_documents.generated_from_event_id → employment_events` has no cascade — the event
    cannot be deleted while a document references it.
  - `employee_documents.supersedes_document_id → employee_documents` is a self-FK — a *later*
    notice pointing at ours would block deletion.
  - `compensation_changes.workflow_id` / `.document_id` point **outward**, so that row goes first.
- **Guard tables:** `payslips(payroll_run_id, employee_id)` and
  `payroll_runs(status payroll_run_status, period_start, period_end)`.
- **`document_status` already has `VOIDED`**; we do not need it, because hard delete removes the row.

## Phase 1 (prerequisite): one change → one document

Today `_generateNow` (`workflow_detail_screen.dart`) knows the DRAFT's id via
`step.generatedDocumentId` and discards it. `GenerateScreen._sessionRecordId` therefore starts
`null`, so `saveGenerated` takes its **insert** path and creates a second, `ISSUED` row with no link
back to the change.

Fix:

1. `_generateNow` appends `&documentId=${step.generatedDocumentId}` when that id is non-null.
2. `router.dart` (`/documents/generate/:templateId`) parses `documentId` and passes it to
   `GenerateScreen`.
3. `GenerateScreen` seeds `_sessionRecordId = widget.documentId`, so `saveGenerated` takes its
   **update** path and rewrites the DRAFT row in place.
4. `buildUpdatePayload` (`employee_document_repository.dart`) adds `'status': 'ISSUED'`.

Result: the DRAFT *becomes* the issued notice. `compensation_changes.document_id` and
`workflow_steps.generated_document_id` both reference that single row. This also stops separation
notices from orphaning, since they take the same code path.

Setting `ISSUED` on the update path is idempotent for the existing in-session re-save case (that row
is already `ISSUED`).

## Phase 2a: Compensation history section

New widget on the Role tab, rendered under "Current Role" and beneath the BASE SALARY tile:

- Data source: the existing `compensationChangesByEmployeeProvider(employee.id)` —
  `listByEmployee` already returns non-deleted rows ordered by `effective_date` descending. No new
  query.
- Each row shows: change-type label · `₱prev → ₱new` (via `Money.fmtPhp`) · `Effective {date}` ·
  a theme-aware `StatusChip` (`SCHEDULED` → `StatusTone.warning`, `APPLIED` → `success`,
  `CANCELLED` → `danger`) · a **Workflow** link (`/workflows/{workflowId}`) and a **Notice** link
  (`/documents/view/{documentId}`), each rendered only when the id is non-null.
- A delete action per row, visible only when `canManage`.
- Empty state: "No compensation changes recorded. Pay comes from the role scorecard."

## Phase 2b: Hard delete

### Migration: `delete_compensation_change(p_change_id uuid)`

`SECURITY INVOKER` (the default) so RLS applies and only `SUPER_ADMIN/ADMIN/HR` can execute the
deletes. `language plpgsql`. Runs entirely inside one transaction.

```
1. Load the change (id, employee_id, effective_date, status,
   prev_scorecard_id, new_scorecard_id, workflow_id, document_id).
   Not found -> raise exception 'compensation change not found'.

2. GUARD: if exists (
        select 1 from payslips ps
        join payroll_runs pr on pr.id = ps.payroll_run_id
        where ps.employee_id = v_employee_id
          and pr.status = 'RELEASED'
          and pr.period_end >= v_effective_date)
   then raise exception 'RELEASED_PAYROLL' using hint = <run period text>;

3. If v_status = 'APPLIED'
      and v_new_scorecard_id is not null
      and v_new_scorecard_id is distinct from v_prev_scorecard_id
      and (select role_scorecard_id from employees where id = v_employee_id) = v_new_scorecard_id
   then update employees set role_scorecard_id = v_prev_scorecard_id where id = v_employee_id;

4. select id into v_event_id from employment_events
     where employee_id = v_employee_id and payload->>'change_id' = p_change_id::text;

5. delete from compensation_changes where id = p_change_id;          -- drops outward FKs
6. delete from workflow_instances  where id = v_workflow_id;         -- steps cascade
7. update employee_documents set supersedes_document_id = null
     where supersedes_document_id = v_document_id;                   -- release the self-FK
8. delete from employee_documents  where id = v_document_id;
9. delete from employment_events   where id = v_event_id;
```

Steps 6 → 8 → 9 must run in that order or the FKs block the delete. Step 6 also releases every
`workflow_steps.generated_document_id` reference, because the steps cascade away with the instance.

**Null ids are expected and must be safe.** `workflow_id` / `document_id` are null when the confirm
handler could not resolve an actor (it skips the workflow + notice in that case), and `v_event_id`
is null if no matching event exists. `delete from … where id = null` deletes zero rows, so steps 6,
8 and 9 are no-ops rather than errors. The function must not `raise` on a missing workflow, document,
or event — only on a missing change (step 1) or a released payroll run (step 2).

`raise exception` aborts the whole transaction, so the guard cannot leave partial state.

### Dart side

- `CompensationChangeRepository.deleteChange(String changeId)` → `_client.rpc(
  'delete_compensation_change', params: {'p_change_id': changeId})`.
- A `ReleasedPayrollException` mapped from the `RELEASED_PAYROLL` Postgres error, so the UI can show
  a specific message instead of a raw Postgrest error.
- Confirm dialog names exactly what will be deleted — the change, its workflow, its notice, and its
  timeline entry — and adds an explicit warning line when the delete will **move the employee back
  to their previous role** (applied role changes only).
- On success, invalidate: `compensationChangesByEmployeeProvider(employeeId)`,
  `pendingCompensationChangesProvider(employeeId)`, `employeeByIdProvider(employeeId)`,
  `timelineProvider(employeeId)`, `employeeDocumentsProvider(employeeId)`, `workflowListProvider`,
  and `compensationChangeByWorkflowProvider(workflowId)`.

## Scope (in)

1. Phase 1 document-linkage fix (4 files + `buildUpdatePayload` status).
2. Migration adding `delete_compensation_change(uuid)`.
3. `deleteChange(...)` on the repository + `ReleasedPayrollException`.
4. Compensation history section on the Role tab, with per-row delete.
5. Tests (below).

## Scope (out / follow-ons)

- Making the existing "Cancel change" also void the notice and revert the scorecard pointer. It
  remains as-is (status flip + workflow cancel). Worth a follow-up, but delete is the action the
  user asked for.
- Undo/restore of a hard-deleted change. Hard delete is final by choice.
- Org-wide compensation reporting (the "Coming Soon" Compensation screen).
- Backfilling a baseline `compensation_changes` row per employee so the scorecard never drives pay.

## Testing

- **`buildUpdatePayload` sets `status: 'ISSUED'`** — extend the existing pure test
  `test/data/repositories/employee_document_payload_test.dart`. Confirms Phase 1 flips the DRAFT.
- **Route threading**: `/documents/generate/:templateId?employeeId=…&documentId=…` parses
  `documentId` into `GenerateScreen`; and `_generateNow` omits it when the step has none
  (separation-style steps without a pre-inserted doc).
- **RPC guard** (SQL, run against a local/scratch Postgres): a change whose `effective_date` falls
  on or before a `RELEASED` run's `period_end` for that employee raises `RELEASED_PAYROLL` and
  deletes nothing; the same change with the run in `REVIEW` deletes cleanly.
- **RPC cascade** (SQL): after deleting an `APPLIED` role change, assert the `compensation_changes`,
  `workflow_instances`, `workflow_steps`, `employee_documents`, and `employment_events` rows are all
  gone, and `employees.role_scorecard_id` is back to `prev_scorecard_id`.
- **RPC pointer revert is conditional**: a pay-only change (scorecard unchanged) must not touch
  `employees.role_scorecard_id`; a `SCHEDULED` role change (never applied) must not touch it either.
- **History section** widget test: renders one row per change with the right status chip; hides the
  delete action when `canManage` is false; shows the empty state with no changes.
- `flutter analyze` clean (0 errors, no new lints). Full suite green.

## Files (anticipated)

**New**
- `supabase/migrations/<ts>_delete_compensation_change.sql`
- `lib/features/employees/profile/widgets/compensation_history_section.dart`
- `lib/features/employees/profile/widgets/delete_compensation_change_action.dart`
- tests as above

**Modified**
- `lib/features/workflows/workflow_detail_screen.dart` (`_generateNow` threads `documentId`)
- `lib/app/router.dart` (parse `documentId`)
- `lib/features/documents/generate_screen.dart` (seed `_sessionRecordId`)
- `lib/data/repositories/employee_document_repository.dart` (`buildUpdatePayload` → `ISSUED`)
- `lib/data/repositories/compensation_change_repository.dart` (`deleteChange`, exception)
- `lib/features/employees/profile/tabs/role_tab.dart` (mount the history section)

## Deploy notes

The new migration must be applied before the delete action is used, or `.rpc(...)` fails with
"function does not exist". `20260708000001_compensation_changes.sql` is already applied to prod
(2026-07-10). Multiple Claude sessions share this working dir — implement on an isolated worktree.
