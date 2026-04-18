-- Relax lark_sync_logs: employee/shift syncs have no date range, and server-
-- initiated syncs (cron) have no synced_by user. Make these nullable.

alter table lark_sync_logs alter column date_from drop not null;
alter table lark_sync_logs alter column date_to drop not null;
alter table lark_sync_logs alter column synced_by_id drop not null;
