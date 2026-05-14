-- Bug fix for 20260506000001_audit_payroll_runs_trigger.sql.
--
-- The original trigger referenced `new.pay_period_id` and looked up
-- start_date/end_date from `pay_periods`. But migration
-- 20260418000006_drop_pay_periods_resilient.sql dropped the
-- pay_period_id column and added period_start / period_end / pay_date
-- directly onto payroll_runs. The bad reference raised
-- `record "new" has no field "pay_period_id" (code 42703)` and
-- aborted every payroll-run INSERT/UPDATE.
--
-- Fix: read period_start/period_end directly from the row. No join.

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
  v_range       text;
  v_start       date;
  v_end         date;
begin
  v_user_id := auth.uid();
  if v_user_id is not null then
    select email::varchar(255) into v_user_email
      from auth.users
      where id = v_user_id;
  end if;

  if tg_op = 'DELETE' then
    v_start := old.period_start;
    v_end   := old.period_end;
  else
    v_start := new.period_start;
    v_end   := new.period_end;
  end if;

  if v_start is not null and v_end is not null then
    v_range := format('%s to %s',
      to_char(v_start, 'YYYY-MM-DD'),
      to_char(v_end,   'YYYY-MM-DD'));
  else
    v_range := '(unknown period)';
  end if;

  if tg_op = 'INSERT' then
    v_action := 'CREATE';
    v_new := to_jsonb(new);
    v_entity_id := new.id;
    v_description := format('Payroll run created: %s', v_range);
  elsif tg_op = 'UPDATE' then
    v_old := to_jsonb(old);
    v_new := to_jsonb(new);
    v_entity_id := new.id;

    if old.status is distinct from new.status then
      if new.status = 'REVIEW' then
        v_action := 'APPROVE';
        v_description := format('Payroll run sent to REVIEW: %s', v_range);
      elsif new.status = 'RELEASED' then
        v_action := 'APPROVE';
        v_description := format(
          'Payroll run RELEASED: %s (%s payslips, ₱%s net)',
          v_range,
          new.payslip_count,
          to_char(new.total_net_pay, 'FM999,999,999,990.00')
        );
      elsif new.status = 'CANCELLED' then
        v_action := 'REJECT';
        v_description := format('Payroll run CANCELLED: %s', v_range);
      elsif new.status = 'DRAFT' then
        v_action := 'UPDATE';
        v_description := format('Payroll run reverted to DRAFT: %s', v_range);
      else
        v_action := 'UPDATE';
        v_description := format(
          'Payroll run status changed %s -> %s: %s',
          old.status, new.status, v_range
        );
      end if;
    else
      v_action := 'UPDATE';
      v_description := format('Payroll run updated: %s', v_range);
    end if;
  else
    v_action := 'DELETE';
    v_old := to_jsonb(old);
    v_entity_id := old.id;
    v_description := format('Payroll run deleted: %s', v_range);
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
