-- =============================================================================
-- User management: admin-set temp passwords + audit + extended app_role enum
-- =============================================================================

-- Extend app_role enum so the codes from the public.roles table can be stamped
-- as JWT app_metadata.app_role and survive the cast in auth_app_role().
-- Existing values (SUPER_ADMIN, ADMIN, HR, MANAGER, EMPLOYEE) stay for
-- back-compat with already-issued JWTs and any legacy seed data.
alter type app_role add value if not exists 'PAYROLL_ADMIN';
alter type app_role add value if not exists 'HR_ADMIN';
alter type app_role add value if not exists 'FINANCE_MANAGER';

-- Track admin-set temp passwords. Cleared when the user changes password
-- via the /change-password screen on first login.
alter table users add column must_change_password boolean not null default false;

-- Audit who provisioned the user, for the Users settings list.
alter table users add column invited_by uuid references users(id) on delete set null;
alter table users add column invited_at timestamptz;

-- Recreate the user_emails view with the columns the Users tab needs.
-- Backward-compat: id, company_id, email are preserved so existing
-- payroll_repository joins (`user_emails!created_by_id(email)`) still resolve.
drop view if exists user_emails;
create or replace view user_emails as
  select
    u.id,
    u.company_id,
    u.status,
    u.must_change_password,
    u.invited_at,
    u.invited_by,
    au.email,
    au.last_sign_in_at,
    (au.raw_app_meta_data ->> 'app_role') as app_role
  from users u
  join auth.users au on au.id = u.id;

comment on view user_emails is
  'Public users joined with their auth.users email + admin metadata. Used for audit UI and the Users settings tab.';

-- Re-grant required: DROP VIEW removed the prior grant from
-- 20260418000004_user_emails_view.sql along with the view object itself.
grant select on user_emails to authenticated;

-- Allow a user to clear their own must_change_password flag — and ONLY that
-- column. Column-level grants restrict the surface; the policy pins the new
-- value to false and the row to the caller.
--
-- The `revoke` is defensive: the `authenticated` role may not currently hold
-- a broad `update` on `users` (Supabase did not grant one in earlier
-- migrations), so this is mostly a guarantee for future maintainers — no
-- accidental grant elsewhere can re-open broad writes.
--
-- This revoke/grant ONLY constrains plain `authenticated` callers. The
-- existing `users_admin_write` RLS policy (see 20260414000014_rls.sql) lets
-- SUPER_ADMIN / ADMIN write any column, and the `manage-user` edge function
-- runs with the service_role key and bypasses RLS entirely.
revoke update on users from authenticated;
grant update (must_change_password) on users to authenticated;

create policy users_self_clear_must_change on users
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid() and must_change_password = false);
