-- Desired Outcomes sit between a role's responsibilities and its KPIs.
-- "Pack orders accurately" is work; "customers receive the correct product"
-- is the outcome; fulfillment accuracy is the number that proves it. Without
-- this layer every responsibility grows its own KPI, which is the failure the
-- KPI cascade spec exists to prevent.
--
-- responsibility_area is TEXT, not a foreign key: accountability areas are not
-- rows in this schema. They are the grouping string on wp_tasks, which is how
-- areasByRole() already derives them.

create table if not exists role_outcomes (
  id                  uuid primary key default gen_random_uuid(),
  company_id          uuid not null references companies(id) on delete cascade,
  role_scorecard_id   uuid not null references role_scorecards(id) on delete cascade,
  responsibility_area text not null,
  text                text not null,
  sort_order          integer not null default 0,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint role_outcomes_text_not_blank check (length(trim(text)) > 0)
);
create index if not exists role_outcomes_role on role_outcomes (role_scorecard_id);

drop trigger if exists _role_outcomes_updated on role_outcomes;
create trigger _role_outcomes_updated before update on role_outcomes
  for each row execute function set_updated_at();

alter table role_outcomes enable row level security;

-- Company-read, admin-write, mirroring kpis (20260718000001:99-105). An
-- outcome is role design, not a judgement about a person, so it carries no
-- personal data and needs no per-employee clause.
drop policy if exists role_outcomes_company_select on role_outcomes;
create policy role_outcomes_company_select on role_outcomes for select
  using (company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN');

drop policy if exists role_outcomes_company_write on role_outcomes;
create policy role_outcomes_company_write on role_outcomes for all
  using (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR','HR_ADMIN')
    and (company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN'))
  with check (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR','HR_ADMIN')
    and (company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN'));

-- Which outcome a role's KPI proves. Nullable: a KPI may exist before anyone
-- has written the outcome, and a COMPANY KPI has no role link at all.
alter table role_scorecard_kpis
  add column if not exists outcome_id uuid references role_outcomes(id) on delete set null;
