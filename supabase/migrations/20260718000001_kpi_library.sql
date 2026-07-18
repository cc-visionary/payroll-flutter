-- Phase 1 of KPI tracking: promote role-card KPIs (JSON on role_scorecards.kpis)
-- into a first-class library + link, losslessly. The legacy JSON column is kept
-- for rollback; a later migration drops it once this path is proven.

-- Pre-flight safety gate: the seed links a role card to a given KPI at most once
-- (unique role_scorecard_id, kpi_id). If a single card lists two KPIs whose names
-- normalize to the same value, one entry's target/frequency would be silently
-- dropped. Refuse to migrate in that case (the whole migration is transactional,
-- so nothing is changed) and name the offending cards; clean the data and re-run.
do $$
declare
  v_dupes text;
begin
  select string_agg(format('card %s -> "%s" (x%s)', role_scorecard_id, nm, cnt), '; ')
    into v_dupes
  from (
    select rs.id as role_scorecard_id,
           lower(trim(coalesce(k->>'name', k->>'metric'))) as nm,
           count(*) as cnt
    from role_scorecards rs
      cross join lateral jsonb_array_elements(coalesce(rs.kpis, '[]'::jsonb)) as k
    where length(trim(coalesce(k->>'name', k->>'metric', ''))) > 0
    group by rs.id, lower(trim(coalesce(k->>'name', k->>'metric')))
    having count(*) > 1
  ) d;
  if v_dupes is not null then
    raise exception
      'KPI library migration aborted: role card(s) have duplicate KPI names that would lose a target on unify. Clean these, then re-run: %',
      v_dupes;
  end if;
end $$;

create table kpis (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null references companies(id),
  name              text not null,
  category          text,
  description       text,
  measurement_unit  text,
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint kpis_name_not_blank check (length(trim(name)) > 0)
);
create unique index kpis_company_lower_name on kpis (company_id, lower(trim(name)));
create index kpis_company_category on kpis (company_id, category);

create trigger _kpis_updated before update on kpis
  for each row execute function set_updated_at();

create table role_scorecard_kpis (
  id                 uuid primary key default gen_random_uuid(),
  role_scorecard_id  uuid not null references role_scorecards(id) on delete cascade,
  kpi_id             uuid not null references kpis(id) on delete restrict,
  target             text,
  frequency          text,
  sort_order         integer not null default 0,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  unique (role_scorecard_id, kpi_id)
);
create index role_scorecard_kpis_role on role_scorecard_kpis (role_scorecard_id);
create index role_scorecard_kpis_kpi on role_scorecard_kpis (kpi_id);

create trigger _role_scorecard_kpis_updated before update on role_scorecard_kpis
  for each row execute function set_updated_at();

-- Seed: one library KPI per distinct name per company; one link per role-card KPI.
insert into kpis (company_id, name, measurement_unit)
select distinct on (rs.company_id, lower(trim(coalesce(k->>'name', k->>'metric'))))
  rs.company_id,
  trim(coalesce(k->>'name', k->>'metric')),
  nullif(trim(coalesce(k->>'measurement', '')), '')
from role_scorecards rs
  cross join lateral jsonb_array_elements(coalesce(rs.kpis, '[]'::jsonb)) as k
where length(trim(coalesce(k->>'name', k->>'metric', ''))) > 0
order by rs.company_id, lower(trim(coalesce(k->>'name', k->>'metric'))), rs.id
on conflict (company_id, lower(trim(name))) do nothing;

insert into role_scorecard_kpis (role_scorecard_id, kpi_id, target, frequency, sort_order)
select distinct on (rs.id, lib.id)
  rs.id,
  lib.id,
  nullif(trim(coalesce(arr.k->>'target', '')), ''),
  nullif(trim(coalesce(arr.k->>'frequency', '')), ''),
  (arr.k_index - 1)::int
from role_scorecards rs
  cross join lateral jsonb_array_elements(coalesce(rs.kpis, '[]'::jsonb))
    with ordinality as arr(k, k_index)
  join kpis lib
    on lib.company_id = rs.company_id
    and lower(trim(lib.name)) = lower(trim(coalesce(arr.k->>'name', arr.k->>'metric', '')))
where length(trim(coalesce(arr.k->>'name', arr.k->>'metric', ''))) > 0
order by rs.id, lib.id, arr.k_index
on conflict (role_scorecard_id, kpi_id) do nothing;

-- RLS: company-scoped, mirroring role_scorecards.
alter table kpis enable row level security;
create policy kpis_company_select on kpis for select
  using (company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN');
create policy kpis_company_write on kpis for all
  using (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR')
    and (company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN'))
  with check (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR')
    and (company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN'));

-- role_scorecard_kpis has no company_id; scope via its parent role card, whose
-- own select policy is already company-read.
alter table role_scorecard_kpis enable row level security;
create policy role_scorecard_kpis_select on role_scorecard_kpis for select
  using (exists (
    select 1 from role_scorecards rs where rs.id = role_scorecard_id
      and (rs.company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN')));
create policy role_scorecard_kpis_write on role_scorecard_kpis for all
  using (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR') and exists (
    select 1 from role_scorecards rs where rs.id = role_scorecard_id
      and (rs.company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN')))
  with check (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR')
    and exists (
      select 1 from role_scorecards rs where rs.id = role_scorecard_id
        and (rs.company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN'))
    and exists (
      select 1 from kpis k where k.id = kpi_id
        and (k.company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN')));
