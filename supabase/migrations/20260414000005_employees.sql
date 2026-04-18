-- Employees + related: statutory IDs, bank accounts, employment events, documents
-- Backfills departments.manager_id FK at end.

create table employees (
  id                            uuid primary key default gen_random_uuid(),
  company_id                    uuid not null references companies(id),
  employee_number               varchar(20) not null,
  user_id                       uuid unique references users(id),
  first_name                    varchar(100) not null,
  middle_name                   varchar(100),
  last_name                     varchar(100) not null,
  suffix                        varchar(20),
  nickname                      varchar(50),
  birth_date                    date,
  gender                        varchar(10),
  civil_status                  varchar(20),
  nationality                   varchar(50) not null default 'Filipino',
  personal_email                varchar(255),
  work_email                    varchar(255),
  mobile_number                 varchar(20),
  phone_number                  varchar(20),
  present_address_line1         varchar(255),
  present_address_line2         varchar(255),
  present_city                  varchar(100),
  present_province              varchar(100),
  present_zip_code              varchar(10),
  permanent_address_line1       varchar(255),
  permanent_address_line2       varchar(255),
  permanent_city                varchar(100),
  permanent_province            varchar(100),
  permanent_zip_code            varchar(10),
  emergency_contact_name        varchar(100),
  emergency_contact_number      varchar(20),
  emergency_contact_relationship varchar(50),
  department_id                 uuid references departments(id),
  role_scorecard_id             uuid references role_scorecards(id),
  job_title                     varchar(100),
  job_level                     varchar(50),
  reports_to_id                 uuid references employees(id),
  hiring_entity_id              uuid references hiring_entities(id),
  employment_type               employment_type not null default 'PROBATIONARY',
  employment_status             employment_status not null default 'ACTIVE',
  hire_date                     date not null,
  regularization_date           date,
  separation_date               date,
  separation_reason             varchar(50),
  is_rank_and_file              boolean not null default true,
  is_ot_eligible                boolean not null default true,
  is_nd_eligible                boolean not null default true,
  is_holiday_pay_eligible       boolean not null default true,
  declared_wage_override        numeric(12,2),
  declared_wage_type            wage_type,
  declared_wage_effective_at    timestamptz,
  declared_wage_set_by_id       uuid references users(id),
  declared_wage_set_at          timestamptz,
  declared_wage_reason          text,
  tax_on_full_earnings          boolean not null default false,
  lark_user_id                  varchar(100),
  lark_employee_id              varchar(100),
  payment_method                varchar(20),
  payment_source_account        varchar(50),
  created_at                    timestamptz not null default now(),
  updated_at                    timestamptz not null default now(),
  deleted_at                    timestamptz,
  unique (company_id, employee_number)
);
create index on employees (company_id, employment_status);
create index on employees (department_id);
create index on employees (role_scorecard_id);
create index on employees (lark_user_id);
create index on employees (last_name, first_name);
create trigger _employees_updated before update on employees for each row execute function set_updated_at();

create table employee_statutory_ids (
  id              uuid primary key default gen_random_uuid(),
  employee_id     uuid not null references employees(id) on delete cascade,
  id_type         varchar(20) not null,
  id_number       varchar(50) not null,
  verified_at     timestamptz,
  verified_by_id  uuid references users(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (employee_id, id_type)
);
create trigger _employee_statutory_ids_updated before update on employee_statutory_ids for each row execute function set_updated_at();

create table employee_bank_accounts (
  id              uuid primary key default gen_random_uuid(),
  employee_id     uuid not null references employees(id) on delete cascade,
  bank_code       varchar(20) not null,
  bank_name       varchar(100) not null,
  account_number  varchar(50) not null,
  account_name    varchar(255) not null,
  account_type    varchar(20),
  is_primary      boolean not null default false,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz
);
create index on employee_bank_accounts (employee_id);
create trigger _employee_bank_accounts_updated before update on employee_bank_accounts for each row execute function set_updated_at();

create table employment_events (
  id                 uuid primary key default gen_random_uuid(),
  employee_id        uuid not null references employees(id) on delete cascade,
  event_type         employment_event_type not null,
  event_date         date not null,
  payload            jsonb not null,
  status             employment_event_status not null default 'PENDING',
  requested_by_id    uuid references users(id),
  approved_by_id     uuid references users(id),
  approved_at        timestamptz,
  rejection_reason   text,
  remarks            text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index on employment_events (employee_id, event_type);
create index on employment_events (event_date);
create trigger _employment_events_updated before update on employment_events for each row execute function set_updated_at();

create table employee_documents (
  id                          uuid primary key default gen_random_uuid(),
  employee_id                 uuid not null references employees(id) on delete cascade,
  document_type               varchar(50) not null,
  title                       varchar(255) not null,
  description                 text,
  file_path                   varchar(500),
  file_name                   varchar(255) not null,
  file_size_bytes             bigint,
  mime_type                   varchar(100),
  generated_from_template_id  uuid,
  generated_from_event_id     uuid references employment_events(id),
  template_version            integer,
  generation_options          jsonb,
  requires_acknowledgment     boolean not null default false,
  acknowledged_at             timestamptz,
  acknowledged_by_id          uuid references users(id),
  status                      document_status not null default 'ISSUED',
  expires_at                  timestamptz,
  supersedes_document_id      uuid references employee_documents(id),
  lark_approval_instance_code varchar(100),
  lark_approval_sent_at       timestamptz,
  lark_approval_status        varchar(20),
  uploaded_by_id              uuid references users(id),
  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now(),
  deleted_at                  timestamptz
);
create index on employee_documents (employee_id, document_type);
create index on employee_documents (status);
create index on employee_documents (expires_at);
create index on employee_documents (lark_approval_instance_code);
create trigger _employee_documents_updated before update on employee_documents for each row execute function set_updated_at();

-- Now that employees exists, backfill the departments.manager_id FK
alter table departments
  add constraint departments_manager_id_fkey
  foreign key (manager_id) references employees(id) on delete set null;
