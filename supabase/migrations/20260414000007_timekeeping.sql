-- Timekeeping: attendance_imports, attendance_day_records
-- Note: attendance_day_records references leave_requests and payroll_runs which are created later.
-- Those FKs are added in later migrations via ALTER TABLE.

create table attendance_imports (
  id              uuid primary key default gen_random_uuid(),
  company_id      uuid not null references companies(id),
  file_name       varchar(255) not null,
  file_path       varchar(500) not null,
  file_size       bigint,
  file_hash       varchar(64),
  column_mapping  jsonb,
  status          import_status not null default 'PENDING',
  total_rows      integer not null default 0,
  processed_rows  integer not null default 0,
  valid_rows      integer not null default 0,
  invalid_rows    integer not null default 0,
  duplicate_rows  integer not null default 0,
  started_at      timestamptz,
  completed_at    timestamptz,
  error_message   text,
  uploaded_by_id  uuid references users(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index on attendance_imports (company_id, created_at);
create index on attendance_imports (file_hash);
create trigger _attendance_imports_updated before update on attendance_imports for each row execute function set_updated_at();

create table attendance_day_records (
  id                        uuid primary key default gen_random_uuid(),
  employee_id               uuid not null references employees(id),
  attendance_date           date not null,
  shift_template_id         uuid references shift_templates(id),
  day_type                  day_type not null,
  holiday_name              varchar(255),
  actual_time_in            timestamptz,
  actual_time_out           timestamptz,
  source_type               attendance_source not null default 'MANUAL',
  source_batch_id           uuid references attendance_imports(id),
  source_record_id          varchar(100),
  entered_by_id             uuid references users(id),
  manual_reason             text,
  attendance_status         attendance_status not null,
  early_in_approved         boolean not null default false,
  late_out_approved         boolean not null default false,
  approved_ot_minutes       integer,
  late_in_approved          boolean not null default false,
  early_out_approved        boolean not null default false,
  override_reason           text,
  override_reason_code      varchar(50),
  override_by_id            uuid references users(id),
  override_at               timestamptz,
  break_minutes_applied     integer,
  daily_rate_override       numeric(12,4),
  leave_request_id          uuid,  -- FK added in leave migration
  leave_hours               numeric(4,2),
  is_locked                 boolean not null default false,
  locked_by_payroll_run_id  uuid,  -- FK added in payroll migration
  locked_at                 timestamptz,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),
  unique (employee_id, attendance_date)
);
create index on attendance_day_records (attendance_date);
create index on attendance_day_records (locked_by_payroll_run_id);
create index on attendance_day_records (source_batch_id);
create trigger _attendance_day_records_updated before update on attendance_day_records for each row execute function set_updated_at();
