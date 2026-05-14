-- Audit trigger on manual_adjustment_lines: every INSERT/UPDATE/DELETE
-- writes one audit_logs row. Manual adjustments are high-signal audit
-- events — any human-entered modification to payroll bypasses the
-- computed engine and needs full traceability (who, what, how much).
--
-- Description includes: employee full name (joined from employees),
-- the payslip_line_category enum value (verbatim, e.g. 'EARNING',
-- 'ADJUSTMENT_DEDUCT'), the amount, and the human-entered description
-- string from the row itself (on INSERT, since that's the rationale).
--
-- Mirrors the structure of audit_employees_changes (security definer,
-- auth.uid() actor lookup, jsonb capture of old/new).

create or replace function audit_manual_adjustment_lines_changes()
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
  v_emp_id      uuid;
  v_name        text;
  v_first       varchar(100);
  v_middle      varchar(100);
  v_last        varchar(100);
  v_category    text;
  v_amount      numeric(12,2);
  v_note        text;
begin
  v_user_id := auth.uid();
  if v_user_id is not null then
    select email::varchar(255) into v_user_email
      from auth.users
      where id = v_user_id;
  end if;

  if tg_op = 'DELETE' then
    v_emp_id := old.employee_id;
    v_category := old.category::text;
    v_amount := old.amount;
    v_note := old.description;
  else
    v_emp_id := new.employee_id;
    v_category := new.category::text;
    v_amount := new.amount;
    v_note := new.description;
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
    v_description := format(
      'Manual adjustment created: %s · %s · ₱%s · "%s"',
      v_name,
      v_category,
      to_char(v_amount, 'FM999,999,999,990.00'),
      v_note
    );
  elsif tg_op = 'UPDATE' then
    v_action := 'UPDATE';
    v_old := to_jsonb(old);
    v_new := to_jsonb(new);
    v_entity_id := new.id;
    v_description := format(
      'Manual adjustment updated: %s · %s',
      v_name,
      v_category
    );
  else
    v_action := 'DELETE';
    v_old := to_jsonb(old);
    v_entity_id := old.id;
    v_description := format(
      'Manual adjustment deleted: %s · %s · ₱%s',
      v_name,
      v_category,
      to_char(v_amount, 'FM999,999,999,990.00')
    );
  end if;

  insert into audit_logs (
    user_id, user_email, action, entity_type, entity_id,
    old_values, new_values, description
  ) values (
    v_user_id, v_user_email, v_action, 'manual_adjustment_lines', v_entity_id,
    v_old, v_new, v_description
  );

  if tg_op = 'DELETE' then
    return old;
  else
    return new;
  end if;
end;
$$;

drop trigger if exists _manual_adjustment_lines_audit on manual_adjustment_lines;
create trigger _manual_adjustment_lines_audit
  after insert or update or delete on manual_adjustment_lines
  for each row execute function audit_manual_adjustment_lines_changes();
