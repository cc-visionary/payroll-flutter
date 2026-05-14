-- Audit triggers on users and user_roles: every INSERT/UPDATE/DELETE writes
-- one audit_logs row. These tables govern access control — a role grant
-- (user_roles INSERT) is the canonical privilege-escalation event and must
-- be traceable. User account activation/deactivation/archival is similarly
-- audit-critical.
--
-- Email is the human-readable identifier (users table only stores id +
-- company_id + status), so descriptions look up email from auth.users via
-- the FK (users.id → auth.users.id). If the auth row is missing (race on
-- deletion) the email falls back to the short id prefix.
--
-- USERS audit semantics:
--   * INSERT ⇒ CREATE, "User created: <email>"
--   * UPDATE status change ⇒ "User status changed: <email> · <old> → <new>"
--   * UPDATE archive (deleted_at null → non-null) ⇒ "User archived: <email>"
--   * UPDATE restore ⇒ "User restored: <email>"
--   * UPDATE other ⇒ "User updated: <email>"
--   * DELETE ⇒ "User deleted: <email>"
--
-- USER_ROLES audit semantics:
--   * INSERT ⇒ CREATE, "Role granted: <email> ← <role_code>"
--   * DELETE ⇒ "Role revoked: <email> ← <role_code>"
--   * UPDATE ⇒ "Role updated: <email> ← <role_code>" (rare — uniq constraint
--     on (user_id, role_id) makes this effectively immutable)
--
-- Mirrors the structure of audit_employees_changes (security definer,
-- auth.uid() actor lookup, jsonb capture of old/new).

-- =============================================================================
-- users
-- =============================================================================
create or replace function audit_users_changes()
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
  v_target_id   uuid;
  v_target_email varchar(255);
begin
  v_user_id := auth.uid();
  if v_user_id is not null then
    select email::varchar(255) into v_user_email
      from auth.users
      where id = v_user_id;
  end if;

  if tg_op = 'DELETE' then
    v_target_id := old.id;
  else
    v_target_id := new.id;
  end if;

  select email::varchar(255) into v_target_email
    from auth.users
    where id = v_target_id;
  if v_target_email is null or v_target_email = '' then
    v_target_email := '(' || substring(v_target_id::text from 1 for 8) || ')';
  end if;

  if tg_op = 'INSERT' then
    v_action := 'CREATE';
    v_new := to_jsonb(new);
    v_entity_id := new.id;
    v_description := format('User created: %s', v_target_email);
  elsif tg_op = 'UPDATE' then
    v_action := 'UPDATE';
    v_old := to_jsonb(old);
    v_new := to_jsonb(new);
    v_entity_id := new.id;

    if old.deleted_at is null and new.deleted_at is not null then
      v_description := format('User archived: %s', v_target_email);
    elsif old.deleted_at is not null and new.deleted_at is null then
      v_description := format('User restored: %s', v_target_email);
    elsif old.status is distinct from new.status then
      v_description := format(
        'User status changed: %s · %s -> %s',
        v_target_email, old.status, new.status
      );
    else
      v_description := format('User updated: %s', v_target_email);
    end if;
  else
    v_action := 'DELETE';
    v_old := to_jsonb(old);
    v_entity_id := old.id;
    v_description := format('User deleted: %s', v_target_email);
  end if;

  insert into audit_logs (
    user_id, user_email, action, entity_type, entity_id,
    old_values, new_values, description
  ) values (
    v_user_id, v_user_email, v_action, 'users', v_entity_id,
    v_old, v_new, v_description
  );

  if tg_op = 'DELETE' then
    return old;
  else
    return new;
  end if;
end;
$$;

drop trigger if exists _users_audit on users;
create trigger _users_audit
  after insert or update or delete on users
  for each row execute function audit_users_changes();

-- =============================================================================
-- user_roles
-- =============================================================================
create or replace function audit_user_roles_changes()
returns trigger
language plpgsql
security definer
as $$
declare
  v_user_id      uuid;
  v_user_email   varchar(255);
  v_action       audit_action;
  v_old          jsonb;
  v_new          jsonb;
  v_entity_id    uuid;
  v_description  text;
  v_target_uid   uuid;
  v_target_email varchar(255);
  v_role_id      uuid;
  v_role_code    varchar(50);
begin
  v_user_id := auth.uid();
  if v_user_id is not null then
    select email::varchar(255) into v_user_email
      from auth.users
      where id = v_user_id;
  end if;

  if tg_op = 'DELETE' then
    v_target_uid := old.user_id;
    v_role_id := old.role_id;
  else
    v_target_uid := new.user_id;
    v_role_id := new.role_id;
  end if;

  select email::varchar(255) into v_target_email
    from auth.users
    where id = v_target_uid;
  if v_target_email is null or v_target_email = '' then
    v_target_email := '(' || substring(v_target_uid::text from 1 for 8) || ')';
  end if;

  select code into v_role_code from roles where id = v_role_id;
  if v_role_code is null or v_role_code = '' then
    v_role_code := '(' || substring(v_role_id::text from 1 for 8) || ')';
  end if;

  if tg_op = 'INSERT' then
    v_action := 'CREATE';
    v_new := to_jsonb(new);
    v_entity_id := new.id;
    v_description := format(
      'Role granted: %s <- %s',
      v_target_email, v_role_code
    );
  elsif tg_op = 'UPDATE' then
    v_action := 'UPDATE';
    v_old := to_jsonb(old);
    v_new := to_jsonb(new);
    v_entity_id := new.id;
    v_description := format(
      'Role updated: %s <- %s',
      v_target_email, v_role_code
    );
  else
    v_action := 'DELETE';
    v_old := to_jsonb(old);
    v_entity_id := old.id;
    v_description := format(
      'Role revoked: %s <- %s',
      v_target_email, v_role_code
    );
  end if;

  insert into audit_logs (
    user_id, user_email, action, entity_type, entity_id,
    old_values, new_values, description
  ) values (
    v_user_id, v_user_email, v_action, 'user_roles', v_entity_id,
    v_old, v_new, v_description
  );

  if tg_op = 'DELETE' then
    return old;
  else
    return new;
  end if;
end;
$$;

drop trigger if exists _user_roles_audit on user_roles;
create trigger _user_roles_audit
  after insert or update or delete on user_roles
  for each row execute function audit_user_roles_changes();
