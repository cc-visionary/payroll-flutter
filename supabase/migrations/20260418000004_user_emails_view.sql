-- View: user_emails
-- Exposes each public.users row with its auth.users email, so the app can
-- render "created by <email>" / "approved by <email>" on audit-style UI
-- (payroll run history, attendance override logs, etc.) without needing
-- an admin-only auth.users query.
--
-- Scoped by company_id like public.users so RLS on the underlying table
-- carries through. Auth email is read-only.

create or replace view user_emails as
  select
    u.id,
    u.company_id,
    au.email
  from users u
  join auth.users au on au.id = u.id;

comment on view user_emails is
  'Public users joined with their auth.users email. Used for audit UI.';

-- PostgREST needs an explicit grant to read the view.
grant select on user_emails to authenticated;
