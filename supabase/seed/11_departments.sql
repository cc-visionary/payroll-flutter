-- Port of payrollos/prisma/seed/seeders/11-departments.ts

insert into departments (id, company_id, code, name) values
  ('99999999-9999-9999-9999-000000000001', '11111111-1111-1111-1111-000000000001', 'OPS', 'Operations'),
  ('99999999-9999-9999-9999-000000000002', '11111111-1111-1111-1111-000000000001', 'HR',  'Human Resources'),
  ('99999999-9999-9999-9999-000000000003', '11111111-1111-1111-1111-000000000001', 'SLS', 'Sales'),
  ('99999999-9999-9999-9999-000000000004', '11111111-1111-1111-1111-000000000001', 'MKT', 'Marketing')
on conflict (company_id, code) do update set name = excluded.name;
