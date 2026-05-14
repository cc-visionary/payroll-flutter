-- Audit trigger on attendance_imports: every file-based attendance import
-- writes one audit_logs row per lifecycle transition with action='IMPORT'
-- (or 'DELETE' for row removal).
--
-- attendance_imports is written by the Flutter app's attendance ingestion
-- flow:
--   * INSERT with status='PENDING' (or 'PROCESSING') and zeroed counters
--   * UPDATE progress counters during parsing/validation
--   * UPDATE status to terminal value ('COMPLETED' / 'FAILED' / similar)
--     with final valid/invalid/total counts
--
-- We want one audit row per lifecycle transition, not one per counter
-- increment. Strategy:
--   * INSERT → emit "Attendance import started: <file_name> (<total_rows> rows)"
--   * UPDATE → emit only when status changed (skip progress-only UPDATEs)
--   * DELETE → emit
--
-- Unlike lark_sync_logs, attendance_imports has no date_from/date_to — the
-- file's contents define the range. Description carries file_name and the
-- valid/invalid/total counter triplet.
--
-- Mirrors the structure of audit_export_artifacts_changes (security definer,
-- auth.uid() actor lookup, jsonb capture of old/new).

create or replace function audit_attendance_imports_changes()
returns trigger
language plpgsql
security definer
as $$
declare
  v_user_id    uuid;
  v_user_email varchar(255);
  v_action     audit_action := 'IMPORT';
  v_desc       text;
begin
  -- Actor lookup. attendance_imports.uploaded_by_id is nullable; fall back to auth.uid().
  if tg_op = 'DELETE' then
    v_user_id := coalesce(old.uploaded_by_id, auth.uid());
  else
    v_user_id := coalesce(new.uploaded_by_id, auth.uid());
  end if;
  if v_user_id is not null then
    select email::varchar(255) into v_user_email
      from auth.users
      where id = v_user_id;
  end if;

  if tg_op = 'INSERT' then
    v_desc := format(
      'Attendance import started: %s (%s rows)',
      new.file_name, new.total_rows
    );
  elsif tg_op = 'UPDATE' then
    -- Skip progress-only UPDATEs (counter increments without status change)
    -- to avoid spamming audit_logs.
    if old.status is not distinct from new.status then
      return new;
    end if;
    v_desc := format(
      'Attendance import %s: %s · %s valid / %s invalid / %s total',
      new.status, new.file_name,
      new.valid_rows, new.invalid_rows, new.total_rows
    );
  else
    -- DELETE
    v_desc := format('Attendance import deleted: %s', old.file_name);
    v_action := 'DELETE';
  end if;

  insert into audit_logs (
    user_id, user_email, action, entity_type, entity_id,
    old_values, new_values, description
  ) values (
    v_user_id, v_user_email, v_action, 'attendance_imports',
    case when tg_op = 'DELETE' then old.id else new.id end,
    case when tg_op = 'INSERT' then null else to_jsonb(old) end,
    case when tg_op = 'DELETE' then null else to_jsonb(new) end,
    v_desc
  );

  if tg_op = 'DELETE' then
    return old;
  else
    return new;
  end if;
end;
$$;

drop trigger if exists _attendance_imports_audit on attendance_imports;
create trigger _attendance_imports_audit
  after insert or update or delete on attendance_imports
  for each row execute function audit_attendance_imports_changes();
