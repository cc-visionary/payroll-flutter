-- =============================================================================
-- Cascade delete for penalty repayment workflows + a standalone document delete
-- =============================================================================
-- Deleting a REPAYMENT_AGREEMENT workflow left its two children behind: the
-- generated agreement stayed on the Documents list and the penalty stayed on
-- the employee's Financials tab, so removing a mistaken penalty took three
-- separate cleanups (and there was no way at all to remove the document).
--
-- `delete_penalty_workflow` mirrors `delete_compensation_change`
-- (20260710000001), which already removes a comp change's notice document and
-- timeline event alongside the workflow. Guards come from `delete_penalty`
-- (20260715000002) and are checked BEFORE anything is deleted, so a penalty
-- that has touched payroll aborts the whole operation rather than leaving a
-- half-deleted workflow behind.
--
-- Both are SECURITY INVOKER: the existing HR/admin write RLS stays the
-- authorisation boundary, with a row_count check so an RLS-filtered zero-row
-- delete raises DELETE_FORBIDDEN instead of silently succeeding.

-- -----------------------------------------------------------------------------
-- delete_penalty_workflow: workflow + steps + generated documents + penalty
-- -----------------------------------------------------------------------------
create or replace function delete_penalty_workflow(p_instance_id uuid)
returns void
language plpgsql
security invoker
as $$
declare
  v_status  text;
  v_type    text;
  v_penalty uuid;
  v_docs    uuid[];
  v_deleted integer;
begin
  select status,
         workflow_type,
         nullif(context->>'penalty_id', '')::uuid
    into v_status, v_type, v_penalty
    from workflow_instances
   where id = p_instance_id;

  if not found then
    raise exception 'WORKFLOW_NOT_FOUND';
  end if;

  if v_type <> 'REPAYMENT_AGREEMENT' then
    raise exception 'WORKFLOW_NOT_PENALTY';
  end if;

  if v_status <> 'CANCELLED' then
    raise exception 'WORKFLOW_NOT_CANCELLED';
  end if;

  -- Guard first, delete second. The penalty may already be gone (deleted by
  -- hand from the Financials tab) — that is fine, the rest still gets cleaned
  -- up. It is only a blocker when it exists AND has touched payroll.
  if v_penalty is not null
     and exists (select 1 from penalties where id = v_penalty) then
    if exists (
      select 1 from penalty_installments
       where penalty_id = v_penalty and is_deducted
    ) then
      raise exception 'RELEASED_PAYROLL';
    end if;
    if exists (
      select 1 from penalty_installments
       where penalty_id = v_penalty and payroll_run_id is not null
    ) then
      raise exception 'ON_PAYROLL_RUN';
    end if;
  end if;

  -- Collect the agreement(s) before the steps cascade away with the instance.
  select coalesce(
           array_agg(generated_document_id)
             filter (where generated_document_id is not null),
           '{}'::uuid[]
         )
    into v_docs
    from workflow_steps
   where workflow_instance_id = p_instance_id;

  delete from workflow_instances where id = p_instance_id;  -- steps cascade
  get diagnostics v_deleted = row_count;
  if v_deleted = 0 then
    raise exception 'DELETE_FORBIDDEN';
  end if;

  if array_length(v_docs, 1) > 0 then
    -- Self-FK: another document may record this one as its predecessor.
    update employee_documents
       set supersedes_document_id = null
     where supersedes_document_id = any(v_docs);
    delete from employee_documents where id = any(v_docs);
  end if;

  if v_penalty is not null then
    delete from penalties where id = v_penalty;  -- installments cascade
  end if;
end;
$$;

revoke execute on function delete_penalty_workflow(uuid) from public;
grant  execute on function delete_penalty_workflow(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- delete_employee_document: remove one document record
-- -----------------------------------------------------------------------------
-- For the case where the penalty (or whatever the document documented) was
-- already removed by hand and only the paperwork is left over. Nothing in the
-- app could delete a document record before this.
create or replace function delete_employee_document(p_id uuid)
returns void
language plpgsql
security invoker
as $$
declare
  v_deleted integer;
begin
  if not exists (select 1 from employee_documents where id = p_id) then
    raise exception 'DOCUMENT_NOT_FOUND';
  end if;

  -- workflow_steps.generated_document_id and the supersedes self-FK both
  -- reference documents without cascade; unlink rather than block the delete.
  -- The step survives, pointing at nothing, which is accurate: the document it
  -- produced no longer exists.
  update workflow_steps
     set generated_document_id = null
   where generated_document_id = p_id;
  update employee_documents
     set supersedes_document_id = null
   where supersedes_document_id = p_id;

  delete from employee_documents where id = p_id;
  get diagnostics v_deleted = row_count;
  if v_deleted = 0 then
    raise exception 'DELETE_FORBIDDEN';
  end if;
end;
$$;

revoke execute on function delete_employee_document(uuid) from public;
grant  execute on function delete_employee_document(uuid) to authenticated;
