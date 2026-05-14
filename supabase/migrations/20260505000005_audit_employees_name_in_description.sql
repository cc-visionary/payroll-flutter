-- Enrich audit_employees_changes() so the audit_logs.description string
-- includes the employee's full name and employee_number. Behavior is
-- otherwise identical to 20260505000002_audit_employees_trigger.sql:
-- security definer, auth.uid() actor lookup, archive/restore detection.
-- The trigger binding itself is unchanged; create or replace function
-- swaps the body in-place.

create or replace function audit_employees_changes()
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
  v_name        text;
  v_number      varchar(50);
  v_verb        text;
begin
  v_user_id := auth.uid();
  if v_user_id is not null then
    select email::varchar(255) into v_user_email
      from auth.users
      where id = v_user_id;
  end if;

  if tg_op = 'INSERT' then
    v_action := 'CREATE';
    v_new := to_jsonb(new);
    v_entity_id := new.id;
    v_name := trim(new.first_name || ' ' || coalesce(new.middle_name || ' ', '') || new.last_name);
    v_number := new.employee_number;
    v_verb := 'created';
  elsif tg_op = 'UPDATE' then
    v_action := 'UPDATE';
    v_old := to_jsonb(old);
    v_new := to_jsonb(new);
    v_entity_id := new.id;
    v_name := trim(new.first_name || ' ' || coalesce(new.middle_name || ' ', '') || new.last_name);
    v_number := new.employee_number;
    if old.deleted_at is null and new.deleted_at is not null then
      v_verb := 'archived';
    elsif old.deleted_at is not null and new.deleted_at is null then
      v_verb := 'restored';
    else
      v_verb := 'updated';
    end if;
  else
    v_action := 'DELETE';
    v_old := to_jsonb(old);
    v_entity_id := old.id;
    v_name := trim(old.first_name || ' ' || coalesce(old.middle_name || ' ', '') || old.last_name);
    v_number := old.employee_number;
    v_verb := 'permanently deleted';
  end if;

  if v_number is null or v_number = '' then
    v_description := format('Employee %s: %s', v_verb, v_name);
  else
    v_description := format('Employee %s: %s (%s)', v_verb, v_name, v_number);
  end if;

  insert into audit_logs (
    user_id, user_email, action, entity_type, entity_id,
    old_values, new_values, description
  ) values (
    v_user_id, v_user_email, v_action, 'employees', v_entity_id,
    v_old, v_new, v_description
  );

  if tg_op = 'DELETE' then
    return old;
  else
    return new;
  end if;
end;
$$;
