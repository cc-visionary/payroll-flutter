-- Migrate the legacy hardcoded `payment_source_account` string constants
-- (LUXIUM_MBTC / GAMECOVE_MBTC / GCASH_CHRIS / GCASH_CLINTON / CASH) into
-- real rows in `hiring_entity_bank_accounts`, add uuid FK columns on
-- payslips + employees, and backfill.
--
-- The legacy `payment_source_account` varchar columns stay populated during
-- the transition for rollback safety. A follow-up cleanup migration drops
-- them once one clean release has run on the FK path.

-- 1. Seed legacy constants as hiring_entity_bank_accounts rows using
--    deterministic UUIDs so the migration is idempotent across environments.
--    Hiring-entity UUIDs match tool/seed_data.dart:
--      GameCove  = 00000000-0000-0000-0000-000000000001
--      Luxium    = 00000000-0000-0000-0000-000000000002
--    Note: GCash personal accounts route to Luxium by default (they're used
--    company-wide but legally Luxium-booked per Finance).
insert into hiring_entity_bank_accounts
  (id, hiring_entity_id, bank_code, bank_name, account_number, account_name, account_type, is_primary, is_active)
values
  ('aaaaaaaa-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'MBTC',  'Metrobank', 'TBD', 'GameCove Inc.',       'SAVINGS', true,  true),
  ('aaaaaaaa-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000002', 'MBTC',  'Metrobank', 'TBD', 'Luxium Trading Inc.', 'SAVINGS', true,  true),
  ('aaaaaaaa-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000002', 'GCASH', 'GCash',     'TBD', 'Chris (GCash)',       'EWALLET', false, true),
  ('aaaaaaaa-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000002', 'GCASH', 'GCash',     'TBD', 'Clinton (GCash)',     'EWALLET', false, true),
  ('aaaaaaaa-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000001', 'CASH',  'Cash',      '—',   'Cash Disbursement',   null,      false, true),
  ('aaaaaaaa-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000002', 'CASH',  'Cash',      '—',   'Cash Disbursement',   null,      false, true)
on conflict (id) do nothing;

-- 2. Add uuid FK columns (nullable — leaves legacy data readable).
alter table payslips
  add column if not exists pay_source_account_id uuid
    references hiring_entity_bank_accounts(id);
create index if not exists idx_payslips_pay_source_account
  on payslips (pay_source_account_id);

alter table employees
  add column if not exists default_pay_source_account_id uuid
    references hiring_entity_bank_accounts(id);
create index if not exists idx_employees_default_pay_source
  on employees (default_pay_source_account_id);

-- 3. Backfill payslips from the legacy string column.
update payslips set pay_source_account_id = case payment_source_account
  when 'LUXIUM_MBTC'    then 'aaaaaaaa-0000-0000-0000-000000000002'::uuid
  when 'GAMECOVE_MBTC'  then 'aaaaaaaa-0000-0000-0000-000000000001'::uuid
  when 'GCASH_CHRIS'    then 'aaaaaaaa-0000-0000-0000-000000000003'::uuid
  when 'GCASH_CLINTON'  then 'aaaaaaaa-0000-0000-0000-000000000004'::uuid
  when 'CASH'           then 'aaaaaaaa-0000-0000-0000-000000000005'::uuid
end
where payment_source_account is not null
  and pay_source_account_id is null;

-- 4. Backfill employees (default_payment_source_account).
update employees set default_pay_source_account_id = case payment_source_account
  when 'LUXIUM_MBTC'    then 'aaaaaaaa-0000-0000-0000-000000000002'::uuid
  when 'GAMECOVE_MBTC'  then 'aaaaaaaa-0000-0000-0000-000000000001'::uuid
  when 'GCASH_CHRIS'    then 'aaaaaaaa-0000-0000-0000-000000000003'::uuid
  when 'GCASH_CLINTON'  then 'aaaaaaaa-0000-0000-0000-000000000004'::uuid
  when 'CASH'           then 'aaaaaaaa-0000-0000-0000-000000000005'::uuid
end
where payment_source_account is not null
  and default_pay_source_account_id is null;

comment on column payslips.payment_source_account is
  'DEPRECATED. Use pay_source_account_id (uuid FK to hiring_entity_bank_accounts). Kept for rollback; drop after one clean release.';
comment on column employees.payment_source_account is
  'DEPRECATED. Use default_pay_source_account_id (uuid FK to hiring_entity_bank_accounts). Kept for rollback; drop after one clean release.';
