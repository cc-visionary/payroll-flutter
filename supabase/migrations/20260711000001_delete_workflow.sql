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
