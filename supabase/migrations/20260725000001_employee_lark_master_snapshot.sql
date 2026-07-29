-- The last set of values Lark sent for an employee's onboarding-form fields,
-- keyed by field. The master-data sync (sync-lark-master-data) compares the
-- app's current value against this snapshot to decide fill / apply / skip, so
-- HR edits made in the app are never overwritten by a later Lark sync, while
-- Lark can still correct fields nobody has touched. Additive; no data change.
alter table employees
  add column if not exists lark_master_snapshot jsonb not null default '{}'::jsonb;

comment on column employees.lark_master_snapshot is
  'Last values Lark sent per onboarding-form field; drives the master-data sync '
  'three-way merge so app edits are not overwritten. See sync-lark-master-data.';
