-- =============================================================================
-- Secure user_emails: stop exposing auth.users through a public, RLS-bypassing view
-- =============================================================================
-- The prior user_emails view (20260420000002_user_management.sql) was a default
-- (SECURITY DEFINER) view granted to `authenticated`. Default Postgres views run
-- as their OWNER (postgres) and BYPASS RLS on the tables underneath them, so any
-- authenticated user — including a plain EMPLOYEE — could `select * from
-- user_emails` and read every user's email, last_sign_in_at and app_role across
-- every company. Supabase flags this as `auth_users_exposed`. The migration/repo
-- comments claiming "RLS on user_emails already scopes to the caller" were wrong:
-- RLS does not carry through a security-definer view.
--
-- A plain `security_invoker` view over the auth.users join does not work either:
-- security_invoker checks the CALLER's privileges, and `authenticated` has no
-- SELECT on auth.users.
--
-- Fix: denormalize the three auth-derived fields onto public.users, keep them in
-- sync with auth.users via triggers, then rebuild user_emails as a
-- security_invoker view over public.users ONLY (no auth.users reference). This
-- removes auth.users from the exposed surface (clears the linter) and lets RLS on
-- public.users (users_self_read: id = auth.uid() OR auth_is_hr_or_admin()) govern
-- who sees which rows (fixes the cross-company leak).

-- 1. Mirror columns on public.users.
alter table users add column if not exists email           text;
alter table users add column if not exists last_sign_in_at timestamptz;
alter table users add column if not exists app_role        text;

-- 2. Backfill from auth.users. The users.id -> auth.users(id) FK guarantees a match.
update users u
   set email           = au.email,
       last_sign_in_at = au.last_sign_in_at,
       app_role        = au.raw_app_meta_data ->> 'app_role'
  from auth.users au
 where au.id = u.id;

-- 3a. Populate the mirror columns when a public.users row is created. The
--     users.id -> auth.users(id) FK guarantees the auth row already exists, so a
--     BEFORE INSERT lookup always finds it.
create or replace function public.users_fill_auth_fields()
  returns trigger
  language plpgsql
  security definer
  set search_path = ''
as $$
begin
  select au.email, au.last_sign_in_at, au.raw_app_meta_data ->> 'app_role'
    into new.email, new.last_sign_in_at, new.app_role
    from auth.users au
   where au.id = new.id;
  return new;
end;
$$;

drop trigger if exists users_fill_auth_fields on users;
create trigger users_fill_auth_fields
  before insert on users
  for each row execute function public.users_fill_auth_fields();

-- 3b. Propagate later auth.users changes — email edits, last_sign_in_at on every
--     login, app_role metadata updates — to the mirror columns. Guarded so token
--     refreshes that touch no mirrored field are a no-op.
create or replace function public.sync_users_auth_fields()
  returns trigger
  language plpgsql
  security definer
  set search_path = ''
as $$
begin
  update public.users u
     set email           = new.email,
         last_sign_in_at = new.last_sign_in_at,
         app_role        = new.raw_app_meta_data ->> 'app_role'
   where u.id = new.id
     and (u.email           is distinct from new.email
       or u.last_sign_in_at is distinct from new.last_sign_in_at
       or u.app_role        is distinct from (new.raw_app_meta_data ->> 'app_role'));
  return new;
end;
$$;

drop trigger if exists sync_users_auth_fields on auth.users;
create trigger sync_users_auth_fields
  after update on auth.users
  for each row execute function public.sync_users_auth_fields();

-- 4. Rebuild user_emails as a security_invoker view over public.users ONLY.
--    Same name + columns as before, so the PostgREST embeds
--    (user_emails!created_by_id(email)) and the Users tab query are unchanged.
drop view if exists user_emails;
create view user_emails
  with (security_invoker = on) as
  select
    id,
    company_id,
    status,
    must_change_password,
    invited_at,
    invited_by,
    email,
    last_sign_in_at,
    app_role
  from users;

comment on view user_emails is
  'Public users with mirrored auth email/last_sign_in_at/app_role. '
  'security_invoker so RLS on public.users governs access. Auth fields are kept '
  'in sync by triggers (see 20260708000002); no auth.users reference.';

-- PostgREST needs an explicit grant to read the view.
grant select on user_emails to authenticated;
