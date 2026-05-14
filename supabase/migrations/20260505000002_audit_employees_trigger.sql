-- Audit trigger on employees: every INSERT/UPDATE/DELETE writes one
-- audit_logs row. Captures actor via auth.uid() and joins to auth.users for
-- the email (public.users has no email column — it lives in auth.users).
-- UPDATE distinguishes archive/restore (toggling deleted_at) from generic
-- updates via the description field.
--
-- The trigger is intentionally generic-ish so it can be cloned to other
-- tables later (hiring_entities, salaries, etc.) without rewriting from
-- scratch. For now it's bound only to employees.

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
    v_description := 'Employee created';
  elsif tg_op = 'UPDATE' then
    v_action := 'UPDATE';
    v_old := to_jsonb(old);
    v_new := to_jsonb(new);
    v_entity_id := new.id;
    if old.deleted_at is null and new.deleted_at is not null then
      v_description := 'Employee archived';
    elsif old.deleted_at is not null and new.deleted_at is null then
      v_description := 'Employee restored';
    else
      v_description := 'Employee updated';
    end if;
  else
    v_action := 'DELETE';
    v_old := to_jsonb(old);
    v_entity_id := old.id;
    v_description := 'Employee permanently deleted';
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

drop trigger if exists _employees_audit on employees;
create trigger _employees_audit
  after insert or update or delete on employees
  for each row execute function audit_employees_changes();
