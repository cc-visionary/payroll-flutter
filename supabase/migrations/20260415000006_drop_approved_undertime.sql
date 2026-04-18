-- Late-in and early-out are always undertime; there is no "approval" path
-- that converts them back into paid work hours. Drop the two booleans.

alter table attendance_day_records drop column if exists late_in_approved;
alter table attendance_day_records drop column if exists early_out_approved;
