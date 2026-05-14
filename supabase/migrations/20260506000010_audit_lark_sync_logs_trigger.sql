-- Audit trigger on lark_sync_logs: every Lark sync lifecycle event is logged
-- to audit_logs with action='IMPORT' (or 'DELETE' for the rare row removal).
--
-- lark_sync_logs is written by the edge functions (sync-lark-attendance,
-- sync-lark-leaves, sync-lark-overtime-approvals, sync-lark-cash-advances,
-- sync-lark-reimbursements) via the shared helpers in
-- supabase/functions/_shared/lark.ts:
--   * logSyncStart   → INSERT with status='IN_PROGRESS', zeroed counters
--   * logSyncProgress → UPDATE counters only (no status change)
--   * logSyncFinish  → UPDATE with status='COMPLETED' / 'PARTIAL' / 'FAILED'
--                     and final counters + completed_at
--
-- We want one audit row per lifecycle transition, not one per counter
-- increment. Strategy:
--   * INSERT → emit "Lark sync started: <type> · <range>"
--   * UPDATE → emit only when status changed (skip progress-only UPDATEs)
--   * DELETE → emit (rare; reflects manual cleanup)
--
-- Range composer ("all" vs explicit dates):
--   * date_to - date_from >= 365 days → label as "(full range)"
--   * date_from <= '2000-01-01' (sentinel) → label as "(full range)"
--   * otherwise show explicit dates
--
-- Mirrors the structure of audit_export_artifacts_changes (security definer,
-- auth.uid() actor lookup, jsonb capture of old/new).

create or replace function audit_lark_sync_logs_changes()
returns trigger
language plpgsql
security definer
as $$
declare
  v_user_id    uuid;
  v_user_email varchar(255);
  v_range      text;
  v_diff       integer;
  v_action     audit_action := 'IMPORT';
  v_desc       text;
  v_d_from     date;
  v_d_to       date;
begin
  -- Actor lookup. lark_sync_logs.synced_by_id is NOT NULL by schema; prefer it.
  if tg_op = 'DELETE' then
    v_user_id := coalesce(old.synced_by_id, auth.uid());
  else
    v_user_id := coalesce(new.synced_by_id, auth.uid());
  end if;
  if v_user_id is not null then
    select email::varchar(255) into v_user_email
      from auth.users
      where id = v_user_id;
  end if;

  -- Pull date range from the appropriate row image.
  if tg_op = 'DELETE' then
    v_d_from := old.date_from;
    v_d_to   := old.date_to;
  else
    v_d_from := new.date_from;
    v_d_to   := new.date_to;
  end if;

  v_diff := (v_d_to - v_d_from);
  if v_diff >= 365 or v_d_from <= date '2000-01-01' then
    v_range := format('all (%s to %s, full range)', v_d_from, v_d_to);
  else
    v_range := format('%s to %s', v_d_from, v_d_to);
  end if;

  if tg_op = 'INSERT' then
    v_desc := format('Lark sync started: %s · %s', new.sync_type, v_range);
  elsif tg_op = 'UPDATE' then
    -- Skip progress-only UPDATEs (counter increments without status change)
    -- to avoid spamming audit_logs.
    if old.status is not distinct from new.status then
      return new;
    end if;
    v_desc := format(
      'Lark sync %s: %s · %s · %s records (%s created, %s updated, %s skipped, %s errors)',
      new.status, new.sync_type, v_range,
      new.total_records, new.created_count, new.updated_count,
      new.skipped_count, new.error_count
    );
  else
    -- DELETE
    v_desc := format('Lark sync deleted: %s · %s', old.sync_type, v_range);
    v_action := 'DELETE';
  end if;

  insert into audit_logs (
    user_id, user_email, action, entity_type, entity_id,
    old_values, new_values, description
  ) values (
    v_user_id, v_user_email, v_action, 'lark_sync_logs',
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

drop trigger if exists _lark_sync_logs_audit on lark_sync_logs;
create trigger _lark_sync_logs_audit
  after insert or update or delete on lark_sync_logs
  for each row execute function audit_lark_sync_logs_changes();
