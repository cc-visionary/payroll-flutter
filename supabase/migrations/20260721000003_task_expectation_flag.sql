-- A responsibility can be an EXPECTATION rather than costable workload.
--
-- 96 of the 164 role-card responsibilities have no hours, and a large share of
-- them never will:
--
--   "Participate in training and development activities based on identified
--    strengths."
--   "Support coworkers and new staff through proper handovers."
--   "Take on small ownership tasks as preparation for higher responsibilities."
--   "Take broader ownership of business activities as leadership
--    responsibilities increase."
--
-- These come from job descriptions. They are behavioural expectations, not
-- monthly workload. Without a way to say so, "96 uncosted" can never reach
-- zero, the costing queue never finishes, and the warning banner becomes
-- wallpaper that everyone learns to ignore.
--
-- DESIGN: only the INTENT is stored. "Costed" is NOT a stored state — it is
-- derived from the row actually having hours. A stored three-way status would
-- drift: a row could claim `costed` while its times/minutes are null, and then
-- the queue and the load math would disagree about the same task.
--
--   is_expectation = true            -> Expectation (no hours expected, ever)
--   else hours > 0                   -> Costed
--   else                             -> Still to cost
--
-- Expectations are excluded from the costing queue and from the "understated
-- load" warning, but they remain real responsibilities: they still appear on
-- the role card, in the contract annex, and in the person's task list. They
-- simply contribute 0 hours, which they already did.

alter table wp_tasks
  add column if not exists is_expectation boolean not null default false;

comment on column wp_tasks.is_expectation is
  'True when this responsibility is a behavioural expectation rather than '
  'costable monthly workload (e.g. "participate in training"). Excluded from '
  'the costing queue and the uncosted warning. "Costed" is derived from having '
  'hours, never stored, so it cannot drift from the load math.';

-- A costed row is by definition not an expectation; the two states are
-- mutually exclusive and the UI must not be able to produce the contradiction.
alter table wp_tasks
  drop constraint if exists wp_tasks_expectation_uncosted;
alter table wp_tasks
  add constraint wp_tasks_expectation_uncosted check (
    not is_expectation
    or (times_manual is null and driver_id is null
        and minutes_manual is null and rate_id is null)
  );

create index if not exists wp_tasks_expectation
  on wp_tasks (company_id) where is_expectation;
