-- =============================================================================
-- Fix: "Database error granting user" on every sign-in
-- =============================================================================
-- Symptom: all logins fail with GoTrue `unexpected_failure` /
-- "Database error granting user".
--
-- Root cause: a search_path cascade introduced by 20260708000002.
--
--   On sign-in GoTrue (connected as supabase_auth_admin) runs
--     UPDATE auth.users SET last_sign_in_at = now() ...
--   inside the token-grant transaction. That fires sync_users_auth_fields()
--   (20260708000002), which is `SECURITY DEFINER SET search_path = ''`, and it
--   runs `UPDATE public.users ...`. Because that UPDATE executes *inside* the
--   sync function's frame, the empty search_path is still in effect when the
--   AFTER-UPDATE audit trigger `_users_audit` -> audit_users_changes()
--   (20260506000008) fires. audit_users_changes() sets no search_path of its
--   own and references `audit_action` (a type) and `audit_logs` (a table)
--   UNqualified, so under search_path = '' they cannot be resolved:
--     ERROR: type "audit_action" does not exist   (or) relation "audit_logs" ...
--   The audit INSERT aborts, the whole grant transaction rolls back, and GoTrue
--   returns "Database error granting user".
--
--   The audit trigger worked for months because every prior write to
--   public.users happened under a normal search_path. 20260708000002 introduced
--   the first write path with search_path = '' (a security-definer trigger that
--   updates public.users), which surfaced the latent fragility.
--
-- Fix: make audit_users_changes() independent of the caller's search_path by
-- pinning its own. The function body is otherwise unchanged. CREATE OR REPLACE
-- keeps the existing `_users_audit` trigger binding, ownership and grants.
-- (sync_users_auth_fields keeps SET search_path = '' — that is correct
-- hardening; the fix belongs in the audit function that must resolve its own
-- objects regardless of who calls it.)

create or replace function audit_users_changes()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
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
