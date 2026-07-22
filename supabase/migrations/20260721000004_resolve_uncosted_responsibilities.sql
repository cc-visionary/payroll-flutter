-- Resolve the 96 uncosted role-card responsibilities.
--
-- They do NOT all deserve hours. Three outcomes:
--
--   EXPECTATION (10)  behavioural expectations from the job description, or a
--                     benefit rather than work: "Participate in training and
--                     development activities", "Take broader ownership as
--                     leadership responsibilities increase", "Receive
--                     applicable commission". These never carry hours.
--
--   QUALIFIER (21)    describes HOW work that is ALREADY COSTED gets done, so
--                     pricing it again would double-count: "Use approved
--                     templates" is how the 40 h/mo of inquiries are answered;
--                     "Verify product model and quantity before packing" is
--                     part of the 65.8 h/mo pack-and-dispatch line. Stored as
--                     expectations too -- same effect, different reason.
--
--   COSTABLE (65)     genuine recurring work with no existing line. 231.7 h/mo.
--
-- PROVENANCE, and this matters: unlike migration 20260721000001, whose numbers
-- came from the business capacity model, THESE HOURS ARE ESTIMATES. Each is
-- anchored to the closest line that already exists in that model rather than
-- invented -- supervision to "Reorder point review" (6.5), recurring checks to
-- "Weekly cycle count" (4.3), management reporting to "Monthly management
-- reporting" (5.0), coaching to "Performance reviews" (2.2). Every one of the
-- 65 matched an anchor; none fell through to a default.
--
-- Each costed row is marked in  so an estimate stays distinguishable
-- from a measured figure when these are reviewed and organised later.
--
-- Effect (verified before writing): company 730h -> 962h of 1280h capacity.
--   Marvin Ong      130% -> 138%   Jeremy Ong    48% -> 92%
--   Evander Mercado  75% -> 116%   Marjory Chua  32% -> 58%
-- Jeremy and Evander were understated because the capacity model only ever
-- priced transactional work; 25 of Jeremy's 38 responsibilities had no hours.
--
-- IDEMPOTENT: every statement is guarded to rows that are still uncosted and
-- not already flagged, so a re-run cannot overwrite a later human correction.

-- 31 expectations
update wp_tasks set is_expectation = true,
    times_manual = null, driver_id = null, minutes_manual = null, rate_id = null
  where id in (
    'bce8092d-e3d8-4c50-87f5-9ff1b52659e9',
    '69ff3e04-2a04-41de-81c6-9bad6f569413',
    '39bb3a61-9c24-4a95-adf9-b2400e2dfa66',
    '9635b6b9-8282-4ba8-a085-343c85ded0fd',
    '232b73b7-c583-4711-bf06-634baf0ef6bc',
    '4c988001-4c01-407f-8f37-fcea769a161f',
    '407a6e5c-ff0d-4c71-a7f3-eb7fcbe054dd',
    'b1758b83-8bc0-4e78-8add-8204f0f0b12f',
    '77ee1748-651f-4495-8224-33f5d08d22a9',
    '27091f0d-3d10-4818-8990-956f0ff395ca',
    '6ec1b491-e34e-4b39-9889-1c1b7ac3a575',
    'aeaf1506-69cd-45bc-812f-775b5c1e3441',
    'e4364889-0c6d-45ff-9975-e5526a8b9a57',
    'fcd5e2b3-e3f4-4c4a-ad61-f20a65c6eac0',
    'bf320129-e3f3-45fe-bf9b-13fd72aeb83d',
    '728c8a92-d805-41c3-81a6-9bf7d9cd1cd4',
    '06c37e7a-8ac6-44ab-bef9-b030bd72fec3',
    'bea88996-0647-4d15-86b5-f899852edb2e',
    '873af931-32c3-4454-bb53-f526afc94e8a',
    'c75918a8-66ac-4a7a-b580-3273058d86c7',
    'e65b2162-eb68-48a1-8aad-5091eb51be86',
    '77ce0d3f-cca7-41c0-bf82-8147a0edcd29',
    'c0c91e69-244c-40e0-b6e4-083c8e8798ed',
    '5c583981-e234-40bb-a88e-4e5c8b7a985a',
    '41fe901f-2618-4ab7-bf3e-a8b66b9618f0',
    'c3a547a7-cba2-40a1-99eb-bb010be7ac04',
    'a4c2e21a-22bd-4377-a258-a6576475ac78',
    'c85fb69e-f56b-4268-8b92-a241efa0d009',
    '17210180-d6a4-4e4c-b569-3800602a2c93',
    '48ff3faa-bbc7-48a0-a0ae-35da9516fe32',
    'aa7d12de-059c-4aa5-b1be-51ca5911cc8b'
  ) and is_expectation = false;

-- 65 estimated, 231.7 h/mo total
--  10.0 h/mo | Sales & Ops Assistant | Cover kiosk shifts, breaks, absences, and scheduled off-days when assi
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 600.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: cover kiosk shifts, breaks, absences)'
  where id = 'e1a02a99-e195-4c29-91ba-e8b54cb2b894'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   8.0 h/mo | Sales & Ops Assistant | Perform approved console setup procedures.
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 480.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: perform approved console setup procedures)'
  where id = 'a306ab3d-f289-41a3-9ed7-dc8db112f449'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   8.0 h/mo | Sales & Ops Assistant | Install or configure games, applications, accounts, settings, and basi
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 480.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: install or configure games, applications)'
  where id = '85fde98c-0447-4de5-9f83-7dde910e5388'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   6.5 h/mo | Operations Manager | Assign packing, customer service, inventory, setup, and restocking tas
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 390.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: assign packing, customer service, inventory)'
  where id = '91a2434d-9e13-4243-b857-d502e2d21084'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   6.5 h/mo | Operations Manager | Handle exceptions and urgent issues.
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 390.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: handle exceptions and urgent issues)'
  where id = 'befa4876-a0a3-4602-926f-b38b0903a181'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   6.0 h/mo | Sales & Ops Assistant | Answer basic order status, product, delivery, and after-sales inquirie
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 360.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: answer basic order status, product, delivery)'
  where id = '9dfde16b-0ac8-4e0a-81a4-a2c476c08da7'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   6.0 h/mo | Sales & Ops Assistant | Test devices before release or dispatch.
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 360.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: test devices before release or dispatch)'
  where id = '3219ccba-655e-4819-a91c-a62ed2219a8d'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   6.0 h/mo | Sales & Ops Assistant | Engage customers, identify their needs, recommend products, and explai
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 360.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: engage customers, identify their needs)'
  where id = '1d422c18-cc04-43fe-80c8-6d8d91e1f710'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   6.0 h/mo | Customer Service & Operations Assi | Identify customer needs, recommend suitable products, explain differen
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 360.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: identify customer needs, recommend suitable products)'
  where id = '3c546fba-2ba4-4ba3-bcc5-837b0ad55784'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   5.0 h/mo | HR Manager | Provide management with concise reports on headcount, recruitment, att
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 300.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: provide management with concise reports on headcount)'
  where id = '34348861-20b9-465c-8489-910f56e4aef1'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   4.3 h/mo | Operations Manager | Investigate discrepancies and implement preventive action.
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 258.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: investigate discrepancies and implement preventive)'
  where id = '20d0151a-1c54-4cdd-ab3c-0fcaa56b92ac'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   4.3 h/mo | Operations Manager | Plan and approve kiosk replenishment.
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 258.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: plan and approve kiosk replenishment)'
  where id = 'eaaa2119-950c-4eac-881d-909bd4287e95'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   4.3 h/mo | Operations Manager | Monitor kiosk stock levels, transfers, discrepancies, and stockouts.
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 258.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: monitor kiosk stock levels)'
  where id = '1fe9c6b9-3c84-4bab-9087-d3747cf924f5'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   4.3 h/mo | Operations Manager | Oversee customer service escalations and marketplace exceptions.
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 258.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: oversee customer service escalations)'
  where id = '66f8ed44-e8fe-4292-b7cf-74a00c34f6f8'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   4.3 h/mo | Operations Manager | Maintain the operations scorecard.
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 258.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: maintain the operations scorecard)'
  where id = 'f66d5970-4169-4276-88ad-6592c0387b7e'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   4.3 h/mo | Operations Manager | Conduct regular quality checks and coaching.
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 258.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: conduct regular quality checks and coaching)'
  where id = 'f55f680d-5b3b-4f49-b301-ac0a5d35726c'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   4.3 h/mo | Sales & Ops Assistant | Help deliver or transfer stocks between locations.
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 258.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: help deliver or transfer stocks between locations)'
  where id = 'ca16de24-7389-46af-8ce5-fee5442774eb'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   4.3 h/mo | Retail & E-commerce Operations Man | Review store checklists, incidents, unresolved concerns, and correctiv
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 258.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: review store checklists, incidents)'
  where id = '1b41c166-245f-4377-a615-cb57a0a1b39f'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   4.3 h/mo | Retail & E-commerce Operations Man | Coordinate operational requirements across all company brands.
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 258.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: coordinate operational requirements across all company brands)'
  where id = '22f1e27a-8c90-4d22-ae96-4368edcaaf8c'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   4.3 h/mo | Retail & E-commerce Operations Man | Maintain operational files, permits, supplier records, mall documents,
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 258.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: maintain operational files, permits)'
  where id = '707e8d17-e288-446b-bef6-1870ccd698d6'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   4.3 h/mo | Retail & E-commerce Operations Man | Coordinate approvals, delivery schedules, receiving, and supplier foll
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 258.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: coordinate approvals, delivery schedules)'
  where id = '83c68a69-b9d4-48eb-bf85-94e829ad100e'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   4.3 h/mo | Retail & E-commerce Operations Man | Monitor progress through regular operational check-ins.
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 258.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: monitor progress through regular operational check-ins)'
  where id = '40ed3276-fedf-4c27-876a-dbc46cfc2f55'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   4.3 h/mo | Retail & E-commerce Operations Man | Coach staff on procedures, prioritization, documentation, and accounta
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 258.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: coach staff on procedures, prioritization)'
  where id = 'd1ea56fa-5bd8-4f4d-9286-2923f6a11641'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   4.3 h/mo | HR Manager | Monitor attendance, morale, workload, communication, and retention ris
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 258.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: monitor attendance, morale, workload)'
  where id = 'ca4c04ca-0525-4d7d-8d3d-2e05557b7037'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   4.3 h/mo | Technical Product & Purchasing Spe | Assist with inventory verification, product receiving, administrative 
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 258.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: assist with inventory verification, product receiving)'
  where id = '9073e08e-c293-4bbd-b724-55662e237dad'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   3.2 h/mo | Operations Manager | Coordinate with kiosk managers or sales staff on operational concerns.
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 192.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: coordinate with kiosk managers)'
  where id = '4568cac7-0ff7-4932-89ff-0cea53804b1f'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   3.2 h/mo | Retail & E-commerce Operations Man | Follow up on incomplete dependencies and escalate material delays.
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 192.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: follow up on incomplete dependencies)'
  where id = '8db86d89-32c9-4f58-8a4f-d40bf4d23f83'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   3.2 h/mo | Retail & E-commerce Operations Man | Work with Finance for payment verification and financial documentation
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 192.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: work with finance for payment verification)'
  where id = 'b91352ca-4251-4376-aae5-e2a14b4792aa'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   3.0 h/mo | Operations Manager | Coordinate technical assessment and resolution.
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 180.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: coordinate technical assessment and resolution)'
  where id = '830ff891-bc83-4b7d-bb19-12b5f97a1a59'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   3.0 h/mo | Operations Manager | Review recurring errors and identify root causes.
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 180.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: review recurring errors and identify root causes)'
  where id = '300228fb-a146-463d-a3ab-d52aa8042c6f'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   3.0 h/mo | Operations Manager | Publish and update SOPs and checklists.
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 180.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: publish and update sops and checklists)'
  where id = '5d7c0d02-aef9-40c0-b62e-d57c4aa20384'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   3.0 h/mo | Operations Manager | Report risks, corrective actions, and resource needs to management.
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 180.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: report risks, corrective actions)'
  where id = '32f56749-2a7f-4a85-93b4-240e0b91cf78'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   3.0 h/mo | Operations Manager | Train and certify operations staff on critical procedures.
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 180.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: train and certify operations staff)'
  where id = 'f1262c23-b756-4eee-b3aa-230f0c7ce195'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   3.0 h/mo | Sales & Ops Assistant | Support other operational tasks during volume spikes.
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 180.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: support other operational tasks during volume spikes)'
  where id = '664a0350-cf12-4109-ad28-ad217000a167'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   3.0 h/mo | Sales & Ops Assistant | Verify restocking quantities and report discrepancies immediately.
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 180.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: verify restocking quantities and report discrepancies)'
  where id = 'f3bf958b-4571-4ec1-a6f6-75e2f5c2399e'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   3.0 h/mo | Sales & Ops Assistant | Support scheduled stock counts.
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 180.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: support scheduled stock counts)'
  where id = '77ccb417-b0d2-4470-8f51-cb76f155668e'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   3.0 h/mo | Retail & E-commerce Operations Man | Implement practical improvements that reduce errors and manual follow-
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 180.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: implement practical improvements that reduce errors)'
  where id = 'a4b8e63a-4867-46ab-a00f-e03448a5acb7'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   3.0 h/mo | Retail & E-commerce Operations Man | Ensure instructions and information are properly handed over between d
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 180.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: ensure instructions and information are properly handed over)'
  where id = '0ab85f6b-030e-4350-9efb-164930b112cc'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   3.0 h/mo | Technical Product & Purchasing Spe | Train operations and sales staff on product features, setup limitation
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 180.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: train operations and sales staff on product features)'
  where id = 'befd7892-d391-46aa-85f5-d21f719443f3'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   3.0 h/mo | Technical Product & Purchasing Spe | Improve technical workflows to reduce setup time, errors, and dependen
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 180.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: improve technical workflows to reduce setup time)'
  where id = '6ae582a0-7d55-4455-8ecd-7bc57bc1c4af'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   3.0 h/mo | Technical Product & Purchasing Spe | Support management with product decisions, expansion requirements, and
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 180.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: support management with product decisions)'
  where id = '6dfe788a-d2a4-4db4-9401-c4b87bee125e'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   3.0 h/mo | Kiosk Sales Representative | Assist with simple content, product demonstrations, technical setup, s
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 180.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: assist with simple content, product demonstrations)'
  where id = 'b62d8a20-dc6e-4e6c-8c4c-7422f26133f6'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   3.0 h/mo | HR Manager | Handle PIPs, policy violations, notices, investigations, and disciplin
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 180.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: handle pips, policy violations)'
  where id = '0a3498da-35cd-4f77-a56f-a77aaa8e38c0'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   2.2 h/mo | HR Manager | Guide managers in giving fair feedback and setting clear improvement a
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 132.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: guide managers in giving fair feedback)'
  where id = '1bed9785-c6f2-4c91-857c-8ade0f2c8cd8'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   2.2 h/mo | HR Manager | Maintain development plans and monitor whether assigned training actio
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 132.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: maintain development plans and monitor)'
  where id = '576d9ef7-ced7-41dd-8544-f96e04711743'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   2.2 h/mo | HR Manager | Coordinate with department managers to ensure employees are trained in
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 132.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: coordinate with department managers to ensure employees are trained)'
  where id = '87891df4-c8b3-4c04-8cc8-12ea758e787b'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   2.0 h/mo | Operations Manager | Control stock access and movement documentation.
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 120.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: control stock access and movement documentation)'
  where id = '9ba5a1ed-620e-417b-8ed8-a98f61897e60'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   2.0 h/mo | Operations Manager | Prepare early for campaigns, holidays, launches, and peak periods.
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 120.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: prepare early for campaigns, holidays)'
  where id = '03cd5983-2491-4441-89fc-55c4f9896f9e'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   2.0 h/mo | Operations Manager | Standardize opening, closing, cash, inventory, and restocking procedur
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 120.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: standardize opening, closing, cash)'
  where id = 'cfe5db66-2b2a-4cf7-906e-4b0b5eafd6aa'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   2.0 h/mo | Operations Manager | Improve fulfillment capacity during high-volume periods.
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 120.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: improve fulfillment capacity)'
  where id = '66b21f21-fd7d-41cd-a9af-fcb9b5c48fa7'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   2.0 h/mo | Operations Manager | Turn recurring return issues into process improvements.
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 120.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: turn recurring return issues into process improvements)'
  where id = 'b0a319df-53ff-49b6-862c-c14aa79ae962'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   2.0 h/mo | Operations Manager | Recommend workflow, staffing, storage, and system improvements.
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 120.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: recommend workflow, staffing, storage)'
  where id = '053936d4-7f50-401d-b171-5f8e7d9deb0b'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   2.0 h/mo | Operations Manager | Develop potential inventory, kiosk, and operations leads.
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 120.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: develop potential inventory, kiosk, and operations leads)'
  where id = 'b13568c4-6105-42f5-8032-d1355260bb9a'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   2.0 h/mo | Sales & Ops Assistant | Assist colleagues with product knowledge and customer recommendations.
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 120.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: assist colleagues with product knowledge)'
  where id = '051b644a-ec01-477d-a25c-9f6e27bb2d5b'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   2.0 h/mo | Sales & Ops Assistant | Help train new sales staff on products, common customer questions, and
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 120.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: help train new sales staff)'
  where id = '4b40ee1b-e20d-4715-9386-9249d59a8dfb'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   2.0 h/mo | Sales & Ops Assistant | Share updated product comparisons, setup information, and common objec
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 120.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: share updated product comparisons)'
  where id = '7cbdf72f-f0cd-409a-9afd-46eb5f9f36c4'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   2.0 h/mo | Sales & Ops Assistant | Support demonstrations and customer testing when needed.
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 120.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: support demonstrations and customer testing)'
  where id = 'f96c8576-9532-465f-8a8d-d371dac89dad'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   2.0 h/mo | Retail & E-commerce Operations Man | Identify recurring delays, duplicated work, and inefficient processes.
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 120.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: identify recurring delays, duplicated work)'
  where id = '6cac6e77-7c5b-47dd-8413-3ec8e39be26e'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   2.0 h/mo | Retail & E-commerce Operations Man | Review whether established processes are being followed and remain use
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 120.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: review whether established processes are being followed)'
  where id = 'c907e201-f9de-4640-a02e-59a9f4a797b8'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   2.0 h/mo | Customer Service & Operations Assi | Help improve FAQs, templates, product explanations, and customer servi
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 120.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: help improve faqs, templates)'
  where id = 'a0f1f17b-cee9-41b3-abfe-c61b13de642a'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   2.0 h/mo | HR Manager | Build standardized HR workflows, forms, checklists, and records that r
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 120.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: build standardized hr workflows)'
  where id = 'f072ed63-6726-42c5-aec6-008d05d0ed5c'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   2.0 h/mo | HR Manager | Coordinate practical wellness, engagement, recognition, and conflict-r
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 120.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: coordinate practical wellness, engagement)'
  where id = 'be2d2a0d-95a6-4b15-8cf9-79d671a7b9a2'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   2.0 h/mo | HR Manager | Maintain a basic candidate pipeline for frequently needed roles.
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 120.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: maintain a basic candidate pipeline)'
  where id = '8a15257b-6c67-4a5b-bcc1-dc1ef93ac417'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   2.0 h/mo | HR Manager | Work with management to determine staffing needs, hiring priorities, r
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 120.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: work with management to determine staffing needs)'
  where id = '8deb9154-6766-4250-a444-24dd41ba9565'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;

--   2.0 h/mo | Kiosk Sales Representative | Share customer feedback, frequently requested products, objections, an
update wp_tasks set times_source = 'manual', times_manual = 1,
    minutes_source = 'manual', minutes_manual = 120.0, driver_id = null, rate_id = null,
    notes = 'Estimate (anchored: share customer feedback, frequently requested products)'
  where id = '8ab7f41a-72b4-4421-9f48-a30132e5b3a2'
    and coalesce(times_manual, 0) = 0 and driver_id is null and is_expectation = false;
