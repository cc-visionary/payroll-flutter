-- Shift templates + role scorecards

create table shift_templates (
  id                        uuid primary key default gen_random_uuid(),
  company_id                uuid not null references companies(id),
  code                      varchar(20) not null,
  name                      varchar(100) not null,
  start_time                time not null,
  end_time                  time not null,
  is_overnight              boolean not null default false,
  break_type                shift_break_type not null default 'AUTO_DEDUCT',
  break_minutes             integer not null default 60,
  break_start_time          time,
  break_end_time            time,
  grace_minutes_late        integer not null default 0,
  grace_minutes_early_out   integer not null default 0,
  scheduled_work_minutes    integer not null,
  ot_early_in_enabled       boolean not null default false,
  ot_early_in_start_minutes integer not null default 0,
  ot_late_out_start_minutes integer not null default 0,
  max_ot_early_in_minutes   integer,
  max_ot_late_out_minutes   integer,
  max_ot_total_minutes      integer,
  nd_start_time             time not null default '22:00:00'::time,
  nd_end_time               time not null default '06:00:00'::time,
  lark_shift_id             varchar(100),
  is_active                 boolean not null default true,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),
  deleted_at                timestamptz,
  unique (company_id, code)
);
create index on shift_templates (company_id, is_active);
create trigger _shift_templates_updated before update on shift_templates for each row execute function set_updated_at();

create table role_scorecards (
  id                     uuid primary key default gen_random_uuid(),
  company_id             uuid not null references companies(id),
  job_title              varchar(100) not null,
  department_id          uuid references departments(id),
  mission_statement      text not null,
  key_responsibilities   jsonb not null,
  kpis                   jsonb not null,
  salary_range_min       numeric(12,2),
  salary_range_max       numeric(12,2),
  base_salary            numeric(12,2),
  wage_type              wage_type not null default 'MONTHLY',
  shift_template_id      uuid references shift_templates(id),
  work_hours_per_day     integer not null default 8,
  work_days_per_week     varchar(100) not null default 'Monday to Saturday',
  flexible_start_time    varchar(50),
  flexible_end_time      varchar(50),
  is_active              boolean not null default true,
  effective_date         date not null,
  superseded_by_id       uuid references role_scorecards(id),
  created_by_id          uuid references users(id),
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  unique (company_id, job_title, effective_date)
);
create index on role_scorecards (company_id, job_title);
create index on role_scorecards (department_id);
create index on role_scorecards (shift_template_id);
create trigger _role_scorecards_updated before update on role_scorecards for each row execute function set_updated_at();
