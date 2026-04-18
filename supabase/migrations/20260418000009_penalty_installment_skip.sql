-- Per-run skip list on penalty installments.
--
-- When HR decides a particular payroll run should not withdraw a specific
-- installment — e.g. employee already paid it out-of-band, or requested a
-- one-period deferral — the run id goes into this array. The compute
-- service treats installments whose array contains the current run id as
-- ineligible for that run, so the next run picks them up naturally.
--
-- Using an array instead of a join table keeps this a zero-migration add
-- and aligns with how Supabase Dart clients already query the row.

alter table penalty_installments
  add column if not exists skipped_payroll_run_ids uuid[] not null default '{}';

-- GIN makes `?payroll_run_id = ANY(skipped_payroll_run_ids)` lookups O(log n).
-- Compute queries one run's worth of installments, so the index earns its
-- keep as the number of skipped rows grows over time.
create index if not exists idx_penalty_installments_skipped
  on penalty_installments using gin (skipped_payroll_run_ids);
