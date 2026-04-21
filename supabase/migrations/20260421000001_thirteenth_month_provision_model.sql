-- Switch 13th-month accrual to the PROVISION model.
--
-- Before: `employees.accrued_thirteenth_month_basis` stored the total
--         basic pay earned across releases. Payout was basis / 12 at
--         distribution time.
-- After:  column stores the 13th-month earned (already divided by 12 at
--         accrual time). Payout equals the accrued value directly.
--
-- Formula at release (applied in PayrollRepository.releaseRun):
--     delta = round((basic_pay - late_ut_deduction) / 12, 2)
--
-- Data fix: any existing balances were accumulated under the old
-- "total basic" meaning, so divide by 12 once to bring them onto the
-- provision scale. Safe for rows that are still zero (0 / 12 = 0).
-- LATE_UT_DEDUCTION is not retroactively subtracted — historical releases
-- didn't factor it in and re-aggregating per run is out of scope for
-- this migration.

update employees
   set accrued_thirteenth_month_basis =
       round(accrued_thirteenth_month_basis / 12.0, 2)
 where accrued_thirteenth_month_basis is not null
   and accrued_thirteenth_month_basis > 0;
