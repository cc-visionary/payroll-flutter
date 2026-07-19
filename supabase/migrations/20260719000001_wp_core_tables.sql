-- Workforce Capacity Planning (Phase A+B) — foundation tables.
-- Driver-based model: costed tasks -> per-person load. Company-scoped.
-- RLS mirrors kpis (20260718000001): company read, HR/Admin/Super-admin write.

create table wp_value_chain_nodes (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references companies(id) on delete cascade,
  code        text not null,
  name        text not null,
  sort_order  int  not null default 0,
  created_at  timestamptz not null default now()
);
create unique index wp_value_chain_nodes_uniq on wp_value_chain_nodes (company_id, lower(trim(name)));
create index wp_value_chain_nodes_company on wp_value_chain_nodes (company_id);

create table wp_drivers (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references companies(id) on delete cascade,
  name        text not null,
  value       numeric not null default 0,
  grows       boolean not null default false,
  note        text,
  sort_order  int  not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index wp_drivers_uniq on wp_drivers (company_id, lower(trim(name)));
create index wp_drivers_company on wp_drivers (company_id);

create table wp_rates (
  id           uuid primary key default gen_random_uuid(),
  company_id   uuid not null references companies(id) on delete cascade,
  name         text not null,
  minutes_each numeric not null default 0,
  note         text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create unique index wp_rates_uniq on wp_rates (company_id, lower(trim(name)));
create index wp_rates_company on wp_rates (company_id);

create table wp_config (
  company_id             uuid primary key references companies(id) on delete cascade,
  growth_multiplier      numeric not null default 1.0,
  default_capacity_hours numeric not null default 160,
  updated_at             timestamptz not null default now()
);

create table wp_tasks (
  id                  uuid primary key default gen_random_uuid(),
  company_id          uuid not null references companies(id) on delete cascade,
  node_id             uuid references wp_value_chain_nodes(id) on delete set null,
  name                text not null,
  brand_scope         text,
  cadence             text,
  times_source        text not null default 'manual' check (times_source in ('manual','driver')),
  times_manual        numeric,
  driver_id           uuid references wp_drivers(id) on delete set null,
  driver_factor       numeric not null default 1,
  minutes_source      text not null default 'manual' check (minutes_source in ('manual','rate')),
  minutes_manual      numeric,
  rate_id             uuid references wp_rates(id) on delete set null,
  skill_tier          text check (skill_tier is null or skill_tier in ('Transactional','Operational','Managerial','Strategic')),
  risk                text check (risk is null or risk in ('Low','Medium','High')),
  capability          text,
  owner_employee_id   uuid references employees(id) on delete set null,
  role_scorecard_id   uuid references role_scorecards(id) on delete set null,
  responsibility_area text,
  notes               text,
  external_ref        text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create unique index wp_tasks_external_ref_uniq on wp_tasks (company_id, external_ref) where external_ref is not null;
create index wp_tasks_company on wp_tasks (company_id);
create index wp_tasks_owner   on wp_tasks (owner_employee_id);
create index wp_tasks_node    on wp_tasks (node_id);

create table wp_capacity_overrides (
  employee_id    uuid primary key references employees(id) on delete cascade,
  capacity_hours numeric not null,
  updated_at     timestamptz not null default now()
);

-- RLS: company-scoped read, HR/Admin/Super-admin write (mirrors kpis).
do $$
declare tbl text;
begin
  foreach tbl in array array['wp_value_chain_nodes','wp_drivers','wp_rates','wp_config','wp_tasks'] loop
    execute format('alter table %I enable row level security;', tbl);
    execute format(
      'create policy %1$s_select on %1$I for select using (company_id = auth_company_id() or auth_app_role() = ''SUPER_ADMIN'');',
      tbl);
    execute format(
      'create policy %1$s_write on %1$I for all '
      'using (auth_app_role() in (''SUPER_ADMIN'',''ADMIN'',''HR'') and (company_id = auth_company_id() or auth_app_role() = ''SUPER_ADMIN'')) '
      'with check (auth_app_role() in (''SUPER_ADMIN'',''ADMIN'',''HR'') and (company_id = auth_company_id() or auth_app_role() = ''SUPER_ADMIN''));',
      tbl);
  end loop;
end $$;

-- wp_capacity_overrides is keyed by employee_id; resolve company through employees.
alter table wp_capacity_overrides enable row level security;
create policy wp_capacity_overrides_select on wp_capacity_overrides for select using (
  exists (select 1 from employees e where e.id = employee_id
    and (e.company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN')));
create policy wp_capacity_overrides_write on wp_capacity_overrides for all
  using (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR') and exists (
    select 1 from employees e where e.id = employee_id
      and (e.company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN')))
  with check (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR') and exists (
    select 1 from employees e where e.id = employee_id
      and (e.company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN')));

-- keep updated_at fresh on every UPDATE (codebase convention)
create trigger _wp_drivers_updated before update on wp_drivers for each row execute function set_updated_at();
create trigger _wp_rates_updated before update on wp_rates for each row execute function set_updated_at();
create trigger _wp_config_updated before update on wp_config for each row execute function set_updated_at();
create trigger _wp_tasks_updated before update on wp_tasks for each row execute function set_updated_at();
create trigger _wp_capacity_overrides_updated before update on wp_capacity_overrides for each row execute function set_updated_at();
