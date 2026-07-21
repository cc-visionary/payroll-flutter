-- Cost the role-card responsibilities from the capacity model.
--
-- The 164 promoted responsibilities carried the org structure but no effort
-- numbers, so every person read 0% load. The 118 legacy rows imported from
-- luxium_capacity_model.xlsx carry REAL numbers (798.6 h/mo) but have neither
-- an owner nor a role card, which makes them UNATTRIBUTED in wp_person_load --
-- they contribute to nobody. This migration transfers that costing onto the
-- responsibilities it describes, so load reflects the model the business
-- already authored instead of invented estimates.
--
-- Mapping: 105 of 118 legacy rows map onto 68 responsibilities (several legacy
-- rows can describe one responsibility, so their hours are summed). The 13
-- unmapped rows are finance/bookkeeping work -- there is no Finance role card
-- among the 7, and inventing a home for them would load somebody with work
-- they do not do. They stay unattributed on purpose.
--
-- Where any contributing row was volume-driven, the driver and factor are kept
-- and minutes-each is solved so the total still matches: a driver-linked row
-- responds to the growth multiplier, a manual one is flat forever. 10 of the
-- 68 end up driver-linked.
--
-- IDEMPOTENT: each update is guarded to rows that are still uncosted, so a
-- re-run cannot overwrite an estimate HR has since corrected by hand.
--
-- The legacy rows are left in place (still unattributed, contributing 0) as a
-- reference. Delete them from the Tasks tab once these numbers are trusted.

-- 80.0 h/mo | Technical Product & Purchasing Specialist | Lead the flashing, installation, configuration, testing, and final
--    <- SD card flashing — OS + games
update wp_tasks set times_source = 'driver', times_manual = null, driver_id = 'c28658f4-73bc-4c6d-8aa0-cd240fed55b0', driver_factor = 1, minutes_source = 'manual', minutes_manual = 12.0, rate_id = null, node_id = 'b2788e46-7bd8-46c8-bd1f-4f7aed62cdad', cadence = 'Per-unit (volume)'
  where id = '42ab0b7e-9250-4d28-a272-f403f14e27bd'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 65.8 h/mo | Sales & Ops Assistant | Pack, label, check, and dispatch online orders.
--    <- Pick / pack / label orders
--    <- Video record packing + upload
--    <- Dispatch batching & courier handoff
update wp_tasks set times_source = 'driver', times_manual = null, driver_id = '8a557173-3fc9-42fd-a23b-1fadefa4b8cb', driver_factor = 1, minutes_source = 'manual', minutes_manual = 13.1667, rate_id = null, node_id = '1bfefe84-a083-4022-8be8-8ee8b71c4be4', cadence = 'Per-unit (volume)'
  where id = 'b3236801-6767-4be0-8c48-c443f7ea5eaa'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 45.0 h/mo | Kiosk Sales Representative | Complete opening and closing procedures, including kiosk readiness
--    <- Store opening routine (setup, float, systems)
--    <- Store closing routine (Z-read, lockup)
--    <- Cash drawer count — opening float
--    <- Cash drawer count — closing / Z-reading
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 2700.0, rate_id = null, node_id = '70d3be0e-547b-4fba-b75d-84b492cab363', cadence = 'Monthly'
  where id = 'dbd3fac0-faf2-43fb-bc88-4f625e13652e'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 40.0 h/mo | Customer Service & Operations Assistant | Respond to customer inquiries across marketplaces, social media, a
--    <- Pre-sales inquiries & order status
update wp_tasks set times_source = 'driver', times_manual = null, driver_id = 'acdf9c9c-9ee1-4489-a6e4-ac431193c729', driver_factor = 1, minutes_source = 'manual', minutes_manual = 4.0, rate_id = null, node_id = 'ab85a426-abe7-44fc-9072-28163ae6ab82', cadence = 'Per-unit (volume)'
  where id = 'b91702a5-b250-4c25-9f9f-efd1c371bb76'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 40.0 h/mo | Kiosk Sales Representative | Welcome customers, understand their needs, recommend suitable prod
--    <- In-store demo / customer education
update wp_tasks set times_source = 'driver', times_manual = null, driver_id = '8a557173-3fc9-42fd-a23b-1fadefa4b8cb', driver_factor = 1, minutes_source = 'manual', minutes_manual = 8.0, rate_id = null, node_id = '70d3be0e-547b-4fba-b75d-84b492cab363', cadence = 'Per-unit (volume)'
  where id = 'f905f601-0212-4758-98c1-058144cc4eb1'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 33.0 h/mo | Sales & Ops Assistant | Assist with receiving, sorting, storage, and general warehouse wor
--    <- Repack / insert / retail prep
--    <- Packing station setup / cleanup / supplies
--    <- Packing material prep (bubble wrap, pouches)
update wp_tasks set times_source = 'driver', times_manual = null, driver_id = 'c28658f4-73bc-4c6d-8aa0-cd240fed55b0', driver_factor = 1, minutes_source = 'manual', minutes_manual = 4.9495, rate_id = null, node_id = 'b2788e46-7bd8-46c8-bd1f-4f7aed62cdad', cadence = 'Per-unit (volume)'
  where id = '8f7b28b0-1cc4-430a-8527-dfec1bd0544f'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 29.1 h/mo | Kiosk Sales Representative | Process payments and receipts accurately, maintain supporting reco
--    <- Daily sales / cash reconciliation
--    <- Invoice / receipt issuance compliance
--    <- POS transaction processing
--    <- Petty cash / change fund management
--    <- Store BIR receipt / invoice compliance
update wp_tasks set times_source = 'driver', times_manual = null, driver_id = '97c9d7a8-37d1-4f64-b350-2d6846e84ffc', driver_factor = 1, minutes_source = 'manual', minutes_manual = 8.7238, rate_id = null, node_id = '70d3be0e-547b-4fba-b75d-84b492cab363', cadence = 'Per-unit (volume)'
  where id = '3cec0952-e115-47f7-9e62-6070e98a3984'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 26.7 h/mo | Technical Product & Purchasing Specialist | Ensure completed devices meet setup, quality, and documentation re
--    <- Device functional testing
update wp_tasks set times_source = 'driver', times_manual = null, driver_id = 'c28658f4-73bc-4c6d-8aa0-cd240fed55b0', driver_factor = 1, minutes_source = 'manual', minutes_manual = 4.0, rate_id = null, node_id = 'b2788e46-7bd8-46c8-bd1f-4f7aed62cdad', cadence = 'Per-unit (volume)'
  where id = 'd3741d81-140d-4e3a-8849-3793eaf9cd16'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 25.0 h/mo | Technical Product & Purchasing Specialist | Compile and maintain approved games, emulators, firmware, artwork,
--    <- Build master image for a NEW model
--    <- Curate game set per model
--    <- Firmware / OS version updates
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 1500.0, rate_id = null, node_id = 'b2788e46-7bd8-46c8-bd1f-4f7aed62cdad', cadence = 'Monthly'
  where id = '7528fc03-5631-4645-a943-1f54db3a7c54'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 17.7 h/mo | Technical Product & Purchasing Specialist | Coordinate with management and operations regarding purchase quant
--    <- Supplier relationship maintenance
--    <- PO placement / order confirmation
--    <- Freight forwarder coordination
--    <- Customs / duties / broker liaison
--    <- Shipment tracking & ETA chasing
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 1059.9, rate_id = null, node_id = 'e6e1ca57-8d21-4010-a4db-53eacedba832', cadence = 'Monthly'
  where id = '943508d7-5d4f-43fb-a25c-29fc39b795e0'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 15.0 h/mo | Technical Product & Purchasing Specialist | Source and compare products, components, technical tools, packagin
--    <- Supplier discovery & canvassing
--    <- Supplier vetting / qualification
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 900.0, rate_id = null, node_id = 'e6e1ca57-8d21-4010-a4db-53eacedba832', cadence = 'Monthly'
  where id = '4c64be1f-0a28-4e43-ade5-e4568daf14af'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 14.7 h/mo | Kiosk Sales Representative | Keep the kiosk secure, organized, and compliant with mall and comp
--    <- Store cleanliness & housekeeping
--    <- Security / CCTV review
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 879.9, rate_id = null, node_id = '70d3be0e-547b-4fba-b75d-84b492cab363', cadence = 'Monthly'
  where id = '837df617-a12d-4e6e-94a3-ca573b7672e0'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 13.9 h/mo | Operations Manager | Schedule stock counts and approve corrections.
--    <- Cycle counts (top SKUs)
--    <- Full physical inventory count
--    <- Weekly cycle count
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 836.4, rate_id = null, node_id = '1dce5488-ba91-438f-b775-043591d3fb42', cadence = 'Monthly'
  where id = '49f2eee0-bcae-4e2f-857e-64a4fa7da43f'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 13.5 h/mo | Operations Manager | Enforce receiving, put-away, transfer, release, return, and adjust
--    <- Goods-in QC against PO
--    <- Put-away / labeling to storage
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 810.0, rate_id = null, node_id = 'b2788e46-7bd8-46c8-bd1f-4f7aed62cdad', cadence = 'Monthly'
  where id = '366b77f4-78cb-42ce-aa5f-a14ea1a577ed'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 12.2 h/mo | Technical Product & Purchasing Specialist | Request quotations, verify specifications, prepare recommendations
--    <- Quote comparison & supplier selection
--    <- Price negotiation
--    <- Quotations & volume pricing
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 734.85, rate_id = null, node_id = 'e6e1ca57-8d21-4010-a4db-53eacedba832', cadence = 'Monthly'
  where id = '772a5e47-f08b-4b9b-9615-b758daddcdf6'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 12.0 h/mo | HR Manager | Monitor compliance deadlines and ensure HR records remain complete
--    <- BIR 1601-C filing
--    <- SSS / PhilHealth / Pag-IBIG remittance
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 720.0, rate_id = null, node_id = 'f2b6d507-0d58-4cde-86c9-719f012883f1', cadence = 'Monthly'
  where id = '8dd27470-3078-42a8-8c2a-3d92c4adad41'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 10.5 h/mo | Retail & E-commerce Operations Manager | Consolidate timelines for launches, events, campaigns, and store p
--    <- Promo / campaign setup per platform
--    <- Paid ads setup & monitoring
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 629.7, rate_id = null, node_id = '3f6bb29f-d094-48e3-974a-12f414dca464', cadence = 'Monthly'
  where id = 'c890ea0f-ba7e-4438-bb57-1b05eb786742'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 10.0 h/mo | Technical Product & Purchasing Specialist | Diagnose common hardware, software, firmware, storage, and configu
--    <- Device repair service
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 600.0, rate_id = null, node_id = '268146b8-012d-41bc-88c1-80b5423d83cb', cadence = 'Monthly'
  where id = '01cf207a-41f5-4d10-941d-78c96c841e32'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 10.0 h/mo | HR Manager | Manage employee files, contracts, attendance records, leave, gover
--    <- Payroll run
--    <- Payroll data prep & DTR review
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 600.0, rate_id = null, node_id = 'd7d93e67-b69f-482e-ba54-7afae920d35e', cadence = 'Monthly'
  where id = '81feb474-3f04-4bae-a169-1d00f3677f1a'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 10.0 h/mo | Sales & Ops Assistant | Prepare and release kiosk replenishment.
--    <- Store restock trip from warehouse
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 600.0, rate_id = null, node_id = '70d3be0e-547b-4fba-b75d-84b492cab363', cadence = 'Monthly'
  where id = '21628744-3374-4e64-beea-f42123992b4c'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 9.7 h/mo | Kiosk Sales Representative | Maintain a clean, complete, correctly priced, and presentable prod
--    <- Visual merchandising / display refresh
--    <- Price tag / label updates
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 584.55, rate_id = null, node_id = '70d3be0e-547b-4fba-b75d-84b492cab363', cadence = 'Monthly'
  where id = '05fb1f3c-da8f-48df-9353-e02f3e6c7f75'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 8.2 h/mo | Retail & E-commerce Operations Manager | Maintain listing standards for prices, variants, images, descripti
--    <- Copywriting / SEO per listing
--    <- Pricing review vs competitors
--    <- Wholesale price list maintenance
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 494.25, rate_id = null, node_id = '3f6bb29f-d094-48e3-974a-12f414dca464', cadence = 'Monthly'
  where id = '7eb38f84-c965-4ee7-9916-397b254a3ff5'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 8.0 h/mo | Customer Service & Operations Assistant | Create simple product videos, photos, captions, pubmats, and promo
--    <- Pubmat / content creation
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 480.0, rate_id = null, node_id = '4698d876-f4a6-4b79-8680-98478d213396', cadence = 'Monthly'
  where id = 'd8893e6f-3675-4bcf-8f1a-18a19ec2055a'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 8.0 h/mo | Sales & Ops Assistant | Sell through approved online channels when assigned or voluntarily
--    <- Live selling sessions
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 480.0, rate_id = null, node_id = '4698d876-f4a6-4b79-8680-98478d213396', cadence = 'Monthly'
  where id = 'f5595a46-187e-4e10-b7fc-4996def613b8'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 7.5 h/mo | Operations Manager | Own inventory accuracy across warehouse, online channels, and kios
--    <- Daily count — high-value items
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 450.0, rate_id = null, node_id = '70d3be0e-547b-4fba-b75d-84b492cab363', cadence = 'Monthly'
  where id = 'bc066fb9-c820-4b44-9b5d-55b2378951e2'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 7.5 h/mo | Kiosk Sales Representative | Record sales, transfers, replenishment, reservations, and other st
--    <- Store sales reporting to HQ
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 450.0, rate_id = null, node_id = '70d3be0e-547b-4fba-b75d-84b492cab363', cadence = 'Monthly'
  where id = 'f717d716-8560-4d2e-a044-0a3393ee7eff'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 6.7 h/mo | Retail & E-commerce Operations Manager | Coordinate listing creation and updates across marketplaces.
--    <- New SKU listing creation (all platforms)
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 400.0, rate_id = null, node_id = '3f6bb29f-d094-48e3-974a-12f414dca464', cadence = 'Monthly'
  where id = '5369e6fc-7737-4cb2-ae94-e16c73d538f2'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 6.5 h/mo | Technical Product & Purchasing Specialist | Research new consoles, accessories, software, suppliers, and marke
--    <- Scan market / spot products worth importing
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 389.7, rate_id = null, node_id = 'e6e1ca57-8d21-4010-a4db-53eacedba832', cadence = 'Monthly'
  where id = 'b539f8d5-6132-4f4f-95ab-0aff3b491662'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 6.5 h/mo | Customer Service & Operations Assistant | Assist customers who inquire through Facebook, Instagram, TikTok, 
--    <- Community / group engagement
--    <- Loyalty / community management
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 389.7, rate_id = null, node_id = '4698d876-f4a6-4b79-8680-98478d213396', cadence = 'Monthly'
  where id = '3c178adc-5df2-49dd-8b5e-52c4073e1720'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 6.5 h/mo | Operations Manager | Maintain reorder points, safety stock, and target stock levels.
--    <- Reorder point / stock cover review
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 389.7, rate_id = null, node_id = '1dce5488-ba91-438f-b775-043591d3fb42', cadence = 'Monthly'
  where id = '98d1f818-816e-4305-9b9e-7a83e32e87a7'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 6.3 h/mo | Operations Manager | Identify slow-moving, overstocked, and at-risk products.
--    <- Slow-mover / ageing stock review
--    <- Liquidation execution (Blindbox / Havit)
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 379.8, rate_id = null, node_id = '1dce5488-ba91-438f-b775-043591d3fb42', cadence = 'Monthly'
  where id = '3b051313-bdcb-4718-9903-230a423e08eb'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 6.0 h/mo | Customer Service & Operations Assistant | Produce content for launches, promotions, restocks, customer educa
--    <- Product photography / asset creation
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 360.0, rate_id = null, node_id = '3f6bb29f-d094-48e3-974a-12f414dca464', cadence = 'Monthly'
  where id = '72185106-be0a-46dd-9007-53cbc9764378'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 5.2 h/mo | Customer Service & Operations Assistant | Follow up on qualified inquiries without spamming or pressuring cu
--    <- Abandoned cart / lead follow-up
--    <- Repeat-buy / winback campaign
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 314.85, rate_id = null, node_id = 'ab85a426-abe7-44fc-9072-28163ae6ab82', cadence = 'Monthly'
  where id = '0992b5b5-e6fb-4d41-b31f-a2f81830c892'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 5.2 h/mo | Customer Service & Operations Assistant | Handle order status, product questions, availability, delivery, re
--    <- Customer status updates on returns
--    <- Post-purchase follow-up
update wp_tasks set times_source = 'driver', times_manual = null, driver_id = 'bdce2d38-7c22-493b-9c12-e8ca797f2f9c', driver_factor = 1, minutes_source = 'manual', minutes_manual = 20.99, rate_id = null, node_id = '268146b8-012d-41bc-88c1-80b5423d83cb', cadence = 'Per-unit (volume)'
  where id = 'c1aaef8c-09ae-4428-8093-092d7d076103'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 5.0 h/mo | Kiosk Sales Representative | Record customer inquiries, reservations, and follow-ups when requi
--    <- Foot traffic / conversion logging
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 300.0, rate_id = null, node_id = '70d3be0e-547b-4fba-b75d-84b492cab363', cadence = 'Monthly'
  where id = '196192c7-3ed8-4ba3-ab62-3c9e01e6047b'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 4.3 h/mo | Retail & E-commerce Operations Manager | Audit listings for errors, missing information, duplicates, and pl
--    <- Shopify site / theme maintenance
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 259.8, rate_id = null, node_id = '3f6bb29f-d094-48e3-974a-12f414dca464', cadence = 'Monthly'
  where id = 'e5906668-52a6-4e14-9097-51e379ea6af8'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 4.3 h/mo | Customer Service & Operations Assistant | Assist with basic editing, posting preparation, and content schedu
--    <- Social posting & scheduling
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 259.8, rate_id = null, node_id = '4698d876-f4a6-4b79-8680-98478d213396', cadence = 'Monthly'
  where id = 'cc7d261c-1087-4821-b224-2b6a93cb69e0'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 4.3 h/mo | Retail & E-commerce Operations Manager | Create and maintain operational trackers, templates, checklists, a
--    <- Consolidate sales data across all channels
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 259.8, rate_id = null, node_id = '1dce5488-ba91-438f-b775-043591d3fb42', cadence = 'Monthly'
  where id = 'f0a59614-98ed-464e-8c2b-a4074ef83231'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 4.0 h/mo | Technical Product & Purchasing Specialist | Evaluate specifications, pricing, performance, compatibility, defe
--    <- Vet new product / brand opportunities
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 240.0, rate_id = null, node_id = 'c58c198f-26db-4c50-b4ae-77c6d504fdeb', cadence = 'Monthly'
  where id = '9fe25417-1006-4ed7-a9cb-18e6f07aa634'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 4.0 h/mo | Retail & E-commerce Operations Manager | Maintain a master tracker of products, platforms, listing status, 
--    <- Account management
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 240.0, rate_id = null, node_id = '8afaf628-d344-4c6f-ba8f-a8f344e89979', cadence = 'Monthly'
  where id = '75daa30f-c000-4a09-b3ee-611ebff03d55'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 4.0 h/mo | Operations Manager | Ensure orders are processed accurately and within cutoff.
--    <- Bulk order processing & dispatch
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 240.0, rate_id = null, node_id = '8afaf628-d344-4c6f-ba8f-a8f344e89979', cadence = 'Monthly'
  where id = 'e0aabece-957a-4f50-90ba-fe7a6a3f6e5f'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 4.0 h/mo | Operations Manager | Review sales velocity, current stock, incoming supply, and lead ti
--    <- Demand forecast per SKU
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 240.0, rate_id = null, node_id = '1dce5488-ba91-438f-b775-043591d3fb42', cadence = 'Monthly'
  where id = '57fbec26-4a70-4fac-9fed-8382f89114c6'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 4.0 h/mo | Operations Manager | Prepare regular purchasing and restocking recommendations.
--    <- Decide what to buy and how much
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 240.0, rate_id = null, node_id = '1dce5488-ba91-438f-b775-043591d3fb42', cadence = 'Monthly'
  where id = '438667da-1975-45a0-91ad-dbb661865a17'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 4.0 h/mo | HR Manager | Coordinate hiring from manpower request to offer, including job po
--    <- Recruitment & onboarding
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 240.0, rate_id = null, node_id = 'c317d491-7095-412c-a062-829f78a706bf', cadence = 'Monthly'
  where id = 'bcf66869-1c07-4ad0-871f-729df5a51393'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 4.0 h/mo | Kiosk Sales Representative | Perform assigned stock counts, report low-stock or discrepancies, 
--    <- Monthly full store inventory count
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 240.0, rate_id = null, node_id = '70d3be0e-547b-4fba-b75d-84b492cab363', cadence = 'Monthly'
  where id = '905053f6-2730-4270-8814-7f43879d6d39'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 3.8 h/mo | Operations Manager | Own return, exchange, damage, missing-item, and defective-item wor
--    <- Returns intake & logging
update wp_tasks set times_source = 'driver', times_manual = null, driver_id = 'bdce2d38-7c22-493b-9c12-e8ca797f2f9c', driver_factor = 1, minutes_source = 'manual', minutes_manual = 15.0, rate_id = null, node_id = '268146b8-012d-41bc-88c1-80b5423d83cb', cadence = 'Per-unit (volume)'
  where id = '0a5a9b4b-8f49-4e67-81cc-e55ad2c26ec6'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 3.8 h/mo | Sales & Ops Assistant | Assist the Inventory Manager with counting, receiving, organizing,
--    <- Receiving store delivery & put-away
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 225.0, rate_id = null, node_id = '70d3be0e-547b-4fba-b75d-84b492cab363', cadence = 'Monthly'
  where id = '211344bc-7ac0-42d9-a6ac-8f8c80b3f7b1'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 3.5 h/mo | Technical Product & Purchasing Specialist | Record findings, recurring defects, solutions, and cases requiring
--    <- Supplier claims (damaged / short-shipped)
--    <- Warranty claim against supplier
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 210.0, rate_id = null, node_id = 'e6e1ca57-8d21-4010-a4db-53eacedba832', cadence = 'Monthly'
  where id = 'c9c0b922-50b0-408d-a914-5806a0626c1e'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 3.5 h/mo | HR Manager | Maintain updated policies, templates, job descriptions, salary rec
--    <- DOLE records upkeep (payroll, DTR, 201)
--    <- HR documentation / 201 file upkeep
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 210.0, rate_id = null, node_id = 'f2b6d507-0d58-4cde-86c9-719f012883f1', cadence = 'Monthly'
  where id = 'ddf69539-4038-4bc2-aed1-d3abdbdf1ecd'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 3.3 h/mo | Retail & E-commerce Operations Manager | Ensure approved changes are completed within the required deadline
--    <- Listing refresh / maintenance
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 200.0, rate_id = null, node_id = '3f6bb29f-d094-48e3-974a-12f414dca464', cadence = 'Monthly'
  where id = 'a2820d09-e7b6-4a40-9c64-0a15f24a9a2d'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 3.2 h/mo | Operations Manager | Monitor packing errors, cancellations, delayed orders, and custome
--    <- Failed delivery / RTS handling
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 194.85, rate_id = null, node_id = '1bfefe84-a083-4022-8be8-8ee8b71c4be4', cadence = 'Monthly'
  where id = '37f21f8b-c523-4962-8238-c7d34534351c'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 3.2 h/mo | Operations Manager | Coordinate inventory availability across selling channels.
--    <- Stock allocation across channels
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 194.85, rate_id = null, node_id = '1dce5488-ba91-438f-b775-043591d3fb42', cadence = 'Monthly'
  where id = '2195a863-616a-4e2b-9c41-f53bd41137c1'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 3.2 h/mo | Operations Manager | Monitor workload, deadlines, quality, and attendance coverage.
--    <- Scheduling & shift planning
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 194.85, rate_id = null, node_id = 'c317d491-7095-412c-a062-829f78a706bf', cadence = 'Monthly'
  where id = '90efd06d-304d-4a35-b554-1190fd6e1cc3'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 3.2 h/mo | Technical Product & Purchasing Specialist | Test incoming samples, new models, returned devices, and reported 
--    <- Walk-in repair / service intake
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 194.85, rate_id = null, node_id = '70d3be0e-547b-4fba-b75d-84b492cab363', cadence = 'Monthly'
  where id = 'f6e0ff22-ef2a-4d72-b401-7dbf8059391a'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 3.2 h/mo | Retail & E-commerce Operations Manager | Consolidate operational purchase requests and obtain required quot
--    <- Quotation for custom / bulk requests
--    <- Store supplies & consumables reorder
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 189.9, rate_id = null, node_id = 'ab85a426-abe7-44fc-9072-28163ae6ab82', cadence = 'Monthly'
  where id = '2e4ee7bd-fcf2-4efa-beaf-7ee7027c8554'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 3.0 h/mo | Technical Product & Purchasing Specialist | Maintain standard setup files, version records, checklists, guides
--    <- Maintain master image library
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 180.0, rate_id = null, node_id = 'b2788e46-7bd8-46c8-bd1f-4f7aed62cdad', cadence = 'Monthly'
  where id = '497eda28-5ec8-422a-9696-6676ee57cf43'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 3.0 h/mo | Customer Service & Operations Assistant | Coordinate with the marketing lead for major campaigns or material
--    <- Email / SMS blast
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 180.0, rate_id = null, node_id = '4698d876-f4a6-4b79-8680-98478d213396', cadence = 'Monthly'
  where id = '4c9f1128-bb73-4481-b2db-9d761f601ee3'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 3.0 h/mo | Operations Manager | Approve exceptions within authority.
--    <- Refund / replacement processing
update wp_tasks set times_source = 'driver', times_manual = null, driver_id = 'bdce2d38-7c22-493b-9c12-e8ca797f2f9c', driver_factor = 1, minutes_source = 'manual', minutes_manual = 12.0, rate_id = null, node_id = '268146b8-012d-41bc-88c1-80b5423d83cb', cadence = 'Per-unit (volume)'
  where id = '2850d853-f454-4bdd-a2a9-0a8f4d599fc7'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 3.0 h/mo | HR Manager | Receive and address employee concerns, conflicts, workplace issues
--    <- Employee relations / discipline
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 180.0, rate_id = null, node_id = 'c317d491-7095-412c-a062-829f78a706bf', cadence = 'Monthly'
  where id = '81c2605f-8603-4a32-92b0-6223cd9b76e0'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 2.2 h/mo | HR Manager | Manage monthly check-ins, quarterly reviews, role scorecards, KPI 
--    <- Performance reviews
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 133.65, rate_id = null, node_id = 'c317d491-7095-412c-a062-829f78a706bf', cadence = 'Monthly'
  where id = '4c4167f0-456c-41f8-b7f0-1676732ffa36'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 2.2 h/mo | Customer Service & Operations Assistant | Share recurring customer questions, objections, complaints, and pr
--    <- Review / rating solicitation
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 129.9, rate_id = null, node_id = '24302b00-1936-493d-b71b-2db02a353523', cadence = 'Monthly'
  where id = '1e227b7a-093f-4daf-97ae-6963a6c08744'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 2.2 h/mo | Kiosk Sales Representative | Explain product differences, promotions, warranties, payment optio
--    <- Service upsell (add-games, repair)
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 129.9, rate_id = null, node_id = '24302b00-1936-493d-b71b-2db02a353523', cadence = 'Monthly'
  where id = 'b88354ac-7ad3-448e-9d28-9b5f030c24a9'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 2.2 h/mo | Retail & E-commerce Operations Manager | Assign work based on employee roles, workload, and priority.
--    <- Store staff shift scheduling
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 129.9, rate_id = null, node_id = '70d3be0e-547b-4fba-b75d-84b492cab363', cadence = 'Monthly'
  where id = '8ae25b3a-3620-4092-8e70-bba9ee4704d0'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 2.0 h/mo | HR Manager | Manage role-based onboarding, orientation, probation tracking, tra
--    <- Training & upskilling
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 120.0, rate_id = null, node_id = 'c317d491-7095-412c-a062-829f78a706bf', cadence = 'Monthly'
  where id = '9c8c20e6-2bb1-4fcb-91f1-267d7472efb6'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 1.9 h/mo | Retail & E-commerce Operations Manager | Monitor renewal dates, document requirements, and submission deadl
--    <- Business permit renewals
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 115.2, rate_id = null, node_id = 'f2b6d507-0d58-4cde-86c9-719f012883f1', cadence = 'Monthly'
  where id = '25bd65e2-0a97-4005-9e53-7e7258f65379'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 1.5 h/mo | Retail & E-commerce Operations Manager | Coordinate operational requirements with store staff, inventory, m
--    <- Mall / landlord coordination & reports
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 90.0, rate_id = null, node_id = '70d3be0e-547b-4fba-b75d-84b492cab363', cadence = 'Monthly'
  where id = 'a9a66dd2-1c5e-44d2-b4cc-b1e390f356ca'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 1.0 h/mo | Retail & E-commerce Operations Manager | Monitor store and kiosk readiness, supplies, equipment, maintenanc
--    <- Store equipment maintenance
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 60.0, rate_id = null, node_id = '70d3be0e-547b-4fba-b75d-84b492cab363', cadence = 'Monthly'
  where id = '1374dd9c-a529-4c53-94f2-9c0a99f4a164'
    and coalesce(times_manual, 0) = 0 and driver_id is null;

-- 1.0 h/mo | Technical Product & Purchasing Specialist | Recommend product improvements, setup changes, new items, or produ
--    <- Kill / continue review of test brands
update wp_tasks set times_source = 'manual', times_manual = 1, driver_id = null, driver_factor = 1, minutes_source = 'manual', minutes_manual = 59.4, rate_id = null, node_id = 'c58c198f-26db-4c50-b4ae-77c6d504fdeb', cadence = 'Monthly'
  where id = 'c6832561-c6ab-473e-8c5e-dd54089f39de'
    and coalesce(times_manual, 0) = 0 and driver_id is null;
