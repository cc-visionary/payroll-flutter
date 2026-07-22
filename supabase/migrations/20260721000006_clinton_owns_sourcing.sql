-- Give Clinton the sourcing work the capacity model already says he owns.
--
-- luxium_capacity_model.xlsx assigns exactly seven tasks to a named person,
-- all to "Clinton Xu", and all of them sourcing/supplier/market work:
--
--   Supplier discovery & canvassing            9.0 h
--   Scan market / spot products worth importing 6.5 h
--   Supplier vetting / qualification            6.0 h
--   Vet new product / brand opportunities       4.0 h
--   PO placement / order confirmation           3.0 h
--   Supplier payment / remittance               2.5 h
--   Kill / continue review of test brands       1.0 h
--
-- Six of those correspond to responsibilities on the Technical Product &
-- Purchasing card, which currently derive to Marvin Ong at 138% of capacity.
-- Setting an explicit owner moves them to Clinton and takes the load off a
-- person who is measurably over. (The seventh, supplier payment, is finance
-- work and now lives on the new COO card.)
--
-- This does NOT change the card: the responsibilities stay on Technical
-- Product & Purchasing, where they belong as a description of the role. Only
-- who carries the hours changes -- which is exactly what owner_employee_id is
-- for.

update wp_tasks set owner_employee_id = '22222222-2222-2222-2222-000000000013'
  where id = '4c64be1f-0a28-4e43-ade5-e4568daf14af' and owner_employee_id is null;
update wp_tasks set owner_employee_id = '22222222-2222-2222-2222-000000000013'
  where id = '772a5e47-f08b-4b9b-9615-b758daddcdf6' and owner_employee_id is null;
update wp_tasks set owner_employee_id = '22222222-2222-2222-2222-000000000013'
  where id = '943508d7-5d4f-43fb-a25c-29fc39b795e0' and owner_employee_id is null;
update wp_tasks set owner_employee_id = '22222222-2222-2222-2222-000000000013'
  where id = 'b539f8d5-6132-4f4f-95ab-0aff3b491662' and owner_employee_id is null;
update wp_tasks set owner_employee_id = '22222222-2222-2222-2222-000000000013'
  where id = '9fe25417-1006-4ed7-a9cb-18e6f07aa634' and owner_employee_id is null;
update wp_tasks set owner_employee_id = '22222222-2222-2222-2222-000000000013'
  where id = 'c6832561-c6ab-473e-8c5e-dd54089f39de' and owner_employee_id is null;