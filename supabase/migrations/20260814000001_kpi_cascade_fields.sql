-- The KPI cascade: a KPI now states which level it lives at, which higher
-- measure it serves, whether it may be recomputed at wider scopes, and where
-- its numbers come from.
--
-- Defaults are deliberately the conservative ones. INDEPENDENT means "compute
-- only my own level", so an unconfigured KPI never silently claims to roll up
-- into a company number. MANUAL_PERIODIC means "nobody has claimed this is
-- automatic" -- the type the owner wants LEAST used, which is exactly why it
-- is the honest default for a KPI nobody has classified.
--
-- department_id is NOT added here: 20260723000002 already added it.

alter table kpis
  add column if not exists level text not null default 'PERSONAL'
    check (level in ('PERSONAL','DEPARTMENT','COMPANY')),
  add column if not exists parent_kpi_id uuid references kpis(id) on delete set null,
  add column if not exists rollup_type text not null default 'INDEPENDENT'
    check (rollup_type in ('DIRECT','SHARED','ALIGNED','INDEPENDENT')),
  add column if not exists data_method text not null default 'MANUAL_PERIODIC'
    check (data_method in ('AUTOMATIC','HYBRID','MANUAL_EXCEPTION','MANUAL_PERIODIC')),
  -- The default target. A DEPARTMENT or COMPANY KPI has no role card to hang
  -- one on, so it cannot live only on role_scorecard_kpis.
  add column if not exists target_direction text
    check (target_direction is null or target_direction in ('HIGHER','LOWER')),
  add column if not exists target_value numeric;

create index if not exists kpis_company_level on kpis (company_id, level);
create index if not exists kpis_parent on kpis (parent_kpi_id);

comment on column kpis.rollup_type is
  'DIRECT: recompute at wider scopes from the same source. SHARED: department '
  'and company only, never personal. ALIGNED/INDEPENDENT: this level only.';
