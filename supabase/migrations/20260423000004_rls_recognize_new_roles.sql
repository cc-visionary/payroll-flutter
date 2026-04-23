-- Recognize the extended app_role values (HR_ADMIN, PAYROLL_ADMIN, FINANCE_MANAGER)
-- in every RLS policy that previously accepted only ('SUPER_ADMIN','ADMIN','HR').
--
-- Background: the `app_role` enum was extended in 20260420000002_user_management
-- so the `manage-user` edge function could stamp the real role code into
-- `app_metadata.app_role`. But the original RLS policies (20260414000014_rls.sql)
-- were written against only the legacy 3-value list, so a user provisioned with
-- role_code = 'HR_ADMIN' via the Users settings UI failed every HR-gated policy
-- and saw an empty roster.
--
-- This migration introduces `auth_is_hr_or_admin()` covering all HR- and
-- admin-level roles, and rewrites every affected policy to use it. Strictly
-- less permissive than the previous seed behavior (which stamped PAYROLL_ADMIN
-- and FINANCE_MANAGER as literal 'ADMIN', granting them user/role/audit-log
-- admin rights they should not have). Policies that are intentionally
-- SUPER_ADMIN/ADMIN only (roles, audit_logs, lark_sync_logs, users_admin_write,
-- user_roles, user_companies, companies, company_settings) are NOT expanded.

create or replace function auth_is_hr_or_admin() returns boolean
  language sql stable as $$
    select auth_app_role() in (
      'SUPER_ADMIN', 'ADMIN', 'HR',
      'HR_ADMIN', 'PAYROLL_ADMIN', 'FINANCE_MANAGER'
    )
  $$;

-- =============================================================================
-- Admin-ish tables that previously allowed 'HR'
-- =============================================================================
drop policy if exists bank_files_admin_all on bank_files;
create policy bank_files_admin_all on bank_files for all
  using (auth_is_hr_or_admin());

drop policy if exists export_artifacts_admin_all on export_artifacts;
create policy export_artifacts_admin_all on export_artifacts for all
  using (auth_is_hr_or_admin());

drop policy if exists attendance_imports_admin_all on attendance_imports;
create policy attendance_imports_admin_all on attendance_imports for all
  using (auth_is_hr_or_admin());

-- =============================================================================
-- Company-scoped tables (regenerated via the same loop used in 14000014)
-- =============================================================================
do $$
declare t text;
begin
  foreach t in array array[
    'hiring_entities','holiday_calendars','departments',
    'role_scorecards','shift_templates','leave_types',
    'penalty_types','cash_advances','reimbursements','no_break_requests',
    'check_in_periods','workflow_instances','applicants'
  ]
  loop
    execute format('drop policy if exists %1$I_company_write on %1$I', t);
    execute format($f$
      create policy %1$I_company_write on %1$I for all
        using (auth_is_hr_or_admin() and (company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN'))
        with check (auth_is_hr_or_admin() and (company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN'));
    $f$, t);
  end loop;
end $$;

-- calendar_events — scoped via holiday_calendars.company_id
drop policy if exists calendar_events_write on calendar_events;
create policy calendar_events_write on calendar_events for all using (
  auth_is_hr_or_admin()
  and exists (
    select 1 from holiday_calendars hc
     where hc.id = calendar_id
       and (hc.company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN')
  )
);

-- =============================================================================
-- users self-read — second OR clause expanded
-- =============================================================================
drop policy if exists users_self_read on users;
create policy users_self_read on users for select using (
  id = auth.uid() or auth_is_hr_or_admin()
);

-- =============================================================================
-- employees — the bug that triggered this migration
-- =============================================================================
drop policy if exists employees_read on employees;
create policy employees_read on employees for select using (
  (auth_is_hr_or_admin() and company_id = auth_company_id())
  or id = auth_employee_id()
  or reports_to_id = auth_employee_id()
);

drop policy if exists employees_admin_write on employees;
create policy employees_admin_write on employees for all
  using (auth_is_hr_or_admin() and company_id = auth_company_id())
  with check (auth_is_hr_or_admin() and company_id = auth_company_id());

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
    execute format('drop policy if exists %1$I_read on %1$I', t);
    execute format('drop policy if exists %1$I_admin_write on %1$I', t);
    execute format($f$
      create policy %1$I_read on %1$I for select using (
        auth_is_hr_or_admin()
        or exists (select 1 from employees e where e.id = employee_id and (e.id = auth_employee_id() or e.reports_to_id = auth_employee_id()))
      );
      create policy %1$I_admin_write on %1$I for all using (
        auth_is_hr_or_admin()
      );
    $f$, t);
  end loop;
end $$;

-- Interviews
drop policy if exists interviews_read on interviews;
create policy interviews_read on interviews for select using (
  auth_is_hr_or_admin()
  or primary_interviewer_id = auth_employee_id()
);
drop policy if exists interviews_admin_write on interviews;
create policy interviews_admin_write on interviews for all
  using (auth_is_hr_or_admin());

-- =============================================================================
-- Attendance
-- =============================================================================
drop policy if exists attendance_day_records_read on attendance_day_records;
create policy attendance_day_records_read on attendance_day_records for select using (
  auth_is_hr_or_admin()
  or exists (select 1 from employees e where e.id = employee_id and (e.id = auth_employee_id() or e.reports_to_id = auth_employee_id()))
);
drop policy if exists attendance_day_records_admin_write on attendance_day_records;
create policy attendance_day_records_admin_write on attendance_day_records for all
  using (auth_is_hr_or_admin());

-- =============================================================================
-- Payroll
-- =============================================================================
-- payroll_runs_admin_write was last redefined in 20260418000006_drop_pay_periods_resilient.
-- Rewrite again using the helper.
drop policy if exists payroll_runs_admin_write on payroll_runs;
create policy payroll_runs_admin_write on payroll_runs for all
  using (
    auth_is_hr_or_admin()
    and (company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN')
  )
  with check (
    auth_is_hr_or_admin()
    and (company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN')
  );

-- payslips
drop policy if exists payslips_read on payslips;
create policy payslips_read on payslips for select using (
  auth_is_hr_or_admin()
  or employee_id = auth_employee_id()
);
drop policy if exists payslips_admin_write on payslips;
create policy payslips_admin_write on payslips for all
  using (auth_is_hr_or_admin());

-- payslip_lines
drop policy if exists payslip_lines_read on payslip_lines;
create policy payslip_lines_read on payslip_lines for select using (
  auth_is_hr_or_admin()
  or exists (select 1 from payslips p where p.id = payslip_id and p.employee_id = auth_employee_id())
);
drop policy if exists payslip_lines_admin_write on payslip_lines;
create policy payslip_lines_admin_write on payslip_lines for all
  using (auth_is_hr_or_admin());

drop policy if exists manual_adjustment_lines_admin_all on manual_adjustment_lines;
create policy manual_adjustment_lines_admin_all on manual_adjustment_lines for all
  using (auth_is_hr_or_admin());

drop policy if exists penalty_installments_read on penalty_installments;
create policy penalty_installments_read on penalty_installments for select using (
  auth_is_hr_or_admin()
  or exists (select 1 from penalties pen where pen.id = penalty_id and pen.employee_id = auth_employee_id())
);
drop policy if exists penalty_installments_admin_write on penalty_installments;
create policy penalty_installments_admin_write on penalty_installments for all
  using (auth_is_hr_or_admin());

-- check_in_goals / skill_ratings
drop policy if exists check_in_goals_read on check_in_goals;
create policy check_in_goals_read on check_in_goals for select using (
  auth_is_hr_or_admin()
  or exists (select 1 from performance_check_ins pci where pci.id = check_in_id and pci.employee_id = auth_employee_id())
);
drop policy if exists check_in_goals_admin_write on check_in_goals;
create policy check_in_goals_admin_write on check_in_goals for all
  using (
    auth_is_hr_or_admin()
    or exists (select 1 from performance_check_ins pci where pci.id = check_in_id and pci.employee_id = auth_employee_id())
  );

drop policy if exists skill_ratings_read on skill_ratings;
create policy skill_ratings_read on skill_ratings for select using (
  auth_is_hr_or_admin()
  or exists (select 1 from performance_check_ins pci where pci.id = check_in_id and pci.employee_id = auth_employee_id())
);
drop policy if exists skill_ratings_admin_write on skill_ratings;
create policy skill_ratings_admin_write on skill_ratings for all
  using (auth_is_hr_or_admin());

-- workflow_steps
drop policy if exists workflow_steps_read on workflow_steps;
create policy workflow_steps_read on workflow_steps for select using (
  auth_is_hr_or_admin()
  or exists (select 1 from workflow_instances wi where wi.id = workflow_instance_id and (wi.employee_id = auth_employee_id() or wi.initiated_by_id = auth.uid()))
);
drop policy if exists workflow_steps_admin_write on workflow_steps;
create policy workflow_steps_admin_write on workflow_steps for all
  using (auth_is_hr_or_admin());

-- =============================================================================
-- hiring_entity_bank_accounts (20260418000001)
-- =============================================================================
drop policy if exists hiring_entity_bank_accounts_write on hiring_entity_bank_accounts;
create policy hiring_entity_bank_accounts_write on hiring_entity_bank_accounts
  for all using (
    auth_is_hr_or_admin()
    and exists (
      select 1 from hiring_entities he
       where he.id = hiring_entity_id
         and (he.company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN')
    )
  ) with check (
    auth_is_hr_or_admin()
    and exists (
      select 1 from hiring_entities he
       where he.id = hiring_entity_id
         and (he.company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN')
    )
  );

-- =============================================================================
-- statutory_payments (20260423000001)
-- =============================================================================
drop policy if exists statutory_payments_hr_read on statutory_payments;
create policy statutory_payments_hr_read on statutory_payments for select
  using (auth_is_hr_or_admin());

drop policy if exists statutory_payments_hr_write on statutory_payments;
create policy statutory_payments_hr_write on statutory_payments for all
  using (auth_is_hr_or_admin())
  with check (auth_is_hr_or_admin());
