-- Company-level app settings (admin-editable).
-- Kept separate from `companies` because `companies` is SUPER_ADMIN-write only
-- (holds statutory identifiers); this table is for operational toggles ADMIN
-- may flip without escalating privileges.

create table company_settings (
  company_id         uuid primary key references companies(id) on delete cascade,
  attendance_source  attendance_source not null default 'LARK_IMPORT',
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create trigger _company_settings_updated before update on company_settings
  for each row execute function set_updated_at();

alter table company_settings enable row level security;

create policy company_settings_select on company_settings for select
  using (company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN');

create policy company_settings_write on company_settings for all
  using (
    auth_app_role() in ('SUPER_ADMIN', 'ADMIN')
    and (company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN')
  )
  with check (
    auth_app_role() in ('SUPER_ADMIN', 'ADMIN')
    and (company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN')
  );

-- Backfill settings row for every existing company
insert into company_settings (company_id)
  select id from companies
  on conflict (company_id) do nothing;
