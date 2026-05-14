-- Audit trigger on leave_requests: every INSERT/UPDATE/DELETE writes one
-- audit_logs row. Leave approvals/rejections affect payroll (paid vs unpaid,
-- balance deductions) so every status transition needs traceability.
--
-- Status-transition mapping (leave_request_status):
--   * → APPROVED  ⇒ action APPROVE
--   * → REJECTED  ⇒ action REJECT
--   * → CANCELLED ⇒ action REJECT (verb "CANCELLED")
--   * other UPDATEs ⇒ UPDATE
-- INSERT ⇒ CREATE; DELETE ⇒ DELETE.
--
-- Description carries: employee full name, start_date → end_date, leave_days
-- (on APPROVE), and leave_type.name appended if the FK join resolves. If
-- leave_types lookup fails (FK drift, type deleted) the leave-type segment
-- is silently omitted — the rest of the description still ships.
--
-- Reuses _audit_employee_name() from 20260506000004.
-- Mirrors the structure of audit_employees_changes (security definer,
-- auth.uid() actor lookup, jsonb capture of old/new).

create or replace function audit_leave_requests_changes()
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
  v_lt_id       uuid;
  v_lt_name     varchar(100);
  v_lt_suffix   text;
  v_start_date  date;
  v_end_date    date;
  v_days        numeric(5,2);
begin
  v_user_id := auth.uid();
  if v_user_id is not null then
    select email::varchar(255) into v_user_email
      from auth.users
      where id = v_user_id;
  end if;

  if tg_op = 'DELETE' then
    v_emp_id := old.employee_id;
    v_lt_id := old.leave_type_id;
    v_start_date := old.start_date;
    v_end_date := old.end_date;
    v_days := old.leave_days;
  else
    v_emp_id := new.employee_id;
    v_lt_id := new.leave_type_id;
    v_start_date := new.start_date;
    v_end_date := new.end_date;
    v_days := new.leave_days;
  end if;

  v_name := _audit_employee_name(v_emp_id);

  select name into v_lt_name from leave_types where id = v_lt_id;
  if v_lt_name is not null and v_lt_name <> '' then
    v_lt_suffix := format(' · %s', v_lt_name);
  else
    v_lt_suffix := '';
  end if;

  if tg_op = 'INSERT' then
    v_action := 'CREATE';
    v_new := to_jsonb(new);
    v_entity_id := new.id;
    v_description := format(
      'Leave requested: %s · %s to %s%s',
      v_name,
      to_char(v_start_date, 'YYYY-MM-DD'),
      to_char(v_end_date, 'YYYY-MM-DD'),
      v_lt_suffix
    );
  elsif tg_op = 'UPDATE' then
    v_old := to_jsonb(old);
    v_new := to_jsonb(new);
    v_entity_id := new.id;

    if old.status is distinct from new.status then
      if new.status = 'APPROVED' then
        v_action := 'APPROVE';
        v_description := format(
          'Leave APPROVED: %s · %s to %s (%s days)%s',
          v_name,
          to_char(v_start_date, 'YYYY-MM-DD'),
          to_char(v_end_date, 'YYYY-MM-DD'),
          to_char(v_days, 'FM999990.00'),
          v_lt_suffix
        );
      elsif new.status = 'REJECTED' then
        v_action := 'REJECT';
        v_description := format(
          'Leave REJECTED: %s · %s to %s%s',
          v_name,
          to_char(v_start_date, 'YYYY-MM-DD'),
          to_char(v_end_date, 'YYYY-MM-DD'),
          v_lt_suffix
        );
      elsif new.status = 'CANCELLED' then
        v_action := 'REJECT';
        v_description := format(
          'Leave CANCELLED: %s · %s to %s%s',
          v_name,
          to_char(v_start_date, 'YYYY-MM-DD'),
          to_char(v_end_date, 'YYYY-MM-DD'),
          v_lt_suffix
        );
      else
        v_action := 'UPDATE';
        v_description := format(
          'Leave status changed %s -> %s: %s%s',
          old.status, new.status, v_name, v_lt_suffix
        );
      end if;
    else
      v_action := 'UPDATE';
      v_description := format(
        'Leave updated: %s · %s to %s%s',
        v_name,
        to_char(v_start_date, 'YYYY-MM-DD'),
        to_char(v_end_date, 'YYYY-MM-DD'),
        v_lt_suffix
      );
    end if;
  else
    v_action := 'DELETE';
    v_old := to_jsonb(old);
    v_entity_id := old.id;
    v_description := format(
      'Leave deleted: %s · %s to %s%s',
      v_name,
      to_char(v_start_date, 'YYYY-MM-DD'),
      to_char(v_end_date, 'YYYY-MM-DD'),
      v_lt_suffix
    );
  end if;

  insert into audit_logs (
    user_id, user_email, action, entity_type, entity_id,
    old_values, new_values, description
  ) values (
    v_user_id, v_user_email, v_action, 'leave_requests', v_entity_id,
    v_old, v_new, v_description
  );

  if tg_op = 'DELETE' then
    return old;
  else
    return new;
  end if;
end;
$$;

drop trigger if exists _leave_requests_audit on leave_requests;
create trigger _leave_requests_audit
  after insert or update or delete on leave_requests
  for each row execute function audit_leave_requests_changes();
