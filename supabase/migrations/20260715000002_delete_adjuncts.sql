-- =============================================================================
-- Hard-delete RPCs for payroll adjuncts: penalties, cash advances, reimbursements
-- =============================================================================
-- The Adjuncts screen was read-only; HR/admin need a way to remove an erroneous
-- or test record. Deletion is refused once the record has touched payroll:
--   * RELEASED_PAYROLL — already deducted/paid on a RELEASED payslip
--     (penalty_installments.is_deducted / cash_advances.is_deducted /
--      reimbursements.is_paid — these flip true only at run release).
--   * ON_PAYROLL_RUN — queued on an UNRELEASED (draft) run
--     (payroll_run_id is not null while the deducted/paid flag is still false).
--     Blocked so we never pull a record out from under a run being reviewed, and
--     so we never hit the raw payslip_lines.<fk> RESTRICT error. Discarding the
--     draft run resets payroll_run_id -> null and re-enables deletion.
--
-- Deleting a penalty cascades its penalty_installments (FK ON DELETE CASCADE).
--
-- Pattern mirrors delete_compensation_change (20260710000001): SECURITY INVOKER
-- so the existing HR/admin write RLS on each table stays the authorisation
-- boundary, plus a row_count check so an RLS-filtered zero-row delete raises
-- DELETE_FORBIDDEN instead of silently succeeding. All in one transaction.

-- -----------------------------------------------------------------------------
-- penalties
-- -----------------------------------------------------------------------------
create or replace function delete_penalty(p_id uuid)
returns void
language plpgsql
security invoker
as $$
declare
  v_deleted integer;
begin
  if not exists (select 1 from penalties where id = p_id) then
    raise exception 'PENALTY_NOT_FOUND';
  end if;

  -- Released: any installment already deducted on a released payslip.
  if exists (
    select 1 from penalty_installments
     where penalty_id = p_id and is_deducted
  ) then
    raise exception 'RELEASED_PAYROLL';
  end if;

  -- Draft-queued: any installment sitting on an unreleased payroll run.
  if exists (
    select 1 from penalty_installments
     where penalty_id = p_id and payroll_run_id is not null
  ) then
    raise exception 'ON_PAYROLL_RUN';
  end if;

  delete from penalties where id = p_id;  -- installments cascade
  get diagnostics v_deleted = row_count;
  if v_deleted = 0 then
    raise exception 'DELETE_FORBIDDEN';
  end if;
end;
$$;

revoke execute on function delete_penalty(uuid) from public;
grant  execute on function delete_penalty(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- cash_advances
-- -----------------------------------------------------------------------------
create or replace function delete_cash_advance(p_id uuid)
returns void
language plpgsql
security invoker
as $$
declare
  v_is_deducted boolean;
  v_run         uuid;
  v_deleted     integer;
begin
  select is_deducted, payroll_run_id
    into v_is_deducted, v_run
    from cash_advances
   where id = p_id;
  if not found then
    raise exception 'CASH_ADVANCE_NOT_FOUND';
  end if;

  if v_is_deducted then
    raise exception 'RELEASED_PAYROLL';
  end if;
  if v_run is not null then
    raise exception 'ON_PAYROLL_RUN';
  end if;

  delete from cash_advances where id = p_id;
  get diagnostics v_deleted = row_count;
  if v_deleted = 0 then
    raise exception 'DELETE_FORBIDDEN';
  end if;
end;
$$;

revoke execute on function delete_cash_advance(uuid) from public;
grant  execute on function delete_cash_advance(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- reimbursements
-- -----------------------------------------------------------------------------
create or replace function delete_reimbursement(p_id uuid)
returns void
language plpgsql
security invoker
as $$
declare
  v_is_paid boolean;
  v_run     uuid;
  v_deleted integer;
begin
  select is_paid, payroll_run_id
    into v_is_paid, v_run
    from reimbursements
   where id = p_id;
  if not found then
    raise exception 'REIMBURSEMENT_NOT_FOUND';
  end if;

  if v_is_paid then
    raise exception 'RELEASED_PAYROLL';
  end if;
  if v_run is not null then
    raise exception 'ON_PAYROLL_RUN';
  end if;

  delete from reimbursements where id = p_id;
  get diagnostics v_deleted = row_count;
  if v_deleted = 0 then
    raise exception 'DELETE_FORBIDDEN';
  end if;
end;
$$;

revoke execute on function delete_reimbursement(uuid) from public;
grant  execute on function delete_reimbursement(uuid) to authenticated;
