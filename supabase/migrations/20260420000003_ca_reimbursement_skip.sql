-- Per-run skip lists on cash_advances and reimbursements. Mirrors the penalty
-- installment pattern (migration 20260418000009): when HR decides a specific
-- payroll run should skip this record (e.g. employee already settled it
-- out-of-band, or wants a one-period deferral), the run id goes into the
-- array. The compute service then treats the record as ineligible for that
-- run only; subsequent runs still pick it up because `is_deducted` /
-- `is_paid` stay false.
--
-- Array column + GIN index keeps this a zero-join design that round-trips
-- cleanly through the Supabase Dart client.

alter table cash_advances
  add column if not exists skipped_payroll_run_ids uuid[] not null default '{}';

create index if not exists idx_cash_advances_skipped
  on cash_advances using gin (skipped_payroll_run_ids);

alter table reimbursements
  add column if not exists skipped_payroll_run_ids uuid[] not null default '{}';

create index if not exists idx_reimbursements_skipped
  on reimbursements using gin (skipped_payroll_run_ids);
