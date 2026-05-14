-- Audit trigger on employee_documents: every INSERT/UPDATE/DELETE writes
-- one audit_logs row. Document lifecycle (ISSUED → SIGNED → VOIDED) is
-- audit-critical because these are legally-binding artifacts (contracts,
-- NTEs, quitclaims) attached to compliance workflows.
--
-- Status-transition mapping (document_status: DRAFT, PENDING_APPROVAL,
-- ISSUED, SIGNED, VOIDED, SUPERSEDED, EXPIRED):
--   * DRAFT → ISSUED ⇒ action CREATE  (first publish)
--   * any   → ISSUED ⇒ action UPDATE  (re-issue / revision)
--   * any   → SIGNED ⇒ action APPROVE
--   * any   → VOIDED ⇒ action REJECT
--   * other UPDATEs ⇒ UPDATE
-- INSERT ⇒ CREATE; DELETE ⇒ DELETE.
--
-- Description carries: title, document_type, employee full name.
--
-- Reuses _audit_employee_name() from 20260506000004.
-- Mirrors the structure of audit_employees_changes (security definer,
-- auth.uid() actor lookup, jsonb capture of old/new).

create or replace function audit_employee_documents_changes()
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
  v_title       varchar(255);
  v_doc_type    varchar(50);
begin
  v_user_id := auth.uid();
  if v_user_id is not null then
    select email::varchar(255) into v_user_email
      from auth.users
      where id = v_user_id;
  end if;

  if tg_op = 'DELETE' then
    v_emp_id := old.employee_id;
    v_title := old.title;
    v_doc_type := old.document_type;
  else
    v_emp_id := new.employee_id;
    v_title := new.title;
    v_doc_type := new.document_type;
  end if;

  v_name := _audit_employee_name(v_emp_id);

  if tg_op = 'INSERT' then
    v_action := 'CREATE';
    v_new := to_jsonb(new);
    v_entity_id := new.id;
    v_description := format(
      'Document created: %s (%s) for %s',
      v_title, v_doc_type, v_name
    );
  elsif tg_op = 'UPDATE' then
    v_old := to_jsonb(old);
    v_new := to_jsonb(new);
    v_entity_id := new.id;

    if old.status is distinct from new.status then
      if new.status = 'ISSUED' then
        if old.status = 'DRAFT' then
          v_action := 'CREATE';
          v_description := format(
            'Document ISSUED: %s (%s) for %s',
            v_title, v_doc_type, v_name
          );
        else
          v_action := 'UPDATE';
          v_description := format(
            'Document re-ISSUED: %s (%s) for %s',
            v_title, v_doc_type, v_name
          );
        end if;
      elsif new.status = 'SIGNED' then
        v_action := 'APPROVE';
        v_description := format(
          'Document SIGNED: %s for %s',
          v_title, v_name
        );
      elsif new.status = 'VOIDED' then
        v_action := 'REJECT';
        v_description := format(
          'Document VOIDED: %s (%s) for %s',
          v_title, v_doc_type, v_name
        );
      else
        v_action := 'UPDATE';
        v_description := format(
          'Document status changed %s -> %s: %s for %s',
          old.status, new.status, v_title, v_name
        );
      end if;
    else
      v_action := 'UPDATE';
      v_description := format(
        'Document updated: %s (%s) for %s',
        v_title, v_doc_type, v_name
      );
    end if;
  else
    v_action := 'DELETE';
    v_old := to_jsonb(old);
    v_entity_id := old.id;
    v_description := format(
      'Document deleted: %s (%s) for %s',
      v_title, v_doc_type, v_name
    );
  end if;

  insert into audit_logs (
    user_id, user_email, action, entity_type, entity_id,
    old_values, new_values, description
  ) values (
    v_user_id, v_user_email, v_action, 'employee_documents', v_entity_id,
    v_old, v_new, v_description
  );

  if tg_op = 'DELETE' then
    return old;
  else
    return new;
  end if;
end;
$$;

drop trigger if exists _employee_documents_audit on employee_documents;
create trigger _employee_documents_audit
  after insert or update or delete on employee_documents
  for each row execute function audit_employee_documents_changes();
