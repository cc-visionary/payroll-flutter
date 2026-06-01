-- Fix 1: RLS gaps for managers on check_in_goals + skill_ratings.
-- Existing policies only let HR/Admin or the employee themselves read child
-- rows. Add a manager (reports_to_id) arm that mirrors the parent
-- performance_check_ins_read policy.
--
-- NOTE: This project uses inline role checks (auth_app_role() in (...))
-- rather than a helper function — adapted from the existing policy style in
-- 20260414000014_rls.sql.
--
-- Existing check_in_goals_admin_write and skill_ratings_admin_write have no
-- WITH CHECK clause — preserved in the replacement policies below.

drop policy if exists check_in_goals_read on check_in_goals;
create policy check_in_goals_read on check_in_goals
  for select
  using (
    auth_app_role() in ('SUPER_ADMIN','ADMIN','HR')
    or exists (
      select 1 from performance_check_ins pci
      join employees e on e.id = pci.employee_id
      where pci.id = check_in_goals.check_in_id
        and (pci.employee_id = auth_employee_id() or e.reports_to_id = auth_employee_id())
    )
  );

drop policy if exists check_in_goals_admin_write on check_in_goals;
create policy check_in_goals_admin_write on check_in_goals
  for all
  using (
    auth_app_role() in ('SUPER_ADMIN','ADMIN','HR')
    or exists (
      select 1 from performance_check_ins pci
      join employees e on e.id = pci.employee_id
      where pci.id = check_in_goals.check_in_id
        and (pci.employee_id = auth_employee_id() or e.reports_to_id = auth_employee_id())
    )
  );

drop policy if exists skill_ratings_read on skill_ratings;
create policy skill_ratings_read on skill_ratings
  for select
  using (
    auth_app_role() in ('SUPER_ADMIN','ADMIN','HR')
    or exists (
      select 1 from performance_check_ins pci
      join employees e on e.id = pci.employee_id
      where pci.id = skill_ratings.check_in_id
        and (pci.employee_id = auth_employee_id() or e.reports_to_id = auth_employee_id())
    )
  );

drop policy if exists skill_ratings_admin_write on skill_ratings;
create policy skill_ratings_admin_write on skill_ratings
  for all
  using (
    auth_app_role() in ('SUPER_ADMIN','ADMIN','HR')
    or exists (
      select 1 from performance_check_ins pci
      join employees e on e.id = pci.employee_id
      where pci.id = skill_ratings.check_in_id
        and (pci.employee_id = auth_employee_id() or e.reports_to_id = auth_employee_id())
    )
  );

-- Fix 2: UNIQUE NULLS NOT DISTINCT so concurrent inserts of the company-wide
-- quarterly period can't both succeed (two NULL target_employee_id rows would
-- otherwise be considered distinct by Postgres default behaviour).
-- Supabase uses Postgres 15+ which supports this syntax.

alter table check_in_periods
  drop constraint check_in_periods_company_name_target_unique;
alter table check_in_periods
  add constraint check_in_periods_company_name_target_unique
  unique nulls not distinct (company_id, name, target_employee_id);
