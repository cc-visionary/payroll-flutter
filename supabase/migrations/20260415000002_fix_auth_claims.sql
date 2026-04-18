-- Patch RLS JWT claim helpers to read from either top-level or nested
-- `app_metadata.*`. Supabase puts values set via auth.admin.updateUserById
-- appMetadata inside `app_metadata`, not at the top level of the JWT.

create or replace function auth_app_role()
returns app_role language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'app_role', ''),
    nullif(current_setting('request.jwt.claims', true)::jsonb -> 'app_metadata' ->> 'app_role', ''),
    'EMPLOYEE'
  )::app_role
$$;

create or replace function auth_company_id()
returns uuid language sql stable as $$
  select nullif(
    coalesce(
      current_setting('request.jwt.claims', true)::jsonb ->> 'company_id',
      current_setting('request.jwt.claims', true)::jsonb -> 'app_metadata' ->> 'company_id'
    ),
    ''
  )::uuid
$$;

create or replace function auth_employee_id()
returns uuid language sql stable as $$
  select nullif(
    coalesce(
      current_setting('request.jwt.claims', true)::jsonb ->> 'employee_id',
      current_setting('request.jwt.claims', true)::jsonb -> 'app_metadata' ->> 'employee_id'
    ),
    ''
  )::uuid
$$;
