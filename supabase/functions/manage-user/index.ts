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

export type ValidationResult = {
  ok: boolean;
  error?: string;
  code?: string;
};

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
