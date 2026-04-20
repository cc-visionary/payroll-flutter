# User Management — Design Spec

**Date:** 2026-04-20
**Status:** Approved, ready for implementation plan
**Owner:** Donald

## Goal

Let a SUPER_ADMIN add login users to the company, assign each a role, optionally link them to an existing employee, and set/reset their passwords — all from inside the Flutter app, with no email delivery.

## Non-goals

- No SMTP / email-based invites or password resets. Email is a login identifier only.
- No multi-role per user. One role per user; the role's `code` becomes the JWT `app_role` claim.
- No fine-grained permission enforcement in this iteration — the existing roles screen remains "informational" as it is today. The JWT `app_role` continues to drive admin gates.
- No employee-self-service login. Admins log in; employees do not (per existing app architecture).

## Decisions (from brainstorming)

- **Q1 password setup:** Admin sets a temporary password; user is forced to change it on first login.
- **Q2 employee link:** Optional — some users link to an existing `employees` row, some are standalone (e.g., external accountant).
- **Q3 role model:** Single role per user. Role code is the JWT claim.

## Architecture

```
Flutter Settings → Users tab
        |
        +-- reads:  user_emails view  (id, email, company_id, status,
        |                              must_change_password, last_sign_in_at,
        |                              app_role, invited_by, invited_at)
        |           user_roles join roles
        |           employees (for "linked to" display)
        |
        +-- writes: invokes manage-user Edge Function (service-role)
                          |
                          +-- auth.admin.createUser({password, email_confirm: true})
                          +-- auth.admin.updateUserById({password | app_metadata | ban_duration})
                          +-- public.users insert/update
                          +-- public.user_roles insert/delete
                          +-- public.employees.user_id update

First-login interceptor (GoRouter redirect):
    session == null              -> /login
    profile.mustChangePassword   -> /change-password (cannot bypass)
    else                          -> requested route
```

Why one edge function: shared auth + company-scope checks; deploy once; matches the `bootstrap-company` pattern already in the repo.

## Schema migration

File: `supabase/migrations/20260420000001_user_management.sql`

```sql
-- Track admin-set temp passwords. Cleared when user changes password.
alter table users add column must_change_password boolean not null default false;

-- Audit who provisioned the user.
alter table users add column invited_by uuid references users(id);
alter table users add column invited_at timestamptz;

-- Recreate the user_emails view with the columns the Users tab needs.
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

grant select on user_emails to authenticated;
-- Backward-compat note: the prior view exposed (id, company_id, email).
-- Those columns are preserved here so the existing payroll_repository
-- joins (`user_emails!created_by_id(email)`) continue to resolve.

-- Allow a user to clear their own must_change_password flag — and ONLY that
-- column. Column-level grants restrict the surface; the policy pins the new
-- value to false and the row to the caller's own. Every other write path
-- stays admin-only via the manage-user edge function.
revoke update on users from authenticated;
grant update (must_change_password) on users to authenticated;

create policy users_self_clear_must_change on users
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid() and must_change_password = false);
```

No new tables. Existing `users`, `user_roles`, `roles`, `employees` reused.

## Edge function: `manage-user`

Path: `supabase/functions/manage-user/index.ts`
Pattern: mirrors `bootstrap-company` — service-role client, validates caller JWT, scopes everything to caller's `company_id`.

### Caller authorization

- Caller JWT must be valid.
- Caller's `app_metadata.app_role` must equal `SUPER_ADMIN`.
- All target user_ids and employee_ids must belong to caller's `company_id`.

### Actions

| `action` | Payload | Behavior |
|---|---|---|
| `create` | `email, password, role_code, employee_id?` | `auth.admin.createUser({email, password, email_confirm: true, app_metadata: {app_role: role_code, company_id}})` → insert `users` row (status=ACTIVE, must_change_password=true, invited_by=caller, invited_at=now) → insert `user_roles` row → if `employee_id` set, update `employees.user_id`. |
| `set_password` | `user_id, password` | `auth.admin.updateUserById({password})` → set `must_change_password=true` so they re-set on next login. |
| `update_role` | `user_id, role_code` | Replace `user_roles` row + `auth.admin.updateUserById({app_metadata: {...existing, app_role: role_code}})`. |
| `link_employee` | `user_id, employee_id\|null` | Set `employees.user_id = user_id` (or clear). |
| `deactivate` | `user_id` | Set `users.status = INACTIVE` + `auth.admin.updateUserById({ban_duration: '876000h'})`. |
| `reactivate` | `user_id` | Set `users.status = ACTIVE` + `auth.admin.updateUserById({ban_duration: 'none'})`. |

No `delete` action — preserves audit references (`created_by`, `approved_by` on payroll runs, attendance edits, etc.).

### Validation guards

- Email uniqueness: surface a friendly error when Supabase rejects a duplicate.
- Password length ≥ 8.
- `role_code` must exist in `roles` table.
- Caller cannot demote/deactivate themselves if they are the last SUPER_ADMIN in the company (count `auth.users` with `app_metadata.app_role = 'SUPER_ADMIN'` within company).
- `employee_id` must be in caller's company AND not already linked to another user.

### Response shape

`{ ok: true, user_id }` on success; `{ ok: false, error: <message>, code?: <enum> }` on failure with `code` in `{ DUPLICATE_EMAIL, WEAK_PASSWORD, INVALID_ROLE, EMPLOYEE_TAKEN, EMPLOYEE_WRONG_COMPANY, LAST_SUPER_ADMIN, NOT_AUTHORIZED }`.

## Flutter UI

### Tab registration

Edit `lib/features/settings/settings_screen.dart`:
- Add `users` enum value to `_Tab` between `roles` and `shifts`.
- Slug `users`, label `Users`, subtitle `Manage who can log in`, icon `Icons.people_alt_outlined`.
- Hide the tab unless `profile.appRole == SUPER_ADMIN` (other admins can manage roles but not users in this iteration).

### Users list screen

File: `lib/features/settings/users/users_settings_screen.dart`

Per-row content:
- Display name: linked employee name if present, else email local-part.
- Email (mono) + linked employee subtitle ("linked: <name>" or "no employee link").
- Role chip (StatusChip with role code).
- Status indicators: "Last sign-in: <relative>", "⚠ Must change password on next login" if flag set, "Inactive" if banned.
- Overflow menu: **Change role** · **Set new password** · **Link/unlink employee** · **Deactivate** / **Reactivate**.

CTA: `[+ Add User]` opens the add dialog.

### Add User dialog

Fields:
- Email (required, validated as email format).
- Password + Confirm (required, ≥8, mismatch error). Generate-button fills both with `crypto.randomBytes(9).base64`-style high-entropy temp password.
- Role dropdown (from `roles` table, system roles first, default `PAYROLL_ADMIN`).
- Link to employee — searchable dropdown of unlinked employees in company, with "(none — standalone user)" option.

On submit: invoke `manage-user` with `action=create`. On success, replace dialog with a "User created" panel showing the temporary password and a copy-to-clipboard button. Password is shown ONCE here; if the admin loses it they must use **Set new password**.

### Set new password dialog

Fields: New password + Confirm + Generate button (same component as Add User). On submit: `manage-user` with `action=set_password`. On success: same "copy once" panel.

### Change role dialog

Radio list of role codes (from `roles` table). On submit: `manage-user` with `action=update_role`.

### Link/unlink employee dialog

Searchable employee dropdown (only employees with `user_id IS NULL` OR currently linked to this user) plus "Unlink" option. On submit: `manage-user` with `action=link_employee`.

### Repository

File: `lib/data/repositories/user_management_repository.dart`. Wraps:
- `list()` → reads `user_emails` view + joins `user_roles` + `employees` for display.
- `unlinkedEmployees(companyId)` → reads `employees` where `user_id is null` (for the dropdown).
- One method per edge-function action.

## First-login change-password flow

### Profile extension

Edit `lib/features/auth/profile_provider.dart`:
- Add `bool mustChangePassword` to `UserProfile`.
- Read it from `user_emails` view alongside `company_id` (single query — currently reads `users` for `company_id`; switch to `user_emails`).

### Router redirect

Edit `lib/app/router.dart` (or wherever GoRouter is configured):
- Redirect order: no session → `/login`; `profile.mustChangePassword == true` → `/change-password`; else allow.
- The `/change-password` route is the only allowed destination when the flag is set; even direct URL navigation gets redirected back.

### Change-password screen

File: `lib/features/auth/change_password_screen.dart`
- Two fields: New password, Confirm. Both ≥8 chars, must match.
- Submit:
  1. `supabase.auth.updateUser(UserAttributes(password: ...))`.
  2. `supabase.from('users').update({'must_change_password': false}).eq('id', userId)` (succeeds via the new self-update RLS policy).
  3. `ref.invalidate(userProfileProvider)` so the router redirect re-fires and drops them at `/`.
- No skip / no back button. Sign-out button in the top-right as escape hatch.

## Touch list

| File | Change |
|---|---|
| `supabase/migrations/20260420000001_user_management.sql` | NEW — schema + view + self-update RLS. |
| `supabase/functions/manage-user/index.ts` | NEW — edge function with all admin actions. |
| `lib/features/settings/settings_screen.dart` | EDIT — add `users` tab. |
| `lib/features/settings/users/users_settings_screen.dart` | NEW — Users list + Add/Edit/Set-password/Link/Deactivate dialogs. |
| `lib/data/repositories/user_management_repository.dart` | NEW — repo wrapping the edge function + view reads. |
| `lib/features/auth/profile_provider.dart` | EDIT — add `mustChangePassword` to `UserProfile`; switch profile read to `user_emails`. |
| `lib/features/auth/change_password_screen.dart` | NEW — first-login change-password screen. |
| `lib/app/router.dart` | EDIT — add `/change-password` route + redirect rule. |

## Open items deferred to later iterations

- Permission enforcement off `roles.permissions` (currently informational).
- Email-based password reset (requires SMTP).
- Multi-role per user with primary-role designation.
- Letting non-SUPER_ADMIN users (e.g., HR_ADMIN) manage subsets of users.
- Audit log of role changes / password resets (today only `invited_by` + `invited_at` are tracked).
