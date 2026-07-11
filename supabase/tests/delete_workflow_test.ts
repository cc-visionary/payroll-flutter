// Run with:
//   export DATABASE_URL=postgres://postgres:postgres@127.0.0.1:54322/postgres
//   deno test --allow-net --allow-env supabase/tests/delete_workflow_test.ts
//
// Verifies delete_workflow against a real Postgres DB. Skips silently when
// DATABASE_URL is unset. Each test runs inside a transaction that is rolled
// back, so state stays clean.
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
