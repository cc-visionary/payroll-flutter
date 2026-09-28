-- 20260928000001_role_rate_changes.sql
--
-- Effective-dated history of a role's base rate (e.g. a wage order moving the
-- NCR minimum from 695 to 755).
--
-- role_scorecards.base_salary used to be immutable after creation: payroll
-- falls back to it for every employee on the role who has no
-- compensation_changes row, so editing it repriced those employees for the
-- whole period, backwards, with no effective date. With this table the
-- fallback is resolved AS OF each day (see payroll/engine/role_rate.dart):
-- the newest change effective on or before the day wins; a day before every
-- change pays the earliest change's prev_base_salary. base_salary itself is
-- kept equal to the newest change's rate so documents, offer letters and the
-- hiring auto-fill read the current figure.
--
-- Employees with their own compensation_changes record are unaffected —
-- their record wins over the role default, exactly as before.

create table role_rate_changes (
  id                 uuid primary key default gen_random_uuid(),
  company_id         uuid not null references companies(id),
  role_scorecard_id  uuid not null references role_scorecards(id) on delete cascade,
  effective_date     date not null,
  prev_base_salary   numeric(14,2),
  new_base_salary    numeric(14,2) not null check (new_base_salary > 0),
  reason             text not null default '',
  initiated_by_id    uuid references users(id),
  created_at         timestamptz not null default now()
);

create index idx_role_rate_changes_card_effective
  on role_rate_changes (role_scorecard_id, effective_date);

-- Company-read, admin-write, mirroring role_scorecards (and role_outcomes,
-- 20260814000002). A role's rate is already company-readable on
-- role_scorecards.base_salary, so its history carries nothing new.
alter table role_rate_changes enable row level security;

drop policy if exists role_rate_changes_company_select on role_rate_changes;
create policy role_rate_changes_company_select on role_rate_changes for select
  using (company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN');

drop policy if exists role_rate_changes_company_write on role_rate_changes;
create policy role_rate_changes_company_write on role_rate_changes for all
  using (auth_is_hr_or_admin()
    and (company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN'))
  with check (auth_is_hr_or_admin()
    and (company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN'));
