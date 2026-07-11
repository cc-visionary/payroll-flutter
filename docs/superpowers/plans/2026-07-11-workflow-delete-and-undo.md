# Delete cancelled / undo completed workflows — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let HR delete a CANCELLED workflow (removing the linked compensation change too, when there is one) and undo a mistakenly-COMPLETED workflow, from the workflow detail screen.

**Architecture:** One new migration adds a `delete_workflow` RPC (standalone workflows). Comp-linked deletes reuse the existing `delete_compensation_change` RPC. Undo is a client-side revert in the repository. The workflow detail screen switches its trailing action on status.

> **⚠️ Task 2 was DROPPED after implementation.** It proposed gating the `delete_compensation_change` released-payroll guard on `applied_at is not null`. Final review proved this unsafe: the payroll resolver (`effective_compensation.dart:17`) selects changes by `status`+`effective_date`, ignoring `applied_at`, and an ahead-dated release (`compute_service.dart:672` resolves at `period_end` while `applyDue` clamps to today) lets a SCHEDULED change pay a RELEASED payslip with `applied_at` still null — so the gate would allow hard-deleting a change that real money was paid at. Task 2 was reverted (commit `9a0fc16`); the guard remains unconditional. **Do not reintroduce it.** See the design doc's "PROPOSED, THEN REJECTED AS UNSAFE" section.

**Tech Stack:** Postgres (plpgsql RPCs, `security invoker` + RLS), Deno tests (`postgres` driver, rolled-back transactions), Flutter (Riverpod, GoRouter, Material 3), Supabase Dart client.

## Global Constraints

- Migration file naming: `supabase/migrations/YYYYMMDDNNNNNN_<name>.sql`; the next free number after `20260710000001` is **`20260711000001`**.
- RPCs are `security invoker` (RLS applies); `revoke execute ... from public; grant execute ... to authenticated;`.
- Deno DB tests connect via `DATABASE_URL`, run inside a rolled-back transaction, and set `ignore: skip` (skip when `DATABASE_URL` is empty) — copy the harness from `supabase/tests/statutory_payables_test.ts`.
- The repo is **not** gated on `dart format` — match surrounding style; gate only on `flutter analyze`.
- No Flutter repository/widget unit tests exist; repository + UI tasks are verified by `flutter analyze` + manual smoke, consistent with the codebase.
- Local DB URL for commands below: `postgres://postgres:postgres@127.0.0.1:54322/postgres`.
- Sentinel exception types `DeleteForbiddenException` / `ReleasedPayrollException` and mappers `deleteForbiddenFrom` / `releasedPayrollFrom` already live in `lib/data/repositories/compensation_change_repository.dart` — reuse via import, do not redefine.

---

## File Structure

- **Create** `supabase/migrations/20260711000001_delete_workflow.sql` — `delete_workflow` RPC (Task 1). (Task 2's refined `delete_compensation_change` was reverted — see the warning above.)
- **Create** `supabase/tests/delete_workflow_test.ts` — DB-integration tests for both RPCs (Tasks 1 & 2).
- **Modify** `lib/data/repositories/workflow_repository.dart` — add `deleteWorkflow()` and `reopenInstance()` (Task 3).
- **Modify** `lib/features/workflows/workflow_detail_screen.dart` — status-switched trailing action + `_deleteWorkflow` / `_reopenWorkflow` handlers (Task 4).

---

## Task 1: `delete_workflow` RPC (standalone workflows)

**Files:**
- Create: `supabase/migrations/20260711000001_delete_workflow.sql`
- Test: `supabase/tests/delete_workflow_test.ts`

**Interfaces:**
- Produces (SQL): `delete_workflow(p_instance_id uuid) returns void`. Raises `WORKFLOW_NOT_FOUND`, `WORKFLOW_NOT_CANCELLED`, `WORKFLOW_HAS_COMPENSATION_CHANGE`, `DELETE_FORBIDDEN`.
- Produces (TS helpers used by Task 2): `withTx`, `pickCompanyId`, `pickUserId`, `seedEmployee`, `seedWorkflow`, `seedCompChange`.

- [ ] **Step 1: Write the failing test file**

Create `supabase/tests/delete_workflow_test.ts`:

```ts
// Run with:
//   export DATABASE_URL=postgres://postgres:postgres@127.0.0.1:54322/postgres
//   deno test --allow-net --allow-env supabase/tests/delete_workflow_test.ts
//
// Verifies delete_workflow + the delete_compensation_change guard refinement
// against a real Postgres DB. Skips silently when DATABASE_URL is unset. Each
// test runs inside a transaction that is rolled back, so state stays clean.
//
// Note: these run as the postgres superuser, which BYPASSES RLS. The
// DELETE_FORBIDDEN path (RLS filters the delete to zero rows) is therefore
// verified manually, not here.
import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { Client, type Transaction } from 'https://deno.land/x/postgres@v0.19.3/mod.ts';

const DATABASE_URL = Deno.env.get('DATABASE_URL') ?? '';
const skip = DATABASE_URL.length === 0;

async function withTx(body: (tx: Transaction) => Promise<void>): Promise<void> {
  const client = new Client(DATABASE_URL);
  await client.connect();
  const tx = client.createTransaction(`del_wf_${crypto.randomUUID().replace(/-/g, '')}`);
  await tx.begin();
  try {
    await body(tx);
  } finally {
    try { await tx.rollback(); } catch (_) { /* already aborted */ }
    await client.end();
  }
}

async function pickCompanyId(tx: Transaction): Promise<string> {
  const r = await tx.queryObject<{ id: string }>`select id from companies order by created_at limit 1`;
  assert(r.rows.length >= 1, 'need a seeded company');
  return r.rows[0].id;
}

async function pickUserId(tx: Transaction): Promise<string> {
  const r = await tx.queryObject<{ id: string }>`select id from users order by created_at limit 1`;
  assert(r.rows.length >= 1, 'need a seeded user');
  return r.rows[0].id;
}

async function seedEmployee(tx: Transaction, companyId: string): Promise<string> {
  const num = crypto.randomUUID().slice(0, 8);
  const r = await tx.queryObject<{ id: string }>`
    insert into employees (
      company_id, employee_number, first_name, last_name,
      employment_type, employment_status, hire_date,
      is_rank_and_file, is_ot_eligible, is_nd_eligible, is_holiday_pay_eligible,
      tax_on_full_earnings
    ) values (
      ${companyId}, ${'TST-' + num}, 'Test', 'User',
      'REGULAR', 'ACTIVE', '2024-01-01', true, true, true, true, false
    ) returning id`;
  return r.rows[0].id;
}

// Insert a workflow_instance (+ one PENDING step) and return both ids.
async function seedWorkflow(
  tx: Transaction,
  args: { companyId: string; employeeId: string; userId: string; status: string },
): Promise<{ instanceId: string; stepId: string }> {
  const wi = await tx.queryObject<{ id: string }>`
    insert into workflow_instances (company_id, employee_id, workflow_type, status, title, initiated_by_id)
    values (${args.companyId}, ${args.employeeId}, 'SEPARATION', ${args.status}, 'Test WF', ${args.userId})
    returning id`;
  const instanceId = wi.rows[0].id;
  const st = await tx.queryObject<{ id: string }>`
    insert into workflow_steps (workflow_instance_id, step_index, step_type, name, status)
    values (${instanceId}, 0, 'DOCUMENT_GENERATION', 'Gen', 'PENDING')
    returning id`;
  return { instanceId, stepId: st.rows[0].id };
}

// Insert a compensation_change; workflowId links it to a workflow.
async function seedCompChange(
  tx: Transaction,
  args: {
    companyId: string; employeeId: string; userId: string;
    status: string; effectiveDate: string; appliedAt: string | null;
    workflowId: string | null;
  },
): Promise<string> {
  const r = await tx.queryObject<{ id: string }>`
    insert into compensation_changes (
      company_id, employee_id, change_type, status, effective_date,
      applied_at, workflow_id, initiated_by_id
    ) values (
      ${args.companyId}, ${args.employeeId}, 'SALARY_INCREASE', ${args.status},
      ${args.effectiveDate}, ${args.appliedAt}, ${args.workflowId}, ${args.userId}
    ) returning id`;
  return r.rows[0].id;
}

Deno.test({
  name: 'delete_workflow removes a CANCELLED standalone workflow and its steps',
  ignore: skip,
  fn: () => withTx(async (tx) => {
    const companyId = await pickCompanyId(tx);
    const userId = await pickUserId(tx);
    const employeeId = await seedEmployee(tx, companyId);
    const { instanceId, stepId } = await seedWorkflow(tx, { companyId, employeeId, userId, status: 'CANCELLED' });

    await tx.queryObject`select delete_workflow(${instanceId})`;

    const wf = await tx.queryObject`select 1 from workflow_instances where id = ${instanceId}`;
    const step = await tx.queryObject`select 1 from workflow_steps where id = ${stepId}`;
    assertEquals(wf.rows.length, 0);
    assertEquals(step.rows.length, 0);
  }),
});

Deno.test({
  name: 'delete_workflow refuses a non-CANCELLED workflow',
  ignore: skip,
  fn: () => withTx(async (tx) => {
    const companyId = await pickCompanyId(tx);
    const userId = await pickUserId(tx);
    const employeeId = await seedEmployee(tx, companyId);
    const { instanceId } = await seedWorkflow(tx, { companyId, employeeId, userId, status: 'IN_PROGRESS' });

    let msg = '';
    try { await tx.queryObject`select delete_workflow(${instanceId})`; }
    catch (e) { msg = (e as Error).message; }
    assert(msg.includes('WORKFLOW_NOT_CANCELLED'), `got: ${msg}`);
  }),
});

Deno.test({
  name: 'delete_workflow refuses a comp-linked workflow',
  ignore: skip,
  fn: () => withTx(async (tx) => {
    const companyId = await pickCompanyId(tx);
    const userId = await pickUserId(tx);
    const employeeId = await seedEmployee(tx, companyId);
    const { instanceId } = await seedWorkflow(tx, { companyId, employeeId, userId, status: 'CANCELLED' });
    await seedCompChange(tx, {
      companyId, employeeId, userId, status: 'CANCELLED',
      effectiveDate: '2026-01-01', appliedAt: null, workflowId: instanceId,
    });

    let msg = '';
    try { await tx.queryObject`select delete_workflow(${instanceId})`; }
    catch (e) { msg = (e as Error).message; }
    assert(msg.includes('WORKFLOW_HAS_COMPENSATION_CHANGE'), `got: ${msg}`);
  }),
});

Deno.test({
  name: 'delete_workflow raises WORKFLOW_NOT_FOUND for a missing id',
  ignore: skip,
  fn: () => withTx(async (tx) => {
    let msg = '';
    try { await tx.queryObject`select delete_workflow('00000000-0000-0000-0000-000000000000')`; }
    catch (e) { msg = (e as Error).message; }
    assert(msg.includes('WORKFLOW_NOT_FOUND'), `got: ${msg}`);
  }),
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
DATABASE_URL=postgres://postgres:postgres@127.0.0.1:54322/postgres \
  deno test --allow-net --allow-env supabase/tests/delete_workflow_test.ts
```
Expected: FAIL — `function delete_workflow(uuid) does not exist` (all four tests error).

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260711000001_delete_workflow.sql`:

```sql
-- 20260711000001_delete_workflow.sql
--
-- delete_workflow(p_instance_id): hard-deletes a CANCELLED, standalone workflow
-- together with its steps (FK cascade). Refuses comp-linked workflows -- those
-- MUST go through delete_compensation_change so the change + notice + event are
-- removed together (and to avoid a raw FK violation, since
-- compensation_changes.workflow_id references workflow_instances with no cascade).
--
-- SECURITY INVOKER (default): RLS applies, so only SUPER_ADMIN/ADMIN/HR in the
-- same company can delete. workflow_instances' SELECT policy is broader than its
-- WRITE policy (a same-company non-HR user can SEE but not DELETE), and Postgres
-- does NOT raise when RLS filters a DELETE to zero rows -- so we check row_count
-- and raise DELETE_FORBIDDEN, mirroring delete_compensation_change.

create or replace function delete_workflow(p_instance_id uuid)
returns void
language plpgsql
security invoker
as $$
declare
  v_status  text;
  v_deleted integer;
begin
  select status into v_status
  from workflow_instances
  where id = p_instance_id;

  if not found then
    raise exception 'WORKFLOW_NOT_FOUND';
  end if;

  if v_status <> 'CANCELLED' then
    raise exception 'WORKFLOW_NOT_CANCELLED';
  end if;

  -- Comp-linked workflows are deleted via delete_compensation_change; refuse
  -- here rather than emit a raw FK error from the restrict constraint.
  if exists (select 1 from compensation_changes where workflow_id = p_instance_id) then
    raise exception 'WORKFLOW_HAS_COMPENSATION_CHANGE';
  end if;

  delete from workflow_instances where id = p_instance_id;  -- workflow_steps cascade
  get diagnostics v_deleted = row_count;
  if v_deleted = 0 then
    -- Visible to the opening SELECT but the write policy filtered the DELETE to
    -- zero rows. Raise rather than silently no-op on a destructive action.
    raise exception 'DELETE_FORBIDDEN';
  end if;
end;
$$;

revoke execute on function delete_workflow(uuid) from public;
grant  execute on function delete_workflow(uuid) to authenticated;
```

- [ ] **Step 4: Apply the migration to the local DB**

Run:
```bash
psql "postgres://postgres:postgres@127.0.0.1:54322/postgres" \
  -f supabase/migrations/20260711000001_delete_workflow.sql
```
Expected: `CREATE FUNCTION`, `REVOKE`, `GRANT`.

- [ ] **Step 5: Run the test to verify it passes**

Run:
```bash
DATABASE_URL=postgres://postgres:postgres@127.0.0.1:54322/postgres \
  deno test --allow-net --allow-env supabase/tests/delete_workflow_test.ts
```
Expected: PASS — 4 passed, 0 failed.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260711000001_delete_workflow.sql supabase/tests/delete_workflow_test.ts
git commit -m "feat(workflows): delete_workflow RPC for standalone cancelled workflows"
```

---

## Task 2: ~~Refine the `delete_compensation_change` released-payroll guard~~ — DROPPED (unsafe)

> **This task was implemented, then reverted in commit `9a0fc16`. Do not execute it.** The
> `applied_at is not null` gate below is UNSAFE — a SCHEDULED change can pay a RELEASED payslip
> without `applied_at` ever being set (ahead-dated release), so the gate would permit deleting a
> compensation change that real money was paid at. The guard stays unconditional. The task text
> is kept below only as a record of what was tried and why it was rejected.

**Files:**
- Modify: `supabase/migrations/20260711000001_delete_workflow.sql` (append the refined function)
- Test: `supabase/tests/delete_workflow_test.ts` (append two tests + one helper)

**Interfaces:**
- Consumes: `withTx`, `pickCompanyId`, `pickUserId`, `seedEmployee`, `seedCompChange` (Task 1).
- Produces (SQL): refined `delete_compensation_change(p_change_id uuid) returns void` — the released-payroll guard now runs **only when `applied_at is not null`**. Same sentinels as before (`CHANGE_NOT_FOUND`, `RELEASED_PAYROLL`, `DELETE_FORBIDDEN`).
- Produces (TS): `seedReleasedRunWithPayslip`.

- [ ] **Step 1: Write the failing tests**

Append to `supabase/tests/delete_workflow_test.ts`:

```ts
// Insert a RELEASED payroll_run + a payslip for the employee. period covers the
// change's effective date so the delete_compensation_change guard can see it.
async function seedReleasedRunWithPayslip(
  tx: Transaction,
  args: { companyId: string; employeeId: string; periodStart: string; periodEnd: string; payDate: string },
): Promise<void> {
  const run = await tx.queryObject<{ id: string }>`
    insert into payroll_runs (company_id, period_start, period_end, pay_date, pay_frequency, status)
    values (${args.companyId}, ${args.periodStart}, ${args.periodEnd}, ${args.payDate}, 'SEMI_MONTHLY', 'RELEASED')
    returning id`;
  await tx.queryObject`
    insert into payslips (
      payroll_run_id, employee_id,
      gross_pay, total_earnings, total_deductions, net_pay,
      sss_ee, sss_er, philhealth_ee, philhealth_er,
      pagibig_ee, pagibig_er, withholding_tax,
      ytd_gross_pay, ytd_taxable_income, ytd_tax_withheld
    ) values (
      ${run.rows[0].id}, ${args.employeeId},
      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )`;
}

Deno.test({
  name: 'delete_compensation_change deletes a never-applied CANCELLED change even under released payroll',
  ignore: skip,
  fn: () => withTx(async (tx) => {
    const companyId = await pickCompanyId(tx);
    const userId = await pickUserId(tx);
    const employeeId = await seedEmployee(tx, companyId);
    await seedReleasedRunWithPayslip(tx, {
      companyId, employeeId, periodStart: '2026-01-01', periodEnd: '2026-01-15', payDate: '2026-01-16',
    });
    const changeId = await seedCompChange(tx, {
      companyId, employeeId, userId, status: 'CANCELLED',
      effectiveDate: '2026-01-10', appliedAt: null, workflowId: null,
    });

    await tx.queryObject`select delete_compensation_change(${changeId})`;

    const c = await tx.queryObject`select 1 from compensation_changes where id = ${changeId}`;
    assertEquals(c.rows.length, 0);
  }),
});

Deno.test({
  name: 'delete_compensation_change still refuses an APPLIED change under released payroll',
  ignore: skip,
  fn: () => withTx(async (tx) => {
    const companyId = await pickCompanyId(tx);
    const userId = await pickUserId(tx);
    const employeeId = await seedEmployee(tx, companyId);
    await seedReleasedRunWithPayslip(tx, {
      companyId, employeeId, periodStart: '2026-01-01', periodEnd: '2026-01-15', payDate: '2026-01-16',
    });
    const changeId = await seedCompChange(tx, {
      companyId, employeeId, userId, status: 'APPLIED',
      effectiveDate: '2026-01-10', appliedAt: '2026-01-10T00:00:00Z', workflowId: null,
    });

    let msg = '';
    try { await tx.queryObject`select delete_compensation_change(${changeId})`; }
    catch (e) { msg = (e as Error).message; }
    assert(msg.includes('RELEASED_PAYROLL'), `got: ${msg}`);
  }),
});
```

- [ ] **Step 2: Run the new tests to verify the first fails**

Run:
```bash
DATABASE_URL=postgres://postgres:postgres@127.0.0.1:54322/postgres \
  deno test --allow-net --allow-env supabase/tests/delete_workflow_test.ts \
  --filter "delete_compensation_change"
```
Expected: FAIL — "deletes a never-applied CANCELLED change" errors with `RELEASED_PAYROLL` (the current guard blocks it); "still refuses an APPLIED change" passes.

- [ ] **Step 3: Append the refined function to the migration**

Append to `supabase/migrations/20260711000001_delete_workflow.sql`:

```sql
-- Refine delete_compensation_change: run the released-payroll guard ONLY when
-- the change actually materialized (applied_at is not null). A change that never
-- applied (SCHEDULED or CANCELLED) never produced a payslip, so erasing it cannot
-- leave a payslip unexplainable -- and blocking it (as the previous unconditional
-- guard did) needlessly prevents deleting a cancelled workflow whose employee has
-- any released run covering the effective date. Changes that DID apply stay
-- protected regardless of later status transitions. Everything else is unchanged
-- from 20260710000001.
create or replace function delete_compensation_change(p_change_id uuid)
returns void
language plpgsql
security invoker
as $$
declare
  v_employee_id    uuid;
  v_effective_date date;
  v_status         text;
  v_applied_at     timestamptz;
  v_prev_scorecard uuid;
  v_new_scorecard  uuid;
  v_workflow_id    uuid;
  v_document_id    uuid;
  v_event_id       uuid;
  v_period_start   date;
  v_period_end     date;
  v_deleted        integer;
begin
  select employee_id, effective_date, status, applied_at,
         prev_scorecard_id, new_scorecard_id, workflow_id, document_id
    into v_employee_id, v_effective_date, v_status, v_applied_at,
         v_prev_scorecard, v_new_scorecard, v_workflow_id, v_document_id
  from compensation_changes
  where id = p_change_id and deleted_at is null;

  if not found then
    raise exception 'CHANGE_NOT_FOUND';
  end if;

  -- Guard only a change that actually paid: applied_at is set. A never-applied
  -- change contributed nothing to any payslip, so deleting it is always safe.
  if v_applied_at is not null then
    select pr.period_start, pr.period_end
      into v_period_start, v_period_end
    from payslips ps
    join payroll_runs pr on pr.id = ps.payroll_run_id
    where ps.employee_id = v_employee_id
      and pr.status = 'RELEASED'
      and (pr.period_end is null or pr.period_end >= v_effective_date)
    limit 1;

    if found then
      raise exception 'RELEASED_PAYROLL'
        using hint = format('%s to %s',
                            coalesce(v_period_start::text, '?'),
                            coalesce(v_period_end::text, '?'));
    end if;
  end if;

  if v_status = 'APPLIED'
     and v_new_scorecard is not null
     and v_new_scorecard is distinct from v_prev_scorecard
     and (select role_scorecard_id from employees where id = v_employee_id) = v_new_scorecard
  then
    update employees set role_scorecard_id = v_prev_scorecard where id = v_employee_id;
  end if;

  select id into v_event_id
  from employment_events
  where employee_id = v_employee_id
    and payload->>'change_id' = p_change_id::text
  limit 1;

  delete from compensation_changes where id = p_change_id;
  get diagnostics v_deleted = row_count;
  if v_deleted = 0 then
    raise exception 'DELETE_FORBIDDEN';
  end if;

  -- Dependent deletes are intentionally NOT row_count-guarded (null ids delete
  -- zero rows legitimately). Safe only while workflow_instances / employee_documents
  -- / employment_events write policies remain a superset of compensation_changes'.
  delete from workflow_instances  where id = v_workflow_id;

  update employee_documents
     set supersedes_document_id = null
   where supersedes_document_id = v_document_id;

  delete from employee_documents where id = v_document_id;
  delete from employment_events  where id = v_event_id;
end;
$$;

revoke execute on function delete_compensation_change(uuid) from public;
grant  execute on function delete_compensation_change(uuid) to authenticated;
```

- [ ] **Step 4: Re-apply the migration to the local DB**

Run:
```bash
psql "postgres://postgres:postgres@127.0.0.1:54322/postgres" \
  -f supabase/migrations/20260711000001_delete_workflow.sql
```
Expected: two `CREATE FUNCTION` (both `create or replace` re-run idempotently), plus REVOKE/GRANT.

- [ ] **Step 5: Run the tests to verify all pass**

Run:
```bash
DATABASE_URL=postgres://postgres:postgres@127.0.0.1:54322/postgres \
  deno test --allow-net --allow-env supabase/tests/delete_workflow_test.ts
```
Expected: PASS — 6 passed, 0 failed.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260711000001_delete_workflow.sql supabase/tests/delete_workflow_test.ts
git commit -m "fix(comp): released-payroll guard applies only to changes that actually paid"
```

---

## Task 3: Repository methods `deleteWorkflow` + `reopenInstance`

**Files:**
- Modify: `lib/data/repositories/workflow_repository.dart`

**Interfaces:**
- Consumes: `delete_workflow` RPC (Task 1); `DeleteForbiddenException` + `deleteForbiddenFrom` from `compensation_change_repository.dart`.
- Produces (Dart, on `WorkflowRepository`): `Future<void> deleteWorkflow(String instanceId)`; `Future<void> reopenInstance(String instanceId)`.

- [ ] **Step 1: Add the import**

At the top of `lib/data/repositories/workflow_repository.dart`, after the existing `import '../models/workflow_step.dart';` line, add:

```dart
import 'compensation_change_repository.dart'
    show DeleteForbiddenException, deleteForbiddenFrom;
```

- [ ] **Step 2: Add `deleteWorkflow` and `reopenInstance` to `WorkflowRepository`**

Inside the `WorkflowRepository` class, immediately after the `cancelInstance` method (before the closing `}` of the class), add:

```dart
  /// Hard-deletes a CANCELLED, standalone (non-compensation) workflow together
  /// with its steps (FK cascade), via the `delete_workflow` RPC. Comp-linked
  /// workflows must be removed through `CompensationChangeRepository.deleteChange`
  /// instead — the RPC refuses them (`WORKFLOW_HAS_COMPENSATION_CHANGE`) so the
  /// change, notice document, and timeline event are cleaned up together.
  ///
  /// Throws [DeleteForbiddenException] when RLS permitted the read but not the
  /// delete — nothing is deleted in that case.
  Future<void> deleteWorkflow(String instanceId) async {
    try {
      await _client.rpc('delete_workflow', params: {'p_instance_id': instanceId});
    } catch (e) {
      final forbidden = deleteForbiddenFrom(e);
      if (forbidden != null) throw forbidden;
      rethrow;
    }
  }

  /// Undo a mistaken completion: revert the most-recently-finished step back to
  /// PENDING and flip the instance from COMPLETED back to IN_PROGRESS. Client-side
  /// (no cascade/integrity to protect), mirroring [cancelInstance]. Step first,
  /// then instance, so no transient auto-complete occurs; the instance flip is a
  /// no-op unless it is still COMPLETED (idempotent). Does not touch any linked
  /// compensation change or generated document.
  Future<void> reopenInstance(String instanceId) async {
    final stepRows = await _client
        .from('workflow_steps')
        .select('id')
        .eq('workflow_instance_id', instanceId)
        .inFilter('status', ['COMPLETED', 'SKIPPED'])
        .order('completed_at', ascending: false)
        .order('step_index', ascending: false)
        .limit(1);
    final rows = stepRows as List;
    if (rows.isNotEmpty) {
      final stepId = (rows.first as Map<String, dynamic>)['id'] as String;
      await _client.from('workflow_steps').update({
        'status': 'PENDING',
        'completed_by_id': null,
        'completed_at': null,
        'remarks': null,
      }).eq('id', stepId);
    }
    await _client
        .from('workflow_instances')
        .update({'status': 'IN_PROGRESS', 'completed_at': null})
        .eq('id', instanceId)
        .eq('status', 'COMPLETED');
  }
```

- [ ] **Step 3: Verify analysis is clean**

Run: `flutter analyze lib/data/repositories/workflow_repository.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/data/repositories/workflow_repository.dart
git commit -m "feat(workflows): deleteWorkflow + reopenInstance repository methods"
```

---

## Task 4: Workflow detail screen — delete (cancelled) + undo (completed) actions

**Files:**
- Modify: `lib/features/workflows/workflow_detail_screen.dart`

**Interfaces:**
- Consumes: `workflowRepositoryProvider.deleteWorkflow` / `.reopenInstance` (Task 3); `compensationChangeByWorkflowProvider`, `compensationChangeRepositoryProvider`, `pendingCompensationChangesProvider`, `ReleasedPayrollException`, `DeleteForbiddenException` (already imported via `compensation_change_repository.dart`); `employeeByIdProvider` (already imported); `workflowListProvider`, `workflowByIdProvider`, `workflowStepsProvider` (already imported).

- [ ] **Step 1: Replace the trailing-action block**

In `lib/features/workflows/workflow_detail_screen.dart`, in `_Body.build`, replace this block:

```dart
            if (w.status == 'IN_PROGRESS' || w.status == 'DRAFT') ...[
              const SizedBox(height: 32),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () => _cancelWorkflow(context, ref),
                  icon: Icon(Icons.cancel_outlined, color: Theme.of(context).colorScheme.error, size: 18),
                  label: Text('Cancel workflow', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              ),
            ],
```

with:

```dart
            if (w.status == 'IN_PROGRESS' || w.status == 'DRAFT') ...[
              const SizedBox(height: 32),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () => _cancelWorkflow(context, ref),
                  icon: Icon(Icons.cancel_outlined, color: Theme.of(context).colorScheme.error, size: 18),
                  label: Text('Cancel workflow', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              ),
            ],
            if (w.status == 'CANCELLED') ...[
              const SizedBox(height: 32),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () => _deleteWorkflow(context, ref),
                  icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error, size: 18),
                  label: Text('Delete workflow', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              ),
            ],
            if (w.status == 'COMPLETED') ...[
              const SizedBox(height: 32),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () => _reopenWorkflow(context, ref),
                  icon: const Icon(Icons.undo, size: 18),
                  label: const Text('Undo completion'),
                ),
              ),
            ],
```

- [ ] **Step 2: Add the `_deleteWorkflow` and `_reopenWorkflow` handlers**

In the `_Body` class, immediately after the existing `_cancelWorkflow` method (before the class closing `}`), add:

```dart
  Future<void> _deleteWorkflow(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    // Route comp-linked workflows through the compensation-change delete so the
    // change + notice + timeline entry go with the workflow (symmetry with the
    // profile-side delete). Standalone workflows use the workflow RPC.
    final change =
        await ref.read(compensationChangeByWorkflowProvider(w.id).future);
    if (!context.mounted) return;

    final body = change != null
        ? 'This permanently deletes the workflow, its steps, and the linked '
            'compensation change — including its notice document and timeline '
            'entry. This cannot be undone.'
        : 'This permanently deletes the workflow and its steps. This cannot be '
            'undone.';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Delete this workflow?'),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dctx).colorScheme.error,
              foregroundColor: Theme.of(dctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      if (change != null) {
        await ref
            .read(compensationChangeRepositoryProvider)
            .deleteChange(change.id);
      } else {
        await ref.read(workflowRepositoryProvider).deleteWorkflow(w.id);
      }
    } on ReleasedPayrollException catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(
          'Cannot delete: released payroll (${e.runPeriod ?? "a released run"}) '
          'already paid at this rate. Cancel the change instead.',
        ),
      ));
      return;
    } on DeleteForbiddenException {
      messenger.showSnackBar(const SnackBar(
        content: Text('You do not have permission to delete this workflow.'),
      ));
      return;
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      return;
    }

    ref.invalidate(workflowListProvider);
    if (change != null) {
      ref.invalidate(compensationChangeByWorkflowProvider(w.id));
      ref.invalidate(pendingCompensationChangesProvider(w.employeeId));
      ref.invalidate(employeeByIdProvider(w.employeeId));
    }
    messenger.showSnackBar(const SnackBar(content: Text('Workflow deleted.')));
    if (context.mounted) context.go('/workflows');
  }

  Future<void> _reopenWorkflow(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Reopen this workflow?'),
        content: const Text(
          'It returns to in-progress and reopens the last completed step so you '
          'can redo it. This does not un-apply any compensation change or '
          'un-issue a generated document.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Reopen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(workflowRepositoryProvider).reopenInstance(w.id);
    ref.invalidate(workflowStepsProvider(w.id));
    ref.invalidate(workflowByIdProvider(w.id));
    ref.invalidate(workflowListProvider);
    messenger.showSnackBar(const SnackBar(content: Text('Workflow reopened.')));
  }
```

- [ ] **Step 3: Verify analysis is clean**

Run: `flutter analyze lib/features/workflows/workflow_detail_screen.dart`
Expected: `No issues found!`

- [ ] **Step 4: Manual smoke test**

Run the app: `flutter run -d linux --dart-define-from-file=env/prod.json`

Verify:
1. **Delete comp workflow** — open a CANCELLED SALARY_CHANGE workflow → **Delete workflow** → confirm. The screen returns to `/workflows`; the workflow is gone; the employee's compensation history no longer lists that change.
2. **Delete standalone workflow** — open a CANCELLED SEPARATION workflow → **Delete workflow** → confirm. Workflow gone; its previously-generated documents still exist in the Documents hub.
3. **Undo completion** — open a COMPLETED workflow → **Undo completion** → confirm. Status returns to IN_PROGRESS, the last step is PENDING again with its actions available; re-completing it flips the workflow back to COMPLETED.

- [ ] **Step 5: Commit**

```bash
git add lib/features/workflows/workflow_detail_screen.dart
git commit -m "feat(workflows): delete cancelled + undo completed from workflow detail"
```

---

## Post-implementation

- **Deploy the migration to prod** once merged: `supabase db push` (or the project's migration deploy step). The refined `delete_compensation_change` is a `create or replace`, so it updates in place; `delete_workflow` is new.
- Follow-up memory note: record that migration `20260711000001` is applied on prod (mirrors the existing compensation-change memory entries).

## Self-Review

- **Spec coverage:** §1 status actions → Task 4; §2 comp-linked delete routing → Task 4 (`deleteChange`); §2 standalone `delete_workflow` RPC → Task 1; §2 guard refinement → Task 2; §3 undo/reopen → Task 3 (`reopenInstance`) + Task 4 handler; testing → Tasks 1, 2, 4; non-goal "standalone delete leaves docs/events" → `delete_workflow` only deletes the instance (Task 1). All covered.
- **Placeholder scan:** none — every step has concrete code/commands.
- **Type consistency:** RPC names (`delete_workflow`, `delete_compensation_change`), params (`p_instance_id`, `p_change_id`), sentinels (`WORKFLOW_NOT_FOUND`/`WORKFLOW_NOT_CANCELLED`/`WORKFLOW_HAS_COMPENSATION_CHANGE`/`DELETE_FORBIDDEN`/`RELEASED_PAYROLL`), and Dart methods (`deleteWorkflow`, `reopenInstance`) are consistent across tasks. `DeleteForbiddenException`/`ReleasedPayrollException`/`deleteForbiddenFrom` reused from `compensation_change_repository.dart` (not redefined).
