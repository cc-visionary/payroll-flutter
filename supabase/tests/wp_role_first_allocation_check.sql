-- Run: psql "$LOCAL_DB" -v ON_ERROR_STOP=1 -f supabase/tests/wp_role_first_allocation_check.sql
-- Against an isolated local copy with every migration BEFORE 20260929000001
-- applied and supabase/seed/01_company.sql loaded (it creates company
-- 11111111-1111-1111-1111-000000000001, used below).
begin;
insert into role_scorecards (id, company_id, job_title, mission_statement, key_responsibilities, kpis, wage_type, work_hours_per_day, work_days_per_week, is_active, effective_date) values
 ('00000000-0000-0000-0000-0000000000a1','11111111-1111-1111-1111-000000000001','Brand Handler','','[]','[]','MONTHLY',8,'MON_FRI',true,'2026-01-01'),
 ('00000000-0000-0000-0000-0000000000a2','11111111-1111-1111-1111-000000000001','Ops Manager',  '','[]','[]','MONTHLY',8,'MON_FRI',true,'2026-01-01');
-- e1/e2 Brand Handler (e2 part-time 80h), e3 Ops Manager, e4 no role.
insert into employees (id, company_id, employee_number, first_name, last_name, hire_date, role_scorecard_id, employment_status) values
 ('00000000-0000-0000-0000-0000000000e1','11111111-1111-1111-1111-000000000001','T-E1','Ana','Test','2024-01-01','00000000-0000-0000-0000-0000000000a1','ACTIVE'),
 ('00000000-0000-0000-0000-0000000000e2','11111111-1111-1111-1111-000000000001','T-E2','Ben','Test','2024-01-01','00000000-0000-0000-0000-0000000000a1','ACTIVE'),
 ('00000000-0000-0000-0000-0000000000e3','11111111-1111-1111-1111-000000000001','T-E3','Jer','Test','2024-01-01','00000000-0000-0000-0000-0000000000a2','ACTIVE'),
 ('00000000-0000-0000-0000-0000000000e4','11111111-1111-1111-1111-000000000001','T-E4','Nox','Test','2024-01-01',null,'ACTIVE');
insert into wp_capacity_overrides (employee_id, capacity_hours) values ('00000000-0000-0000-0000-0000000000e2', 80);
insert into wp_tasks (id, company_id, name, role_scorecard_id, owner_employee_id, hours_per_month, external_ref) values
 ('00000000-0000-0000-0000-0000000000f1','11111111-1111-1111-1111-000000000001','card only',        '00000000-0000-0000-0000-0000000000a1', null, 30, null),
 ('00000000-0000-0000-0000-0000000000f2','11111111-1111-1111-1111-000000000001','split 60/40',      '00000000-0000-0000-0000-0000000000a1', null, 10, null),
 ('00000000-0000-0000-0000-0000000000f3','11111111-1111-1111-1111-000000000001','owner no card',    null, '00000000-0000-0000-0000-0000000000e3', 5, null),
 ('00000000-0000-0000-0000-0000000000f4','11111111-1111-1111-1111-000000000001','owner has no role',null, '00000000-0000-0000-0000-0000000000e4', 5, null),
 ('00000000-0000-0000-0000-0000000000f5','11111111-1111-1111-1111-000000000001','legacy ref',       null, null, 99, 'XLSX-1');
insert into wp_task_assignments (company_id, task_id, role_scorecard_id, employee_id, assignment_role, allocation_pct) values
 ('11111111-1111-1111-1111-000000000001','00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-0000000000a1',null,'PRIMARY',100),
 ('11111111-1111-1111-1111-000000000001','00000000-0000-0000-0000-0000000000f2',null,'00000000-0000-0000-0000-0000000000e3','PRIMARY',60),
 ('11111111-1111-1111-1111-000000000001','00000000-0000-0000-0000-0000000000f2','00000000-0000-0000-0000-0000000000a1',null,'CONTRIBUTOR',40);

\i supabase/migrations/20260929000001_wp_role_first_allocation.sql

do $$
declare r record;
begin
  select role_scorecard_id, allocation_review_note into r from wp_tasks where id = '00000000-0000-0000-0000-0000000000f1';
  assert r.role_scorecard_id = '00000000-0000-0000-0000-0000000000a1' and r.allocation_review_note is null, 'f1 unchanged, unflagged';
  select role_scorecard_id, allocation_review_note into r from wp_tasks where id = '00000000-0000-0000-0000-0000000000f2';
  assert r.role_scorecard_id = '00000000-0000-0000-0000-0000000000a2', 'f2 -> PRIMARY person''s role (Ops Manager)';
  assert r.allocation_review_note like 'was: %60%%40%', 'f2 flagged with both rows';
  select role_scorecard_id, allocation_review_note into r from wp_tasks where id = '00000000-0000-0000-0000-0000000000f3';
  assert r.role_scorecard_id = '00000000-0000-0000-0000-0000000000a2' and r.allocation_review_note is null, 'f3 -> owner role';
  select role_scorecard_id, allocation_review_note into r from wp_tasks where id = '00000000-0000-0000-0000-0000000000f4';
  assert r.role_scorecard_id is null and r.allocation_review_note like '%has no role%', 'f4 flagged';
  select role_scorecard_id, allocation_review_note into r from wp_tasks where id = '00000000-0000-0000-0000-0000000000f5';
  assert r.role_scorecard_id is null and r.allocation_review_note is null, 'legacy untouched';
  assert (select count(*) from wp_task_assignments where task_id = '00000000-0000-0000-0000-0000000000f2') = 2, 'assignments kept';
  -- capacity-weighted: Brand Handler has 30h (f1); e1 160h gets 20h, e2 80h gets 10h -> both 12.5%
  assert (select round(hours_fixed::numeric,2) from wp_person_load where employee_id = '00000000-0000-0000-0000-0000000000e1') = 20.00, 'e1 20h';
  assert (select round(hours_fixed::numeric,2) from wp_person_load where employee_id = '00000000-0000-0000-0000-0000000000e2') = 10.00, 'e2 10h';
  -- Ops Manager: f2 10h + f3 5h
  assert (select round(hours_fixed::numeric,2) from wp_person_load where employee_id = '00000000-0000-0000-0000-0000000000e3') = 15.00, 'e3 15h';
  assert (select hours_fixed from wp_person_load where employee_id = '00000000-0000-0000-0000-0000000000e4') = 0, 'no-role person 0h';
end $$;
rollback;
