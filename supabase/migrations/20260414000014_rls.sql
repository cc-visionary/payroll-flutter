-- Row-Level Security: enable on every table + scaffold policies.
-- Uses helpers: auth_app_role(), auth_company_id(), auth_employee_id() from migration 1.
-- Policies are intentionally scaffolded (not exhaustive) — refined per feature later.

-- =============================================================================
-- Enable RLS on every application table
-- =============================================================================
alter table companies                  enable row level security;
alter table hiring_entities            enable row level security;
alter table holiday_calendars          enable row level security;
alter table calendar_events            enable row level security;
alter table departments                enable row level security;
alter table users                      enable row level security;
alter table roles                      enable row level security;
alter table user_roles                 enable row level security;
alter table user_companies             enable row level security;
alter table sessions                   enable row level security;
alter table shift_templates            enable row level security;
alter table role_scorecards            enable row level security;
alter table employees                  enable row level security;
alter table employee_statutory_ids     enable row level security;
alter table employee_bank_accounts     enable row level security;
alter table employment_events          enable row level security;
alter table employee_documents         enable row level security;
alter table applicants                 enable row level security;
alter table interviews                 enable row level security;
alter table attendance_imports         enable row level security;
alter table attendance_day_records     enable row level security;
alter table leave_types                enable row level security;
alter table leave_balances             enable row level security;
alter table leave_requests             enable row level security;
alter table payroll_calendars          enable row level security;
alter table pay_periods                enable row level security;
alter table payroll_runs               enable row level security;
alter table payslips                   enable row level security;
alter table payslip_lines              enable row level security;
alter table manual_adjustment_lines    enable row level security;
alter table penalty_types              enable row level security;
alter table penalties                  enable row level security;
alter table penalty_installments       enable row level security;
alter table cash_advances              enable row level security;
alter table reimbursements             enable row level security;
alter table no_break_requests          enable row level security;
alter table bank_files                 enable row level security;
alter table export_artifacts           enable row level security;
alter table audit_logs                 enable row level security;
alter table lark_sync_logs             enable row level security;
alter table check_in_periods           enable row level security;
alter table performance_check_ins      enable row level security;
alter table check_in_goals             enable row level security;
alter table skill_ratings              enable row level security;
alter table workflow_instances         enable row level security;
alter table workflow_steps             enable row level security;

-- =============================================================================
-- Admin-only tables (roles, audit_logs, bank_files, export_artifacts,
-- lark_sync_logs, attendance_imports)
-- =============================================================================
create policy roles_admin_all on roles for all
  using (auth_app_role() in ('SUPER_ADMIN','ADMIN'))
  with check (auth_app_role() in ('SUPER_ADMIN','ADMIN'));

create policy audit_logs_admin_read on audit_logs for select
  using (auth_app_role() in ('SUPER_ADMIN','ADMIN'));
create policy audit_logs_insert_any on audit_logs for insert
  with check (true);  -- any authenticated user can append; edits blocked (no update/delete policy)

create policy bank_files_admin_all on bank_files for all
  using (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR'));
create policy export_artifacts_admin_all on export_artifacts for all
  using (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR'));
create policy lark_sync_logs_admin_all on lark_sync_logs for all
  using (auth_app_role() in ('SUPER_ADMIN','ADMIN'));
create policy attendance_imports_admin_all on attendance_imports for all
  using (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR'));

create policy sessions_owner on sessions for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- =============================================================================
-- Reusable macro: company-scoped tables (select/insert/update/delete)
-- =============================================================================
-- companies
create policy companies_select on companies for select
  using (id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN');
create policy companies_write on companies for all
  using (auth_app_role() = 'SUPER_ADMIN')
  with check (auth_app_role() = 'SUPER_ADMIN');

-- hiring_entities / holiday_calendars / calendar_events / departments /
-- role_scorecards / shift_templates / leave_types / payroll_calendars /
-- pay_periods (via calendar) / payroll_runs (via pay_period) / penalty_types /
-- cash_advances / reimbursements / no_break_requests / check_in_periods /
-- workflow_instances / applicants
do $$
declare t text;
begin
  foreach t in array array[
    'hiring_entities','holiday_calendars','departments',
    'role_scorecards','shift_templates','leave_types','payroll_calendars',
    'penalty_types','cash_advances','reimbursements','no_break_requests',
    'check_in_periods','workflow_instances','applicants'
  ]
  loop
    execute format($f$
      create policy %1$I_company_select on %1$I for select
        using (company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN');
      create policy %1$I_company_write on %1$I for all
        using ((auth_app_role() in ('SUPER_ADMIN','ADMIN','HR')) and (company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN'))
        with check ((auth_app_role() in ('SUPER_ADMIN','ADMIN','HR')) and (company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN'));
    $f$, t);
  end loop;
end $$;

-- calendar_events — scoped via holiday_calendars.company_id
create policy calendar_events_select on calendar_events for select using (
  exists (select 1 from holiday_calendars hc where hc.id = calendar_id and (hc.company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN'))
);
create policy calendar_events_write on calendar_events for all using (
  auth_app_role() in ('SUPER_ADMIN','ADMIN','HR')
  and exists (select 1 from holiday_calendars hc where hc.id = calendar_id and (hc.company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN'))
);

-- =============================================================================
-- People: users, user_roles, user_companies
-- =============================================================================
create policy users_self_read on users for select using (
  id = auth.uid()
  or auth_app_role() in ('SUPER_ADMIN','ADMIN','HR')
);
create policy users_admin_write on users for all
  using (auth_app_role() in ('SUPER_ADMIN','ADMIN'))
  with check (auth_app_role() in ('SUPER_ADMIN','ADMIN'));

create policy user_roles_admin_all on user_roles for all
  using (auth_app_role() in ('SUPER_ADMIN','ADMIN'));
create policy user_companies_admin_all on user_companies for all
  using (auth_app_role() in ('SUPER_ADMIN','ADMIN'));

-- =============================================================================
-- Employees — self, direct reports, or company admin
-- =============================================================================
create policy employees_read on employees for select using (
  (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR') and company_id = auth_company_id())
  or id = auth_employee_id()
  or reports_to_id = auth_employee_id()
);
create policy employees_admin_write on employees for all
  using (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR') and company_id = auth_company_id())
  with check (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR') and company_id = auth_company_id());

-- Employee-scoped children
do $$
declare t text;
begin
  foreach t in array array[
    'employee_statutory_ids','employee_bank_accounts','employment_events',
    'employee_documents','leave_balances','leave_requests','penalties',
    'performance_check_ins'
  ]
  loop
    execute format($f$
      create policy %1$I_read on %1$I for select using (
        auth_app_role() in ('SUPER_ADMIN','ADMIN','HR')
        or exists (select 1 from employees e where e.id = employee_id and (e.id = auth_employee_id() or e.reports_to_id = auth_employee_id()))
      );
      create policy %1$I_admin_write on %1$I for all using (
        auth_app_role() in ('SUPER_ADMIN','ADMIN','HR')
      );
    $f$, t);
  end loop;
end $$;

-- Interviews — admins + HR + the primary interviewer
create policy interviews_read on interviews for select using (
  auth_app_role() in ('SUPER_ADMIN','ADMIN','HR')
  or primary_interviewer_id = auth_employee_id()
);
create policy interviews_admin_write on interviews for all
  using (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR'));

-- =============================================================================
-- Attendance
-- =============================================================================
create policy attendance_day_records_read on attendance_day_records for select using (
  auth_app_role() in ('SUPER_ADMIN','ADMIN','HR')
  or exists (select 1 from employees e where e.id = employee_id and (e.id = auth_employee_id() or e.reports_to_id = auth_employee_id()))
);
create policy attendance_day_records_admin_write on attendance_day_records for all
  using (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR'));

-- =============================================================================
-- Payroll
-- =============================================================================
-- pay_periods: via calendar -> company
create policy pay_periods_select on pay_periods for select using (
  exists (select 1 from payroll_calendars pc where pc.id = calendar_id and (pc.company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN'))
);
create policy pay_periods_write on pay_periods for all using (
  auth_app_role() in ('SUPER_ADMIN','ADMIN','HR')
  and exists (select 1 from payroll_calendars pc where pc.id = calendar_id and (pc.company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN'))
);

-- payroll_runs: via pay_period -> calendar -> company
create policy payroll_runs_select on payroll_runs for select using (
  auth_app_role() in ('SUPER_ADMIN','ADMIN','HR')
  or exists (
    select 1 from pay_periods pp
    join payroll_calendars pc on pc.id = pp.calendar_id
    where pp.id = pay_period_id and pc.company_id = auth_company_id()
  )
);
create policy payroll_runs_admin_write on payroll_runs for all
  using (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR'));

-- payslips: employee self + admins
create policy payslips_read on payslips for select using (
  auth_app_role() in ('SUPER_ADMIN','ADMIN','HR')
  or employee_id = auth_employee_id()
);
create policy payslips_admin_write on payslips for all
  using (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR'));

-- payslip_lines: via payslip
create policy payslip_lines_read on payslip_lines for select using (
  auth_app_role() in ('SUPER_ADMIN','ADMIN','HR')
  or exists (select 1 from payslips p where p.id = payslip_id and p.employee_id = auth_employee_id())
);
create policy payslip_lines_admin_write on payslip_lines for all
  using (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR'));

-- manual_adjustment_lines: admin only
create policy manual_adjustment_lines_admin_all on manual_adjustment_lines for all
  using (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR'));

-- penalty_installments: via penalty -> employee
create policy penalty_installments_read on penalty_installments for select using (
  auth_app_role() in ('SUPER_ADMIN','ADMIN','HR')
  or exists (select 1 from penalties pen where pen.id = penalty_id and pen.employee_id = auth_employee_id())
);
create policy penalty_installments_admin_write on penalty_installments for all
  using (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR'));

-- check_in_goals / skill_ratings: via performance_check_ins -> employee
create policy check_in_goals_read on check_in_goals for select using (
  auth_app_role() in ('SUPER_ADMIN','ADMIN','HR')
  or exists (select 1 from performance_check_ins pci where pci.id = check_in_id and pci.employee_id = auth_employee_id())
);
create policy check_in_goals_admin_write on check_in_goals for all
  using (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR') or exists (
    select 1 from performance_check_ins pci where pci.id = check_in_id and pci.employee_id = auth_employee_id()
  ));

create policy skill_ratings_read on skill_ratings for select using (
  auth_app_role() in ('SUPER_ADMIN','ADMIN','HR')
  or exists (select 1 from performance_check_ins pci where pci.id = check_in_id and pci.employee_id = auth_employee_id())
);
create policy skill_ratings_admin_write on skill_ratings for all
  using (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR'));

-- workflow_steps: via workflow_instance -> employee
create policy workflow_steps_read on workflow_steps for select using (
  auth_app_role() in ('SUPER_ADMIN','ADMIN','HR')
  or exists (select 1 from workflow_instances wi where wi.id = workflow_instance_id and (wi.employee_id = auth_employee_id() or wi.initiated_by_id = auth.uid()))
);
create policy workflow_steps_admin_write on workflow_steps for all
  using (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR'));
