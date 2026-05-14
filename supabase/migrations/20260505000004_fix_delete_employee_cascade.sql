-- Bug fix for 20260505000003_delete_employee_cascade.sql.
--
-- The original RPC tried to NULL `primary_interviewer_id` on the
-- `applicants` table, but that column lives on `interviews`. The bad
-- statement raised `column "primary_interviewer_id" does not exist
-- (code 42703)` and aborted every hard-delete attempt.
--
-- Fixes:
--   - Move the primary_interviewer_id unlink to the `interviews` table.
--   - Also clear the employee from `interviews.interviewer_ids uuid[]`
--     (an array we missed in the original migration).
-- Everything else is unchanged.

create or replace function delete_employee_cascade(_employee_id uuid)
returns void
language plpgsql
security definer
as $$
declare
  v_role text;
begin
  -- Authorization: SUPER_ADMIN only.
  v_role := auth_app_role();
  if v_role is null or v_role <> 'SUPER_ADMIN' then
    raise exception 'Only SUPER_ADMIN can hard-delete employees'
      using errcode = '42501';
  end if;

  -- Unlink applicant references (preserve applicant rows).
  update applicants set converted_to_employee_id = null
    where converted_to_employee_id = _employee_id;
  update applicants set referred_by_id = null
    where referred_by_id = _employee_id;

  -- Unlink interview references (NOT applicants — separate table).
  update interviews set primary_interviewer_id = null
    where primary_interviewer_id = _employee_id;
  update interviews
    set interviewer_ids = array_remove(interviewer_ids, _employee_id)
    where _employee_id = any(interviewer_ids);

  -- Unlink org-chart references.
  update employees set reports_to_id = null
    where reports_to_id = _employee_id;
  -- departments.manager_id has ON DELETE SET NULL (employees migration
  -- line 159), so no manual unlink is needed.

  -- Hard-delete non-cascading children.
  delete from payslip_lines
    where payslip_id in (select id from payslips where employee_id = _employee_id);
  delete from payslips where employee_id = _employee_id;
  delete from attendance_day_records where employee_id = _employee_id;
  delete from workflow_instances where employee_id = _employee_id;
  delete from manual_adjustment_lines where employee_id = _employee_id;

  -- Finally: the employee row. The audit trigger writes the DELETE row.
  delete from employees where id = _employee_id;
end;
$$;

grant execute on function delete_employee_cascade(uuid) to authenticated;
