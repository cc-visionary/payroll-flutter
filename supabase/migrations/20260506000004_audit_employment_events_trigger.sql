-- Audit trigger on employment_events: every INSERT/UPDATE/DELETE writes one
-- audit_logs row. Employment events are the canonical lifecycle log for an
-- employee (hire, regularization, salary change, role change, separation,
-- etc.) — every status transition is audit-critical because these rows can
-- justify pay changes, exits, and disciplinary action.
--
-- Status-transition mapping (employment_event_status):
--   * → APPROVED  ⇒ action APPROVE
--   * → REJECTED  ⇒ action REJECT
--   * → CANCELLED ⇒ action REJECT (verb "CANCELLED")
--   * other UPDATEs ⇒ UPDATE
-- INSERT ⇒ CREATE; DELETE ⇒ DELETE.
--
-- Description carries: event_type, employee full name, event_date.
--
-- Also defines a shared helper `_audit_employee_name(uuid)` that returns the
-- trimmed full name for an employee — used by this trigger and the three
-- subsequent Tier 2 triggers (employee_documents, leave_requests). The
-- pre-existing employees/payslips/manual_adjustment_lines triggers continue
-- to inline the same expression; not refactoring them avoids a churn diff
-- on already-shipped audit semantics.
--
-- Mirrors the structure of audit_employees_changes (security definer,
-- auth.uid() actor lookup, jsonb capture of old/new).

create or replace function _audit_employee_name(p_employee_id uuid)
returns text
language sql
stable
security definer
as $$
  select coalesce(
    nullif(
      trim(
        coalesce(first_name, '') || ' ' ||
        coalesce(middle_name || ' ', '') ||
        coalesce(last_name, '')
      ),
      ''
    ),
    '(unknown employee)'
  )
  from employees
  where id = p_employee_id;
$$;

create or replace function audit_employment_events_changes()
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
  v_event_type  text;
  v_event_date  date;
begin
  v_user_id := auth.uid();
  if v_user_id is not null then
    select email::varchar(255) into v_user_email
      from auth.users
      where id = v_user_id;
  end if;

  if tg_op = 'DELETE' then
    v_emp_id := old.employee_id;
    v_event_type := old.event_type::text;
    v_event_date := old.event_date;
  else
    v_emp_id := new.employee_id;
    v_event_type := new.event_type::text;
    v_event_date := new.event_date;
  end if;

  v_name := _audit_employee_name(v_emp_id);

  if tg_op = 'INSERT' then
    v_action := 'CREATE';
    v_new := to_jsonb(new);
    v_entity_id := new.id;
    v_description := format(
      'Employment event created: %s for %s on %s',
      v_event_type,
      v_name,
      to_char(v_event_date, 'YYYY-MM-DD')
    );
  elsif tg_op = 'UPDATE' then
    v_old := to_jsonb(old);
    v_new := to_jsonb(new);
    v_entity_id := new.id;

    if old.status is distinct from new.status then
      if new.status = 'APPROVED' then
        v_action := 'APPROVE';
        v_description := format(
          'Employment event APPROVED: %s for %s on %s',
          v_event_type,
          v_name,
          to_char(v_event_date, 'YYYY-MM-DD')
        );
      elsif new.status = 'REJECTED' then
        v_action := 'REJECT';
        v_description := format(
          'Employment event REJECTED: %s for %s on %s',
          v_event_type,
          v_name,
          to_char(v_event_date, 'YYYY-MM-DD')
        );
      elsif new.status = 'CANCELLED' then
        v_action := 'REJECT';
        v_description := format(
          'Employment event CANCELLED: %s for %s on %s',
          v_event_type,
          v_name,
          to_char(v_event_date, 'YYYY-MM-DD')
        );
      else
        v_action := 'UPDATE';
        v_description := format(
          'Employment event status changed %s -> %s: %s for %s',
          old.status, new.status, v_event_type, v_name
        );
      end if;
    else
      v_action := 'UPDATE';
      v_description := format(
        'Employment event updated: %s for %s on %s',
        v_event_type,
        v_name,
        to_char(v_event_date, 'YYYY-MM-DD')
      );
    end if;
  else
    v_action := 'DELETE';
    v_old := to_jsonb(old);
    v_entity_id := old.id;
    v_description := format(
      'Employment event deleted: %s for %s on %s',
      v_event_type,
      v_name,
      to_char(v_event_date, 'YYYY-MM-DD')
    );
  end if;

  insert into audit_logs (
    user_id, user_email, action, entity_type, entity_id,
    old_values, new_values, description
  ) values (
    v_user_id, v_user_email, v_action, 'employment_events', v_entity_id,
    v_old, v_new, v_description
  );

  if tg_op = 'DELETE' then
    return old;
  else
    return new;
  end if;
end;
$$;

drop trigger if exists _employment_events_audit on employment_events;
create trigger _employment_events_audit
  after insert or update or delete on employment_events
  for each row execute function audit_employment_events_changes();
