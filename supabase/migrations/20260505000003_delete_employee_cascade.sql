-- Hard-delete an employee with full cascade across non-cascading FKs.
-- Use this only for cancelled candidates / data-entry mistakes;
-- normally separated employees should be archived (deleted_at set)
-- to preserve their history.
--
-- FKs that don't cascade are handled explicitly here:
--   attendance_day_records, payslips (+ payslip_lines via cascade),
--   manual_adjustment_lines, workflow_instances,
--   applicants.{converted_to_employee_id, primary_interviewer_id,
--   referred_by_id}, employees.reports_to_id.
-- departments.manager_id already has ON DELETE SET NULL on its FK
-- (see 20260414000005_employees.sql), so no explicit handling needed.
-- All other child tables (employee_documents, leave_*, cash_advances,
-- reimbursements, penalties, salaries, employee_addresses, employment_
-- events, performance_reviews, no_break_requests, employee_bank_*) cascade
-- automatically via ON DELETE CASCADE.
--
-- The trigger from migration 20260505000002_audit_employees_trigger.sql
-- captures the final DELETE row in audit_logs.

create or replace function delete_employee_cascade(_employee_id uuid)
returns void
language plpgsql
security definer
as $$
declare
  v_role text;
begin
  -- Authorization: SUPER_ADMIN only. Mirrors the existing role-check
  -- pattern using the auth_app_role() helper from migration
  -- 20260414000001_enums_and_helpers.sql.
  v_role := auth_app_role();
  if v_role is null or v_role <> 'SUPER_ADMIN' then
    raise exception 'Only SUPER_ADMIN can hard-delete employees'
      using errcode = '42501';  -- insufficient_privilege
  end if;

  -- Unlink applicant references (preserve applicant rows).
  update applicants set converted_to_employee_id = null
    where converted_to_employee_id = _employee_id;
  update applicants set primary_interviewer_id = null
    where primary_interviewer_id = _employee_id;
  update applicants set referred_by_id = null
    where referred_by_id = _employee_id;

  -- Unlink org-chart references (departments.manager_id already cascades
  -- to NULL via FK definition, so no manual unlink needed there).
  update employees set reports_to_id = null
    where reports_to_id = _employee_id;

  -- Hard-delete non-cascading children.
  -- payslip_lines cascade from payslips, but we delete them explicitly
  -- first for clarity / in case the FK definition ever changes.
  delete from payslip_lines
    where payslip_id in (select id from payslips where employee_id = _employee_id);
  delete from payslips where employee_id = _employee_id;
  delete from manual_adjustment_lines where employee_id = _employee_id;
  delete from attendance_day_records where employee_id = _employee_id;
  delete from workflow_instances where employee_id = _employee_id;

  -- Finally: the employee row. The audit trigger writes the DELETE row.
  -- Cascading children (employment_events, employee_documents, leave_*,
  -- cash_advances, reimbursements, penalties, salaries, etc.) clean up
  -- automatically via their ON DELETE CASCADE.
  delete from employees where id = _employee_id;
end;
$$;

grant execute on function delete_employee_cascade(uuid) to authenticated;
