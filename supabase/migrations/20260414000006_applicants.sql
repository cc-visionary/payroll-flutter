-- Applicants + interviews

create table applicants (
  id                        uuid primary key default gen_random_uuid(),
  company_id                uuid not null references companies(id),
  first_name                varchar(100) not null,
  middle_name               varchar(100),
  last_name                 varchar(100) not null,
  suffix                    varchar(20),
  email                     varchar(255) not null,
  phone_number              varchar(20),
  mobile_number             varchar(20),
  role_scorecard_id         uuid references role_scorecards(id),
  custom_job_title          varchar(100),
  department_id             uuid references departments(id),
  hiring_entity_id          uuid references hiring_entities(id),
  source                    varchar(100),
  referred_by_id            uuid references employees(id),
  resume_path               varchar(500),
  resume_file_name          varchar(255),
  cover_letter_path         varchar(500),
  portfolio_url             varchar(500),
  linkedin_url              varchar(500),
  offer_letter_path         varchar(500),
  expected_salary_min       numeric(12,2),
  expected_salary_max       numeric(12,2),
  expected_start_date       date,
  status                    applicant_status not null default 'NEW',
  status_changed_at         timestamptz not null default now(),
  status_changed_by_id      uuid references users(id),
  notes                     text,
  rejection_reason          text,
  withdrawal_reason         text,
  converted_to_employee_id  uuid unique references employees(id),
  converted_at              timestamptz,
  applied_at                timestamptz not null default now(),
  created_by_id             uuid references users(id),
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),
  deleted_at                timestamptz
);
create index on applicants (company_id, status);
create index on applicants (company_id, role_scorecard_id);
create index on applicants (email);
create trigger _applicants_updated before update on applicants for each row execute function set_updated_at();

create table interviews (
  id                      uuid primary key default gen_random_uuid(),
  applicant_id            uuid not null references applicants(id) on delete cascade,
  interview_type          interview_type not null,
  title                   varchar(255),
  description             text,
  scheduled_date          date not null,
  scheduled_start_time    time not null,
  scheduled_end_time      time not null,
  location                varchar(255),
  is_virtual              boolean not null default false,
  meeting_link            varchar(500),
  primary_interviewer_id  uuid references employees(id),
  interviewer_ids         uuid[],
  result                  interview_result not null default 'PENDING',
  result_notes            text,
  rating                  integer,
  strengths               text,
  concerns                text,
  recommendation          text,
  created_by_id           uuid references users(id),
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);
create index on interviews (applicant_id);
create index on interviews (scheduled_date);
create index on interviews (primary_interviewer_id);
create trigger _interviews_updated before update on interviews for each row execute function set_updated_at();
