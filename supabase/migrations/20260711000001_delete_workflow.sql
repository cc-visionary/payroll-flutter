-- 20260711000001_delete_workflow.sql
--
-- delete_workflow(p_instance_id): hard-deletes a CANCELLED, standalone workflow
-- together with its steps (FK cascade). Refuses comp-linked workflows -- those
-- MUST go through delete_compensation_change so the change + notice + event are
-- removed together (and to avoid a raw FK violation, since
-- compensation_changes.workflow_id references workflow_instances with no cascade).
--
-- SECURITY INVOKER (default): RLS applies, so only SUPER_ADMIN/ADMIN/HR in the
-- same company can delete. workflow_instances' SELECT policy is broader than its
-- WRITE policy (a same-company non-HR user can SEE but not DELETE), and Postgres
-- does NOT raise when RLS filters a DELETE to zero rows -- so we check row_count
-- and raise DELETE_FORBIDDEN, mirroring delete_compensation_change.

create or replace function delete_workflow(p_instance_id uuid)
returns void
language plpgsql
security invoker
as $$
declare
  v_status  text;
  v_deleted integer;
begin
  select status into v_status
  from workflow_instances
  where id = p_instance_id;

  if not found then
    raise exception 'WORKFLOW_NOT_FOUND';
  end if;

  if v_status <> 'CANCELLED' then
    raise exception 'WORKFLOW_NOT_CANCELLED';
  end if;

  -- Comp-linked workflows are deleted via delete_compensation_change; refuse
  -- here rather than emit a raw FK error from the restrict constraint.
  if exists (select 1 from compensation_changes where workflow_id = p_instance_id) then
    raise exception 'WORKFLOW_HAS_COMPENSATION_CHANGE';
  end if;

  delete from workflow_instances where id = p_instance_id;  -- workflow_steps cascade
  get diagnostics v_deleted = row_count;
  if v_deleted = 0 then
    -- Visible to the opening SELECT but the write policy filtered the DELETE to
    -- zero rows. Raise rather than silently no-op on a destructive action.
    raise exception 'DELETE_FORBIDDEN';
  end if;
end;
$$;

revoke execute on function delete_workflow(uuid) from public;
grant  execute on function delete_workflow(uuid) to authenticated;

-- Refine delete_compensation_change: run the released-payroll guard ONLY when
-- the change actually materialized (applied_at is not null). A change that never
-- applied (SCHEDULED or CANCELLED) never produced a payslip, so erasing it cannot
-- leave a payslip unexplainable -- and blocking it (as the previous unconditional
-- guard did) needlessly prevents deleting a cancelled workflow whose employee has
-- any released run covering the effective date. Changes that DID apply stay
-- protected regardless of later status transitions. Everything else is unchanged
-- from 20260710000001.
create or replace function delete_compensation_change(p_change_id uuid)
returns void
language plpgsql
security invoker
as $$
declare
  v_employee_id    uuid;
  v_effective_date date;
  v_status         text;
  v_applied_at     timestamptz;
  v_prev_scorecard uuid;
  v_new_scorecard  uuid;
  v_workflow_id    uuid;
  v_document_id    uuid;
  v_event_id       uuid;
  v_period_start   date;
  v_period_end     date;
  v_deleted        integer;
begin
  select employee_id, effective_date, status, applied_at,
         prev_scorecard_id, new_scorecard_id, workflow_id, document_id
    into v_employee_id, v_effective_date, v_status, v_applied_at,
         v_prev_scorecard, v_new_scorecard, v_workflow_id, v_document_id
  from compensation_changes
  where id = p_change_id and deleted_at is null;

  if not found then
    raise exception 'CHANGE_NOT_FOUND';
  end if;

  -- Guard only a change that actually paid: applied_at is set. A never-applied
  -- change contributed nothing to any payslip, so deleting it is always safe.
  if v_applied_at is not null then
    select pr.period_start, pr.period_end
      into v_period_start, v_period_end
    from payslips ps
    join payroll_runs pr on pr.id = ps.payroll_run_id
    where ps.employee_id = v_employee_id
      and pr.status = 'RELEASED'
      and (pr.period_end is null or pr.period_end >= v_effective_date)
    limit 1;

    if found then
      raise exception 'RELEASED_PAYROLL'
        using hint = format('%s to %s',
                            coalesce(v_period_start::text, '?'),
                            coalesce(v_period_end::text, '?'));
    end if;
  end if;

  if v_status = 'APPLIED'
     and v_new_scorecard is not null
     and v_new_scorecard is distinct from v_prev_scorecard
     and (select role_scorecard_id from employees where id = v_employee_id) = v_new_scorecard
  then
    update employees set role_scorecard_id = v_prev_scorecard where id = v_employee_id;
  end if;

  select id into v_event_id
  from employment_events
  where employee_id = v_employee_id
    and payload->>'change_id' = p_change_id::text
  limit 1;

  delete from compensation_changes where id = p_change_id;
  get diagnostics v_deleted = row_count;
  if v_deleted = 0 then
    raise exception 'DELETE_FORBIDDEN';
  end if;

  -- Dependent deletes are intentionally NOT row_count-guarded (null ids delete
  -- zero rows legitimately). Safe only while workflow_instances / employee_documents
  -- / employment_events write policies remain a superset of compensation_changes'.
  delete from workflow_instances  where id = v_workflow_id;

  update employee_documents
     set supersedes_document_id = null
   where supersedes_document_id = v_document_id;

  delete from employee_documents where id = v_document_id;
  delete from employment_events  where id = v_event_id;
end;
$$;

revoke execute on function delete_compensation_change(uuid) from public;
grant  execute on function delete_compensation_change(uuid) to authenticated;
