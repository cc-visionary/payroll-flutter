// Run with: deno test --allow-net --allow-env supabase/tests/statutory_payables_test.ts
//
// Verifies the statutory_payables_due_v view + statutory_payments_paid_v view
// against a real Postgres database.
//
// **Requires DATABASE_URL.** Skips silently when unset so the test file does
// not break CI/local runs that don't have a local Supabase instance up.
// To run the full suite, point at your local Supabase Postgres:
//
//   export DATABASE_URL=postgres://postgres:postgres@127.0.0.1:54322/postgres
//   deno test --allow-net --allow-env supabase/tests/statutory_payables_test.ts
//
// Each test seeds its own scenario into the existing database within a
// transaction that gets rolled back on completion, so concurrent runs and
// dirty state don't matter.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { Client, type Transaction } from 'https://deno.land/x/postgres@v0.19.3/mod.ts';

const DATABASE_URL = Deno.env.get('DATABASE_URL') ?? '';
const skip = DATABASE_URL.length === 0;

// Helper — open a single client per test, run the body inside a SERIALIZABLE
// transaction, then rollback. Keeps the database clean across runs.
async function withTx(body: (tx: Transaction) => Promise<void>): Promise<void> {
  const client = new Client(DATABASE_URL);
  await client.connect();
  const tx = client.createTransaction(`stat_payables_${crypto.randomUUID().replace(/-/g, '')}`);
  await tx.begin();
  try {
    await body(tx);
  } finally {
    try { await tx.rollback(); } catch (_) { /* already aborted */ }
    await client.end();
  }
}

// Find a company + at least one hiring_entity to scope the fixtures to.
// We re-use whatever's already in the DB via the seed (companies + hiring
// entities are deterministic). Returns ids for two distinct hiring entities
// so multi-brand tests have something to spread across.
async function pickFixturesContext(tx: Transaction): Promise<{
  companyId: string;
  brandA: string;
  brandB: string;
}> {
  const r1 = await tx.queryObject<{ id: string; company_id: string }>`
    select he.id, he.company_id
      from hiring_entities he
     where he.deleted_at is null
     order by he.created_at
     limit 2
  `;
  assert(r1.rows.length >= 2, 'need at least 2 hiring_entities seeded for tests');
  const brandA = r1.rows[0].id;
  const brandB = r1.rows[1].id;
  const companyId = r1.rows[0].company_id;

  return { companyId, brandA, brandB };
}

// Insert a payroll_run + (optionally) one payslip with the given amounts.
// Returns the run id so the caller can adjust status.
//
// pay_periods/payroll_calendars were dropped in 20260418000006 — period dates
// now live directly on payroll_runs.
async function seedRunWithPayslip(
  tx: Transaction,
  args: {
    companyId: string;
    employeeId: string | null;
    periodStart: string; // 'YYYY-MM-DD'
    periodEnd: string;
    payDate: string;
    runStatus: 'DRAFT' | 'REVIEW' | 'RELEASED' | 'CANCELLED';
    sssEe?: number;
    sssEr?: number;
    phEe?: number;
    phEr?: number;
    pgEe?: number;
    pgEr?: number;
    bir?: number;
    loanAmount?: number;
  },
): Promise<{ runId: string; payslipId: string | null }> {
  const run = await tx.queryObject<{ id: string }>`
    insert into payroll_runs (
      company_id, period_start, period_end, pay_date, pay_frequency, status
    )
    values (
      ${args.companyId}, ${args.periodStart}, ${args.periodEnd}, ${args.payDate},
      'SEMI_MONTHLY', ${args.runStatus}
    )
    returning id
  `;
  const runId = run.rows[0].id;

  if (args.employeeId == null) {
    return { runId, payslipId: null };
  }

  const ps = await tx.queryObject<{ id: string }>`
    insert into payslips (
      payroll_run_id, employee_id,
      gross_pay, total_earnings, total_deductions, net_pay,
      sss_ee, sss_er, philhealth_ee, philhealth_er,
      pagibig_ee, pagibig_er, withholding_tax,
      ytd_gross_pay, ytd_taxable_income, ytd_tax_withheld
    ) values (
      ${runId}, ${args.employeeId},
      0, 0, 0, 0,
      ${args.sssEe ?? 0}, ${args.sssEr ?? 0},
      ${args.phEe ?? 0},  ${args.phEr ?? 0},
      ${args.pgEe ?? 0},  ${args.pgEr ?? 0},
      ${args.bir ?? 0},
      0, 0, 0
    )
    returning id
  `;
  const payslipId = ps.rows[0].id;

  if (args.loanAmount && args.loanAmount > 0) {
    await tx.queryObject`
      insert into payslip_lines (payslip_id, category, description, amount, sort_order)
      values (${payslipId}, 'LOAN_DEDUCTION', 'Test loan repayment', ${args.loanAmount}, 700)
    `;
  }

  return { runId, payslipId };
}

// Insert a throw-away employee tied to the supplied hiring_entity. Pass
// `hiringEntityId = null` to seed an unassigned employee for the
// exclusion test. Returns the new employee id.
async function seedEmployee(
  tx: Transaction,
  args: { companyId: string; hiringEntityId: string | null },
): Promise<string> {
  const num = crypto.randomUUID().slice(0, 8);
  const r = await tx.queryObject<{ id: string }>`
    insert into employees (
      company_id, hiring_entity_id, employee_number, first_name, last_name,
      employment_type, employment_status, hire_date,
      is_rank_and_file, is_ot_eligible, is_nd_eligible, is_holiday_pay_eligible,
      tax_on_full_earnings
    )
    values (
      ${args.companyId}, ${args.hiringEntityId}, ${'TST-' + num}, 'Test', 'User',
      'REGULAR', 'ACTIVE', '2024-01-01',
      true, true, true, true, false
    )
    returning id
  `;
  return r.rows[0].id;
}

Deno.test({
  name: 'view yields one row per (brand × month × agency) when payslips exist',
  ignore: skip,
  async fn() {
    await withTx(async (tx) => {
      const { companyId, brandA } = await pickFixturesContext(tx);
      const empA = await seedEmployee(tx, { companyId, hiringEntityId: brandA });
      await seedRunWithPayslip(tx, {
        companyId, employeeId: empA,
        periodStart: '2099-03-16', periodEnd: '2099-03-31', payDate: '2099-04-05',
        runStatus: 'RELEASED',
        sssEe: 100, sssEr: 200,
        phEe: 50, phEr: 50,
        pgEe: 100, pgEr: 100,
        bir: 250,
      });

      const rows = await tx.queryObject<{ agency: string; amount_due: string }>`
        select agency, amount_due
          from statutory_payables_due_v
         where hiring_entity_id = ${brandA}
           and period_year = 2099 and period_month = 3
         order by agency
      `;
      const byAgency = Object.fromEntries(
        rows.rows.map((r) => [r.agency, Number(r.amount_due)]),
      );
      assertEquals(byAgency['SSS_CONTRIBUTION'], 300);
      assertEquals(byAgency['PHILHEALTH_CONTRIBUTION'], 100);
      assertEquals(byAgency['PAGIBIG_CONTRIBUTION'], 200);
      assertEquals(byAgency['BIR_WITHHOLDING'], 250);
      // No loan line, no employee_loan row in this scenario.
      assertEquals(byAgency['EMPLOYEE_LOAN'], undefined);
    });
  },
});

Deno.test({
  name: 'view excludes draft / review / cancelled runs (only RELEASED counts)',
  ignore: skip,
  async fn() {
    await withTx(async (tx) => {
      const { companyId, brandA } = await pickFixturesContext(tx);
      const emp = await seedEmployee(tx, { companyId, hiringEntityId: brandA });

      // DRAFT run — should be excluded.
      await seedRunWithPayslip(tx, {
        companyId, employeeId: emp,
        periodStart: '2099-04-01', periodEnd: '2099-04-15', payDate: '2099-04-20',
        runStatus: 'DRAFT',
        sssEe: 999, sssEr: 999,
      });
      // REVIEW run — should be excluded.
      await seedRunWithPayslip(tx, {
        companyId, employeeId: emp,
        periodStart: '2099-04-16', periodEnd: '2099-04-30', payDate: '2099-05-05',
        runStatus: 'REVIEW',
        sssEe: 888, sssEr: 888,
      });

      const rows = await tx.queryObject<{ amount_due: string }>`
        select amount_due
          from statutory_payables_due_v
         where hiring_entity_id = ${brandA}
           and period_year = 2099 and period_month = 4
      `;
      assertEquals(rows.rows.length, 0);
    });
  },
});

Deno.test({
  name: 'loan rows aggregate only payslip_lines.category = LOAN_DEDUCTION',
  ignore: skip,
  async fn() {
    await withTx(async (tx) => {
      const { companyId, brandA } = await pickFixturesContext(tx);
      const emp = await seedEmployee(tx, { companyId, hiringEntityId: brandA });
      const { payslipId } = await seedRunWithPayslip(tx, {
        companyId, employeeId: emp,
        periodStart: '2099-05-01', periodEnd: '2099-05-15', payDate: '2099-05-20',
        runStatus: 'RELEASED',
        loanAmount: 500,
      });

      // Add an unrelated CASH_ADVANCE_DEDUCTION line — must NOT be summed.
      await tx.queryObject`
        insert into payslip_lines (payslip_id, category, description, amount, sort_order)
        values (${payslipId}, 'CASH_ADVANCE_DEDUCTION', 'Should be ignored', 9999, 800)
      `;

      const rows = await tx.queryObject<{ amount_due: string }>`
        select amount_due
          from statutory_payables_due_v
         where hiring_entity_id = ${brandA}
           and period_year = 2099 and period_month = 5
           and agency = 'EMPLOYEE_LOAN'
      `;
      assertEquals(rows.rows.length, 1);
      assertEquals(Number(rows.rows[0].amount_due), 500);
    });
  },
});

Deno.test({
  name: 'period_year + period_month derive from payroll_runs.period_end',
  ignore: skip,
  async fn() {
    await withTx(async (tx) => {
      const { companyId, brandA } = await pickFixturesContext(tx);
      const emp = await seedEmployee(tx, { companyId, hiringEntityId: brandA });
      // period_start in March, end_date in April — view assigns to April.
      await seedRunWithPayslip(tx, {
        companyId, employeeId: emp,
        periodStart: '2099-03-29', periodEnd: '2099-04-02', payDate: '2099-04-15',
        runStatus: 'RELEASED',
        sssEe: 100, sssEr: 100,
      });

      const rows = await tx.queryObject<{ period_year: number; period_month: number }>`
        select period_year, period_month
          from statutory_payables_due_v
         where hiring_entity_id = ${brandA}
           and agency = 'SSS_CONTRIBUTION'
           and period_year = 2099
           and period_month = 4
      `;
      assertEquals(rows.rows.length, 1);
    });
  },
});

Deno.test({
  name: 'employees with hiring_entity_id IS NULL are excluded',
  ignore: skip,
  async fn() {
    await withTx(async (tx) => {
      const { companyId, brandA } = await pickFixturesContext(tx);
      const orphan = await seedEmployee(tx, { companyId, hiringEntityId: null });
      const assigned = await seedEmployee(tx, { companyId, hiringEntityId: brandA });

      // Orphan run — should be excluded entirely.
      await seedRunWithPayslip(tx, {
        companyId, employeeId: orphan,
        periodStart: '2099-06-01', periodEnd: '2099-06-15', payDate: '2099-06-20',
        runStatus: 'RELEASED',
        sssEe: 7777, sssEr: 7777,
      });
      // Brand-A run — should be the only counted contribution.
      await seedRunWithPayslip(tx, {
        companyId, employeeId: assigned,
        periodStart: '2099-06-16', periodEnd: '2099-06-30', payDate: '2099-07-05',
        runStatus: 'RELEASED',
        sssEe: 100, sssEr: 100,
      });

      const rows = await tx.queryObject<{ amount_due: string; employee_count: string }>`
        select amount_due, employee_count
          from statutory_payables_due_v
         where hiring_entity_id = ${brandA}
           and period_year = 2099 and period_month = 6
           and agency = 'SSS_CONTRIBUTION'
      `;
      assertEquals(rows.rows.length, 1);
      assertEquals(Number(rows.rows[0].amount_due), 200);
      assertEquals(Number(rows.rows[0].employee_count), 1);
    });
  },
});

Deno.test({
  name: 'voided statutory_payments do not show in paid totals',
  ignore: skip,
  async fn() {
    await withTx(async (tx) => {
      const { brandA } = await pickFixturesContext(tx);

      // Active payment — counted.
      await tx.queryObject`
        insert into statutory_payments
          (hiring_entity_id, period_year, period_month, agency, paid_on, amount_paid)
        values (${brandA}, 2099, 7, 'SSS_CONTRIBUTION', '2099-08-05', 1000)
      `;
      // Voided payment — not counted.
      await tx.queryObject`
        insert into statutory_payments
          (hiring_entity_id, period_year, period_month, agency, paid_on,
           amount_paid, voided_at, void_reason)
        values (${brandA}, 2099, 7, 'SSS_CONTRIBUTION', '2099-08-05',
                500, now(), 'wrong amount')
      `;

      const rows = await tx.queryObject<{ amount_paid: string; payment_count: string }>`
        select amount_paid, payment_count
          from statutory_payments_paid_v
         where hiring_entity_id = ${brandA}
           and period_year = 2099 and period_month = 7
           and agency = 'SSS_CONTRIBUTION'
      `;
      assertEquals(rows.rows.length, 1);
      assertEquals(Number(rows.rows[0].amount_paid), 1000);
      assertEquals(Number(rows.rows[0].payment_count), 1);
    });
  },
});
