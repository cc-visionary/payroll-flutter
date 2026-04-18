-- Performance: check_in_periods, performance_check_ins, check_in_goals, skill_ratings

create table check_in_periods (
  id           uuid primary key default gen_random_uuid(),
  company_id   uuid not null references companies(id) on delete cascade,
  name         varchar(100) not null,
  period_type  check_in_type not null default 'MONTHLY',
  start_date   date not null,
  end_date     date not null,
  due_date     date not null,
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (company_id, name)
);
create index on check_in_periods (company_id, start_date);
create trigger _check_in_periods_updated before update on check_in_periods for each row execute function set_updated_at();

create table performance_check_ins (
  id                     uuid primary key default gen_random_uuid(),
  period_id              uuid not null references check_in_periods(id) on delete cascade,
  employee_id            uuid not null references employees(id) on delete cascade,
  reviewer_id            uuid references users(id),
  status                 check_in_status not null default 'DRAFT',
  overall_rating         integer,
  overall_comments       text,
  accomplishments        text,
  challenges             text,
  learnings              text,
  support_needed         text,
  manager_feedback       text,
  strengths              text,
  areas_for_improvement  text,
  submitted_at           timestamptz,
  reviewed_at            timestamptz,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  unique (period_id, employee_id)
);
create index on performance_check_ins (employee_id);
create index on performance_check_ins (status);
create trigger _performance_check_ins_updated before update on performance_check_ins for each row execute function set_updated_at();

create table check_in_goals (
  id                  uuid primary key default gen_random_uuid(),
  check_in_id         uuid not null references performance_check_ins(id) on delete cascade,
  goal_type           goal_type not null default 'PERFORMANCE',
  title               varchar(255) not null,
  description         text,
  target_date         date,
  progress            integer not null default 0,
  status              goal_status not null default 'IN_PROGRESS',
  self_assessment     text,
  manager_assessment  text,
  rating              integer,
  carry_forward       boolean not null default false,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create index on check_in_goals (check_in_id);
create trigger _check_in_goals_updated before update on check_in_goals for each row execute function set_updated_at();

create table skill_ratings (
  id                uuid primary key default gen_random_uuid(),
  check_in_id       uuid not null references performance_check_ins(id) on delete cascade,
  skill_category    varchar(100) not null,
  skill_name        varchar(100) not null,
  self_rating       integer,
  manager_rating    integer,
  comments          text,
  development_plan  text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (check_in_id, skill_category, skill_name)
);
create index on skill_ratings (check_in_id);
create trigger _skill_ratings_updated before update on skill_ratings for each row execute function set_updated_at();
