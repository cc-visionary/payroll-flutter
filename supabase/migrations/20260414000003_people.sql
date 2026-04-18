-- People: users (profile linked to auth.users), roles, user_roles, user_companies
-- Auth (password, MFA, email verification, sessions, refresh tokens) lives in
-- Supabase's auth.users — this table only holds app-level profile data.

create table users (
  id          uuid primary key references auth.users(id) on delete cascade,
  company_id  uuid not null references companies(id),
  status      user_status not null default 'ACTIVE',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);
create index on users (company_id);
create trigger _users_updated before update on users for each row execute function set_updated_at();

create table roles (
  id           uuid primary key default gen_random_uuid(),
  code         varchar(50) not null unique,
  name         varchar(100) not null,
  description  text,
  permissions  jsonb not null default '[]'::jsonb,
  is_system    boolean not null default false,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create trigger _roles_updated before update on roles for each row execute function set_updated_at();

create table user_roles (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references users(id) on delete cascade,
  role_id     uuid not null references roles(id) on delete cascade,
  created_at  timestamptz not null default now(),
  unique (user_id, role_id)
);

create table user_companies (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references users(id) on delete cascade,
  company_id  uuid not null references companies(id) on delete cascade,
  is_default  boolean not null default false,
  created_at  timestamptz not null default now(),
  unique (user_id, company_id)
);
create index on user_companies (user_id);
create index on user_companies (company_id);

-- App-level session tracking (device list, audit). Supabase auth.sessions still
-- handles the actual refresh-token lifecycle — this table is for app metadata.
create table sessions (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references users(id) on delete cascade,
  refresh_token  varchar(500) not null unique,
  user_agent     varchar(500),
  ip_address     varchar(45),
  expires_at     timestamptz not null,
  created_at     timestamptz not null default now()
);
create index on sessions (user_id);
create index on sessions (expires_at);
