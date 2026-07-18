-- Merge confirmed duplicate library KPIs into their canonical survivor (HR
-- decision, 2026-07-18), keyed on exact (case-insensitive) prod names. Each
-- cluster: re-point the absorbed KPI's role_scorecard_kpis links onto the
-- survivor (each role keeps its own target), drop the absorbed link+KPI. Safe
-- no-op per cluster if a name isn't found. Transactional.

do $$
declare
  c record;
  s uuid;
  a uuid;
begin
  for c in
    select * from (values
      ('Inventory Accuracy', 'Inventory Record Accuracy'),
      ('Setup Accuracy',     'Console Setup Accuracy')
    ) as t(survivor, absorbed)
  loop
    select id into s from kpis where lower(trim(name)) = lower(trim(c.survivor)) limit 1;
    select id into a from kpis where lower(trim(name)) = lower(trim(c.absorbed)) limit 1;
    if s is null or a is null or s = a then
      raise notice 'KPI merge skipped (survivor=%, absorbed=%): % <- %', s, a, c.survivor, c.absorbed;
      continue;
    end if;
    update role_scorecard_kpis rsk
      set kpi_id = s
      where rsk.kpi_id = a
        and not exists (
          select 1 from role_scorecard_kpis x
          where x.role_scorecard_id = rsk.role_scorecard_id and x.kpi_id = s
        );
    delete from role_scorecard_kpis where kpi_id = a;
    delete from kpis where id = a;
    raise notice 'KPI merged: % <- %', c.survivor, c.absorbed;
  end loop;
end $$;
