-- Give every KPI an owning department, and stop the library being one flat
-- list.
--
-- A KPI is a departmental measure before it is a personal one, so the library
-- reads department -> category -> KPI. Assignment is DERIVED, not invented:
-- 52 of 58 are used by role cards in exactly one department, so that department
-- owns them.
--
-- Six needed a decision:
--
--   Case Resolution   Operations   used by both Ops and HR; customer cases are
--                                  the primary sense, HR reuses it for concerns
--   Setup Accuracy    Sales        device configuration quality, owned by
--                                  Technical Product & Purchasing
--   Issue Resolution  Operations   generic operational escalation measure
--   ROAS / MER        Marketing    no role card uses these three yet; they are
--   Channel contrib.  Marketing    commercial metrics with no owner, which is
--   Bazaar ROI        Marketing    itself worth seeing
--
-- OWNERSHIP, NOT RESTRICTION. department_id says which department the measure
-- belongs to. It does NOT stop a role card in another department linking it --
-- Case Resolution is owned by Operations and still used by HR. Enforcing it
-- would break three working assignments today.

alter table kpis
  add column if not exists department_id uuid references departments(id);

create index if not exists kpis_company_department
  on kpis (company_id, department_id);

comment on column kpis.department_id is
  'The department that owns this measure. Organisational only -- role cards in '
  'other departments may still link it.';

-- Marketing        | not used by any role card; commercial metric
--   Bazaar ROI: profit per event + “go/no-go” decision documented
update kpis set department_id = '99999999-9999-9999-9999-000000000004'
  where id = 'd50bfd05-914c-431b-9357-3ef1f5019332' and department_id is null;

-- Marketing        | not used by any role card; commercial metric
--   Channel contribution: Revenue + gross margin % by platform
update kpis set department_id = '99999999-9999-9999-9999-000000000004'
  where id = '12b517e1-188b-4d1e-b1b3-1f8066712309' and department_id is null;

-- Operations       | the only department using it
--   Conversion rate
update kpis set department_id = '99999999-9999-9999-9999-000000000001'
  where id = '8aaac008-c61d-48f5-8668-a2f9e06f7d0c' and department_id is null;

-- Marketing        | not used by any role card; commercial metric
--   ROAS / MER (whichever you use consistently) with trend
update kpis set department_id = '99999999-9999-9999-9999-000000000004'
  where id = 'c26f6492-2db6-4852-b38b-34aa46aa11ed' and department_id is null;

-- Operations       | the only department using it
--   Documentation Completeness
update kpis set department_id = '99999999-9999-9999-9999-000000000001'
  where id = '746d8862-11e7-4bdd-9573-1a11e980be01' and department_id is null;

-- Operations       | the only department using it
--   Sales Performance
update kpis set department_id = '99999999-9999-9999-9999-000000000001'
  where id = '07df1ffe-e443-4339-8f76-f839ca761a4c' and department_id is null;

-- Operations       | the only department using it
--   Preventable Stockouts
update kpis set department_id = '99999999-9999-9999-9999-000000000001'
  where id = '5c67907b-8198-4f13-890a-6b8145380471' and department_id is null;

-- Operations       | the only department using it
--   Stock Availability
update kpis set department_id = '99999999-9999-9999-9999-000000000001'
  where id = '3da4d137-6302-4b87-92dd-903473912269' and department_id is null;

-- Operations       | the only department using it
--   Stock Count Completion
update kpis set department_id = '99999999-9999-9999-9999-000000000001'
  where id = '8e1e149d-6d2f-48f9-aa78-686207b6b672' and department_id is null;

-- Operations       | the only department using it
--   Attendance and Punctuality
update kpis set department_id = '99999999-9999-9999-9999-000000000001'
  where id = '83fd7777-7b6c-4c91-bf3a-e3a0fa377126' and department_id is null;

-- Human Resources  | the only department using it
--   Probation Review Completion
update kpis set department_id = '99999999-9999-9999-9999-000000000002'
  where id = '2df1f96f-5633-4bfb-8824-43a64e1d078b' and department_id is null;

-- Human Resources  | the only department using it
--   Quarterly Review Completion
update kpis set department_id = '99999999-9999-9999-9999-000000000002'
  where id = 'ae44aa6c-4491-4ea7-961b-c3fe1c02d24f' and department_id is null;

-- Human Resources  | the only department using it
--   Training Coverage
update kpis set department_id = '99999999-9999-9999-9999-000000000002'
  where id = 'be92c46b-33ab-411c-b88e-3d496671094d' and department_id is null;

-- Sales            | the only department using it
--   Product Evaluation Completion
update kpis set department_id = '99999999-9999-9999-9999-000000000003'
  where id = '64be7ed4-e1e7-43b6-9a45-fd9f9fd86430' and department_id is null;

-- Sales            | the only department using it
--   Product Improvement Contribution
update kpis set department_id = '99999999-9999-9999-9999-000000000003'
  where id = '373c6de0-0019-45ed-a422-c33140692629' and department_id is null;

-- Operations       | the only department using it
--   Process Improvement
update kpis set department_id = '99999999-9999-9999-9999-000000000001'
  where id = '83fe579e-cbc3-41d7-a224-da48bb3c6e63' and department_id is null;

-- Operations       | the only department using it
--   Cash Accuracy
update kpis set department_id = '99999999-9999-9999-9999-000000000001'
  where id = 'ea38b55b-79c7-488a-995a-00a392bd69c6' and department_id is null;

-- Human Resources  | the only department using it
--   Documentation Accuracy
update kpis set department_id = '99999999-9999-9999-9999-000000000002'
  where id = 'c0ebd0ba-5088-489d-809d-8b94306946a1' and department_id is null;

-- Operations       | the only department using it
--   Forecast Accuracy
update kpis set department_id = '99999999-9999-9999-9999-000000000001'
  where id = '37dfb84e-cb1e-47b3-be66-c6bcc2bcdff5' and department_id is null;

-- Operations       | the only department using it
--   Fulfillment Accuracy
update kpis set department_id = '99999999-9999-9999-9999-000000000001'
  where id = 'ab97a649-d98a-4f0a-8dbf-d99e5d81f2dd' and department_id is null;

-- Operations       | the only department using it
--   Inventory Accuracy
update kpis set department_id = '99999999-9999-9999-9999-000000000001'
  where id = '8c3f28cb-4def-4010-9179-f4b216254616' and department_id is null;

-- Operations       | the only department using it
--   Order Accuracy
update kpis set department_id = '99999999-9999-9999-9999-000000000001'
  where id = '98370e1b-36e4-4192-b595-2bfc34aac6a0' and department_id is null;

-- Sales            | the only department using it
--   Purchasing Accuracy
update kpis set department_id = '99999999-9999-9999-9999-000000000003'
  where id = 'bc9b541b-20e4-42d1-8732-6b5a707b7223' and department_id is null;

-- Operations       | the only department using it
--   Response Accuracy
update kpis set department_id = '99999999-9999-9999-9999-000000000001'
  where id = '56b3d77c-0efc-479a-be0a-6158e5c5e553' and department_id is null;

-- Operations       | the only department using it
--   Returns and Error Rate
update kpis set department_id = '99999999-9999-9999-9999-000000000001'
  where id = 'd90079e2-b351-42f2-9482-cf2cee4ace6f' and department_id is null;

-- Sales            | device configuration quality, owned by Technical Product & Purchasing
--   Setup Accuracy
update kpis set department_id = '99999999-9999-9999-9999-000000000003'
  where id = '40d10f72-c3c0-4f7c-b2df-59b4a6b06610' and department_id is null;

-- Sales            | the only department using it
--   Technical Rework Rate
update kpis set department_id = '99999999-9999-9999-9999-000000000003'
  where id = '86bb2f73-3f80-4b22-9a2b-c8e0624d7919' and department_id is null;

-- Operations       | the only department using it
--   Listing Accuracy
update kpis set department_id = '99999999-9999-9999-9999-000000000001'
  where id = '0d2cb1a8-b7af-419e-b294-13758f11ddf6' and department_id is null;

-- Operations       | customer cases; HR also uses it for employee concerns
--   Case Resolution
update kpis set department_id = '99999999-9999-9999-9999-000000000001'
  where id = 'f0e05ec2-4bbe-4656-ba79-fbcf9b92e157' and department_id is null;

-- Human Resources  | the only department using it
--   Employee Concern Response Time
update kpis set department_id = '99999999-9999-9999-9999-000000000002'
  where id = 'e9d48df0-4caf-4112-a6b4-69f023ae04a0' and department_id is null;

-- Human Resources  | the only department using it
--   HR Compliance Timeliness
update kpis set department_id = '99999999-9999-9999-9999-000000000002'
  where id = '33f0dc50-6281-4250-8616-d168f225f454' and department_id is null;

-- Operations       | the only department using it
--   Checklist Compliance
update kpis set department_id = '99999999-9999-9999-9999-000000000001'
  where id = '4eca32ff-35d1-4df3-9fe6-b7a54000a03c' and department_id is null;

-- Operations       | the only department using it
--   Documentation Compliance
update kpis set department_id = '99999999-9999-9999-9999-000000000001'
  where id = '9a2305b7-51ff-405f-b881-6c25653ca603' and department_id is null;

-- Human Resources  | the only department using it
--   Employee File Completeness
update kpis set department_id = '99999999-9999-9999-9999-000000000002'
  where id = '16d6b70b-6039-415f-abfe-e34b8191f29e' and department_id is null;

-- Operations       | the only department using it
--   Kiosk Compliance
update kpis set department_id = '99999999-9999-9999-9999-000000000001'
  where id = '8b991fe6-8567-490b-89bb-da5d276d8c17' and department_id is null;

-- Operations       | the only department using it
--   Customer Experience
update kpis set department_id = '99999999-9999-9999-9999-000000000001'
  where id = '4d2816a2-6e6d-417d-b6b3-0c9e3da207b9' and department_id is null;

-- Operations       | the only department using it
--   Customer Service Quality
update kpis set department_id = '99999999-9999-9999-9999-000000000001'
  where id = '108d414b-23ff-4dbc-b9fe-016c29c09367' and department_id is null;

-- Operations       | the only department using it
--   Discrepancy Resolution
update kpis set department_id = '99999999-9999-9999-9999-000000000001'
  where id = 'f0ac9c28-9e5f-4bc6-9b05-fe6526d12f17' and department_id is null;

-- Operations       | the only department using it
--   Kiosk Restocking
update kpis set department_id = '99999999-9999-9999-9999-000000000001'
  where id = '17a417b2-6286-4fff-b0c9-e00c3ebadce9' and department_id is null;

-- Operations       | the only department using it
--   Development Completion
update kpis set department_id = '99999999-9999-9999-9999-000000000001'
  where id = '3b6d0e64-4d33-41c8-9530-bb6b34cd74a3' and department_id is null;

-- Human Resources  | the only department using it
--   Employee Turnover Tracking
update kpis set department_id = '99999999-9999-9999-9999-000000000002'
  where id = 'fd519aa1-1aaf-42cd-b74a-61a5ca224dcf' and department_id is null;

-- Sales            | the only department using it
--   Knowledge Transfer
update kpis set department_id = '99999999-9999-9999-9999-000000000003'
  where id = '56d81e52-c540-41a2-bc03-58bce7a1604f' and department_id is null;

-- Human Resources  | the only department using it
--   Monthly Check-In Completion
update kpis set department_id = '99999999-9999-9999-9999-000000000002'
  where id = '06e539f2-b358-4a0d-a8aa-f39a508c0720' and department_id is null;

-- Human Resources  | the only department using it
--   Onboarding Completion
update kpis set department_id = '99999999-9999-9999-9999-000000000002'
  where id = 'c06072e8-c2d1-4369-ae80-f88cbf4a894d' and department_id is null;

-- Operations       | the only department using it
--   SOP Compliance
update kpis set department_id = '99999999-9999-9999-9999-000000000001'
  where id = '90f1bbd7-2ed3-4231-91e6-f5d9ba12e1e8' and department_id is null;

-- Sales            | the only department using it
--   Technical Documentation
update kpis set department_id = '99999999-9999-9999-9999-000000000003'
  where id = 'f038d913-b4ca-41c7-837c-64e03448530d' and department_id is null;

-- Operations       | the only department using it
--   Retail Operations Compliance
update kpis set department_id = '99999999-9999-9999-9999-000000000001'
  where id = '1002fc51-86e0-4019-9609-9ed36a54cc4c' and department_id is null;

-- Operations       | the only department using it
--   Product Knowledge
update kpis set department_id = '99999999-9999-9999-9999-000000000001'
  where id = 'b29cd037-88b7-45c6-985a-11135452e456' and department_id is null;

-- Operations       | the only department using it
--   Cross-Brand Project Execution
update kpis set department_id = '99999999-9999-9999-9999-000000000001'
  where id = '296633b7-0d20-456d-872c-6abe2a8bca5a' and department_id is null;

-- Operations       | the only department using it
--   On-Time Dispatch
update kpis set department_id = '99999999-9999-9999-9999-000000000001'
  where id = '70fb97fc-52d0-4b50-b07d-5124454477bf' and department_id is null;

-- Sales            | the only department using it
--   Purchase Timeliness
update kpis set department_id = '99999999-9999-9999-9999-000000000003'
  where id = '24317847-c432-417c-b698-afc4558c5c48' and department_id is null;

-- Human Resources  | the only department using it
--   Recruitment Turnaround
update kpis set department_id = '99999999-9999-9999-9999-000000000002'
  where id = '53c3e1dd-1a03-4e68-9f5b-7bc0357a4bdf' and department_id is null;

-- Operations       | the only department using it
--   Response Time
update kpis set department_id = '99999999-9999-9999-9999-000000000001'
  where id = 'a7be20ac-57db-4074-9fa1-4760a10c911c' and department_id is null;

-- Sales            | the only department using it
--   Setup Completion
update kpis set department_id = '99999999-9999-9999-9999-000000000003'
  where id = '69ee5cb8-1e60-42c5-890a-f32d9599be51' and department_id is null;

-- Operations       | the only department using it
--   Task Reliability
update kpis set department_id = '99999999-9999-9999-9999-000000000001'
  where id = '6531b24a-6c63-42e3-a1cb-77ce8573b095' and department_id is null;

-- Operations       | the only department using it
--   Listing Update Timeliness
update kpis set department_id = '99999999-9999-9999-9999-000000000001'
  where id = '2a9f615a-18cc-4cdb-84b9-a8ca0859df34' and department_id is null;

-- Operations       | the only department using it
--   Task Completion
update kpis set department_id = '99999999-9999-9999-9999-000000000001'
  where id = 'f910b33b-e662-4893-88be-1c6b647572a6' and department_id is null;

-- Operations       | generic operational escalation measure
--   Issue Resolution
update kpis set department_id = '99999999-9999-9999-9999-000000000001'
  where id = '874819cd-13aa-4627-b4c5-7bcb67258873' and department_id is null;
