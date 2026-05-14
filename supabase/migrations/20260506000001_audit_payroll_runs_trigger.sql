-- Audit trigger on payroll_runs: every INSERT/UPDATE/DELETE writes one
-- audit_logs row. Status transitions are the audit-critical events:
--   * DRAFT/COMPUTING -> REVIEW    -> APPROVE action ("sent to REVIEW")
--   * REVIEW          -> RELEASED  -> APPROVE action ("RELEASED", includes
--                                    payslip count + total net pay since this
--                                    is the moment money actually moves)
--   * any             -> CANCELLED -> REJECT action
--   * any             -> DRAFT     -> UPDATE  ("reverted to DRAFT")
-- Generic UPDATEs without a status change become 'UPDATE' with a plain
-- description. Description includes the pay-period label (start-end date)
-- by joining pay_periods.
--
-- Mirrors the structure of audit_employees_changes (security definer,
-- auth.uid() actor lookup, jsonb capture of old/new).
--
-- NOTE on enum values: payroll_run_status is
-- ('DRAFT','COMPUTING','REVIEW','RELEASED','CANCELLED') — there is no
-- 'APPROVED'. REVIEW is the approval-pending phase; RELEASED is the
-- post-approval payout phase.

create or replace function audit_payroll_runs_changes()
returns trigger
language plpgsql
security definer
as $$
declare
  v_user_id     uuid;
  v_user_email  varchar(255);
  v_action      audit_action;
  v_old         jsonb;
  v_new         jsonb;
  v_entity_id   uuid;
  v_description text;
  v_period      text;
  v_start_date  date;
  v_end_date    date;
  v_period_id   uuid;
begin
  v_user_id := auth.uid();
  if v_user_id is not null then
    select email::varchar(255) into v_user_email
      from auth.users
      where id = v_user_id;
  end if;

  if tg_op = 'DELETE' then
    v_period_id := old.pay_period_id;
  else
    v_period_id := new.pay_period_id;
  end if;

  select start_date, end_date into v_start_date, v_end_date
    from pay_periods
    where id = v_period_id;

  if v_start_date is not null and v_end_date is not null then
    v_period := format('%s to %s', to_char(v_start_date, 'YYYY-MM-DD'), to_char(v_end_date, 'YYYY-MM-DD'));
  else
    v_period := '(unknown period)';
  end if;

  if tg_op = 'INSERT' then
    v_action := 'CREATE';
    v_new := to_jsonb(new);
    v_entity_id := new.id;
    v_description := format('Payroll run created: %s', v_period);
  elsif tg_op = 'UPDATE' then
    v_old := to_jsonb(old);
    v_new := to_jsonb(new);
    v_entity_id := new.id;

    if old.status is distinct from new.status then
      if new.status = 'REVIEW' then
        v_action := 'APPROVE';
        v_description := format('Payroll run sent to REVIEW: %s', v_period);
      elsif new.status = 'RELEASED' then
        v_action := 'APPROVE';
        v_description := format(
          'Payroll run RELEASED: %s (%s payslips, ₱%s net)',
          v_period,
          new.payslip_count,
          to_char(new.total_net_pay, 'FM999,999,999,990.00')
        );
      elsif new.status = 'CANCELLED' then
        v_action := 'REJECT';
        v_description := format('Payroll run CANCELLED: %s', v_period);
      elsif new.status = 'DRAFT' then
        v_action := 'UPDATE';
        v_description := format('Payroll run reverted to DRAFT: %s', v_period);
      else
        v_action := 'UPDATE';
        v_description := format(
          'Payroll run status changed %s -> %s: %s',
          old.status, new.status, v_period
        );
      end if;
    else
      v_action := 'UPDATE';
      v_description := format('Payroll run updated: %s', v_period);
    end if;
  else
    v_action := 'DELETE';
    v_old := to_jsonb(old);
    v_entity_id := old.id;
    v_description := format('Payroll run deleted: %s', v_period);
  end if;

  insert into audit_logs (
    user_id, user_email, action, entity_type, entity_id,
    old_values, new_values, description
  ) values (
    v_user_id, v_user_email, v_action, 'payroll_runs', v_entity_id,
    v_old, v_new, v_description
  );

  if tg_op = 'DELETE' then
    return old;
  else
    return new;
  end if;
end;
$$;

drop trigger if exists _payroll_runs_audit on payroll_runs;
create trigger _payroll_runs_audit
  after insert or update or delete on payroll_runs
  for each row execute function audit_payroll_runs_changes();
