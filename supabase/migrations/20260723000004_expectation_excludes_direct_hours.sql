-- An expectation must carry no hours by ANY path, including the new direct
-- hours_per_month column. The 000003 CHECK predated that column.
alter table wp_tasks drop constraint if exists wp_tasks_expectation_uncosted;
alter table wp_tasks add constraint wp_tasks_expectation_uncosted check (
  not is_expectation
  or (times_manual is null and driver_id is null
      and minutes_manual is null and rate_id is null
      and hours_per_month is null)
);
