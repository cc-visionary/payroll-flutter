-- Documentation only. No DDL, no data change.
--
-- 20260718000005 created employee_kpis with a header comment asserting "Zero
-- rows for an employee means 'tracked on the full role set'". 20260811000002
-- ended that: it materialised today's effective set for everyone who had one,
-- so the stored set IS the set and zero rows means nobody has chosen yet — a
-- gap the app now flags and refuses to author.
--
-- The historical migration file is left exactly as it ran. This records the
-- current rule where anyone reading the live schema will find it.
--
-- The empty-set fallbacks in generate_employee_review (20260718000006),
-- performance_repository.seedSkillRatingsForCheckIn and employeesByKpi are
-- DELIBERATELY still in place, and are not what this comment describes. They
-- are safety nets for a genuinely absent set, where generating a review with
-- no KPIs at all would be worse than generating the role's. The rule below is
-- what the AUTHORING screens enforce: the role workbench's People pane and the
-- employee profile's Role tab both refuse to save an empty selection.
comment on table employee_kpis is
  'The KPIs an employee is measured on: a subset of their role card''s '
  'role_scorecard_kpis. Since 20260811000002 the stored set IS the set — zero '
  'rows means nobody has chosen yet (a gap to close), NOT "tracked on the full '
  'role set". Review generation still falls back to the role set for an absent '
  'set rather than produce an empty review, but no UI may author one.';
