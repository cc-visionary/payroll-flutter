-- Admin: no_break_requests, bank_files, export_artifacts, audit_logs, lark_sync_logs

create table no_break_requests (
  id                  uuid primary key default gen_random_uuid(),
  company_id          uuid not null references companies(id),
  employee_id         uuid not null references employees(id) on delete cascade,
  lark_instance_code  varchar(100) not null unique,
  lark_approved_at    timestamptz,
  break_minutes       integer not null,
  reason              text,
  request_date        date not null,
  is_applied          boolean not null default false,
  applied_at          timestamptz,
  synced_at           timestamptz not null default now(),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create index on no_break_requests (employee_id, request_date);
create index on no_break_requests (company_id);
create trigger _no_break_requests_updated before update on no_break_requests for each row execute function set_updated_at();

create table bank_files (
  id              uuid primary key default gen_random_uuid(),
  payroll_run_id  uuid not null references payroll_runs(id) on delete cascade,
  bank_code       varchar(20) not null,
  file_name       varchar(255) not null,
  file_path       varchar(500) not null,
  file_format     varchar(50) not null,
  record_count    integer not null,
  total_amount    numeric(14,2) not null,
  checksum        varchar(64),
  generated_at    timestamptz not null default now()
);
create index on bank_files (payroll_run_id);

create table export_artifacts (
  id               uuid primary key default gen_random_uuid(),
  company_id       uuid not null references companies(id),
  payroll_run_id   uuid not null references payroll_runs(id) on delete cascade,
  export_type      export_type not null,
  file_name        varchar(255) not null,
  mime_type        varchar(100) not null,
  file_size_bytes  integer not null,
  blob_url         varchar(500),
  file_content     bytea,
  data_snapshot    jsonb,
  content_hash     varchar(64) not null,
  record_count     integer not null default 0,
  total_amount     numeric(14,2),
  generated_by_id  uuid not null references users(id),
  generated_at     timestamptz not null default now(),
  expires_at       timestamptz
);
create index on export_artifacts (payroll_run_id, export_type);
create index on export_artifacts (company_id, generated_at);
create index on export_artifacts (generated_by_id);

create table audit_logs (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references users(id),
  user_email  varchar(255),
  ip_address  varchar(45),
  user_agent  varchar(500),
  action      audit_action not null,
  entity_type varchar(50) not null,
  entity_id   uuid,
  old_values  jsonb,
  new_values  jsonb,
  description text,
  metadata    jsonb,
  created_at  timestamptz not null default now()
);
create index on audit_logs (entity_type, entity_id);
create index on audit_logs (user_id, created_at);
create index on audit_logs (action, created_at);
create index on audit_logs (created_at);

create table lark_sync_logs (
  id             uuid primary key default gen_random_uuid(),
  company_id     uuid not null references companies(id),
  sync_type      varchar(50) not null,
  date_from      date not null,
  date_to        date not null,
  status         varchar(20) not null,
  total_records  integer not null default 0,
  created_count  integer not null default 0,
  updated_count  integer not null default 0,
  skipped_count  integer not null default 0,
  error_count    integer not null default 0,
  error_details  jsonb,
  synced_by_id   uuid not null references users(id),
  started_at     timestamptz not null default now(),
  completed_at   timestamptz
);
create index on lark_sync_logs (company_id, sync_type, started_at);
