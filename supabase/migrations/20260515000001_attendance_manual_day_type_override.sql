-- Manual day-type override on attendance_day_records.
--
-- The existing `day_type` column is written by Lark sync and the deficit-model
-- inference (shift_template_id presence → WORKDAY, absence → REST_DAY). When
-- Lark assigns an ad-hoc coverage shift on what is actually the employee's
-- rest day, the row flips to WORKDAY and the rest-day premium is lost.
--
-- This override lets an admin pin the day type for a specific row from the
-- attendance edit dialog. When set, both `AttendanceRowVm.dayType` (UI) and
-- `compute_service._attendanceFromRow` (engine) consult the override first
-- and ignore the shift-template heuristic. The Lark sync NEVER writes this
-- column, so the override survives every future sync.
--
-- Nullable; null = "use the existing auto-detection rule". Constrained to
-- the same enum as `day_type` so we can't drift into invalid values.

alter table attendance_day_records
  add column manual_day_type_override day_type;

comment on column attendance_day_records.manual_day_type_override is
  'Admin-set day type that overrides shift-template inference and Lark-synced day_type. Null = auto-detect.';
