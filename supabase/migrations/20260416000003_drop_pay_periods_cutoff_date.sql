-- pay_periods.cutoff_date is redundant with end_date (they're always equal in
-- our payroll flow). Dropping the column so the create-run dialog only has to
-- collect start/end/pay dates.
alter table pay_periods drop column cutoff_date;
