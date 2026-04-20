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
//   USER_NOT_IN_COMPANY · BAD_REQUEST · NOT_IMPLEMENTED · INTERNAL

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
  if (employeeId !== null) {
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
    // Match Supabase Auth's actual duplicate-email message. Avoid the bare
    // 'exists' branch — too broad (would catch "Connection already exists",
    // "Index exists", etc., misclassifying infra errors as user errors).
    const code = /already registered/i.test(msg) ? 'DUPLICATE_EMAIL' : 'INTERNAL';
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
  if (employeeId !== null) {
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
async function handleDeactivate(_c: HandlerContext, _b: Record<string, unknown>): Promise<Response> {
  return json({ ok: false, error: 'deactivate not implemented', code: 'NOT_IMPLEMENTED' }, 501);
}
async function handleReactivate(_c: HandlerContext, _b: Record<string, unknown>): Promise<Response> {
  return json({ ok: false, error: 'reactivate not implemented', code: 'NOT_IMPLEMENTED' }, 501);
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
  // Same response for "not found" and "wrong company" — don't leak existence
  // across company boundaries.
  if (!emp) return json({ ok: false, error: 'Employee not in your company', code: 'EMPLOYEE_WRONG_COMPANY' }, 400);
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
