-- Keep Lark's raw unit + duration alongside the computed leave_days so the UI
-- can render the original "4 hrs" / "1 day" / "0.5 half-days" label instead
-- of always rounding to a day count.
alter table leave_requests
  add column lark_leave_unit     integer,
  add column lark_leave_duration numeric(6,2);
