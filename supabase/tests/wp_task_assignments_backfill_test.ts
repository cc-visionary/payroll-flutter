// Run with:
//   export DATABASE_URL=postgres://postgres:postgres@127.0.0.1:54322/postgres
//   deno test --allow-net --allow-env supabase/tests/wp_task_assignments_backfill_test.ts
//
// Verifies the wp_task_assignments backfill (migration 20260724000001) and its
// wp_person_load parity (migration 20260724000002) against a real Postgres DB.
// Skips silently when DATABASE_URL is unset. Each test runs inside a
// transaction that is rolled back, so state stays clean.
//
// Note: these run as the postgres superuser, which BYPASSES RLS -- fine here
// since the backfill logic under test is the SQL itself, not the RLS policies.
//
// Tests seed their own wp_tasks (fresh company data, freshly created
// employees/role_scorecards/wp_drivers), then re-run the SAME two
// INSERT...NOT EXISTS statements the migration ships (mirrored verbatim in
// backfillOwnerAssignments/backfillCardAssignments below) so freshly seeded
// tasks -- which did not exist when the migration's own backfill ran once at
// db-push time -- get backfilled too. This also lets the idempotency test
// (re-running the statements) observe zero new rows on the second pass.
import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { Client, type Transaction } from 'https://deno.land/x/postgres@v0.19.3/mod.ts';

const DATABASE_URL = Deno.env.get('DATABASE_URL') ?? '';
const skip = DATABASE_URL.length === 0;

async function withTx(body: (tx: Transaction) => Promise<void>): Promise<void> {
  const client = new Client(DATABASE_URL);
  await client.connect();
  const tx = client.createTransaction(`wta_bf_${crypto.randomUUID().replace(/-/g, '')}`);
  await tx.begin();
  try {
    await body(tx);
  } finally {
    try { await tx.rollback(); } catch (_) { /* already aborted */ }
    await client.end();
  }
}

function assertClose(actual: number, expected: number, label: string, eps = 1e-6): void {
  assert(Math.abs(actual - expected) < eps, `${label}: expected ${expected}, got ${actual}`);
}

async function pickCompanyId(tx: Transaction): Promise<string> {
  const r = await tx.queryObject<{ id: string }>`select id from companies order by created_at limit 1`;
  assert(r.rows.length >= 1, 'need a seeded company');
  return r.rows[0].id;
}

async function seedEmployee(
  tx: Transaction,
  companyId: string,
  opts: { roleScorecardId?: string | null; deletedAt?: string | null } = {},
): Promise<string> {
  const num = crypto.randomUUID().slice(0, 8);
  const r = await tx.queryObject<{ id: string }>`
    insert into employees (
      company_id, employee_number, first_name, last_name,
      employment_type, employment_status, hire_date,
      is_rank_and_file, is_ot_eligible, is_nd_eligible, is_holiday_pay_eligible,
      tax_on_full_earnings, role_scorecard_id, deleted_at
    ) values (
      ${companyId}, ${'WTA-' + num}, 'Test', 'Employee',
      'REGULAR', 'ACTIVE', '2024-01-01', true, true, true, true, false,
      ${opts.roleScorecardId ?? null}, ${opts.deletedAt ?? null}
    ) returning id`;
  return r.rows[0].id;
}

async function seedRoleScorecard(tx: Transaction, companyId: string): Promise<string> {
  const title = 'WTA Test Role ' + crypto.randomUUID().slice(0, 8);
  const r = await tx.queryObject<{ id: string }>`
    insert into role_scorecards (
      company_id, job_title, mission_statement, key_responsibilities, kpis, effective_date
    ) values (
      ${companyId}, ${title}, 'Test mission', '[]'::jsonb, '[]'::jsonb, '2024-01-01'
    ) returning id`;
  return r.rows[0].id;
}

async function seedDriver(
  tx: Transaction,
  companyId: string,
  args: { value: number; grows: boolean },
): Promise<string> {
  const name = 'wta_driver_' + crypto.randomUUID().slice(0, 8);
  const r = await tx.queryObject<{ id: string }>`
    insert into wp_drivers (company_id, name, value, grows)
    values (${companyId}, ${name}, ${args.value}, ${args.grows})
    returning id`;
  return r.rows[0].id;
}

// A task is either direct-hours (hoursPerMonth set) or driver-calc
// (timesSource:'driver' + driverId + minutesManual); see 20260723000003.
async function seedTask(
  tx: Transaction,
  args: {
    companyId: string;
    name: string;
    ownerEmployeeId?: string | null;
    roleScorecardId?: string | null;
    hoursPerMonth?: number | null;
    timesSource?: 'manual' | 'driver';
    driverId?: string | null;
    driverFactor?: number;
    minutesManual?: number | null;
  },
): Promise<string> {
  const r = await tx.queryObject<{ id: string }>`
    insert into wp_tasks (
      company_id, name, owner_employee_id, role_scorecard_id, hours_per_month,
      times_source, driver_id, driver_factor, minutes_source, minutes_manual
    ) values (
      ${args.companyId}, ${args.name}, ${args.ownerEmployeeId ?? null}, ${args.roleScorecardId ?? null},
      ${args.hoursPerMonth ?? null}, ${args.timesSource ?? 'manual'}, ${args.driverId ?? null},
      ${args.driverFactor ?? 1}, 'manual', ${args.minutesManual ?? null}
    ) returning id`;
  return r.rows[0].id;
}

// Mirrors the migration's backfill (a): explicit owner -> person PRIMARY@100.
async function backfillOwnerAssignments(tx: Transaction): Promise<number> {
  const r = await tx.queryObject<{ id: string }>`
    insert into wp_task_assignments (company_id, task_id, employee_id, assignment_role, allocation_pct)
    select t.company_id, t.id, t.owner_employee_id, 'PRIMARY', 100
    from wp_tasks t
    where t.owner_employee_id is not null
      and not exists (select 1 from wp_task_assignments a
                      where a.task_id = t.id and a.assignment_role = 'PRIMARY')
    returning id`;
  return r.rows.length;
}

// Mirrors the migration's backfill (b): no owner, has a card -> card PRIMARY@100.
async function backfillCardAssignments(tx: Transaction): Promise<number> {
  const r = await tx.queryObject<{ id: string }>`
    insert into wp_task_assignments (company_id, task_id, role_scorecard_id, assignment_role, allocation_pct)
    select t.company_id, t.id, t.role_scorecard_id, 'PRIMARY', 100
    from wp_tasks t
    where t.owner_employee_id is null and t.role_scorecard_id is not null
      and not exists (select 1 from wp_task_assignments a
                      where a.task_id = t.id and a.assignment_role = 'PRIMARY')
    returning id`;
  return r.rows.length;
}

async function runBackfill(tx: Transaction): Promise<{ owner: number; card: number }> {
  const owner = await backfillOwnerAssignments(tx);
  const card = await backfillCardAssignments(tx);
  return { owner, card };
}

async function loadFor(
  tx: Transaction,
  employeeId: string,
): Promise<{ hoursFixed: number; hoursGrowingBase: number } | null> {
  const r = await tx.queryObject<{ hours_fixed: string; hours_growing_base: string }>`
    select hours_fixed, hours_growing_base from wp_person_load where employee_id = ${employeeId}`;
  if (r.rows.length === 0) return null;
  return {
    hoursFixed: Number(r.rows[0].hours_fixed),
    hoursGrowingBase: Number(r.rows[0].hours_growing_base),
  };
}

Deno.test({
  name: 'backfill: owner -> exactly one person PRIMARY@100, owner-less card -> exactly one card PRIMARY@100, neither -> zero',
  ignore: skip,
  fn: () => withTx(async (tx) => {
    const companyId = await pickCompanyId(tx);
    const scorecardId = await seedRoleScorecard(tx, companyId);
    const owner = await seedEmployee(tx, companyId);

    const ownedTaskId = await seedTask(tx, {
      companyId, name: 'Owned task', ownerEmployeeId: owner, hoursPerMonth: 40,
    });
    const cardTaskId = await seedTask(tx, {
      companyId, name: 'Card task', roleScorecardId: scorecardId, hoursPerMonth: 20,
    });
    const orphanTaskId = await seedTask(tx, { companyId, name: 'Orphan task', hoursPerMonth: 10 });

    await runBackfill(tx);

    const ownedRows = await tx.queryObject<{
      assignment_role: string; employee_id: string | null; role_scorecard_id: string | null; allocation_pct: string;
    }>`
      select assignment_role, employee_id, role_scorecard_id, allocation_pct
      from wp_task_assignments where task_id = ${ownedTaskId}`;
    assertEquals(ownedRows.rows.length, 1, 'owned task must have exactly one assignment');
    assertEquals(ownedRows.rows[0].assignment_role, 'PRIMARY');
    assertEquals(ownedRows.rows[0].employee_id, owner);
    assertEquals(ownedRows.rows[0].role_scorecard_id, null);
    assertEquals(Number(ownedRows.rows[0].allocation_pct), 100);

    const cardRows = await tx.queryObject<{
      assignment_role: string; employee_id: string | null; role_scorecard_id: string | null; allocation_pct: string;
    }>`
      select assignment_role, employee_id, role_scorecard_id, allocation_pct
      from wp_task_assignments where task_id = ${cardTaskId}`;
    assertEquals(cardRows.rows.length, 1, 'owner-less carded task must have exactly one assignment');
    assertEquals(cardRows.rows[0].assignment_role, 'PRIMARY');
    assertEquals(cardRows.rows[0].role_scorecard_id, scorecardId);
    assertEquals(cardRows.rows[0].employee_id, null);
    assertEquals(Number(cardRows.rows[0].allocation_pct), 100);

    const orphanRows = await tx.queryObject`select 1 from wp_task_assignments where task_id = ${orphanTaskId}`;
    assertEquals(orphanRows.rows.length, 0, 'task with neither owner nor card must have zero assignments');
  }),
});

Deno.test({
  name: 'backfill is idempotent: re-running the two INSERT...NOT EXISTS statements a second time adds zero rows',
  ignore: skip,
  fn: () => withTx(async (tx) => {
    const companyId = await pickCompanyId(tx);
    const scorecardId = await seedRoleScorecard(tx, companyId);
    const owner = await seedEmployee(tx, companyId);
    await seedTask(tx, { companyId, name: 'Owned task', ownerEmployeeId: owner, hoursPerMonth: 40 });
    await seedTask(tx, { companyId, name: 'Card task', roleScorecardId: scorecardId, hoursPerMonth: 20 });

    const first = await runBackfill(tx);
    assert(first.owner >= 1 && first.card >= 1, 'first backfill run should insert at least one row each');

    const before = await tx.queryObject<{ n: string }>`select count(*)::text as n from wp_task_assignments`;

    const second = await runBackfill(tx);
    assertEquals(second.owner, 0, 'second owner backfill pass must add zero rows');
    assertEquals(second.card, 0, 'second card backfill pass must add zero rows');

    const after = await tx.queryObject<{ n: string }>`select count(*)::text as n from wp_task_assignments`;
    assertEquals(after.rows[0].n, before.rows[0].n, 'total assignment row count must be unchanged');
  }),
});

Deno.test({
  name: 'wp_task_assignments_one_primary forbids a second PRIMARY row for the same task',
  ignore: skip,
  fn: () => withTx(async (tx) => {
    const companyId = await pickCompanyId(tx);
    const owner = await seedEmployee(tx, companyId);
    const other = await seedEmployee(tx, companyId);
    const taskId = await seedTask(tx, { companyId, name: 'Owned task', ownerEmployeeId: owner, hoursPerMonth: 10 });
    await runBackfill(tx); // creates the first (person) PRIMARY for taskId

    let msg = '';
    try {
      await tx.queryObject`
        insert into wp_task_assignments (company_id, task_id, employee_id, assignment_role, allocation_pct)
        values (${companyId}, ${taskId}, ${other}, 'PRIMARY', 100)`;
    } catch (e) {
      msg = (e as Error).message;
    }
    assert(msg.length > 0, 'expected the second PRIMARY insert to throw');
    assert(/one_primary|duplicate key/i.test(msg), `got: ${msg}`);
  }),
});

Deno.test({
  name: 'one_target forbids a row with both role_scorecard_id and employee_id set',
  ignore: skip,
  fn: () => withTx(async (tx) => {
    const companyId = await pickCompanyId(tx);
    const scorecardId = await seedRoleScorecard(tx, companyId);
    const emp = await seedEmployee(tx, companyId);
    const taskId = await seedTask(tx, { companyId, name: 'Some task', hoursPerMonth: 5 });

    let msg = '';
    try {
      await tx.queryObject`
        insert into wp_task_assignments (company_id, task_id, role_scorecard_id, employee_id, assignment_role, allocation_pct)
        values (${companyId}, ${taskId}, ${scorecardId}, ${emp}, 'CONTRIBUTOR', 50)`;
    } catch (e) {
      msg = (e as Error).message;
    }
    assert(msg.includes('one_target'), `got: ${msg}`);
  }),
});

Deno.test({
  name: 'one_target forbids a row with neither role_scorecard_id nor employee_id set',
  ignore: skip,
  fn: () => withTx(async (tx) => {
    const companyId = await pickCompanyId(tx);
    const taskId = await seedTask(tx, { companyId, name: 'Some task', hoursPerMonth: 5 });

    let msg = '';
    try {
      await tx.queryObject`
        insert into wp_task_assignments (company_id, task_id, assignment_role, allocation_pct)
        values (${companyId}, ${taskId}, 'CONTRIBUTOR', 50)`;
    } catch (e) {
      msg = (e as Error).message;
    }
    assert(msg.includes('one_target'), `got: ${msg}`);
  }),
});

Deno.test({
  name: 'wp_person_load hours_fixed/hours_growing_base match the hand-computed split of seeded ownership',
  ignore: skip,
  fn: () => withTx(async (tx) => {
    const companyId = await pickCompanyId(tx);
    const scorecardId = await seedRoleScorecard(tx, companyId);

    const owner = await seedEmployee(tx, companyId);
    const holder1 = await seedEmployee(tx, companyId, { roleScorecardId: scorecardId });
    const holder2 = await seedEmployee(tx, companyId, { roleScorecardId: scorecardId });
    // A third holder that is soft-deleted: must not count toward holder_count
    // and must not appear in wp_person_load at all.
    const holderDeleted = await seedEmployee(tx, companyId, {
      roleScorecardId: scorecardId,
      deletedAt: new Date().toISOString(),
    });

    const growingDriver = await seedDriver(tx, companyId, { value: 10, grows: true });

    // Explicit owner: person PRIMARY -> full hours, regardless of any card.
    await seedTask(tx, { companyId, name: 'Owner fixed', ownerEmployeeId: owner, hoursPerMonth: 40 });
    await seedTask(tx, {
      companyId, name: 'Owner growing', ownerEmployeeId: owner,
      timesSource: 'driver', driverId: growingDriver, driverFactor: 2, minutesManual: 60,
    }); // hours_per_month_base = (10*2) * 60/60 = 20, growing

    // No owner, has a card: card PRIMARY -> split evenly across the 2 ACTIVE
    // non-deleted holders (holderDeleted is excluded).
    await seedTask(tx, { companyId, name: 'Card fixed', roleScorecardId: scorecardId, hoursPerMonth: 60 });
    await seedTask(tx, {
      companyId, name: 'Card growing', roleScorecardId: scorecardId,
      timesSource: 'driver', driverId: growingDriver, driverFactor: 3, minutesManual: 60,
    }); // hours_per_month_base = (10*3) * 60/60 = 30, growing

    await runBackfill(tx);

    const ownerLoad = await loadFor(tx, owner);
    assert(ownerLoad !== null, 'owner should appear in wp_person_load');
    assertClose(ownerLoad!.hoursFixed, 40, 'owner hours_fixed');
    assertClose(ownerLoad!.hoursGrowingBase, 20, 'owner hours_growing_base');

    for (const holder of [holder1, holder2]) {
      const load = await loadFor(tx, holder);
      assert(load !== null, `${holder} should appear in wp_person_load`);
      // Card hours split evenly across the 2 active holders: 60/2 = 30 fixed, 30/2 = 15 growing.
      assertClose(load!.hoursFixed, 30, `${holder} hours_fixed`);
      assertClose(load!.hoursGrowingBase, 15, `${holder} hours_growing_base`);
    }

    const deletedLoad = await loadFor(tx, holderDeleted);
    assertEquals(deletedLoad, null, 'soft-deleted holder must not appear in wp_person_load');
  }),
});
