-- Audit trigger on payslips: every INSERT/UPDATE/DELETE writes one
-- audit_logs row. Description includes the employee's full name (looked
-- up via employees) and the payslip_number for material context, plus
-- the net pay on INSERT (where it's a brand-new computed value).
--
-- PERFORMANCE NOTE: payslips are bulk-inserted when a payroll run is
-- computed (typically hundreds of rows per run, one per employee). This
-- trigger writes one audit_logs row per payslip, which is acceptable
-- for the volume but worth flagging: a run with 500 employees writes
-- 500 audit rows in a single transaction. If this becomes a hot path,
-- consider switching to a statement-level trigger with a summary row.
--
-- Mirrors the structure of audit_employees_changes (security definer,
-- auth.uid() actor lookup, jsonb capture of old/new).

create or replace function audit_payslips_changes()
returns trigger
language plpgsql
security definer
as $$
declare
  v_user_id        uuid;
  v_user_email     varchar(255);
  v_action         audit_action;
  v_old            jsonb;
  v_new            jsonb;
  v_entity_id      uuid;
  v_description    text;
  v_emp_id         uuid;
  v_name           text;
  v_payslip_number varchar(50);
  v_first          varchar(100);
  v_middle         varchar(100);
  v_last           varchar(100);
begin
  v_user_id := auth.uid();
  if v_user_id is not null then
    select email::varchar(255) into v_user_email
      from auth.users
      where id = v_user_id;
  end if;

  if tg_op = 'DELETE' then
    v_emp_id := old.employee_id;
    v_payslip_number := old.payslip_number;
  else
    v_emp_id := new.employee_id;
    v_payslip_number := new.payslip_number;
  end if;

  select first_name, middle_name, last_name
    into v_first, v_middle, v_last
    from employees
    where id = v_emp_id;

  v_name := trim(coalesce(v_first, '') || ' ' || coalesce(v_middle || ' ', '') || coalesce(v_last, ''));
  if v_name = '' then
    v_name := '(unknown employee)';
  end if;

  if tg_op = 'INSERT' then
    v_action := 'CREATE';
    v_new := to_jsonb(new);
    v_entity_id := new.id;
    if v_payslip_number is null or v_payslip_number = '' then
      v_description := format(
        'Payslip created: %s · ₱%s',
        v_name,
        to_char(new.net_pay, 'FM999,999,999,990.00')
      );
    else
      v_description := format(
        'Payslip created: %s · %s · ₱%s',
        v_name,
        v_payslip_number,
        to_char(new.net_pay, 'FM999,999,999,990.00')
      );
    end if;
  elsif tg_op = 'UPDATE' then
    v_action := 'UPDATE';
    v_old := to_jsonb(old);
    v_new := to_jsonb(new);
    v_entity_id := new.id;
    if v_payslip_number is null or v_payslip_number = '' then
      v_description := format('Payslip updated: %s', v_name);
    else
      v_description := format('Payslip updated: %s · %s', v_name, v_payslip_number);
    end if;
  else
    v_action := 'DELETE';
    v_old := to_jsonb(old);
    v_entity_id := old.id;
    if v_payslip_number is null or v_payslip_number = '' then
      v_description := format('Payslip deleted: %s', v_name);
    else
      v_description := format('Payslip deleted: %s · %s', v_name, v_payslip_number);
    end if;
  end if;

  insert into audit_logs (
    user_id, user_email, action, entity_type, entity_id,
    old_values, new_values, description
  ) values (
    v_user_id, v_user_email, v_action, 'payslips', v_entity_id,
    v_old, v_new, v_description
  );

  if tg_op = 'DELETE' then
    return old;
  else
    return new;
  end if;
end;
$$;

drop trigger if exists _payslips_audit on payslips;
create trigger _payslips_audit
  after insert or update or delete on payslips
  for each row execute function audit_payslips_changes();
