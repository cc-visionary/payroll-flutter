-- Foundation: companies, hiring entities, departments, holiday calendars, role scorecards
-- Shift templates + role scorecards depend on each other; create shift_templates first (see next migration).

-- =============================================================================
-- companies
-- =============================================================================
create table companies (
  id                      uuid primary key default gen_random_uuid(),
  code                    varchar(20) not null unique,
  name                    varchar(255) not null,
  trade_name              varchar(255),
  tin                     varchar(20),
  sss_employer_id         varchar(20),
  philhealth_employer_id  varchar(20),
  pagibig_employer_id     varchar(20),
  address_line1           varchar(255),
  address_line2           varchar(255),
  city                    varchar(100),
  province                varchar(100),
  zip_code                varchar(10),
  country                 varchar(2) not null default 'PH',
  rdo_code                varchar(10),
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  deleted_at              timestamptz
);
create trigger _companies_updated before update on companies for each row execute function set_updated_at();

-- =============================================================================
-- hiring_entities
-- =============================================================================
create table hiring_entities (
  id                      uuid primary key default gen_random_uuid(),
  company_id              uuid not null references companies(id),
  code                    varchar(20) not null,
  name                    varchar(255) not null,
  trade_name              varchar(255),
  tin                     varchar(20),
  rdo_code                varchar(10),
  sss_employer_id         varchar(20),
  philhealth_employer_id  varchar(20),
  pagibig_employer_id     varchar(20),
  address_line1           varchar(255),
  address_line2           varchar(255),
  city                    varchar(100),
  province                varchar(100),
  zip_code                varchar(10),
  country                 varchar(2) not null default 'PH',
  phone_number            varchar(20),
  email                   varchar(255),
  is_active               boolean not null default true,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  deleted_at              timestamptz,
  unique (company_id, code)
);
create index on hiring_entities (company_id);
create trigger _hiring_entities_updated before update on hiring_entities for each row execute function set_updated_at();

-- =============================================================================
-- holiday_calendars + calendar_events
-- =============================================================================
create table holiday_calendars (
  id              uuid primary key default gen_random_uuid(),
  company_id      uuid not null references companies(id),
  year            integer not null,
  name            varchar(100) not null,
  is_active       boolean not null default true,
  last_synced_at  timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (company_id, year)
);
create trigger _holiday_calendars_updated before update on holiday_calendars for each row execute function set_updated_at();

create table calendar_events (
  id           uuid primary key default gen_random_uuid(),
  calendar_id  uuid not null references holiday_calendars(id) on delete cascade,
  date         date not null,
  name         varchar(255) not null,
  day_type     day_type not null,
  source       varchar(20) not null default 'LARK',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (calendar_id, date)
);
create trigger _calendar_events_updated before update on calendar_events for each row execute function set_updated_at();

-- =============================================================================
-- departments (self-referential; manager FK added later after employees table)
-- =============================================================================
create table departments (
  id                    uuid primary key default gen_random_uuid(),
  company_id            uuid not null references companies(id),
  code                  varchar(20) not null,
  name                  varchar(255) not null,
  parent_department_id  uuid references departments(id),
  cost_center_code      varchar(20),
  manager_id            uuid,  -- FK added after employees
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  deleted_at            timestamptz,
  unique (company_id, code)
);
create index on departments (company_id);
create trigger _departments_updated before update on departments for each row execute function set_updated_at();
