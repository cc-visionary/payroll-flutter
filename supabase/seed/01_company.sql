-- Port of payrollos/prisma/seed/seeders/01-company.ts
-- Creates the parent company + hiring entities. Deterministic UUIDs so the
-- seed is idempotent and cross-referenceable.

insert into companies (id, code, name, trade_name, country)
values (
  '11111111-1111-1111-1111-000000000001',
  'GAMECOVE',
  'GameCove Inc.',
  'GameCove',
  'PH'
)
on conflict (code) do update set
  name       = excluded.name,
  trade_name = excluded.trade_name,
  country    = excluded.country;

insert into hiring_entities (
  id, company_id, code, name, trade_name,
  tin, rdo_code, sss_employer_id, philhealth_employer_id, pagibig_employer_id,
  address_line1, address_line2, city, province, zip_code,
  phone_number, email, country
) values (
  '00000000-0000-0000-0000-000000000001',
  '11111111-1111-1111-1111-000000000001',
  'GC', 'GameCove Inc.', 'GameCove',
  '000-000-000-000', '044', '00-0000000-0', '00-000000000-0', '0000-0000-0000',
  'Unit 123, Sample Building', 'Sample Street, Sample Barangay',
  'Makati City', 'Metro Manila', '1234',
  '+63 2 1234 5678', 'hr@gamecove.ph', 'PH'
)
on conflict (id) do update set
  name = excluded.name,
  trade_name = excluded.trade_name,
  tin = excluded.tin,
  rdo_code = excluded.rdo_code,
  sss_employer_id = excluded.sss_employer_id,
  philhealth_employer_id = excluded.philhealth_employer_id,
  pagibig_employer_id = excluded.pagibig_employer_id,
  address_line1 = excluded.address_line1,
  address_line2 = excluded.address_line2,
  city = excluded.city,
  province = excluded.province,
  zip_code = excluded.zip_code,
  phone_number = excluded.phone_number,
  email = excluded.email;

insert into hiring_entities (
  id, company_id, code, name, trade_name,
  tin, rdo_code, sss_employer_id, philhealth_employer_id, pagibig_employer_id,
  address_line1, address_line2, city, province, zip_code,
  phone_number, email, country
) values (
  '00000000-0000-0000-0000-000000000002',
  '11111111-1111-1111-1111-000000000001',
  'LX', 'Luxium Trading Inc.', 'Luxium',
  '000-000-000-001', '044', '00-0000000-1', '00-000000000-1', '0000-0000-0001',
  'Unit 456, Sample Building', 'Sample Street, Sample Barangay',
  'Makati City', 'Metro Manila', '1234',
  '+63 2 1234 5679', 'hr@luxium.ph', 'PH'
)
on conflict (id) do update set
  name = excluded.name,
  trade_name = excluded.trade_name,
  tin = excluded.tin,
  rdo_code = excluded.rdo_code;
