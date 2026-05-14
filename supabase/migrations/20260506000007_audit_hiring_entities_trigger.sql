-- Audit trigger on hiring_entities: every INSERT/UPDATE/DELETE writes one
-- audit_logs row. Hiring entities are the legal employers of record (per-
-- brand), so changes to their identity, TIN, signatories, or active state
-- are audit-critical for compliance (BIR/SSS/PhilHealth/Pag-IBIG filings).
--
-- Description carries: name and code. Special UPDATEs are detected and
-- get distinct phrasing:
--   * archive  (deleted_at null   → non-null) ⇒ "Hiring entity archived"
--   * restore  (deleted_at non-nl → null   ) ⇒ "Hiring entity restored"
--   * is_active true  → false ⇒ "Hiring entity deactivated"
--   * is_active false → true  ⇒ "Hiring entity activated"
-- Otherwise plain "Hiring entity updated: <name> (<code>)".
--
-- Mirrors the structure of audit_employees_changes (security definer,
-- auth.uid() actor lookup, jsonb capture of old/new).

create or replace function audit_hiring_entities_changes()
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
  v_name        varchar(255);
  v_code        varchar(20);
begin
  v_user_id := auth.uid();
  if v_user_id is not null then
    select email::varchar(255) into v_user_email
      from auth.users
      where id = v_user_id;
  end if;

  if tg_op = 'DELETE' then
    v_name := old.name;
    v_code := old.code;
  else
    v_name := new.name;
    v_code := new.code;
  end if;

  if tg_op = 'INSERT' then
    v_action := 'CREATE';
    v_new := to_jsonb(new);
    v_entity_id := new.id;
    v_description := format(
      'Hiring entity created: %s (%s)',
      v_name, v_code
    );
  elsif tg_op = 'UPDATE' then
    v_action := 'UPDATE';
    v_old := to_jsonb(old);
    v_new := to_jsonb(new);
    v_entity_id := new.id;

    if old.deleted_at is null and new.deleted_at is not null then
      v_description := format(
        'Hiring entity archived: %s (%s)',
        v_name, v_code
      );
    elsif old.deleted_at is not null and new.deleted_at is null then
      v_description := format(
        'Hiring entity restored: %s (%s)',
        v_name, v_code
      );
    elsif old.is_active is distinct from new.is_active then
      if new.is_active then
        v_description := format(
          'Hiring entity activated: %s (%s)',
          v_name, v_code
        );
      else
        v_description := format(
          'Hiring entity deactivated: %s (%s)',
          v_name, v_code
        );
      end if;
    else
      v_description := format(
        'Hiring entity updated: %s (%s)',
        v_name, v_code
      );
    end if;
  else
    v_action := 'DELETE';
    v_old := to_jsonb(old);
    v_entity_id := old.id;
    v_description := format(
      'Hiring entity deleted: %s',
      v_name
    );
  end if;

  insert into audit_logs (
    user_id, user_email, action, entity_type, entity_id,
    old_values, new_values, description
  ) values (
    v_user_id, v_user_email, v_action, 'hiring_entities', v_entity_id,
    v_old, v_new, v_description
  );

  if tg_op = 'DELETE' then
    return old;
  else
    return new;
  end if;
end;
$$;

drop trigger if exists _hiring_entities_audit on hiring_entities;
create trigger _hiring_entities_audit
  after insert or update or delete on hiring_entities
  for each row execute function audit_hiring_entities_changes();
