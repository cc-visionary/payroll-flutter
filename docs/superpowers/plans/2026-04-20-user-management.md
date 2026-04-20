# User Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a SUPER_ADMIN add login users, assign one role per user, optionally link to an existing employee, and set/reset temp passwords from inside the Flutter app — with users forced to change the temp password on first login. No SMTP / email delivery.

**Architecture:** One Postgres migration extends the `app_role` enum, adds three columns to `users`, and recreates the `user_emails` view. One Edge Function `manage-user` (service-role) implements every privileged op behind an `action` discriminator. Flutter adds a Users tab in Settings (visible only to SUPER_ADMIN) plus a `/change-password` route that the GoRouter redirect forces on any user whose `must_change_password` flag is true.

**Tech Stack:** Flutter 3 + Riverpod 3 + GoRouter 17 + supabase_flutter 2.12 (client) · Supabase Postgres + Edge Functions on Deno (server) · supabase-js v2 (admin in edge functions).

**Spec:** `docs/superpowers/specs/2026-04-20-user-management-design.md`

---

## File Structure

| Path | Type | Responsibility |
|---|---|---|
| `supabase/migrations/20260420000002_user_management.sql` | NEW | Extend `app_role` enum, add `must_change_password / invited_by / invited_at` columns, recreate `user_emails` view, add column-level self-update RLS. (Slot bumped from 000001 to avoid collision with the pre-existing `20260420000001_thirteenth_month_accrual.sql`.) |
| `supabase/functions/manage-user/index.ts` | NEW | Single edge function. Action discriminator routes to `create / set_password / update_role / link_employee / deactivate / reactivate`. Validates caller is SUPER_ADMIN of caller's company. |
| `supabase/tests/manage_user_test.ts` | NEW | Pure-function tests for the validation/dispatch helpers extracted from the edge function (action enum parser + payload validators). |
| `lib/features/auth/profile_provider.dart` | EDIT | Extend `AppRole` enum; add `mustChangePassword`; switch profile read to `user_emails` view. |
| `lib/app/router.dart` | EDIT | Add `/change-password` route + redirect rule that forces it when `mustChangePassword` is true. |
| `lib/features/auth/change_password_screen.dart` | NEW | First-login screen — two password fields, calls `auth.updateUser` then clears the flag. No back button, sign-out escape hatch. |
| `lib/data/repositories/user_management_repository.dart` | NEW | Wraps the edge function calls + reads from `user_emails` + `user_roles` + `employees` for the Users tab. |
| `lib/data/models/managed_user.dart` | NEW | DTO for a row in the Users tab list (email, role, status, employee link, must_change_password, last_sign_in_at). |
| `lib/features/settings/users/users_settings_screen.dart` | NEW | Users list + Add / Set-password / Change-role / Link-employee / Deactivate dialogs. |
| `lib/features/settings/settings_screen.dart` | EDIT | Add `users` value to `_Tab` enum; mount the new screen; hide the tab unless `appRole == SUPER_ADMIN`. |

Each task below produces self-contained changes.

---

## Task 1: Database migration

**Files:**
- Create: `supabase/migrations/20260420000002_user_management.sql` (000001 is taken by the unrelated `thirteenth_month_accrual` migration).

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260420000001_user_management.sql`:

```sql
-- =============================================================================
-- User management: admin-set temp passwords + audit + extended app_role enum
-- =============================================================================

-- Extend app_role enum so the codes from the public.roles table can be stamped
-- as JWT app_metadata.app_role and survive the cast in auth_app_role().
-- Existing values (ADMIN, HR, MANAGER, EMPLOYEE) stay for back-compat with
-- already-issued JWTs and any legacy seed data.
alter type app_role add value if not exists 'PAYROLL_ADMIN';
alter type app_role add value if not exists 'HR_ADMIN';
alter type app_role add value if not exists 'FINANCE_MANAGER';

-- Track admin-set temp passwords. Cleared when the user changes password
-- via the /change-password screen on first login.
alter table users add column must_change_password boolean not null default false;

-- Audit who provisioned the user, for the Users settings list.
alter table users add column invited_by uuid references users(id);
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

grant select on user_emails to authenticated;

-- Allow a user to clear their own must_change_password flag — and ONLY that
-- column. Column-level grants restrict the surface; the policy pins the new
-- value to false and the row to the caller. Every other write path stays
-- admin-only via the manage-user edge function.
revoke update on users from authenticated;
grant update (must_change_password) on users to authenticated;

create policy users_self_clear_must_change on users
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid() and must_change_password = false);
```

- [ ] **Step 2: Apply the migration locally and confirm**

Run:
```bash
supabase db reset --local
```
Expected: migration applies without error. The `app_role` enum now contains the three new values; `users` has the three new columns; `user_emails` view exposes `must_change_password` and `app_role`.

- [ ] **Step 3: Smoke-check the view shape**

Run:
```bash
supabase db psql --local -c "select column_name, data_type from information_schema.columns where table_name = 'user_emails' order by ordinal_position;"
```
Expected output includes `id, company_id, status, must_change_password, invited_at, invited_by, email, last_sign_in_at, app_role`.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260420000001_user_management.sql
git commit -m "feat(db): user management — enum + audit cols + self-update RLS"
```

---

## Task 2: Edge function — scaffolding + validators (test-first)

**Files:**
- Create: `supabase/functions/manage-user/index.ts`
- Create: `supabase/tests/manage_user_test.ts`

This task lays in the helpers and pure-function validators that make the action handlers small. Subsequent tasks add one action each.

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/manage_user_test.ts`:

```typescript
import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { parseAction, validatePayload } from '../functions/manage-user/index.ts';

Deno.test('parseAction recognises every supported action', () => {
  assertEquals(parseAction('create'), 'create');
  assertEquals(parseAction('set_password'), 'set_password');
  assertEquals(parseAction('update_role'), 'update_role');
  assertEquals(parseAction('link_employee'), 'link_employee');
  assertEquals(parseAction('deactivate'), 'deactivate');
  assertEquals(parseAction('reactivate'), 'reactivate');
});

Deno.test('parseAction returns null for unknown', () => {
  assertEquals(parseAction('delete'), null);
  assertEquals(parseAction(''), null);
  assertEquals(parseAction(undefined), null);
});

Deno.test('validatePayload create requires email/password/role_code', () => {
  const ok = validatePayload('create', {
    email: 'a@b.com',
    password: 'longenough',
    role_code: 'PAYROLL_ADMIN',
  });
  assertEquals(ok.ok, true);

  const noEmail = validatePayload('create', {
    password: 'longenough',
    role_code: 'PAYROLL_ADMIN',
  });
  assertEquals(noEmail.ok, false);

  const shortPw = validatePayload('create', {
    email: 'a@b.com',
    password: 'short',
    role_code: 'PAYROLL_ADMIN',
  });
  assertEquals(shortPw.ok, false);
  assertEquals(shortPw.code, 'WEAK_PASSWORD');
});

Deno.test('validatePayload set_password requires user_id + password ≥ 8', () => {
  assertEquals(validatePayload('set_password', { user_id: 'u', password: 'longenough' }).ok, true);
  assertEquals(validatePayload('set_password', { user_id: 'u', password: '1234567' }).code, 'WEAK_PASSWORD');
  assertEquals(validatePayload('set_password', { password: 'longenough' }).ok, false);
});

Deno.test('validatePayload link_employee accepts null employee_id (unlink)', () => {
  assertEquals(validatePayload('link_employee', { user_id: 'u', employee_id: null }).ok, true);
  assertEquals(validatePayload('link_employee', { user_id: 'u', employee_id: 'e' }).ok, true);
  assertEquals(validatePayload('link_employee', { employee_id: 'e' }).ok, false);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
deno test --allow-env --allow-net supabase/tests/manage_user_test.ts
```
Expected: FAIL — `parseAction` and `validatePayload` not defined yet (module not found).

- [ ] **Step 3: Implement the scaffolding**

Create `supabase/functions/manage-user/index.ts`:

```typescript
// Edge Function: manage-user
//
// All admin user-management operations behind one action discriminator.
// Caller JWT must have app_metadata.app_role = 'SUPER_ADMIN'. Every target
// (user_id, employee_id) is verified to belong to the caller's company.
//
// Actions:
//   create            { email, password, role_code, employee_id? }
//   set_password      { user_id, password }
//   update_role       { user_id, role_code }
//   link_employee     { user_id, employee_id|null }
//   deactivate        { user_id }
//   reactivate        { user_id }
//
// Response: { ok: true, ... } | { ok: false, error, code? }
//
// Error codes:
//   DUPLICATE_EMAIL · WEAK_PASSWORD · INVALID_ROLE · EMPLOYEE_TAKEN ·
//   EMPLOYEE_WRONG_COMPANY · LAST_SUPER_ADMIN · NOT_AUTHORIZED ·
//   USER_NOT_IN_COMPANY · BAD_REQUEST · INTERNAL

import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

export type Action =
  | 'create'
  | 'set_password'
  | 'update_role'
  | 'link_employee'
  | 'deactivate'
  | 'reactivate';

const ACTIONS: readonly Action[] = [
  'create',
  'set_password',
  'update_role',
  'link_employee',
  'deactivate',
  'reactivate',
];

export function parseAction(value: unknown): Action | null {
  if (typeof value !== 'string') return null;
  return (ACTIONS as readonly string[]).includes(value) ? (value as Action) : null;
}

export type ValidationResult =
  | { ok: true }
  | { ok: false; error: string; code: string };

const MIN_PASSWORD = 8;

export function validatePayload(
  action: Action,
  body: Record<string, unknown>,
): ValidationResult {
  function need(field: string): ValidationResult | null {
    const v = body[field];
    if (typeof v !== 'string' || v.length === 0) {
      return { ok: false, error: `${field} required`, code: 'BAD_REQUEST' };
    }
    return null;
  }

  function password(): ValidationResult | null {
    const v = body['password'];
    if (typeof v !== 'string' || v.length === 0) {
      return { ok: false, error: 'password required', code: 'BAD_REQUEST' };
    }
    if (v.length < MIN_PASSWORD) {
      return {
        ok: false,
        error: `Password must be at least ${MIN_PASSWORD} characters`,
        code: 'WEAK_PASSWORD',
      };
    }
    return null;
  }

  switch (action) {
    case 'create': {
      const e = need('email'); if (e) return e;
      const p = password(); if (p) return p;
      const r = need('role_code'); if (r) return r;
      return { ok: true };
    }
    case 'set_password': {
      const u = need('user_id'); if (u) return u;
      const p = password(); if (p) return p;
      return { ok: true };
    }
    case 'update_role': {
      const u = need('user_id'); if (u) return u;
      const r = need('role_code'); if (r) return r;
      return { ok: true };
    }
    case 'link_employee': {
      const u = need('user_id'); if (u) return u;
      // employee_id may be string or explicit null (unlink). Reject undefined.
      if (!('employee_id' in body)) {
        return { ok: false, error: 'employee_id required (string or null)', code: 'BAD_REQUEST' };
      }
      const v = body['employee_id'];
      if (v !== null && typeof v !== 'string') {
        return { ok: false, error: 'employee_id must be string or null', code: 'BAD_REQUEST' };
      }
      return { ok: true };
    }
    case 'deactivate':
    case 'reactivate': {
      const u = need('user_id'); if (u) return u;
      return { ok: true };
    }
  }
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...corsHeaders },
  });
}

// ---------------------------------------------------------------------------
// HTTP entry point — dispatches to action handlers added in later tasks.
// ---------------------------------------------------------------------------

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ ok: false, error: 'POST required', code: 'BAD_REQUEST' }, 405);

  const url = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !serviceKey) return json({ ok: false, error: 'Server not configured', code: 'INTERNAL' }, 500);

  const authHeader = req.headers.get('Authorization');
  if (!authHeader?.startsWith('Bearer ')) {
    return json({ ok: false, error: 'Missing Authorization', code: 'NOT_AUTHORIZED' }, 401);
  }
  const callerJwt = authHeader.substring('Bearer '.length);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, error: 'Invalid JSON', code: 'BAD_REQUEST' }, 400);
  }

  const action = parseAction(body['action']);
  if (!action) return json({ ok: false, error: 'Unknown action', code: 'BAD_REQUEST' }, 400);

  const v = validatePayload(action, body);
  if (!v.ok) return json(v, 400);

  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Validate caller — must be SUPER_ADMIN with a company_id claim.
  const { data: callerData, error: callerErr } = await admin.auth.getUser(callerJwt);
  if (callerErr || !callerData?.user) {
    return json({ ok: false, error: 'Invalid token', code: 'NOT_AUTHORIZED' }, 401);
  }
  const callerRole = (callerData.user.app_metadata?.app_role as string | undefined) ?? '';
  const callerCompany = (callerData.user.app_metadata?.company_id as string | undefined) ?? '';
  if (callerRole !== 'SUPER_ADMIN' || !callerCompany) {
    return json({ ok: false, error: 'Forbidden', code: 'NOT_AUTHORIZED' }, 403);
  }

  const ctx: HandlerContext = {
    admin,
    callerId: callerData.user.id,
    callerCompanyId: callerCompany,
  };

  // Dispatcher — handler implementations added in Tasks 3–8.
  switch (action) {
    case 'create':         return await handleCreate(ctx, body);
    case 'set_password':   return await handleSetPassword(ctx, body);
    case 'update_role':    return await handleUpdateRole(ctx, body);
    case 'link_employee':  return await handleLinkEmployee(ctx, body);
    case 'deactivate':     return await handleDeactivate(ctx, body);
    case 'reactivate':     return await handleReactivate(ctx, body);
  }
});

// ---------------------------------------------------------------------------
// Handler context + stubs (real implementations added in Tasks 3–8).
// ---------------------------------------------------------------------------

interface HandlerContext {
  admin: SupabaseClient;
  callerId: string;
  callerCompanyId: string;
}

async function handleCreate(_c: HandlerContext, _b: Record<string, unknown>): Promise<Response> {
  return json({ ok: false, error: 'create not implemented', code: 'INTERNAL' }, 501);
}
async function handleSetPassword(_c: HandlerContext, _b: Record<string, unknown>): Promise<Response> {
  return json({ ok: false, error: 'set_password not implemented', code: 'INTERNAL' }, 501);
}
async function handleUpdateRole(_c: HandlerContext, _b: Record<string, unknown>): Promise<Response> {
  return json({ ok: false, error: 'update_role not implemented', code: 'INTERNAL' }, 501);
}
async function handleLinkEmployee(_c: HandlerContext, _b: Record<string, unknown>): Promise<Response> {
  return json({ ok: false, error: 'link_employee not implemented', code: 'INTERNAL' }, 501);
}
async function handleDeactivate(_c: HandlerContext, _b: Record<string, unknown>): Promise<Response> {
  return json({ ok: false, error: 'deactivate not implemented', code: 'INTERNAL' }, 501);
}
async function handleReactivate(_c: HandlerContext, _b: Record<string, unknown>): Promise<Response> {
  return json({ ok: false, error: 'reactivate not implemented', code: 'INTERNAL' }, 501);
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
deno test --allow-env --allow-net supabase/tests/manage_user_test.ts
```
Expected: 5 passed, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/manage-user/index.ts supabase/tests/manage_user_test.ts
git commit -m "feat(edge): manage-user scaffolding + validation tests"
```

---

## Task 3: `create` action

**Files:**
- Modify: `supabase/functions/manage-user/index.ts` (replace `handleCreate` stub)

- [ ] **Step 1: Replace the `handleCreate` stub**

Find:
```typescript
async function handleCreate(_c: HandlerContext, _b: Record<string, unknown>): Promise<Response> {
  return json({ ok: false, error: 'create not implemented', code: 'INTERNAL' }, 501);
}
```

Replace with:

```typescript
async function handleCreate(ctx: HandlerContext, body: Record<string, unknown>): Promise<Response> {
  const email = (body.email as string).trim().toLowerCase();
  const password = body.password as string;
  const roleCode = (body.role_code as string).trim().toUpperCase();
  const employeeId = (body.employee_id as string | undefined) ?? null;

  // role_code must exist
  const { data: role, error: roleErr } = await ctx.admin
    .from('roles')
    .select('id, code')
    .eq('code', roleCode)
    .maybeSingle();
  if (roleErr) return json({ ok: false, error: roleErr.message, code: 'INTERNAL' }, 500);
  if (!role)  return json({ ok: false, error: `Unknown role code: ${roleCode}`, code: 'INVALID_ROLE' }, 400);

  // employee_id (optional): must be in caller's company AND unlinked
  if (employeeId) {
    const empCheck = await assertEmployeeAvailable(ctx, employeeId, null);
    if (empCheck) return empCheck;
  }

  // Create the auth user (email_confirm so they can sign in immediately, no email sent).
  const { data: created, error: createErr } = await ctx.admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    app_metadata: {
      app_role: roleCode,
      company_id: ctx.callerCompanyId,
    },
  });
  if (createErr || !created?.user) {
    const msg = createErr?.message ?? 'createUser failed';
    const code = /already.*registered|exists/i.test(msg) ? 'DUPLICATE_EMAIL' : 'INTERNAL';
    return json({ ok: false, error: msg, code }, 400);
  }
  const newUserId = created.user.id;

  // Insert public.users row.
  const { error: userErr } = await ctx.admin.from('users').insert({
    id: newUserId,
    company_id: ctx.callerCompanyId,
    status: 'ACTIVE',
    must_change_password: true,
    invited_by: ctx.callerId,
    invited_at: new Date().toISOString(),
  });
  if (userErr) {
    // Roll back the auth user so the operation is atomic from the caller's POV.
    await ctx.admin.auth.admin.deleteUser(newUserId);
    return json({ ok: false, error: userErr.message, code: 'INTERNAL' }, 500);
  }

  // Insert user_roles row.
  const { error: roleAssignErr } = await ctx.admin
    .from('user_roles')
    .insert({ user_id: newUserId, role_id: role.id });
  if (roleAssignErr) {
    // Best-effort cleanup; the auth user + users row remain reachable but a
    // retry with the same email will hit DUPLICATE_EMAIL — surface the error.
    return json({ ok: false, error: roleAssignErr.message, code: 'INTERNAL' }, 500);
  }

  // Optional employee link.
  if (employeeId) {
    const { error: linkErr } = await ctx.admin
      .from('employees')
      .update({ user_id: newUserId })
      .eq('id', employeeId)
      .eq('company_id', ctx.callerCompanyId);
    if (linkErr) {
      return json({ ok: false, error: linkErr.message, code: 'INTERNAL' }, 500);
    }
  }

  return json({ ok: true, user_id: newUserId });
}

// ---------------------------------------------------------------------------
// Shared helpers used by multiple handlers.
// ---------------------------------------------------------------------------

async function assertEmployeeAvailable(
  ctx: HandlerContext,
  employeeId: string,
  expectCurrentUserId: string | null,
): Promise<Response | null> {
  const { data: emp, error } = await ctx.admin
    .from('employees')
    .select('id, company_id, user_id')
    .eq('id', employeeId)
    .maybeSingle();
  if (error) return json({ ok: false, error: error.message, code: 'INTERNAL' }, 500);
  if (!emp) return json({ ok: false, error: 'Employee not found', code: 'EMPLOYEE_WRONG_COMPANY' }, 400);
  if (emp.company_id !== ctx.callerCompanyId) {
    return json({ ok: false, error: 'Employee not in your company', code: 'EMPLOYEE_WRONG_COMPANY' }, 400);
  }
  if (emp.user_id && emp.user_id !== expectCurrentUserId) {
    return json({ ok: false, error: 'Employee already linked to another user', code: 'EMPLOYEE_TAKEN' }, 400);
  }
  return null;
}

async function assertUserInCompany(
  ctx: HandlerContext,
  userId: string,
): Promise<Response | null> {
  const { data: row, error } = await ctx.admin
    .from('users')
    .select('id, company_id')
    .eq('id', userId)
    .maybeSingle();
  if (error) return json({ ok: false, error: error.message, code: 'INTERNAL' }, 500);
  if (!row || row.company_id !== ctx.callerCompanyId) {
    return json({ ok: false, error: 'User not in your company', code: 'USER_NOT_IN_COMPANY' }, 400);
  }
  return null;
}

async function countSuperAdmins(ctx: HandlerContext): Promise<number> {
  // Walk the public.users in this company and ask auth.admin for each one's
  // app_metadata. Cheap because a company has at most a handful of admins.
  const { data: rows, error } = await ctx.admin
    .from('users')
    .select('id, status')
    .eq('company_id', ctx.callerCompanyId)
    .eq('status', 'ACTIVE');
  if (error || !rows) return 0;
  let count = 0;
  for (const r of rows) {
    const { data } = await ctx.admin.auth.admin.getUserById(r.id as string);
    if ((data?.user?.app_metadata?.app_role as string | undefined) === 'SUPER_ADMIN') count++;
  }
  return count;
}
```

- [ ] **Step 2: Deploy and smoke-test against local Supabase**

Run:
```bash
supabase functions serve manage-user --env-file supabase/.env.local --no-verify-jwt &
sleep 2
# Sign in as the bootstrapped super admin and capture the access token.
TOKEN="<paste a SUPER_ADMIN access token>"
curl -s -X POST http://127.0.0.1:54321/functions/v1/manage-user \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"action":"create","email":"plan-test@example.com","password":"temppass99","role_code":"PAYROLL_ADMIN"}'
```
Expected: `{"ok":true,"user_id":"<uuid>"}`. Re-run with the same email → `{"ok":false,"error":"...","code":"DUPLICATE_EMAIL"}`. Stop the local function with `kill %1`.

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/manage-user/index.ts
git commit -m "feat(edge): manage-user create action + cross-company guards"
```

---

## Task 4: `set_password` action

**Files:**
- Modify: `supabase/functions/manage-user/index.ts` (replace `handleSetPassword` stub)

- [ ] **Step 1: Replace the `handleSetPassword` stub**

Find:
```typescript
async function handleSetPassword(_c: HandlerContext, _b: Record<string, unknown>): Promise<Response> {
  return json({ ok: false, error: 'set_password not implemented', code: 'INTERNAL' }, 501);
}
```

Replace with:

```typescript
async function handleSetPassword(ctx: HandlerContext, body: Record<string, unknown>): Promise<Response> {
  const userId = body.user_id as string;
  const password = body.password as string;

  const guard = await assertUserInCompany(ctx, userId);
  if (guard) return guard;

  const { error: pwErr } = await ctx.admin.auth.admin.updateUserById(userId, { password });
  if (pwErr) return json({ ok: false, error: pwErr.message, code: 'INTERNAL' }, 500);

  const { error: flagErr } = await ctx.admin
    .from('users')
    .update({ must_change_password: true })
    .eq('id', userId);
  if (flagErr) return json({ ok: false, error: flagErr.message, code: 'INTERNAL' }, 500);

  return json({ ok: true, user_id: userId });
}
```

- [ ] **Step 2: Smoke-test against local Supabase**

Run (with the function still served from Task 3 or a fresh `supabase functions serve manage-user`):
```bash
TARGET="<user_id created in Task 3>"
TOKEN="<SUPER_ADMIN access token>"
curl -s -X POST http://127.0.0.1:54321/functions/v1/manage-user \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"action\":\"set_password\",\"user_id\":\"$TARGET\",\"password\":\"newtemp123\"}"
```
Expected: `{"ok":true,"user_id":"<uuid>"}`. Verify the flag in psql:
```bash
supabase db psql --local -c "select must_change_password from users where id = '$TARGET';"
```
Expected: `t`.

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/manage-user/index.ts
git commit -m "feat(edge): manage-user set_password action"
```

---

## Task 5: `update_role` action

**Files:**
- Modify: `supabase/functions/manage-user/index.ts` (replace `handleUpdateRole` stub)

- [ ] **Step 1: Replace the `handleUpdateRole` stub**

Find:
```typescript
async function handleUpdateRole(_c: HandlerContext, _b: Record<string, unknown>): Promise<Response> {
  return json({ ok: false, error: 'update_role not implemented', code: 'INTERNAL' }, 501);
}
```

Replace with:

```typescript
async function handleUpdateRole(ctx: HandlerContext, body: Record<string, unknown>): Promise<Response> {
  const userId = body.user_id as string;
  const roleCode = (body.role_code as string).trim().toUpperCase();

  const guard = await assertUserInCompany(ctx, userId);
  if (guard) return guard;

  const { data: role, error: roleErr } = await ctx.admin
    .from('roles')
    .select('id, code')
    .eq('code', roleCode)
    .maybeSingle();
  if (roleErr) return json({ ok: false, error: roleErr.message, code: 'INTERNAL' }, 500);
  if (!role)  return json({ ok: false, error: `Unknown role code: ${roleCode}`, code: 'INVALID_ROLE' }, 400);

  // Last-super-admin guard: if the caller is downgrading themselves and they
  // are the only SUPER_ADMIN left, block.
  if (userId === ctx.callerId && roleCode !== 'SUPER_ADMIN') {
    const supers = await countSuperAdmins(ctx);
    if (supers <= 1) {
      return json({
        ok: false,
        error: 'Cannot demote the last SUPER_ADMIN in this company',
        code: 'LAST_SUPER_ADMIN',
      }, 400);
    }
  }

  // Replace user_roles row.
  await ctx.admin.from('user_roles').delete().eq('user_id', userId);
  const { error: insertErr } = await ctx.admin
    .from('user_roles')
    .insert({ user_id: userId, role_id: role.id });
  if (insertErr) return json({ ok: false, error: insertErr.message, code: 'INTERNAL' }, 500);

  // Rewrite the JWT app_role claim.
  const { data: existing } = await ctx.admin.auth.admin.getUserById(userId);
  const merged = {
    ...(existing?.user?.app_metadata ?? {}),
    app_role: roleCode,
    company_id: ctx.callerCompanyId,
  };
  const { error: metaErr } = await ctx.admin.auth.admin.updateUserById(userId, {
    app_metadata: merged,
  });
  if (metaErr) return json({ ok: false, error: metaErr.message, code: 'INTERNAL' }, 500);

  return json({ ok: true, user_id: userId, role_code: roleCode });
}
```

- [ ] **Step 2: Smoke-test against local Supabase**

Run:
```bash
TARGET="<user_id from Task 3>"
TOKEN="<SUPER_ADMIN access token>"
curl -s -X POST http://127.0.0.1:54321/functions/v1/manage-user \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"action\":\"update_role\",\"user_id\":\"$TARGET\",\"role_code\":\"FINANCE_MANAGER\"}"
```
Expected: `{"ok":true,"user_id":"<uuid>","role_code":"FINANCE_MANAGER"}`.

Try demoting yourself when alone:
```bash
SELF="<your own user_id>"
curl -s -X POST http://127.0.0.1:54321/functions/v1/manage-user \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"action\":\"update_role\",\"user_id\":\"$SELF\",\"role_code\":\"PAYROLL_ADMIN\"}"
```
Expected: `{"ok":false,"error":"Cannot demote ...","code":"LAST_SUPER_ADMIN"}`.

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/manage-user/index.ts
git commit -m "feat(edge): manage-user update_role + last-super-admin guard"
```

---

## Task 6: `link_employee` action

**Files:**
- Modify: `supabase/functions/manage-user/index.ts` (replace `handleLinkEmployee` stub)

- [ ] **Step 1: Replace the `handleLinkEmployee` stub**

Find:
```typescript
async function handleLinkEmployee(_c: HandlerContext, _b: Record<string, unknown>): Promise<Response> {
  return json({ ok: false, error: 'link_employee not implemented', code: 'INTERNAL' }, 501);
}
```

Replace with:

```typescript
async function handleLinkEmployee(ctx: HandlerContext, body: Record<string, unknown>): Promise<Response> {
  const userId = body.user_id as string;
  const employeeId = body.employee_id as string | null;

  const guard = await assertUserInCompany(ctx, userId);
  if (guard) return guard;

  // Clear any existing link from THIS user — only one employee per user.
  const { error: clearErr } = await ctx.admin
    .from('employees')
    .update({ user_id: null })
    .eq('user_id', userId)
    .eq('company_id', ctx.callerCompanyId);
  if (clearErr) return json({ ok: false, error: clearErr.message, code: 'INTERNAL' }, 500);

  if (employeeId === null) {
    return json({ ok: true, user_id: userId, employee_id: null });
  }

  const empGuard = await assertEmployeeAvailable(ctx, employeeId, userId);
  if (empGuard) return empGuard;

  const { error: linkErr } = await ctx.admin
    .from('employees')
    .update({ user_id: userId })
    .eq('id', employeeId)
    .eq('company_id', ctx.callerCompanyId);
  if (linkErr) return json({ ok: false, error: linkErr.message, code: 'INTERNAL' }, 500);

  return json({ ok: true, user_id: userId, employee_id: employeeId });
}
```

- [ ] **Step 2: Smoke-test against local Supabase**

Run:
```bash
TARGET="<user_id from Task 3>"
EMP="<an unlinked employee_id in your company>"
TOKEN="<SUPER_ADMIN access token>"
curl -s -X POST http://127.0.0.1:54321/functions/v1/manage-user \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"action\":\"link_employee\",\"user_id\":\"$TARGET\",\"employee_id\":\"$EMP\"}"
```
Expected: `{"ok":true,"user_id":"<uuid>","employee_id":"<uuid>"}`. Re-run with `"employee_id":null` → `{"ok":true,"user_id":"<uuid>","employee_id":null}`.

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/manage-user/index.ts
git commit -m "feat(edge): manage-user link_employee action"
```

---

## Task 7: `deactivate` and `reactivate` actions

**Files:**
- Modify: `supabase/functions/manage-user/index.ts` (replace both stubs)

- [ ] **Step 1: Replace both stubs**

Find:
```typescript
async function handleDeactivate(_c: HandlerContext, _b: Record<string, unknown>): Promise<Response> {
  return json({ ok: false, error: 'deactivate not implemented', code: 'INTERNAL' }, 501);
}
async function handleReactivate(_c: HandlerContext, _b: Record<string, unknown>): Promise<Response> {
  return json({ ok: false, error: 'reactivate not implemented', code: 'INTERNAL' }, 501);
}
```

Replace with:

```typescript
async function handleDeactivate(ctx: HandlerContext, body: Record<string, unknown>): Promise<Response> {
  const userId = body.user_id as string;

  const guard = await assertUserInCompany(ctx, userId);
  if (guard) return guard;

  if (userId === ctx.callerId) {
    return json({ ok: false, error: 'Cannot deactivate yourself', code: 'LAST_SUPER_ADMIN' }, 400);
  }

  // If the target is a SUPER_ADMIN and the only one left, refuse.
  const { data: target } = await ctx.admin.auth.admin.getUserById(userId);
  const targetRole = target?.user?.app_metadata?.app_role as string | undefined;
  if (targetRole === 'SUPER_ADMIN') {
    const supers = await countSuperAdmins(ctx);
    if (supers <= 1) {
      return json({
        ok: false,
        error: 'Cannot deactivate the last SUPER_ADMIN',
        code: 'LAST_SUPER_ADMIN',
      }, 400);
    }
  }

  const { error: statusErr } = await ctx.admin
    .from('users')
    .update({ status: 'INACTIVE' })
    .eq('id', userId);
  if (statusErr) return json({ ok: false, error: statusErr.message, code: 'INTERNAL' }, 500);

  // Effectively a permanent ban (~100 years). Reactivate clears it.
  // GoTrue's admin updateUserById accepts ban_duration as a duration string.
  const { error: banErr } = await ctx.admin.auth.admin.updateUserById(userId, {
    ban_duration: '876000h',
  });
  if (banErr) return json({ ok: false, error: banErr.message, code: 'INTERNAL' }, 500);

  return json({ ok: true, user_id: userId });
}

async function handleReactivate(ctx: HandlerContext, body: Record<string, unknown>): Promise<Response> {
  const userId = body.user_id as string;

  const guard = await assertUserInCompany(ctx, userId);
  if (guard) return guard;

  const { error: statusErr } = await ctx.admin
    .from('users')
    .update({ status: 'ACTIVE' })
    .eq('id', userId);
  if (statusErr) return json({ ok: false, error: statusErr.message, code: 'INTERNAL' }, 500);

  const { error: banErr } = await ctx.admin.auth.admin.updateUserById(userId, {
    ban_duration: 'none',
  });
  if (banErr) return json({ ok: false, error: banErr.message, code: 'INTERNAL' }, 500);

  return json({ ok: true, user_id: userId });
}
```

- [ ] **Step 2: Smoke-test**

Run:
```bash
TARGET="<user_id from Task 3>"
TOKEN="<SUPER_ADMIN access token>"
curl -s -X POST http://127.0.0.1:54321/functions/v1/manage-user \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"action\":\"deactivate\",\"user_id\":\"$TARGET\"}"
```
Expected: `{"ok":true,"user_id":"<uuid>"}`. Verify in psql:
```bash
supabase db psql --local -c "select status from users where id = '$TARGET';"
```
Expected: `INACTIVE`. Re-run with `reactivate` and verify `ACTIVE`.

- [ ] **Step 3: Deploy the function**

Run:
```bash
supabase functions deploy manage-user
```
Expected: `Deployed Function manage-user on project ...`.

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/manage-user/index.ts
git commit -m "feat(edge): manage-user deactivate/reactivate + ban handling"
```

---

## Task 8: Profile provider — extend AppRole + read mustChangePassword

**Files:**
- Modify: `lib/features/auth/profile_provider.dart`

- [ ] **Step 1: Replace `lib/features/auth/profile_provider.dart`**

Replace the file with:

```dart
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'session_provider.dart';

enum AppRole {
  SUPER_ADMIN,
  ADMIN,
  PAYROLL_ADMIN,
  HR,
  HR_ADMIN,
  MANAGER,
  FINANCE_MANAGER,
  EMPLOYEE,
}

AppRole _parseRole(String? s) {
  switch (s) {
    case 'SUPER_ADMIN':
      return AppRole.SUPER_ADMIN;
    case 'ADMIN':
      return AppRole.ADMIN;
    case 'PAYROLL_ADMIN':
      return AppRole.PAYROLL_ADMIN;
    case 'HR':
      return AppRole.HR;
    case 'HR_ADMIN':
      return AppRole.HR_ADMIN;
    case 'MANAGER':
      return AppRole.MANAGER;
    case 'FINANCE_MANAGER':
      return AppRole.FINANCE_MANAGER;
    default:
      return AppRole.EMPLOYEE;
  }
}

class UserProfile {
  final String userId;
  final String email;
  final String companyId;
  final String? employeeId;
  final AppRole appRole;
  final bool mustChangePassword;

  const UserProfile({
    required this.userId,
    required this.email,
    required this.companyId,
    required this.employeeId,
    required this.appRole,
    required this.mustChangePassword,
  });

  bool get isAdmin =>
      appRole == AppRole.SUPER_ADMIN ||
      appRole == AppRole.ADMIN ||
      appRole == AppRole.PAYROLL_ADMIN ||
      appRole == AppRole.HR_ADMIN;

  bool get isHrOrAdmin =>
      isAdmin || appRole == AppRole.HR;

  bool get canManageEmployees => isHrOrAdmin;
  bool get canRunPayroll =>
      isHrOrAdmin || appRole == AppRole.PAYROLL_ADMIN;
  bool get canEditTaxTables => appRole == AppRole.SUPER_ADMIN;
}

/// Loads the authenticated user's app-level profile (users row + employee_id +
/// app_role claim from JWT + must_change_password flag). Null while logged out.
final userProfileProvider = FutureProvider<UserProfile?>((ref) async {
  final session = ref.watch(authStateProvider).value;
  if (session == null) return null;

  final client = Supabase.instance.client;
  final userId = session.user.id;
  final email = session.user.email ?? '';

  final claims = session.accessToken.isEmpty
      ? <String, dynamic>{}
      : _decodeJwtPayload(session.accessToken);
  final appRole = _parseRole(
    (claims['app_role'] ?? claims['app_metadata']?['app_role']) as String?,
  );

  Map<String, dynamic>? userRow;
  try {
    userRow = await client
        .from('user_emails')
        .select('company_id, must_change_password')
        .eq('id', userId)
        .maybeSingle();
  } catch (_) {
    userRow = null;
  }

  String? employeeId;
  try {
    final emp = await client
        .from('employees')
        .select('id')
        .eq('user_id', userId)
        .maybeSingle();
    employeeId = emp?['id'] as String?;
  } catch (_) {
    employeeId = null;
  }

  return UserProfile(
    userId: userId,
    email: email,
    companyId: userRow?['company_id'] as String? ?? '',
    employeeId: employeeId,
    appRole: appRole,
    mustChangePassword: (userRow?['must_change_password'] as bool?) ?? false,
  );
});

Map<String, dynamic> _decodeJwtPayload(String jwt) {
  try {
    final parts = jwt.split('.');
    if (parts.length != 3) return {};
    final normalized = _b64NormalizePad(parts[1]);
    final decoded = String.fromCharCodes(_base64Decode(normalized));
    final obj = _parseJson(decoded);
    return obj is Map<String, dynamic> ? obj : {};
  } catch (_) {
    return {};
  }
}

String _b64NormalizePad(String s) {
  var out = s.replaceAll('-', '+').replaceAll('_', '/');
  while (out.length % 4 != 0) {
    out += '=';
  }
  return out;
}

List<int> _base64Decode(String s) => base64.decode(s);

dynamic _parseJson(String s) => jsonDecode(s);
```

- [ ] **Step 2: Verify the app still compiles**

Run:
```bash
flutter analyze lib/features/auth/profile_provider.dart
```
Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add lib/features/auth/profile_provider.dart
git commit -m "feat(auth): extend AppRole + surface mustChangePassword on UserProfile"
```

---

## Task 9: First-login change-password screen + router redirect

**Files:**
- Create: `lib/features/auth/change_password_screen.dart`
- Modify: `lib/app/router.dart`

- [ ] **Step 1: Create the change-password screen**

Create `lib/features/auth/change_password_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'profile_provider.dart';

/// Forced first-login screen. Shown when `users.must_change_password = true`.
/// The router redirect prevents navigation away until the flag is cleared.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});
  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pw = _password.text;
    if (pw.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    if (pw != _confirm.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      await client.auth.updateUser(UserAttributes(password: pw));
      final userId = client.auth.currentUser!.id;
      await client
          .from('users')
          .update({'must_change_password': false})
          .eq('id', userId);
      ref.invalidate(userProfileProvider);
      if (mounted) context.go('/dashboard');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set a new password'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: _saving ? null : _signOut,
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Your administrator set a temporary password for you. '
                  'Choose a new password to continue.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'New password (min 8 chars)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirm,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm password',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Set password'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Wire the route + redirect into `lib/app/router.dart`**

Add the import (insert with the other auth imports):
```dart
import '../features/auth/change_password_screen.dart';
```

Replace the existing `redirect:` block:
```dart
redirect: (context, state) {
  final loggedIn = auth.asData?.value != null;
  final loggingIn = state.matchedLocation == '/login';
  if (!loggedIn && !loggingIn) return '/login';
  if (loggedIn && loggingIn) return '/dashboard';

  // Role-based route gating
  final profile = ref.read(userProfileProvider).asData?.value;
  if (profile != null) {
    final loc = state.matchedLocation;
    if (loc.startsWith('/settings') && !profile.isAdmin) return '/dashboard';
    if (loc.startsWith('/responsibility-cards') && !profile.isHrOrAdmin) return '/dashboard';
  }
  return null;
},
```

With:
```dart
redirect: (context, state) {
  final loggedIn = auth.asData?.value != null;
  final loggingIn = state.matchedLocation == '/login';
  final changingPassword = state.matchedLocation == '/change-password';
  if (!loggedIn && !loggingIn) return '/login';
  if (loggedIn && loggingIn) return '/dashboard';

  final profile = ref.read(userProfileProvider).asData?.value;
  if (profile != null) {
    if (profile.mustChangePassword && !changingPassword) {
      return '/change-password';
    }
    if (!profile.mustChangePassword && changingPassword) {
      return '/dashboard';
    }
    final loc = state.matchedLocation;
    if (loc.startsWith('/settings') && !profile.isAdmin) return '/dashboard';
    if (loc.startsWith('/responsibility-cards') && !profile.isHrOrAdmin) return '/dashboard';
  }
  return null;
},
```

Add a top-level (non-shell) `GoRoute` for `/change-password` immediately after the `/login` route:
```dart
GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
GoRoute(path: '/change-password', builder: (c, s) => const ChangePasswordScreen()),
```

- [ ] **Step 3: Manual verification**

Run:
```bash
flutter run -d chrome
```
- Sign in as a user with `must_change_password = true` (use the user created in Task 3).
- Expected: app immediately routes to `/change-password`; navigating to `/dashboard` bounces back.
- Submit a new password ≥ 8 chars matching confirm; expected to land on `/dashboard`.
- Sign in again → no forced redirect.

- [ ] **Step 4: Commit**

```bash
git add lib/features/auth/change_password_screen.dart lib/app/router.dart
git commit -m "feat(auth): forced first-login change-password screen + router gate"
```

---

## Task 10: Managed-user model + repository

**Files:**
- Create: `lib/data/models/managed_user.dart`
- Create: `lib/data/repositories/user_management_repository.dart`

- [ ] **Step 1: Create the model**

Create `lib/data/models/managed_user.dart`:

```dart
class ManagedUser {
  final String userId;
  final String email;
  final String? roleCode;
  final String status;            // ACTIVE / INACTIVE
  final bool mustChangePassword;
  final DateTime? invitedAt;
  final String? invitedBy;
  final DateTime? lastSignInAt;
  final String? linkedEmployeeId;
  final String? linkedEmployeeName;

  const ManagedUser({
    required this.userId,
    required this.email,
    required this.roleCode,
    required this.status,
    required this.mustChangePassword,
    required this.invitedAt,
    required this.invitedBy,
    required this.lastSignInAt,
    required this.linkedEmployeeId,
    required this.linkedEmployeeName,
  });

  bool get isInactive => status == 'INACTIVE';

  String displayName() {
    if (linkedEmployeeName != null && linkedEmployeeName!.isNotEmpty) {
      return linkedEmployeeName!;
    }
    final at = email.indexOf('@');
    return at > 0 ? email.substring(0, at) : email;
  }
}

class UnlinkedEmployee {
  final String id;
  final String name;
  const UnlinkedEmployee({required this.id, required this.name});
}
```

- [ ] **Step 2: Create the repository**

Create `lib/data/repositories/user_management_repository.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/managed_user.dart';

class UserManagementRepository {
  final SupabaseClient _client;
  UserManagementRepository(this._client);

  /// Lists every user in the caller's company. RLS on `user_emails` already
  /// scopes to the caller's company_id.
  Future<List<ManagedUser>> list() async {
    final rows = await _client
        .from('user_emails')
        .select('id, email, status, must_change_password, invited_at, invited_by, last_sign_in_at, app_role')
        .order('email');

    final userIds = rows.map((r) => r['id'] as String).toList();
    if (userIds.isEmpty) return const [];

    // Fetch employee links + names in one round-trip.
    final emps = await _client
        .from('employees')
        .select('id, user_id, first_name, last_name')
        .inFilter('user_id', userIds);
    final empByUser = <String, Map<String, dynamic>>{
      for (final e in emps) (e['user_id'] as String): e,
    };

    return rows.map<ManagedUser>((r) {
      final id = r['id'] as String;
      final emp = empByUser[id];
      final name = emp == null
          ? null
          : '${emp['first_name'] ?? ''} ${emp['last_name'] ?? ''}'.trim();
      return ManagedUser(
        userId: id,
        email: (r['email'] as String?) ?? '',
        roleCode: r['app_role'] as String?,
        status: (r['status'] as String?) ?? 'ACTIVE',
        mustChangePassword: (r['must_change_password'] as bool?) ?? false,
        invitedAt: r['invited_at'] == null
            ? null
            : DateTime.parse(r['invited_at'] as String),
        invitedBy: r['invited_by'] as String?,
        lastSignInAt: r['last_sign_in_at'] == null
            ? null
            : DateTime.parse(r['last_sign_in_at'] as String),
        linkedEmployeeId: emp?['id'] as String?,
        linkedEmployeeName: (name == null || name.isEmpty) ? null : name,
      );
    }).toList();
  }

  /// Employees in the caller's company that aren't linked to any user yet.
  /// `includeUserId` keeps the currently-linked employee in the list when
  /// editing an existing user's link.
  Future<List<UnlinkedEmployee>> unlinkedEmployees({String? includeUserId}) async {
    final rows = await _client
        .from('employees')
        .select('id, first_name, last_name, user_id')
        .order('first_name');
    return rows
        .where((e) {
          final uid = e['user_id'] as String?;
          return uid == null || uid == includeUserId;
        })
        .map<UnlinkedEmployee>((e) => UnlinkedEmployee(
              id: e['id'] as String,
              name: '${e['first_name'] ?? ''} ${e['last_name'] ?? ''}'.trim(),
            ))
        .toList();
  }

  Future<void> _invoke(String action, Map<String, dynamic> payload) async {
    final res = await _client.functions.invoke('manage-user', body: {
      'action': action,
      ...payload,
    });
    final data = (res.data as Map?) ?? const {};
    if (data['ok'] != true) {
      throw UserManagementException(
        data['error']?.toString() ?? 'manage-user failed',
        code: data['code']?.toString(),
      );
    }
  }

  Future<void> create({
    required String email,
    required String password,
    required String roleCode,
    String? employeeId,
  }) =>
      _invoke('create', {
        'email': email,
        'password': password,
        'role_code': roleCode,
        if (employeeId != null) 'employee_id': employeeId,
      });

  Future<void> setPassword(String userId, String password) =>
      _invoke('set_password', {'user_id': userId, 'password': password});

  Future<void> updateRole(String userId, String roleCode) =>
      _invoke('update_role', {'user_id': userId, 'role_code': roleCode});

  Future<void> linkEmployee(String userId, String? employeeId) =>
      _invoke('link_employee', {'user_id': userId, 'employee_id': employeeId});

  Future<void> deactivate(String userId) =>
      _invoke('deactivate', {'user_id': userId});

  Future<void> reactivate(String userId) =>
      _invoke('reactivate', {'user_id': userId});
}

class UserManagementException implements Exception {
  final String message;
  final String? code;
  UserManagementException(this.message, {this.code});
  @override
  String toString() => code == null ? message : '$message ($code)';
}

final userManagementRepositoryProvider = Provider<UserManagementRepository>(
  (ref) => UserManagementRepository(Supabase.instance.client),
);

final managedUsersProvider = FutureProvider<List<ManagedUser>>((ref) async {
  return ref.watch(userManagementRepositoryProvider).list();
});

final unlinkedEmployeesProvider =
    FutureProvider.family<List<UnlinkedEmployee>, String?>(
  (ref, includeUserId) =>
      ref.watch(userManagementRepositoryProvider).unlinkedEmployees(includeUserId: includeUserId),
);
```

- [ ] **Step 3: Verify it compiles**

Run:
```bash
flutter analyze lib/data/models/managed_user.dart lib/data/repositories/user_management_repository.dart
```
Expected: No issues found.

- [ ] **Step 4: Commit**

```bash
git add lib/data/models/managed_user.dart lib/data/repositories/user_management_repository.dart
git commit -m "feat(data): managed user model + repository wrapping manage-user"
```

---

## Task 11: Users settings screen

**Files:**
- Create: `lib/features/settings/users/users_settings_screen.dart`

- [ ] **Step 1: Create the screen**

Create `lib/features/settings/users/users_settings_screen.dart`:

```dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/status_colors.dart';
import '../../../data/models/managed_user.dart';
import '../../../data/models/role.dart';
import '../../../data/repositories/role_repository.dart';
import '../../../data/repositories/user_management_repository.dart';
import '../../auth/profile_provider.dart';

class UsersSettingsScreen extends ConsumerWidget {
  const UsersSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(managedUsersProvider);
    final rolesAsync = ref.watch(roleListProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Users', style: Theme.of(context).textTheme.headlineSmall),
          const Spacer(),
          FilledButton.icon(
            onPressed: () => _openAddDialog(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('Add User'),
          ),
        ]),
        const SizedBox(height: 4),
        const Text(
          'Manage who can log in to the payroll app. Email is used as the login identifier — passwords are set here, not via email.',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: usersAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
                child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
            data: (users) {
              if (users.isEmpty) {
                return const Center(child: Text('No users yet.'));
              }
              final roles = rolesAsync.asData?.value ?? const <Role>[];
              return ListView.separated(
                itemCount: users.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _UserTile(
                  user: users[i],
                  roles: roles,
                  onChanged: () => ref.invalidate(managedUsersProvider),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }

  Future<void> _openAddDialog(BuildContext context, WidgetRef ref) async {
    await showDialog(
      context: context,
      builder: (_) => _AddUserDialog(
        onCreated: () => ref.invalidate(managedUsersProvider),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// User tile
// ---------------------------------------------------------------------------

class _UserTile extends ConsumerWidget {
  final ManagedUser user;
  final List<Role> roles;
  final VoidCallback onChanged;
  const _UserTile({required this.user, required this.roles, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = roles.firstWhere(
      (r) => r.code == user.roleCode,
      orElse: () => Role(id: '', code: user.roleCode ?? '—', name: user.roleCode ?? '—', permissions: const [], isSystem: false),
    );
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(user.displayName(), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Chip(
                label: Text(role.code, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: 4),
              if (user.isInactive)
                const StatusChip(label: 'Inactive', tone: StatusTone.danger),
            ]),
            const SizedBox(height: 2),
            Text(
              user.email + (user.linkedEmployeeName == null ? ' · no employee link' : ' · linked: ${user.linkedEmployeeName}'),
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 2),
            if (user.mustChangePassword)
              const Text(
                '⚠ Must change password on next login',
                style: TextStyle(color: Colors.orange, fontSize: 12),
              )
            else if (user.lastSignInAt != null)
              Text(
                'Last sign-in: ${_relative(user.lastSignInAt!)}',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              )
            else
              const Text('Never signed in', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ]),
        ),
        PopupMenuButton<_UserAction>(
          onSelected: (a) => _onAction(context, ref, a),
          itemBuilder: (_) => [
            const PopupMenuItem(value: _UserAction.changeRole, child: Text('Change role')),
            const PopupMenuItem(value: _UserAction.setPassword, child: Text('Set new password')),
            const PopupMenuItem(value: _UserAction.linkEmployee, child: Text('Link / unlink employee')),
            if (user.isInactive)
              const PopupMenuItem(value: _UserAction.reactivate, child: Text('Reactivate'))
            else
              const PopupMenuItem(value: _UserAction.deactivate, child: Text('Deactivate', style: TextStyle(color: Colors.red))),
          ],
        ),
      ]),
    );
  }

  Future<void> _onAction(BuildContext context, WidgetRef ref, _UserAction action) async {
    final repo = ref.read(userManagementRepositoryProvider);
    try {
      switch (action) {
        case _UserAction.changeRole:
          await showDialog(
            context: context,
            builder: (_) => _ChangeRoleDialog(user: user, roles: roles),
          );
          break;
        case _UserAction.setPassword:
          await showDialog(
            context: context,
            builder: (_) => _SetPasswordDialog(user: user),
          );
          break;
        case _UserAction.linkEmployee:
          await showDialog(
            context: context,
            builder: (_) => _LinkEmployeeDialog(user: user),
          );
          break;
        case _UserAction.deactivate:
          final ok = await _confirm(context, 'Deactivate ${user.displayName()}?', 'They will be unable to sign in until reactivated.');
          if (ok) await repo.deactivate(user.userId);
          break;
        case _UserAction.reactivate:
          await repo.reactivate(user.userId);
          break;
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
    onChanged();
  }
}

enum _UserAction { changeRole, setPassword, linkEmployee, deactivate, reactivate }

Future<bool> _confirm(BuildContext context, String title, String body) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
  return ok == true;
}

String _relative(DateTime dt) {
  final d = DateTime.now().difference(dt);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes}m ago';
  if (d.inDays < 1) return '${d.inHours}h ago';
  if (d.inDays < 30) return '${d.inDays}d ago';
  return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// Add user dialog
// ---------------------------------------------------------------------------

String _generateTempPassword() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
  final r = Random.secure();
  return List.generate(14, (_) => chars[r.nextInt(chars.length)]).join();
}

class _AddUserDialog extends ConsumerStatefulWidget {
  final VoidCallback onCreated;
  const _AddUserDialog({required this.onCreated});
  @override
  ConsumerState<_AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends ConsumerState<_AddUserDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String _roleCode = 'PAYROLL_ADMIN';
  String? _employeeId;
  bool _saving = false;
  String? _error;
  String? _createdPassword;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim().toLowerCase();
    final pw = _password.text;
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Valid email is required.');
      return;
    }
    if (pw.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    if (pw != _confirm.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(userManagementRepositoryProvider).create(
            email: email,
            password: pw,
            roleCode: _roleCode,
            employeeId: _employeeId,
          );
      widget.onCreated();
      setState(() => _createdPassword = pw);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_createdPassword != null) {
      return AlertDialog(
        title: const Text('User created'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_email.text} can now sign in. The temporary password is shown below — copy it now, it will not be shown again.'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(children: [
              Expanded(child: SelectableText(_createdPassword!, style: const TextStyle(fontFamily: 'monospace', fontSize: 14))),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: 'Copy',
                onPressed: () => Clipboard.setData(ClipboardData(text: _createdPassword!)),
              ),
            ]),
          ),
        ]),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
        ],
      );
    }
    final unlinkedAsync = ref.watch(unlinkedEmployeesProvider(null));
    final rolesAsync = ref.watch(roleListProvider);
    return AlertDialog(
      title: const Text('Add User'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder(), isDense: true),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              decoration: InputDecoration(
                labelText: 'Temporary password (min 8)',
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: 'Generate',
                  onPressed: () {
                    final pw = _generateTempPassword();
                    _password.text = pw;
                    _confirm.text = pw;
                  },
                ),
              ),
              obscureText: false,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirm,
              decoration: const InputDecoration(labelText: 'Confirm password', border: OutlineInputBorder(), isDense: true),
              obscureText: false,
            ),
            const SizedBox(height: 12),
            rolesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Roles: $e'),
              data: (roles) => DropdownButtonFormField<String>(
                value: roles.any((r) => r.code == _roleCode) ? _roleCode : roles.first.code,
                decoration: const InputDecoration(labelText: 'Role', border: OutlineInputBorder(), isDense: true),
                items: [for (final r in roles) DropdownMenuItem(value: r.code, child: Text('${r.name}  (${r.code})'))],
                onChanged: (v) => setState(() => _roleCode = v!),
              ),
            ),
            const SizedBox(height: 12),
            unlinkedAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Employees: $e'),
              data: (emps) => DropdownButtonFormField<String?>(
                value: _employeeId,
                decoration: const InputDecoration(labelText: 'Link to employee (optional)', border: OutlineInputBorder(), isDense: true),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('(none — standalone user)')),
                  for (final e in emps) DropdownMenuItem<String?>(value: e.id, child: Text(e.name)),
                ],
                onChanged: (v) => setState(() => _employeeId = v),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Create'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Set password dialog
// ---------------------------------------------------------------------------

class _SetPasswordDialog extends ConsumerStatefulWidget {
  final ManagedUser user;
  const _SetPasswordDialog({required this.user});
  @override
  ConsumerState<_SetPasswordDialog> createState() => _SetPasswordDialogState();
}

class _SetPasswordDialogState extends ConsumerState<_SetPasswordDialog> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  String? _error;
  String? _newPassword;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pw = _password.text;
    if (pw.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    if (pw != _confirm.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(userManagementRepositoryProvider).setPassword(widget.user.userId, pw);
      setState(() => _newPassword = pw);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_newPassword != null) {
      return AlertDialog(
        title: const Text('Password set'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${widget.user.email} must change this password on next login. Copy it now — it will not be shown again.'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(children: [
              Expanded(child: SelectableText(_newPassword!, style: const TextStyle(fontFamily: 'monospace', fontSize: 14))),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () => Clipboard.setData(ClipboardData(text: _newPassword!)),
              ),
            ]),
          ),
        ]),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
      );
    }
    return AlertDialog(
      title: Text('Set new password — ${widget.user.email}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _password,
            decoration: InputDecoration(
              labelText: 'New password (min 8)',
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: () {
                  final pw = _generateTempPassword();
                  _password.text = pw;
                  _confirm.text = pw;
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirm,
            decoration: const InputDecoration(labelText: 'Confirm', border: OutlineInputBorder(), isDense: true),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Set password'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Change role dialog
// ---------------------------------------------------------------------------

class _ChangeRoleDialog extends ConsumerStatefulWidget {
  final ManagedUser user;
  final List<Role> roles;
  const _ChangeRoleDialog({required this.user, required this.roles});
  @override
  ConsumerState<_ChangeRoleDialog> createState() => _ChangeRoleDialogState();
}

class _ChangeRoleDialogState extends ConsumerState<_ChangeRoleDialog> {
  late String _selected = widget.user.roleCode ?? widget.roles.first.code;
  bool _saving = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(userManagementRepositoryProvider).updateRole(widget.user.userId, _selected);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Change role — ${widget.user.email}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final r in widget.roles)
            RadioListTile<String>(
              value: r.code,
              groupValue: _selected,
              onChanged: (v) => setState(() => _selected = v!),
              title: Text(r.name),
              subtitle: Text(r.code, style: const TextStyle(fontFamily: 'monospace')),
              dense: true,
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Link/unlink employee dialog
// ---------------------------------------------------------------------------

class _LinkEmployeeDialog extends ConsumerStatefulWidget {
  final ManagedUser user;
  const _LinkEmployeeDialog({required this.user});
  @override
  ConsumerState<_LinkEmployeeDialog> createState() => _LinkEmployeeDialogState();
}

class _LinkEmployeeDialogState extends ConsumerState<_LinkEmployeeDialog> {
  late String? _selected = widget.user.linkedEmployeeId;
  bool _saving = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(userManagementRepositoryProvider).linkEmployee(widget.user.userId, _selected);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final empsAsync = ref.watch(unlinkedEmployeesProvider(widget.user.userId));
    return AlertDialog(
      title: Text('Link / unlink employee — ${widget.user.email}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: empsAsync.when(
          loading: () => const SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Text('$e', style: const TextStyle(color: Colors.red)),
          data: (emps) => DropdownButtonFormField<String?>(
            value: _selected,
            decoration: const InputDecoration(labelText: 'Employee', border: OutlineInputBorder(), isDense: true),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('(none — unlink)')),
              for (final e in emps) DropdownMenuItem<String?>(value: e.id, child: Text(e.name)),
            ],
            onChanged: (v) => setState(() => _selected = v),
          ),
        ),
      ),
      actions: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
          ),
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run:
```bash
flutter analyze lib/features/settings/users/users_settings_screen.dart
```
Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add lib/features/settings/users/users_settings_screen.dart
git commit -m "feat(settings): users tab — list, add, set password, role, link, deactivate"
```

---

## Task 12: Mount the Users tab in Settings

**Files:**
- Modify: `lib/features/settings/settings_screen.dart`

- [ ] **Step 1: Add the import**

Insert with the other settings imports near the top of the file:
```dart
import 'users/users_settings_screen.dart';
```

- [ ] **Step 2: Add `users` to the `_Tab` enum**

Find:
```dart
enum _Tab {
  departments('departments', 'Departments', 'Manage company departments',
      Icons.apartment_outlined),
  hiringEntities('hiring-entities', 'Company Info',
      'Hiring entities & registrations', Icons.business_outlined),
  bankAccounts('bank-accounts', 'Bank Accounts', 'Company payment sources',
      Icons.account_balance_outlined),
  roles('roles', 'Roles', 'Manage roles and permissions',
      Icons.shield_outlined),
  shifts('shifts', 'Shift Templates', 'Define work schedules', Icons.schedule),
```

Insert a `users` value between `roles` and `shifts`:
```dart
enum _Tab {
  departments('departments', 'Departments', 'Manage company departments',
      Icons.apartment_outlined),
  hiringEntities('hiring-entities', 'Company Info',
      'Hiring entities & registrations', Icons.business_outlined),
  bankAccounts('bank-accounts', 'Bank Accounts', 'Company payment sources',
      Icons.account_balance_outlined),
  roles('roles', 'Roles', 'Manage roles and permissions',
      Icons.shield_outlined),
  users('users', 'Users', 'Manage who can log in',
      Icons.people_alt_outlined),
  shifts('shifts', 'Shift Templates', 'Define work schedules', Icons.schedule),
```

- [ ] **Step 3: Wire the screen into the body switcher**

Find the body builder that maps `_Tab` values to screens (look for the existing `case _Tab.roles:` arm). Add a sibling arm:
```dart
case _Tab.users:
  return const UsersSettingsScreen();
```

- [ ] **Step 4: Hide the Users tab unless caller is SUPER_ADMIN**

In the sidebar list builder, find where `_Tab.values` is iterated to render nav tiles. Filter the list:
```dart
final visibleTabs = [
  for (final t in _Tab.values)
    if (t != _Tab.users || profile.appRole == AppRole.SUPER_ADMIN) t
];
```
Use `visibleTabs` in the `for`/`map` that renders the sidebar tiles AND in the mobile drawer if applicable.

If the caller navigates to `/settings/users` directly without SUPER_ADMIN, also short-circuit in `build`:
```dart
if (_tab == _Tab.users && profile.appRole != AppRole.SUPER_ADMIN) {
  return const Center(child: Text('Super Admins only.'));
}
```
Place this inside the body builder right after the existing admins-only check.

- [ ] **Step 5: Manual verification**

Run:
```bash
flutter run -d chrome
```
- Sign in as the SUPER_ADMIN. Open `/settings`. Expected: a new "Users" tab appears between Roles and Shift Templates. The tab lists existing users.
- Click "Add User", fill in the form, submit. Expected: a "User created" panel shows the temp password (copy works), and the list refreshes with the new user marked "⚠ Must change password on next login".
- Sign out. Sign in as the new user. Expected: forced redirect to `/change-password`. After setting a password ≥ 8 chars, you land on `/dashboard` and `/settings/users` is hidden (non-SUPER_ADMIN).

- [ ] **Step 6: Commit**

```bash
git add lib/features/settings/settings_screen.dart
git commit -m "feat(settings): mount Users tab (SUPER_ADMIN only)"
```

---

## Task 13: End-to-end smoke + cleanup

- [ ] **Step 1: Run the full Deno test suite**

Run:
```bash
deno test --allow-env --allow-net supabase/tests/
```
Expected: all tests pass (manage-user + existing parse_holiday_summary).

- [ ] **Step 2: Run flutter analyze across the whole repo**

Run:
```bash
flutter analyze
```
Expected: No issues found.

- [ ] **Step 3: Walk the whole flow once**

In a single browser session:
1. Bootstrap or sign in as SUPER_ADMIN.
2. Settings → Users → Add User with employee link → copy temp password.
3. Sign out, sign in as the new user → forced change-password → set new pw → dashboard.
4. Sign back in as SUPER_ADMIN.
5. Settings → Users → row overflow → Change role to FINANCE_MANAGER → close.
6. Settings → Users → row overflow → Set new password → copy → close.
7. Settings → Users → row overflow → Link/unlink employee → unlink → save.
8. Settings → Users → row overflow → Deactivate → confirm. The row now shows "Inactive".
9. Reactivate the user from the same overflow menu.

Expected: every step succeeds with no console errors.

- [ ] **Step 4: Final commit**

```bash
git status
# If anything is left untracked from manual testing, stash or remove it.
git log --oneline -15
```
Expected: 11–12 feature commits forming a clean linear history. Open a PR if your team uses one.

---

## Self-Review Notes

- **Spec coverage:** every section in the spec maps to at least one task — schema (Task 1), edge-function actions (Tasks 2–7), profile + RLS-aware reads (Task 8), first-login flow (Task 9), repository (Task 10), UI (Task 11), tab mount + visibility (Task 12), end-to-end verification (Task 13).
- **Type consistency:** `ManagedUser`, `UnlinkedEmployee`, `UserManagementException`, `AppRole` enum members, and edge-function action strings are all referenced consistently across tasks.
- **No placeholders:** every step contains the exact code or command an engineer needs.
- **Open follow-ups (intentionally out of scope):** `roles.permissions` enforcement; email-based reset (would need SMTP); audit log of role changes / password resets; multi-role support.
