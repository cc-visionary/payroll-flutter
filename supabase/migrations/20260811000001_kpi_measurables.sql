-- KPIs become EOS measurables: every number declares how it is counted, from
-- which source, at what rhythm, and against a structured goal.
-- Spec: docs/superpowers/specs/2026-08-11-role-workbench-design.md
--
-- The legacy free-text role_scorecard_kpis.target and .frequency columns are
-- DELIBERATELY kept. They are now derived (written from the goal and the
-- cadence by the Dart repository) and are still read by the role-card PDF, the
-- employment-contract templates and review_kpi_results snapshots.

-- 1. How the number is produced. Sources stay free text with autocomplete in
--    the UI: BigSeller and Lark today, Shopee or Shopify tomorrow, no
--    migration to add one.
alter table kpis
  add column if not exists value_type text not null default 'COUNT'
    check (value_type in ('COUNT','RATIO','CURRENCY','PERCENT','DURATION')),
  add column if not exists numerator_label text,
  add column if not exists numerator_source text,
  add column if not exists denominator_label text,
  add column if not exists denominator_source text,
  add column if not exists unit text,
  add column if not exists cadence text not null default 'WEEKLY'
    check (cadence in ('WEEKLY','MONTHLY','QUARTERLY')),
  add column if not exists proof_type text
    check (proof_type is null or proof_type in ('REPORT_EXPORT','SCREENSHOT','SYSTEM_LINK'));

comment on column kpis.value_type is
  'COUNT | RATIO | CURRENCY | PERCENT | DURATION. RATIO requires both denominator columns.';
comment on column kpis.numerator_source is
  'Free text naming the system the count is read from (BigSeller, Lark, ...). '
  'Autocompleted in the UI from values already in use; deliberately unconstrained '
  'so a new channel needs no migration.';
comment on column kpis.cadence is
  'The measurable rhythm. Lives here, not on role_scorecard_kpis: an EOS '
  'measurable has ONE cadence regardless of which role carries it.';

-- Backfill cadence from history rather than leaving every legacy KPI at the
-- column default. Without this, the first time a later plan re-saves a
-- genuinely monthly or quarterly KPI, the Dart repository derives frequency
-- back OUT of this column (frequencyLabelFromCadence) and writes "Weekly"
-- into the card, the PDF and the next generated contract — converting real
-- history into a default and then treating the default as authoritative.
-- Deliberately conservative: only a link whose frequency text unambiguously
-- names one of the three cadences (case-insensitively, once trimmed) is
-- trusted; anything else, or a KPI with no link at all, stays at WEEKLY.
do $$
declare
  v_backfilled int;
begin
  with latest_frequency as (
    select distinct on (l.kpi_id)
      l.kpi_id,
      lower(trim(l.frequency)) as frequency
    from role_scorecard_kpis l
    where l.frequency is not null
    order by l.kpi_id, l.updated_at desc
  )
  update kpis k
  set cadence = upper(lf.frequency)
  from latest_frequency lf
  where lf.kpi_id = k.id
    and lf.frequency in ('weekly', 'monthly', 'quarterly');
  get diagnostics v_backfilled = row_count;
  raise notice 'backfilled cadence for % KPI(s) from their most recent role_scorecard_kpis.frequency', v_backfilled;
end $$;

-- 2. The goal lives on the LINK — the same measurable can carry a different bar
--    on a different role.
alter table role_scorecard_kpis
  add column if not exists goal_direction text
    check (goal_direction is null or goal_direction in ('GTE','LTE','EQ','BETWEEN')),
  add column if not exists goal_value numeric,
  add column if not exists goal_value_max numeric;

-- add constraint has no IF NOT EXISTS; guard so a re-run is a no-op.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'role_scorecard_kpis_goal_complete'
  ) then
    alter table role_scorecard_kpis
      add constraint role_scorecard_kpis_goal_complete check (
        goal_direction is null
        or (goal_value is not null
            and (goal_direction <> 'BETWEEN'
                 or (goal_value_max is not null and goal_value_max > goal_value)))
      );
  end if;
end $$;

comment on column role_scorecard_kpis.target is
  'DERIVED display text, written from the goal columns by the Dart repository '
  '(see lib/data/models/kpi_goal.dart, formatGoal). Kept because the card PDF, '
  'contract templates and review_kpi_results snapshots read it. Do not hand-edit.';

-- 3. Legacy cleanup. Existing targets are NOT parsed into goals: "98%" carries
--    no direction and guessing would silently invert a bar. Old KPIs simply
--    read as "not yet measurable" until a manager upgrades them.
--
--    Of the KPIs that measure nobody, only those on NO role card are deleted.
--    One on a card with no current holder also measures nobody, but deleting it
--    would silently strip a role that is merely unfilled — those deactivate.
--    "Reaches nobody" mirrors employeesByKpi in role_scorecard_repository.dart:
--    an employee reaches a KPI through their role card's links (deleted
--    employees excluded), or through a direct employee_kpis row.
do $$
declare
  r record;
  v_deleted int := 0;
  v_deactivated int := 0;
begin
  for r in
    select k.id,
           k.name,
           exists (
             select 1 from role_scorecard_kpis l where l.kpi_id = k.id
           ) as on_a_card
    from kpis k
    where k.is_active
      and not exists (
        select 1
        from role_scorecard_kpis l
        join employees e on e.role_scorecard_id = l.role_scorecard_id
        where l.kpi_id = k.id
          and e.deleted_at is null
      )
      -- Belt-and-braces, not a mirror of live reachability: deliberately does
      -- not join employees or check deleted_at, so it can only SAVE a KPI
      -- from cleanup (a false positive here), never cause one to be deleted
      -- or deactivated that should have survived.
      and not exists (
        select 1 from employee_kpis ek where ek.kpi_id = k.id
      )
  loop
    if r.on_a_card then
      update kpis set is_active = false where id = r.id;
      raise notice 'DEACTIVATED (on a role card with no holder): %', r.name;
      v_deactivated := v_deactivated + 1;
    else
      -- No links exist (on_a_card is false), so the FK from
      -- role_scorecard_kpis (on delete restrict) cannot block this.
      delete from kpis where id = r.id;
      raise notice 'DELETED (on no role card at all): %', r.name;
      v_deleted := v_deleted + 1;
    end if;
  end loop;
  raise notice 'legacy KPI cleanup: % deleted, % deactivated', v_deleted, v_deactivated;
end $$;
