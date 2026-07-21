-- Demand aggregates must grow when their components do.
--
-- The xlsx seed left three volume aggregates flagged `grows = false` while
-- every component that feeds them is flagged true:
--
--   ONLINE orders per month        = 300 = Shopee 120 + Lazada 60
--                                        + TikTok 90 + Shopify 30   (all grow)
--   TOTAL units sold per month     = 500  (sales volume)
--   Units needing config per month = 400  = 80% of units sold
--
-- A task only responds to `wp_config.growth_multiplier` when its times come
-- from a driver flagged `grows`. With these three flat, the heaviest
-- volume-driven responsibilities were pinned:
--
--   Lead the flashing, installation, configuration…  80.0 h/mo
--   Pack, label, check, and dispatch online orders   65.8 h/mo
--   Welcome customers, recommend products, demo…     40.0 h/mo
--   Ensure completed devices meet setup and QC…      26.7 h/mo
--   Assist with receiving, sorting, storage…         33.0 h/mo
--
-- That is 11 of 16 driver-linked tasks and roughly a third of all modelled
-- work sitting immovable, so scenario planning barely moved the numbers —
-- which defeats the point of driver-based costing.
--
-- Structural drivers are deliberately NOT touched: working days per month,
-- store operating days/hours, employees on payroll, physical stores,
-- registered entities, sales platforms and the like do not scale with demand.
--
-- Idempotent and reversible: set `grows = false` on these three names to undo.
update wp_drivers
   set grows = true
 where lower(trim(name)) in (
         'online orders per month',
         'total units sold per month',
         'units needing config per month'
       )
   and grows = false;
