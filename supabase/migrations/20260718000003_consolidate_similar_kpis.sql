-- Consolidate similar library KPIs into shared canonical entries, per an HR
-- curation decision (2026-07-18). Each cluster: keep one survivor, re-point the
-- other's role_scorecard_kpis links onto it (each role keeps its own target),
-- delete the absorbed library KPI, and rename the survivor to a short canonical
-- name. KPIs are matched by distinctive substring (case-insensitive) so this is
-- robust to the exact stored wording; if a cluster's members aren't found, that
-- cluster is a safe no-op. The whole migration is transactional.

do $$
declare
  c record;
  s uuid;
  a uuid;
begin
  for c in
    select * from (values
      ('%opening + closing checklist%', '%checklist completion rate on shifts%', 'Checklist compliance'),
      ('%inventory discrepancy%',       '%cycle count completion rate%',         'Stock accuracy'),
      ('%order accuracy%',              '%packing/dispatch error incidents%',    'Order accuracy')
    ) as t(survivor_like, absorbed_like, canonical)
  loop
    select id into s from kpis where name ilike c.survivor_like order by name limit 1;
    select id into a from kpis where name ilike c.absorbed_like order by name limit 1;
    if s is null or a is null or s = a then
      raise notice 'KPI merge skipped (survivor=%, absorbed=%): %', s, a, c.canonical;
      continue;
    end if;
    -- Move the absorbed KPI's links to the survivor, unless that card already
    -- links the survivor (unique role_scorecard_id, kpi_id).
    update role_scorecard_kpis rsk
      set kpi_id = s
      where rsk.kpi_id = a
        and not exists (
          select 1 from role_scorecard_kpis x
          where x.role_scorecard_id = rsk.role_scorecard_id and x.kpi_id = s
        );
    -- Drop any links that couldn't move (card already had the survivor).
    delete from role_scorecard_kpis where kpi_id = a;
    -- Remove the now-unreferenced absorbed library KPI.
    delete from kpis where id = a;
    -- Canonicalize the survivor's name.
    update kpis set name = c.canonical where id = s;
    raise notice 'KPI merged into "%": survivor=%, absorbed=%', c.canonical, s, a;
  end loop;
end $$;
