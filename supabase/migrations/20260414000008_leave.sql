-- Leave: types, balances, requests

create table leave_types (
  id                        uuid primary key default gen_random_uuid(),
  company_id                uuid not null references companies(id),
  code                      varchar(20) not null,
  name                      varchar(100) not null,
  description               text,
  accrual_type              leave_accrual_type not null,
  accrual_amount            numeric(5,2),
  accrual_cap               numeric(5,2),
  min_tenure_days           integer not null default 0,
  requires_regularization   boolean not null default false,
  is_paid                   boolean not null default true,
  is_convertible            boolean not null default false,
  conversion_rate           numeric(5,4) not null default 1.0,
  can_carry_over            boolean not null default false,
  carry_over_cap            numeric(5,2),
  carry_over_expiry_months  integer,
  requires_attachment       boolean not null default false,
  requires_approval         boolean not null default true,
  min_advance_days          integer not null default 0,
  lark_leave_type_id        varchar(100),
  is_active                 boolean not null default true,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),
  unique (company_id, code)
);
create trigger _leave_types_updated before update on leave_types for each row execute function set_updated_at();

create table leave_balances (
  id                         uuid primary key default gen_random_uuid(),
  employee_id                uuid not null references employees(id) on delete cascade,
  leave_type_id              uuid not null references leave_types(id),
  year                       integer not null,
  opening_balance            numeric(6,2) not null default 0,
  accrued                    numeric(6,2) not null default 0,
  used                       numeric(6,2) not null default 0,
  forfeited                  numeric(6,2) not null default 0,
  converted                  numeric(6,2) not null default 0,
  adjusted                   numeric(6,2) not null default 0,
  carried_over_from_previous numeric(6,2) not null default 0,
  carry_over_expiry_date     date,
  last_accrual_date          date,
  created_at                 timestamptz not null default now(),
  updated_at                 timestamptz not null default now(),
  unique (employee_id, leave_type_id, year)
);
create trigger _leave_balances_updated before update on leave_balances for each row execute function set_updated_at();

create table leave_requests (
  id                   uuid primary key default gen_random_uuid(),
  employee_id          uuid not null references employees(id) on delete cascade,
  leave_type_id        uuid not null references leave_types(id),
  start_date           date not null,
  end_date             date not null,
  leave_days           numeric(5,2) not null,
  start_half           varchar(20),
  end_half             varchar(20),
  reason               text,
  attachment_path      varchar(500),
  attachment_filename  varchar(255),
  status               leave_request_status not null default 'PENDING',
  requested_at         timestamptz not null default now(),
  approved_by_id       uuid references users(id),
  approved_at          timestamptz,
  rejection_reason     text,
  cancelled_at         timestamptz,
  cancellation_reason  text,
  balance_deducted     numeric(5,2),
  leave_balance_id     uuid references leave_balances(id),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);
create index on leave_requests (employee_id, start_date, end_date);
create index on leave_requests (status);
create trigger _leave_requests_updated before update on leave_requests for each row execute function set_updated_at();

-- Now add the deferred FK from attendance_day_records to leave_requests
alter table attendance_day_records
  add constraint attendance_day_records_leave_request_id_fkey
  foreign key (leave_request_id) references leave_requests(id);
