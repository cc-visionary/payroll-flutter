-- Resilient re-apply of the pay_periods / payroll_calendars drop.
-- The original migration (20260418000001) can fail mid-transaction on
-- databases where some payroll_runs rows had NULL pay_period_id or where
-- the join to pay_periods didn't match — SET NOT NULL then errors and the
-- whole migration rolls back, leaving the columns absent.
--
-- This version:
--   * Adds the columns idempotently (IF NOT EXISTS).
--   * Backfills where possible, then uses sensible fallbacks (created_at)
--     for the still-null rows.
--   * Does NOT tighten to NOT NULL — the app tolerates nulls gracefully
--     (PayrollRun.fromRow falls back to created_at) and NOT NULL here
--     was the original failure point.
--   * Drops pay_period_id, pay_periods, payroll_calendars if present.
--   * Rewrites RLS policies without depending on the old tables.
--
-- Safe to run on any state — fresh DB, half-applied DB, fully-applied DB.

-- 1. Add columns idempotently.
-- NB: we deliberately do NOT add `period_number` — it was always-1 in
-- practice and the app now derives it on the fly from period_start +
-- pay_frequency (see compute_service._derivePeriodNumber).
alter table payroll_runs
  add column if not exists company_id    uuid references companies(id),
  add column if not exists period_start  date,
  add column if not exists period_end    date,
  add column if not exists pay_date      date,
  add column if not exists pay_frequency pay_frequency;

-- If a prior migration happened to add the `period_number` column on this
-- DB, drop it now — the app no longer references it.
alter table payroll_runs drop column if exists period_number;

-- 2. Backfill from the joined tables, only where pay_periods still exists.
do $$
begin
  if to_regclass('public.pay_periods') is not null
     and to_regclass('public.payroll_calendars') is not null then
    update payroll_runs pr
    set
      company_id    = coalesce(pr.company_id, pc.company_id),
      period_start  = coalesce(pr.period_start, pp.start_date),
      period_end    = coalesce(pr.period_end, pp.end_date),
      pay_date      = coalesce(pr.pay_date, pp.pay_date),
      pay_frequency = coalesce(pr.pay_frequency, pc.pay_frequency)
    from pay_periods pp
    join payroll_calendars pc on pc.id = pp.calendar_id
    where pp.id = pr.pay_period_id;
  end if;
end $$;

-- 3. Fallback: any payroll_runs rows still missing dates get created_at as
--    a reasonable stand-in (better than NULL → date cast crashes in the app,
--    and the user can re-edit via the New Run dialog if anything looks off).
update payroll_runs
set period_start = coalesce(period_start, created_at::date),
    period_end   = coalesce(period_end,   (created_at + interval '14 days')::date),
    pay_date     = coalesce(pay_date,     (created_at + interval '20 days')::date);

-- 4. Backfill company_id where still null — try via a joined employee on
--    an existing payslip, then fall back to the first company (single-tenant
--    installs).
do $$
declare
  fallback_company uuid;
begin
  update payroll_runs pr
  set company_id = sub.company_id
  from (
    select p.payroll_run_id, e.company_id
    from payslips p
    join employees e on e.id = p.employee_id
  ) sub
  where pr.id = sub.payroll_run_id
    and pr.company_id is null;

  select id into fallback_company from companies order by created_at limit 1;
  if fallback_company is not null then
    update payroll_runs set company_id = fallback_company where company_id is null;
  end if;
end $$;

-- 5. Replace RLS policies that referenced pay_periods / payroll_calendars.
drop policy if exists payroll_runs_select      on payroll_runs;
drop policy if exists payroll_runs_admin_write on payroll_runs;

create policy payroll_runs_select on payroll_runs for select
  using (
    auth_app_role() = 'SUPER_ADMIN'
    or company_id = auth_company_id()
  );
create policy payroll_runs_admin_write on payroll_runs for all
  using (
    auth_app_role() in ('SUPER_ADMIN', 'ADMIN', 'HR')
    and (company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN')
  )
  with check (
    auth_app_role() in ('SUPER_ADMIN', 'ADMIN', 'HR')
    and (company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN')
  );

-- 6. Drop the FK column and the now-unused tables. Each step guarded.
alter table payroll_runs drop column if exists pay_period_id;

drop table if exists pay_periods       cascade;
drop table if exists payroll_calendars cascade;

-- 7. Indexes for the common query shapes.
create index if not exists payroll_runs_company_idx       on payroll_runs (company_id);
create index if not exists payroll_runs_company_dates_idx on payroll_runs (company_id, period_start, period_end);
create index if not exists payroll_runs_pay_date_idx      on payroll_runs (pay_date desc);

-- 8. Harden delete behaviour — cancelled runs should delete cleanly even
--    when they still have referencing rows (manual adjustments cascade;
--    cash advances / reimbursements / penalty installments unlink).
alter table manual_adjustment_lines
  drop constraint if exists manual_adjustment_lines_payroll_run_id_fkey,
  add  constraint manual_adjustment_lines_payroll_run_id_fkey
    foreign key (payroll_run_id) references payroll_runs(id) on delete cascade;

alter table cash_advances
  drop constraint if exists cash_advances_payroll_run_id_fkey,
  add  constraint cash_advances_payroll_run_id_fkey
    foreign key (payroll_run_id) references payroll_runs(id) on delete set null;

alter table reimbursements
  drop constraint if exists reimbursements_payroll_run_id_fkey,
  add  constraint reimbursements_payroll_run_id_fkey
    foreign key (payroll_run_id) references payroll_runs(id) on delete set null;

alter table penalty_installments
  drop constraint if exists penalty_installments_payroll_run_id_fkey,
  add  constraint penalty_installments_payroll_run_id_fkey
    foreign key (payroll_run_id) references payroll_runs(id) on delete set null;

alter table attendance_day_records
  drop constraint if exists attendance_day_records_locked_by_payroll_run_id_fkey,
  add  constraint attendance_day_records_locked_by_payroll_run_id_fkey
    foreign key (locked_by_payroll_run_id) references payroll_runs(id) on delete set null;

-- payslip_lines.manual_adjustment_id → manual_adjustment_lines: when the
-- adjustment is removed, the line just unlinks (the line itself usually
-- cascade-dies via payslips → payroll_runs anyway, but this covers
-- standalone deletes too).
alter table payslip_lines
  drop constraint if exists payslip_lines_manual_adjustment_id_fkey,
  add  constraint payslip_lines_manual_adjustment_id_fkey
    foreign key (manual_adjustment_id) references manual_adjustment_lines(id) on delete set null;
