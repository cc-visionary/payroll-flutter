-- Split the single-choice `attendance_source` selector into two independent
-- boolean feature flags so admins can enable Manual CSV import and Lark sync
-- at the same time (or either alone). The old column stays for compatibility
-- but the app no longer reads it.
--
-- Backfill semantics:
--   LARK_IMPORT  → lark_enabled=true,  manual_csv_enabled=true (CSV button has
--                  always been visible for HR/admin regardless of source)
--   MANUAL       → lark_enabled=false, manual_csv_enabled=true
--   BIOMETRIC/SYSTEM (future) → both default true

alter table company_settings
  add column lark_enabled       boolean not null default true,
  add column manual_csv_enabled boolean not null default true;

update company_settings
  set lark_enabled = (attendance_source = 'LARK_IMPORT');
