-- Audit trigger on export_artifacts: every INSERT (and the rare
-- UPDATE/DELETE) writes one audit_logs row. The artifacts table is
-- effectively append-only — exports get generated once, the row
-- captures the artifact's metadata (export_type, file_name, hashes,
-- counts, totals) and persists. We map INSERT → action 'EXPORT' so the
-- audit log reads as the user actually performed an export, not as a
-- generic row insert.
--
-- This trigger covers every flow that already writes to
-- export_artifacts (PAYROLL_REGISTER, BANK_DISBURSEMENT, the four
-- statutory contribution exports, TAX_ALPHALIST, the two payslip-PDF
-- variants). Ad-hoc PDF Download/Print flows and CSV/XLSX dumps that
-- do NOT touch this table are covered by the Dart `AuditRepository`
-- helper called from each export site.
--
-- Actor resolution: export_artifacts.generated_by_id is non-null by
-- schema, so we prefer it. Fall back to auth.uid() (and its email) for
-- the unusual UPDATE/DELETE paths where the row might have been moved
-- by a different operator.

create or replace function audit_export_artifacts_changes()
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
  v_amount_str  text;
begin
  -- Prefer the actor recorded on the row itself (writes to
  -- export_artifacts always set generated_by_id). For UPDATE/DELETE
  -- without that context, fall back to auth.uid().
  if tg_op = 'DELETE' then
    v_user_id := coalesce(old.generated_by_id, auth.uid());
  else
    v_user_id := coalesce(new.generated_by_id, auth.uid());
  end if;
  if v_user_id is not null then
    select email::varchar(255) into v_user_email
      from auth.users
      where id = v_user_id;
  end if;

  if tg_op = 'INSERT' then
    v_action := 'EXPORT';
    v_new := to_jsonb(new);
    v_entity_id := new.id;
    if new.total_amount is null then
      v_description := format(
        'Export generated: %s · %s · %s records',
        new.export_type::text,
        new.file_name,
        new.record_count
      );
    else
      v_amount_str := to_char(new.total_amount, 'FM999,999,999,990.00');
      v_description := format(
        'Export generated: %s · %s · %s records · ₱%s',
        new.export_type::text,
        new.file_name,
        new.record_count,
        v_amount_str
      );
    end if;
  elsif tg_op = 'UPDATE' then
    v_action := 'UPDATE';
    v_old := to_jsonb(old);
    v_new := to_jsonb(new);
    v_entity_id := new.id;
    v_description := format(
      'Export artifact updated: %s',
      new.file_name
    );
  else
    v_action := 'DELETE';
    v_old := to_jsonb(old);
    v_entity_id := old.id;
    v_description := format(
      'Export artifact deleted: %s',
      old.file_name
    );
  end if;

  insert into audit_logs (
    user_id, user_email, action, entity_type, entity_id,
    old_values, new_values, description
  ) values (
    v_user_id, v_user_email, v_action, 'export_artifacts', v_entity_id,
    v_old, v_new, v_description
  );

  if tg_op = 'DELETE' then
    return old;
  else
    return new;
  end if;
end;
$$;

drop trigger if exists _export_artifacts_audit on export_artifacts;
create trigger _export_artifacts_audit
  after insert or update or delete on export_artifacts
  for each row execute function audit_export_artifacts_changes();
