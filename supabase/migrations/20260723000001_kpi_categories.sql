-- Categorise the KPI library, and stop each row printing itself twice.
--
-- All 58 KPIs sat under "Uncategorized", so the library was one flat wall with
-- no way to find anything. Categories are assigned from what each KPI actually
-- measures:
--
--   Quality & Accuracy          12   error and rework rates
--   Timeliness & Delivery       12   on-time / within-target measures
--   Compliance & Documentation   8   checklists, records, SOPs
--   People & Development         9   training, reviews, onboarding
--   Customer & Sales             8   revenue, conversion, service quality
--   Inventory & Stock            5   availability, counts, discrepancies
--   Process & Improvement        4   improvements and project execution
--
-- Every KPI maps to exactly one; none was left over and none invented.
--
-- ALSO: every row had `description` set to the same sentence as
-- `measurement_unit`, so the screen rendered it twice — once as a chip beside
-- the name and again underneath. The duplicate description is cleared; the
-- measurement stays, since that is the one that says how the KPI is computed.
-- The UI is being fixed to stop showing both regardless, but leaving 58 exact
-- duplicates in the data would just wait to resurface somewhere else.

-- Compliance & Documentation (8)
update kpis set category = 'Compliance & Documentation'
  where id in (
    '4eca32ff-35d1-4df3-9fe6-b7a54000a03c',
    '9a2305b7-51ff-405f-b881-6c25653ca603',
    '16d6b70b-6039-415f-abfe-e34b8191f29e',
    '8b991fe6-8567-490b-89bb-da5d276d8c17',
    '90f1bbd7-2ed3-4231-91e6-f5d9ba12e1e8',
    'f038d913-b4ca-41c7-837c-64e03448530d',
    '1002fc51-86e0-4019-9609-9ed36a54cc4c',
    '746d8862-11e7-4bdd-9573-1a11e980be01'
  ) and category is null;

-- Customer & Sales (8)
update kpis set category = 'Customer & Sales'
  where id in (
    'd50bfd05-914c-431b-9357-3ef1f5019332',
    '12b517e1-188b-4d1e-b1b3-1f8066712309',
    '8aaac008-c61d-48f5-8668-a2f9e06f7d0c',
    'c26f6492-2db6-4852-b38b-34aa46aa11ed',
    '4d2816a2-6e6d-417d-b6b3-0c9e3da207b9',
    '108d414b-23ff-4dbc-b9fe-016c29c09367',
    'b29cd037-88b7-45c6-985a-11135452e456',
    '07df1ffe-e443-4339-8f76-f839ca761a4c'
  ) and category is null;

-- Inventory & Stock (5)
update kpis set category = 'Inventory & Stock'
  where id in (
    'f0ac9c28-9e5f-4bc6-9b05-fe6526d12f17',
    '17a417b2-6286-4fff-b0c9-e00c3ebadce9',
    '5c67907b-8198-4f13-890a-6b8145380471',
    '3da4d137-6302-4b87-92dd-903473912269',
    '8e1e149d-6d2f-48f9-aa78-686207b6b672'
  ) and category is null;

-- People & Development (9)
update kpis set category = 'People & Development'
  where id in (
    '83fd7777-7b6c-4c91-bf3a-e3a0fa377126',
    '3b6d0e64-4d33-41c8-9530-bb6b34cd74a3',
    'fd519aa1-1aaf-42cd-b74a-61a5ca224dcf',
    '56d81e52-c540-41a2-bc03-58bce7a1604f',
    '06e539f2-b358-4a0d-a8aa-f39a508c0720',
    'c06072e8-c2d1-4369-ae80-f88cbf4a894d',
    '2df1f96f-5633-4bfb-8824-43a64e1d078b',
    'ae44aa6c-4491-4ea7-961b-c3fe1c02d24f',
    'be92c46b-33ab-411c-b88e-3d496671094d'
  ) and category is null;

-- Process & Improvement (4)
update kpis set category = 'Process & Improvement'
  where id in (
    '64be7ed4-e1e7-43b6-9a45-fd9f9fd86430',
    '373c6de0-0019-45ed-a422-c33140692629',
    '83fe579e-cbc3-41d7-a224-da48bb3c6e63',
    '296633b7-0d20-456d-872c-6abe2a8bca5a'
  ) and category is null;

-- Quality & Accuracy (12)
update kpis set category = 'Quality & Accuracy'
  where id in (
    'ea38b55b-79c7-488a-995a-00a392bd69c6',
    'c0ebd0ba-5088-489d-809d-8b94306946a1',
    '37dfb84e-cb1e-47b3-be66-c6bcc2bcdff5',
    'ab97a649-d98a-4f0a-8dbf-d99e5d81f2dd',
    '8c3f28cb-4def-4010-9179-f4b216254616',
    '98370e1b-36e4-4192-b595-2bfc34aac6a0',
    'bc9b541b-20e4-42d1-8732-6b5a707b7223',
    '56b3d77c-0efc-479a-be0a-6158e5c5e553',
    'd90079e2-b351-42f2-9482-cf2cee4ace6f',
    '40d10f72-c3c0-4f7c-b2df-59b4a6b06610',
    '86bb2f73-3f80-4b22-9a2b-c8e0624d7919',
    '0d2cb1a8-b7af-419e-b294-13758f11ddf6'
  ) and category is null;

-- Timeliness & Delivery (12)
update kpis set category = 'Timeliness & Delivery'
  where id in (
    'f0e05ec2-4bbe-4656-ba79-fbcf9b92e157',
    'e9d48df0-4caf-4112-a6b4-69f023ae04a0',
    '33f0dc50-6281-4250-8616-d168f225f454',
    '70fb97fc-52d0-4b50-b07d-5124454477bf',
    '24317847-c432-417c-b698-afc4558c5c48',
    '53c3e1dd-1a03-4e68-9f5b-7bc0357a4bdf',
    'a7be20ac-57db-4074-9fa1-4760a10c911c',
    '69ee5cb8-1e60-42c5-890a-f32d9599be51',
    '6531b24a-6c63-42e3-a1cb-77ce8573b095',
    '2a9f615a-18cc-4cdb-84b9-a8ca0859df34',
    'f910b33b-e662-4893-88be-1c6b647572a6',
    '874819cd-13aa-4627-b4c5-7bcb67258873'
  ) and category is null;

-- Clear descriptions that merely repeat the measurement.
update kpis set description = null
  where description is not null
    and measurement_unit is not null
    and lower(trim(description)) = lower(trim(measurement_unit));