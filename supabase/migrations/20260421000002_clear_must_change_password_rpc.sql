-- =============================================================================
-- Self-service RPC: clear must_change_password for the current user
-- =============================================================================
--
-- The change-password screen needs to flip public.users.must_change_password
-- to false for the authenticated user after they pick a new password.
--
-- Going through PostgREST directly depends on a layered combination of
-- column-level GRANTs + RLS policies that has proven brittle in practice
-- (silent 0-row updates when any layer mis-evaluates, leaving the user
-- trapped on /change-password). This RPC sidesteps all of it by running as
-- SECURITY DEFINER but constraining the write to the caller's own row, so
-- there is no elevated privilege surface to abuse.

create or replace function public.clear_must_change_password()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  update public.users
     set must_change_password = false
   where id = auth.uid();
end;
$$;

revoke all on function public.clear_must_change_password() from public;
grant execute on function public.clear_must_change_password() to authenticated;

comment on function public.clear_must_change_password() is
  'Clears must_change_password for the authenticated user. Called by the change-password screen after the new password is accepted by Supabase Auth.';
