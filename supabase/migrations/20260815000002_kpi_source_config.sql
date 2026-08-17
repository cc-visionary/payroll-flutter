-- Configuration for external (non-app) KPI data sources -- see
-- docs/superpowers/specs/2026-08-14-configurable-kpi-sources-design.md.
--
-- Three tables, each pure configuration, never computed:
--   kpi_connections     -- a named source system (Cashflow's Postgres, a
--                          sibling Supabase project, ...).
--   kpi_source_bindings -- how one KPI reads from one connection: which
--                          table/view, and which of its columns are the
--                          period, subject, numerator and denominator.
--   kpi_subject_map     -- a source's own key (a staff id, an email) ->
--                          this app's employee or department, per
--                          connection.
--
-- Nothing here executes SQL. `object_name` and the four *_column values are
-- validated as strict identifiers (see the CHECK constraints below, and
-- their Dart/TS twins: isValidSqlIdentifier in
-- lib/data/models/kpi_result.dart's sibling
-- lib/features/kpi_results/sql_identifier.dart, and quoteIdentifier in
-- supabase/functions/_shared/source_query.ts) before Task 5's edge function
-- ever builds a statement from them. The period is always a bound
-- parameter, never interpolated.
--
-- ## Credential design -- replaces this task's "verify Vault" step
--
-- The plan that produced this migration asked the implementer to check
-- whether `vault.create_secret`/`vault.decrypted_secrets` are available on
-- this project. That step was withdrawn before this file was written: an
-- implementer with no database session cannot run `select * from
-- vault.decrypted_secrets limit 1` any more than it can run `supabase db
-- push`, so "verify Vault" was asking for something this task has no
-- authority to do. Deciding which retrieval path a given connection uses is
-- deferred to whoever applies this migration and configures the first real
-- connection -- a decision made once, with a live database in front of
-- them, not guessed at from a worktree.
--
-- What ships instead is a column pair that names the decision without
-- making it: `credential_kind` records WHICH mechanism holds the secret,
-- `credential_ref` names it within that mechanism. Task 5's edge function
-- branches on `credential_kind`:
--   'VAULT' -- the secret is a row in Supabase Vault; read it via
--             `select decrypted_secret from vault.decrypted_secrets where
--             name = credential_ref`. Available if this project's Vault
--             extension is enabled -- confirm at apply time.
--   'ENV'   -- the secret is a function environment variable, the same
--             pattern `authFromEnv()` already uses for Lark
--             (supabase/functions/_shared/lark.ts:18): `Deno.env.get(credential_ref)`,
--             set once per connection via `supabase secrets set
--             <credential_ref>=<password>`. Configuration, not code, but
--             not self-service from the UI either -- adding a connection
--             this way still needs an admin with CLI access.
--
-- Either path, `credential_ref` names a secret holding the PASSWORD ALONE
-- -- see `db_user` below for the username, which is not secret and does
-- not live behind either mechanism. This table never stores the password
-- itself, only the name of where to find it. Nothing granted SELECT on
-- kpi_connections (see RLS below) can ever read a credential through it.
--
-- ## `db_user` is not secret
--
-- Task 5's first pass had no column for the external database's username
-- and worked around that by packing it into the credential secret as
-- `user:password`. That was flagged as an assumption needing sign-off, and
-- on review it was rejected in favour of a real column: a username is
-- configuration an admin can read at a glance, not something that should
-- require decrypting a secret to see, and rotating a password should never
-- require re-typing (and risk mistyping) the username alongside it. Keep
-- host/port/database/db_schema/db_user together as the non-secret half.

create table if not exists kpi_connections (
  id              uuid primary key default gen_random_uuid(),
  company_id      uuid not null references companies(id) on delete cascade,
  name            text not null,
  kind            text not null check (kind in ('POSTGRES', 'SUPABASE')),
  host            text not null,
  port            integer not null default 5432,
  database        text not null,
  db_schema       text not null default 'public',
  -- Non-secret. See "`db_user` is not secret" above.
  db_user         text not null,
  -- See the credential design note above. Names a secret holding the
  -- PASSWORD ALONE -- never combined with the username as "user:password".
  credential_kind text not null check (credential_kind in ('VAULT', 'ENV')),
  credential_ref  text not null,
  is_active       boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint kpi_connections_name_not_blank check (length(trim(name)) > 0),
  constraint kpi_connections_db_user_not_blank
    check (length(trim(db_user)) > 0),
  constraint kpi_connections_credential_ref_not_blank
    check (length(trim(credential_ref)) > 0)
);

create index if not exists kpi_connections_company
  on kpi_connections (company_id);

drop trigger if exists _kpi_connections_updated on kpi_connections;
create trigger _kpi_connections_updated before update on kpi_connections
  for each row execute function set_updated_at();

-- An identifier safe to quote and use, unescaped, as a Postgres table or
-- column name -- the DB-side half of the rule enforced in three places now
-- (this constraint, isValidSqlIdentifier in Dart, quoteIdentifier in the
-- edge function's TS). ASCII letter or underscore, then any number of
-- ASCII letters/digits/underscores, at most 63 bytes (NAMEDATALEN - 1). No
-- dots, quotes, whitespace or comment markers -- anything outside that
-- shape is refused here rather than trusted to the two application-layer
-- checks alone.
create table if not exists kpi_source_bindings (
  id                 uuid primary key default gen_random_uuid(),
  company_id         uuid not null references companies(id) on delete cascade,
  kpi_id             uuid not null references kpis(id) on delete cascade,
  connection_id      uuid not null references kpi_connections(id) on delete cascade,
  object_name        text not null,
  period_column      text not null,
  subject_column     text not null,
  numerator_column   text not null,
  -- Nullable: a COUNT KPI has no denominator. Must round-trip as null, not
  -- '' -- see KpiSourceBinding.fromRow / toUpsertPayload and its test.
  denominator_column text,
  subject_kind       text not null check (subject_kind in ('EMPLOYEE', 'DEPARTMENT', 'NONE')),
  period_format      text not null default 'YYYY-MM',
  is_active          boolean not null default true,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  constraint kpi_source_bindings_object_name_valid
    check (object_name ~ '^[A-Za-z_][A-Za-z0-9_]{0,62}$'),
  constraint kpi_source_bindings_period_column_valid
    check (period_column ~ '^[A-Za-z_][A-Za-z0-9_]{0,62}$'),
  constraint kpi_source_bindings_subject_column_valid
    check (subject_column ~ '^[A-Za-z_][A-Za-z0-9_]{0,62}$'),
  constraint kpi_source_bindings_numerator_column_valid
    check (numerator_column ~ '^[A-Za-z_][A-Za-z0-9_]{0,62}$'),
  constraint kpi_source_bindings_denominator_column_valid
    check (denominator_column is null or denominator_column ~ '^[A-Za-z_][A-Za-z0-9_]{0,62}$')
);

create index if not exists kpi_source_bindings_company
  on kpi_source_bindings (company_id);
create index if not exists kpi_source_bindings_kpi
  on kpi_source_bindings (kpi_id);
create index if not exists kpi_source_bindings_connection
  on kpi_source_bindings (connection_id);

-- At most one ACTIVE binding per KPI. This is not merely tidiness: a KPI
-- selects its source by matching `kpis.numerator_source` against the
-- registry, and Task 6 keys a configured source as `cfg:<bindingId>`. If
-- two active bindings could exist for one KPI, resolving "which one" would
-- need an admin to paste a specific binding's uuid into a free-text field.
-- With at most one, the binding's existence is what selects it -- there is
-- no second thing to disambiguate from. Partial (WHERE is_active) so a
-- retired binding can be deactivated and a replacement created without
-- deleting history.
create unique index if not exists kpi_source_bindings_kpi_active
  on kpi_source_bindings (kpi_id) where is_active;

drop trigger if exists _kpi_source_bindings_updated on kpi_source_bindings;
create trigger _kpi_source_bindings_updated before update on kpi_source_bindings
  for each row execute function set_updated_at();

-- external_key -> this app's employee or department, scoped to one
-- connection: two connections may reuse the same external key for
-- different people, so the uniqueness and the resolution both key off
-- (connection_id, external_key), never external_key alone.
create table if not exists kpi_subject_map (
  id            uuid primary key default gen_random_uuid(),
  company_id    uuid not null references companies(id) on delete cascade,
  connection_id uuid not null references kpi_connections(id) on delete cascade,
  external_key  text not null,
  employee_id   uuid references employees(id) on delete cascade,
  department_id uuid references departments(id) on delete cascade,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint kpi_subject_map_external_key_not_blank
    check (length(trim(external_key)) > 0),
  -- Exactly one of the two -- a row that resolves to neither is a dangling
  -- mapping nobody will ever match, and a row that resolves to both is
  -- ambiguous about which scope it feeds.
  constraint kpi_subject_map_exactly_one_subject check (
    (employee_id is not null)::int + (department_id is not null)::int = 1
  )
);

create unique index if not exists kpi_subject_map_connection_external_key
  on kpi_subject_map (connection_id, external_key);
create index if not exists kpi_subject_map_company
  on kpi_subject_map (company_id);
create index if not exists kpi_subject_map_employee
  on kpi_subject_map (employee_id);
create index if not exists kpi_subject_map_department
  on kpi_subject_map (department_id);

drop trigger if exists _kpi_subject_map_updated on kpi_subject_map;
create trigger _kpi_subject_map_updated before update on kpi_subject_map
  for each row execute function set_updated_at();

alter table kpi_connections enable row level security;
alter table kpi_source_bindings enable row level security;
alter table kpi_subject_map enable row level security;

-- All three are configuration, not a person's own data -- there is no
-- "self" a connection, a binding or a subject-map row could belong to, so
-- unlike kpi_results/kpi_readings there is deliberately no self-read or
-- manager clause. Admin-only read AND write, company-scoped, via
-- auth_is_hr_or_admin() (20260423000004_rls_recognize_new_roles.sql) --
-- not a hardcoded ('SUPER_ADMIN','ADMIN','HR','HR_ADMIN') list, which would
-- silently exclude PAYROLL_ADMIN/FINANCE_MANAGER today and drift again the
-- next time an admin-ish role is added. Modelled on kpi_results
-- (20260814000004_kpi_results.sql), which the brief names as the policy
-- that got this right, not an older one.
drop policy if exists kpi_connections_read on kpi_connections;
create policy kpi_connections_read on kpi_connections for select using (
  auth_is_hr_or_admin() and company_id = auth_company_id()
);

drop policy if exists kpi_connections_write on kpi_connections;
create policy kpi_connections_write on kpi_connections for all
  using (auth_is_hr_or_admin() and company_id = auth_company_id())
  with check (auth_is_hr_or_admin() and company_id = auth_company_id());

drop policy if exists kpi_source_bindings_read on kpi_source_bindings;
create policy kpi_source_bindings_read on kpi_source_bindings for select using (
  auth_is_hr_or_admin() and company_id = auth_company_id()
);

drop policy if exists kpi_source_bindings_write on kpi_source_bindings;
create policy kpi_source_bindings_write on kpi_source_bindings for all
  using (auth_is_hr_or_admin() and company_id = auth_company_id())
  with check (auth_is_hr_or_admin() and company_id = auth_company_id());

drop policy if exists kpi_subject_map_read on kpi_subject_map;
create policy kpi_subject_map_read on kpi_subject_map for select using (
  auth_is_hr_or_admin() and company_id = auth_company_id()
);

drop policy if exists kpi_subject_map_write on kpi_subject_map;
create policy kpi_subject_map_write on kpi_subject_map for all
  using (auth_is_hr_or_admin() and company_id = auth_company_id())
  with check (auth_is_hr_or_admin() and company_id = auth_company_id());
