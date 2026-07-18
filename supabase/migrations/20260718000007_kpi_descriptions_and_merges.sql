-- KPI curation (2026-07-18):
-- #1 Fill each KPI's empty description from its measurement text (the
--    descriptive wording lives in measurement_unit; description was empty).
--    Non-destructive: measurement_unit is left in place.
-- #2 Merge four confirmed duplicate pairs (survivor <- absorbed): re-point
--    role_scorecard_kpis AND employee_kpis links (each keeps its own target /
--    assignment), then delete the absorbed link rows and library KPI. Matched by
--    exact case-insensitive name; safe no-op per pair if a name isn't found.
-- Transactional.

update kpis
  set description = measurement_unit
  where (description is null or trim(description) = '')
    and measurement_unit is not null
    and trim(measurement_unit) <> '';

do $$
declare
  c record;
  s uuid;
  a uuid;
begin
  for c in
    select * from (values
      ('Issue Resolution', 'Quality Issue Resolution'),
      ('Task Completion',  'Team Task Completion'),
      ('Conversion rate',  'Sales Conversion'),
      ('Case Resolution',  'Attendance Case Resolution')
    ) as t(survivor, absorbed)
  loop
    select id into s from kpis where lower(trim(name)) = lower(trim(c.survivor)) limit 1;
    select id into a from kpis where lower(trim(name)) = lower(trim(c.absorbed)) limit 1;
    if s is null or a is null or s = a then
      raise notice 'KPI merge skipped (survivor=%, absorbed=%): % <- %', s, a, c.survivor, c.absorbed;
      continue;
    end if;
    -- role_scorecard_kpis: move links unless the card already links the survivor
    update role_scorecard_kpis rsk set kpi_id = s
      where rsk.kpi_id = a
        and not exists (
          select 1 from role_scorecard_kpis x
          where x.role_scorecard_id = rsk.role_scorecard_id and x.kpi_id = s
        );
    delete from role_scorecard_kpis where kpi_id = a;
    -- employee_kpis (Phase 2): move assignments unless the employee already has the survivor
    update employee_kpis ek set kpi_id = s
      where ek.kpi_id = a
        and not exists (
          select 1 from employee_kpis y
          where y.employee_id = ek.employee_id and y.kpi_id = s
        );
    delete from employee_kpis where kpi_id = a;
    -- remove the now-unreferenced absorbed library KPI
    delete from kpis where id = a;
    raise notice 'KPI merged: % <- %', c.survivor, c.absorbed;
  end loop;
end $$;
