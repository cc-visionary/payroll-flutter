-- Add the three executives and their role cards.
--
-- Clinton Xu (CEO), Donald Xu (CTO) and Christopher Lim (COO) appear in
-- luxium_capacity_model.xlsx on the People sheet -- Strategic tier, 160
-- productive hrs/mo, monthly cost 0 -- but have never existed in this system,
-- so none of their work has been visible in workforce planning.
--
-- The card responsibilities are DRAFTED, not measured. They are grounded in
-- the ownership the business already documents (CEO: revenue, sourcing,
-- partnerships; CTO: technology, automation; COO: finance, admin, systems)
-- and in the seven sourcing tasks the spreadsheet already assigns to Clinton.
-- They are left UNCOSTED on purpose: nobody has estimated executive hours, and
-- inventing them would be worse than showing them as outstanding work.
--
-- hire_date is a PLACEHOLDER (2023-01-01, before the earliest existing hire).
-- base_salary is left NULL rather than 0 -- the sheet reports zero monthly
-- cost, but NULL renders as "unknown" while 0 would assert they are unpaid.
--
-- The COO card adopts the 13 finance tasks (68.4 h/mo) that migration
-- 20260721000001 deliberately left unmapped because there was no Finance role
-- card among the seven. That is real work which until now reached nobody --
-- a re-home, NOT a duplication, so no hours are double-counted.

insert into role_scorecards (id, company_id, job_title, mission_statement,
    key_responsibilities, kpis, wage_type, work_hours_per_day,
    work_days_per_week, is_active, effective_date)
  values ('33333333-3333-3333-3333-000000000008', '11111111-1111-1111-1111-000000000001', 'CEO', 'Own revenue, sourcing and partnerships, and set the commercial direction the rest of the organisation executes against.',
    '[]'::jsonb, '[]'::jsonb, 'MONTHLY', 8, 'Monday to Friday', true, date '2023-01-01')
  on conflict (id) do nothing;

insert into wp_tasks (company_id, role_scorecard_id, responsibility_area, name,
    area_sort, task_sort, times_source, minutes_source)
  select '11111111-1111-1111-1111-000000000001', '33333333-3333-3333-3333-000000000008', 'Sourcing and Supplier Strategy', 'Scan the market for products, categories, and brands worth importing.', 0, 0, 'manual', 'manual'
  where not exists (select 1 from wp_tasks w
    where w.role_scorecard_id = '33333333-3333-3333-3333-000000000008' and w.name = 'Scan the market for products, categories, and brands worth importing.');
insert into wp_tasks (company_id, role_scorecard_id, responsibility_area, name,
    area_sort, task_sort, times_source, minutes_source)
  select '11111111-1111-1111-1111-000000000001', '33333333-3333-3333-3333-000000000008', 'Sourcing and Supplier Strategy', 'Discover, canvass, and qualify suppliers, and decide which relationships to build.', 0, 1, 'manual', 'manual'
  where not exists (select 1 from wp_tasks w
    where w.role_scorecard_id = '33333333-3333-3333-3333-000000000008' and w.name = 'Discover, canvass, and qualify suppliers, and decide which relationships to build.');
insert into wp_tasks (company_id, role_scorecard_id, responsibility_area, name,
    area_sort, task_sort, times_source, minutes_source)
  select '11111111-1111-1111-1111-000000000001', '33333333-3333-3333-3333-000000000008', 'Sourcing and Supplier Strategy', 'Negotiate pricing, terms, and volume commitments with suppliers.', 0, 2, 'manual', 'manual'
  where not exists (select 1 from wp_tasks w
    where w.role_scorecard_id = '33333333-3333-3333-3333-000000000008' and w.name = 'Negotiate pricing, terms, and volume commitments with suppliers.');
insert into wp_tasks (company_id, role_scorecard_id, responsibility_area, name,
    area_sort, task_sort, times_source, minutes_source)
  select '11111111-1111-1111-1111-000000000001', '33333333-3333-3333-3333-000000000008', 'Sourcing and Supplier Strategy', 'Approve what to buy, in what quantity, and at what commitment level.', 0, 3, 'manual', 'manual'
  where not exists (select 1 from wp_tasks w
    where w.role_scorecard_id = '33333333-3333-3333-3333-000000000008' and w.name = 'Approve what to buy, in what quantity, and at what commitment level.');
insert into wp_tasks (company_id, role_scorecard_id, responsibility_area, name,
    area_sort, task_sort, times_source, minutes_source)
  select '11111111-1111-1111-1111-000000000001', '33333333-3333-3333-3333-000000000008', 'Revenue and Commercial Growth', 'Own overall revenue performance across brands and channels.', 1, 0, 'manual', 'manual'
  where not exists (select 1 from wp_tasks w
    where w.role_scorecard_id = '33333333-3333-3333-3333-000000000008' and w.name = 'Own overall revenue performance across brands and channels.');
insert into wp_tasks (company_id, role_scorecard_id, responsibility_area, name,
    area_sort, task_sort, times_source, minutes_source)
  select '11111111-1111-1111-1111-000000000001', '33333333-3333-3333-3333-000000000008', 'Revenue and Commercial Growth', 'Decide channel priorities, pricing posture, and promotional direction.', 1, 1, 'manual', 'manual'
  where not exists (select 1 from wp_tasks w
    where w.role_scorecard_id = '33333333-3333-3333-3333-000000000008' and w.name = 'Decide channel priorities, pricing posture, and promotional direction.');
insert into wp_tasks (company_id, role_scorecard_id, responsibility_area, name,
    area_sort, task_sort, times_source, minutes_source)
  select '11111111-1111-1111-1111-000000000001', '33333333-3333-3333-3333-000000000008', 'Revenue and Commercial Growth', 'Identify and close wholesale, bazaar, and consignment opportunities.', 1, 2, 'manual', 'manual'
  where not exists (select 1 from wp_tasks w
    where w.role_scorecard_id = '33333333-3333-3333-3333-000000000008' and w.name = 'Identify and close wholesale, bazaar, and consignment opportunities.');
insert into wp_tasks (company_id, role_scorecard_id, responsibility_area, name,
    area_sort, task_sort, times_source, minutes_source)
  select '11111111-1111-1111-1111-000000000001', '33333333-3333-3333-3333-000000000008', 'Partnerships and Brand Portfolio', 'Build and maintain partner, distributor, and principal relationships.', 2, 0, 'manual', 'manual'
  where not exists (select 1 from wp_tasks w
    where w.role_scorecard_id = '33333333-3333-3333-3333-000000000008' and w.name = 'Build and maintain partner, distributor, and principal relationships.');
insert into wp_tasks (company_id, role_scorecard_id, responsibility_area, name,
    area_sort, task_sort, times_source, minutes_source)
  select '11111111-1111-1111-1111-000000000001', '33333333-3333-3333-3333-000000000008', 'Partnerships and Brand Portfolio', 'Decide which brands to launch, continue, or discontinue.', 2, 1, 'manual', 'manual'
  where not exists (select 1 from wp_tasks w
    where w.role_scorecard_id = '33333333-3333-3333-3333-000000000008' and w.name = 'Decide which brands to launch, continue, or discontinue.');
insert into wp_tasks (company_id, role_scorecard_id, responsibility_area, name,
    area_sort, task_sort, times_source, minutes_source)
  select '11111111-1111-1111-1111-000000000001', '33333333-3333-3333-3333-000000000008', 'Strategic Direction', 'Set company priorities and resolve escalated commercial decisions.', 3, 0, 'manual', 'manual'
  where not exists (select 1 from wp_tasks w
    where w.role_scorecard_id = '33333333-3333-3333-3333-000000000008' and w.name = 'Set company priorities and resolve escalated commercial decisions.');
insert into wp_tasks (company_id, role_scorecard_id, responsibility_area, name,
    area_sort, task_sort, times_source, minutes_source)
  select '11111111-1111-1111-1111-000000000001', '33333333-3333-3333-3333-000000000008', 'Strategic Direction', 'Approve major spend, expansion, and structural commitments.', 3, 1, 'manual', 'manual'
  where not exists (select 1 from wp_tasks w
    where w.role_scorecard_id = '33333333-3333-3333-3333-000000000008' and w.name = 'Approve major spend, expansion, and structural commitments.');

insert into role_scorecards (id, company_id, job_title, mission_statement,
    key_responsibilities, kpis, wage_type, work_hours_per_day,
    work_days_per_week, is_active, effective_date)
  values ('33333333-3333-3333-3333-000000000009', '11111111-1111-1111-1111-000000000001', 'CTO', 'Own the technology the business runs on, and reduce manual operational work through systems and automation.',
    '[]'::jsonb, '[]'::jsonb, 'MONTHLY', 8, 'Monday to Friday', true, date '2023-01-01')
  on conflict (id) do nothing;

insert into wp_tasks (company_id, role_scorecard_id, responsibility_area, name,
    area_sort, task_sort, times_source, minutes_source)
  select '11111111-1111-1111-1111-000000000001', '33333333-3333-3333-3333-000000000009', 'Systems and Platform Ownership', 'Own the selling, inventory, and back-office platforms and how they connect.', 0, 0, 'manual', 'manual'
  where not exists (select 1 from wp_tasks w
    where w.role_scorecard_id = '33333333-3333-3333-3333-000000000009' and w.name = 'Own the selling, inventory, and back-office platforms and how they connect.');
insert into wp_tasks (company_id, role_scorecard_id, responsibility_area, name,
    area_sort, task_sort, times_source, minutes_source)
  select '11111111-1111-1111-1111-000000000001', '33333333-3333-3333-3333-000000000009', 'Systems and Platform Ownership', 'Decide system changes, integrations, and vendor selection for technology.', 0, 1, 'manual', 'manual'
  where not exists (select 1 from wp_tasks w
    where w.role_scorecard_id = '33333333-3333-3333-3333-000000000009' and w.name = 'Decide system changes, integrations, and vendor selection for technology.');
insert into wp_tasks (company_id, role_scorecard_id, responsibility_area, name,
    area_sort, task_sort, times_source, minutes_source)
  select '11111111-1111-1111-1111-000000000001', '33333333-3333-3333-3333-000000000009', 'Systems and Platform Ownership', 'Maintain access, accounts, and technical continuity across the business.', 0, 2, 'manual', 'manual'
  where not exists (select 1 from wp_tasks w
    where w.role_scorecard_id = '33333333-3333-3333-3333-000000000009' and w.name = 'Maintain access, accounts, and technical continuity across the business.');
insert into wp_tasks (company_id, role_scorecard_id, responsibility_area, name,
    area_sort, task_sort, times_source, minutes_source)
  select '11111111-1111-1111-1111-000000000001', '33333333-3333-3333-3333-000000000009', 'Automation and Tooling', 'Identify manual, repetitive operational work worth automating.', 1, 0, 'manual', 'manual'
  where not exists (select 1 from wp_tasks w
    where w.role_scorecard_id = '33333333-3333-3333-3333-000000000009' and w.name = 'Identify manual, repetitive operational work worth automating.');
insert into wp_tasks (company_id, role_scorecard_id, responsibility_area, name,
    area_sort, task_sort, times_source, minutes_source)
  select '11111111-1111-1111-1111-000000000001', '33333333-3333-3333-3333-000000000009', 'Automation and Tooling', 'Build and maintain internal tools, scrapers, and reporting automation.', 1, 1, 'manual', 'manual'
  where not exists (select 1 from wp_tasks w
    where w.role_scorecard_id = '33333333-3333-3333-3333-000000000009' and w.name = 'Build and maintain internal tools, scrapers, and reporting automation.');
insert into wp_tasks (company_id, role_scorecard_id, responsibility_area, name,
    area_sort, task_sort, times_source, minutes_source)
  select '11111111-1111-1111-1111-000000000001', '33333333-3333-3333-3333-000000000009', 'Technical Standards and Data', 'Set standards for product data, device configuration, and technical documentation.', 2, 0, 'manual', 'manual'
  where not exists (select 1 from wp_tasks w
    where w.role_scorecard_id = '33333333-3333-3333-3333-000000000009' and w.name = 'Set standards for product data, device configuration, and technical documentation.');
insert into wp_tasks (company_id, role_scorecard_id, responsibility_area, name,
    area_sort, task_sort, times_source, minutes_source)
  select '11111111-1111-1111-1111-000000000001', '33333333-3333-3333-3333-000000000009', 'Technical Standards and Data', 'Own data accuracy and availability for reporting and decision-making.', 2, 1, 'manual', 'manual'
  where not exists (select 1 from wp_tasks w
    where w.role_scorecard_id = '33333333-3333-3333-3333-000000000009' and w.name = 'Own data accuracy and availability for reporting and decision-making.');

insert into role_scorecards (id, company_id, job_title, mission_statement,
    key_responsibilities, kpis, wage_type, work_hours_per_day,
    work_days_per_week, is_active, effective_date)
  values ('33333333-3333-3333-3333-000000000010', '11111111-1111-1111-1111-000000000001', 'COO', 'Keep the business solvent, compliant, and organised: cash, books, statutory obligations, and the structures the team works inside.',
    '[]'::jsonb, '[]'::jsonb, 'MONTHLY', 8, 'Monday to Friday', true, date '2023-01-01')
  on conflict (id) do nothing;

insert into wp_tasks (company_id, role_scorecard_id, responsibility_area, name,
    area_sort, task_sort, times_source, minutes_source)
  select '11111111-1111-1111-1111-000000000001', '33333333-3333-3333-3333-000000000010', 'Organisation and Systems', 'Own the operating structure, role definitions, and reporting lines.', 1, 0, 'manual', 'manual'
  where not exists (select 1 from wp_tasks w
    where w.role_scorecard_id = '33333333-3333-3333-3333-000000000010' and w.name = 'Own the operating structure, role definitions, and reporting lines.');
insert into wp_tasks (company_id, role_scorecard_id, responsibility_area, name,
    area_sort, task_sort, times_source, minutes_source)
  select '11111111-1111-1111-1111-000000000001', '33333333-3333-3333-3333-000000000010', 'Organisation and Systems', 'Maintain company policies, approval limits, and administrative procedures.', 1, 1, 'manual', 'manual'
  where not exists (select 1 from wp_tasks w
    where w.role_scorecard_id = '33333333-3333-3333-3333-000000000010' and w.name = 'Maintain company policies, approval limits, and administrative procedures.');
insert into wp_tasks (company_id, role_scorecard_id, responsibility_area, name,
    area_sort, task_sort, times_source, minutes_source)
  select '11111111-1111-1111-1111-000000000001', '33333333-3333-3333-3333-000000000010', 'Organisation and Systems', 'Resolve escalated cross-department and resourcing decisions.', 1, 2, 'manual', 'manual'
  where not exists (select 1 from wp_tasks w
    where w.role_scorecard_id = '33333333-3333-3333-3333-000000000010' and w.name = 'Resolve escalated cross-department and resourcing decisions.');
insert into wp_tasks (company_id, role_scorecard_id, responsibility_area, name,
    area_sort, task_sort, times_source, minutes_source)
  select '11111111-1111-1111-1111-000000000001', '33333333-3333-3333-3333-000000000010', 'Governance and Risk', 'Monitor business risk, controls, and exceptions requiring management attention.', 2, 0, 'manual', 'manual'
  where not exists (select 1 from wp_tasks w
    where w.role_scorecard_id = '33333333-3333-3333-3333-000000000010' and w.name = 'Monitor business risk, controls, and exceptions requiring management attention.');
insert into wp_tasks (company_id, role_scorecard_id, responsibility_area, name,
    area_sort, task_sort, times_source, minutes_source)
  select '11111111-1111-1111-1111-000000000001', '33333333-3333-3333-3333-000000000010', 'Governance and Risk', 'Approve exceptions beyond departmental authority.', 2, 1, 'manual', 'manual'
  where not exists (select 1 from wp_tasks w
    where w.role_scorecard_id = '33333333-3333-3333-3333-000000000010' and w.name = 'Approve exceptions beyond departmental authority.');

-- The COO card adopts the 13 orphaned finance tasks, heaviest first.
update wp_tasks set role_scorecard_id = '33333333-3333-3333-3333-000000000010',
    responsibility_area = 'Finance and Cash Management', area_sort = 0, task_sort = 0
  where id = '871ec2f5-9f6d-4e99-8766-2e490d1349f8' and role_scorecard_id is null;
update wp_tasks set role_scorecard_id = '33333333-3333-3333-3333-000000000010',
    responsibility_area = 'Finance and Cash Management', area_sort = 0, task_sort = 1
  where id = '19c4c945-a16d-4f11-9e3f-61065016762f' and role_scorecard_id is null;
update wp_tasks set role_scorecard_id = '33333333-3333-3333-3333-000000000010',
    responsibility_area = 'Finance and Cash Management', area_sort = 0, task_sort = 2
  where id = '47d5e81c-58f0-49b1-a07e-d2be2b34abce' and role_scorecard_id is null;
update wp_tasks set role_scorecard_id = '33333333-3333-3333-3333-000000000010',
    responsibility_area = 'Finance and Cash Management', area_sort = 0, task_sort = 3
  where id = '6bc1c6bb-cddf-4dcf-9520-0c2554bf11e7' and role_scorecard_id is null;
update wp_tasks set role_scorecard_id = '33333333-3333-3333-3333-000000000010',
    responsibility_area = 'Finance and Cash Management', area_sort = 0, task_sort = 4
  where id = 'e84ccd2b-7518-41fe-8993-87ef53e63074' and role_scorecard_id is null;
update wp_tasks set role_scorecard_id = '33333333-3333-3333-3333-000000000010',
    responsibility_area = 'Finance and Cash Management', area_sort = 0, task_sort = 5
  where id = '320c6b7f-bd1a-48d7-8cb1-6d36b1f9cb92' and role_scorecard_id is null;
update wp_tasks set role_scorecard_id = '33333333-3333-3333-3333-000000000010',
    responsibility_area = 'Finance and Cash Management', area_sort = 0, task_sort = 6
  where id = 'b44e9abe-8733-4d0b-8785-59af06d175ba' and role_scorecard_id is null;
update wp_tasks set role_scorecard_id = '33333333-3333-3333-3333-000000000010',
    responsibility_area = 'Finance and Cash Management', area_sort = 0, task_sort = 7
  where id = '5970e3fb-2a9e-4845-a4ad-0cdc6d76c0e2' and role_scorecard_id is null;
update wp_tasks set role_scorecard_id = '33333333-3333-3333-3333-000000000010',
    responsibility_area = 'Finance and Cash Management', area_sort = 0, task_sort = 8
  where id = 'c4b8db39-6a70-43c0-b9a2-37941fda0d58' and role_scorecard_id is null;
update wp_tasks set role_scorecard_id = '33333333-3333-3333-3333-000000000010',
    responsibility_area = 'Finance and Cash Management', area_sort = 0, task_sort = 9
  where id = 'd75049c2-578a-4b97-9873-a1c95a94665c' and role_scorecard_id is null;
update wp_tasks set role_scorecard_id = '33333333-3333-3333-3333-000000000010',
    responsibility_area = 'Finance and Cash Management', area_sort = 0, task_sort = 10
  where id = 'e7ab4492-2cc5-4f68-94f7-424e62e8ff02' and role_scorecard_id is null;
update wp_tasks set role_scorecard_id = '33333333-3333-3333-3333-000000000010',
    responsibility_area = 'Finance and Cash Management', area_sort = 0, task_sort = 11
  where id = '49abc2b5-53d9-4bfd-ad22-581d8b844058' and role_scorecard_id is null;
update wp_tasks set role_scorecard_id = '33333333-3333-3333-3333-000000000010',
    responsibility_area = 'Finance and Cash Management', area_sort = 0, task_sort = 12
  where id = '2a7b7057-753c-4724-96ee-ffc65a84e9fd' and role_scorecard_id is null;

insert into employees (id, company_id, employee_number, first_name, last_name,
    job_title, role_scorecard_id, reports_to_id, employment_type, employment_status, hire_date)
  values ('22222222-2222-2222-2222-000000000013', '11111111-1111-1111-1111-000000000001', 'EMP013', 'Clinton', 'Xu', 'CEO', '33333333-3333-3333-3333-000000000008', null,
    'REGULAR', 'ACTIVE', date '2023-01-01')
  on conflict (id) do nothing;

insert into employees (id, company_id, employee_number, first_name, last_name,
    job_title, role_scorecard_id, reports_to_id, employment_type, employment_status, hire_date)
  values ('22222222-2222-2222-2222-000000000014', '11111111-1111-1111-1111-000000000001', 'EMP014', 'Donald', 'Xu', 'CTO', '33333333-3333-3333-3333-000000000009', '22222222-2222-2222-2222-000000000013',
    'REGULAR', 'ACTIVE', date '2023-01-01')
  on conflict (id) do nothing;

insert into employees (id, company_id, employee_number, first_name, last_name,
    job_title, role_scorecard_id, reports_to_id, employment_type, employment_status, hire_date)
  values ('22222222-2222-2222-2222-000000000015', '11111111-1111-1111-1111-000000000001', 'EMP015', 'Christopher', 'Lim', 'COO', '33333333-3333-3333-3333-000000000010', '22222222-2222-2222-2222-000000000013',
    'REGULAR', 'ACTIVE', date '2023-01-01')
  on conflict (id) do nothing;
