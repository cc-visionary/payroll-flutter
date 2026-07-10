-- 20260710000001_delete_compensation_change.sql
--
-- Hard-deletes a compensation change together with everything it spawned:
-- its workflow (steps cascade), its notice document, and its timeline event.
-- Reverts employees.role_scorecard_id when an APPLIED role change is removed.
--
-- Refuses when a RELEASED payroll run has already paid at that rate: the money
-- went out, so erasing the record would leave the payslip unexplainable. Use
-- "Cancel change" for that case.
--
-- BOTH payroll_runs.period_start AND payroll_runs.period_end are nullable (added
-- with no `set not null` by 20260418000006_drop_pay_periods_resilient.sql), and
-- NULL comparisons/concatenations in Postgres do NOT yield true. So the guard:
--   (a) decides whether to block via `found`, not by inspecting a hint string
--       (`NULL || ' to ' || x` is NULL, which would fail the block open);
--   (b) treats a null period_end as blocking -- `NULL >= effective_date` is NULL,
--       so a plain `period_end >= effective_date` would silently DROP a RELEASED
--       run whose end is unknown from the guard query. We cannot prove such a run
--       did NOT cover this effective date, so we must assume it did and refuse.
--       A run with a KNOWN period_end strictly before the effective date still
--       does not block (it never paid at this rate);
--   (c) builds the hint with coalesce so a null bound renders as '?'.
--
-- SECURITY INVOKER (the default): RLS still applies, so only SUPER_ADMIN/ADMIN/HR
-- can perform the deletes. Everything runs in one transaction, so the guard can
-- never leave partial state.
--
-- The opening lookup runs under the SELECT policy (same company OR SUPER_ADMIN),
-- but the deletes run under the WRITE policy (company + ADMIN/HR OR SUPER_ADMIN).
-- A same-company non-HR caller can therefore SEE the change yet be unable to
-- delete it, and Postgres does NOT raise when RLS filters a DELETE to zero rows.
-- So we check `row_count` after the change delete and raise DELETE_FORBIDDEN when
-- nothing was removed -- returning void there would be a silent no-op the UI
-- would report as a successful destructive action.
--
-- FK order is forced:
--   compensation_changes  (points outward at workflow + document)
--   -> workflow_instances (workflow_steps cascade, releasing generated_document_id)
--   -> employee_documents (generated_from_event_id still references the event)
--   -> employment_events
-- Null workflow_id / document_id / event id are EXPECTED (the confirm handler
-- skips the workflow + notice when it cannot resolve an actor); `where id = null`
-- deletes zero rows, which is intended -- do not raise on them.

create or replace function delete_compensation_change(p_change_id uuid)
returns void
language plpgsql
security invoker
as $$
declare
  v_employee_id    uuid;
  v_effective_date date;
  v_status         text;
  v_prev_scorecard uuid;
  v_new_scorecard  uuid;
  v_workflow_id    uuid;
  v_document_id    uuid;
  v_event_id       uuid;
  v_period_start   date;
  v_period_end     date;
  v_deleted        integer;
begin
  select employee_id, effective_date, status,
         prev_scorecard_id, new_scorecard_id, workflow_id, document_id
    into v_employee_id, v_effective_date, v_status,
         v_prev_scorecard, v_new_scorecard, v_workflow_id, v_document_id
  from compensation_changes
  where id = p_change_id and deleted_at is null;

  if not found then
    raise exception 'CHANGE_NOT_FOUND';
  end if;

  -- Guard: has released payroll already paid at this rate? Detect via `found`,
  -- not via the hint string (period_start/end are nullable and would
  -- NULL-propagate through `||`, failing the guard open). A null period_end is
  -- treated as a possible match and blocks, because `NULL >= effective_date` is
  -- NULL and would otherwise drop the run from the query entirely.
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

  -- Revert the scorecard pointer only when applyDue actually moved it, and the
  -- employee is still sitting on the role this change assigned.
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
    -- Row was visible to the opening SELECT but the write policy filtered the
    -- DELETE to zero rows. `raise` aborts before any dependent delete, so nothing
    -- partial survives; without it the function would silently no-op.
    raise exception 'DELETE_FORBIDDEN';
  end if;

  -- INVARIANT: the three dependent deletes below (workflow_instances,
  -- employee_documents, employment_events) are NOT row_count-guarded, unlike
  -- compensation_changes above. That is intentional -- a null workflow_id /
  -- document_id / event_id legitimately deletes zero rows here (the confirm
  -- handler skips the workflow + notice when it cannot resolve an actor), and
  -- guarding on row_count would raise on that legitimate zero-row case.
  --
  -- This is only safe as long as EVERY ONE of these three tables' write policy
  -- is a SUPERSET of compensation_changes' write policy -- i.e. any caller RLS
  -- allows to delete the change is also allowed to delete its workflow, its
  -- document, and its event. The row_count check above already proved the
  -- caller can delete the change; under the superset assumption that proves
  -- they can delete the dependents too, so skipping the guard here is safe.
  --
  -- If a FUTURE migration ever tightens workflow_instances', employee_documents',
  -- or employment_events' write policy so it is narrower than
  -- compensation_changes' write policy, this invariant breaks silently: the
  -- change (and possibly its workflow) would be deleted while the narrowed
  -- table's delete gets filtered to zero rows by RLS with no raise -- orphaning
  -- the issued notice/workflow/event with no error surfaced to the caller.
  -- Before narrowing any of those three tables' write policies, either restore
  -- policy parity with compensation_changes or add an explicit row_count guard
  -- (matching the compensation_changes pattern above) to the affected delete.
  delete from workflow_instances  where id = v_workflow_id;

  update employee_documents
     set supersedes_document_id = null
   where supersedes_document_id = v_document_id;

  delete from employee_documents where id = v_document_id;
  delete from employment_events  where id = v_event_id;
end;
$$;

-- Least privilege: create function grants EXECUTE to PUBLIC by default (so anon
-- could invoke it). RLS backstops the deletes, but revoke the blanket grant and
-- hand it only to authenticated callers.
revoke execute on function delete_compensation_change(uuid) from public;
grant  execute on function delete_compensation_change(uuid) to authenticated;
