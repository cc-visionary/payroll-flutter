-- Adds signatory + HR-manager defaults to hiring_entities so generated
-- documents (Quitclaim, COE, NTE) can autofill these per-brand instead of
-- prompting HR to type the same name on every doc.
--
-- All three columns are nullable so the migration is non-breaking; an admin
-- form in Settings → Hiring Entities lets users fill them as a one-time
-- per-brand setup. Templates fall back to manual entry with a warning
-- banner when any of these is null on the selected entity.

alter table hiring_entities
  add column legal_signatory_name varchar(255),
  add column legal_signatory_role varchar(255),
  add column hr_manager_name      varchar(255);
