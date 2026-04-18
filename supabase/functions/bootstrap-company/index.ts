// Edge Function: bootstrap-company
//
// Runs immediately after a new employer completes `auth.signUp`. Creates the
// tenant (companies + hiring_entity + departments + users rows), then sets
// `app_metadata.app_role = SUPER_ADMIN` and `app_metadata.company_id` on the
// new auth user so RLS works on the very next request.
//
// Idempotent: calling twice for the same caller is a no-op if the caller
// already has a `company_id` in their JWT.
//
// Request body:
//   { "company_name": "Acme Inc." }
//
// Response:
//   { "ok": true, "company_id": "<uuid>" }
//
// Required env vars (set via `supabase secrets set`):
//   SUPABASE_URL
//   SUPABASE_SERVICE_ROLE_KEY

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...corsHeaders },
  });
}

/// Quick slug from a company name, used as the `companies.code`. Must match
/// the `varchar(20)` constraint + uniqueness. Adds a short random suffix so
/// two customers with the same name don't collide.
function deriveCode(name: string): string {
  const base = name
    .toUpperCase()
    .replace(/[^A-Z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 14);
  const suffix = crypto.randomUUID().replace(/-/g, '').slice(0, 5).toUpperCase();
  return base ? `${base}-${suffix}` : `CO-${suffix}`;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') return json({ ok: false, error: 'POST required' }, 405);

  const url = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !serviceKey) {
    return json({ ok: false, error: 'Server not configured' }, 500);
  }

  const authHeader = req.headers.get('Authorization');
  if (!authHeader?.startsWith('Bearer ')) {
    return json({ ok: false, error: 'Missing Authorization' }, 401);
  }
  const callerJwt = authHeader.substring('Bearer '.length);

  let body: { company_name?: string; trade_name?: string };
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, error: 'Invalid JSON body' }, 400);
  }
  const companyName = (body.company_name ?? '').trim();
  if (!companyName) return json({ ok: false, error: 'company_name required' }, 400);

  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // 1. Validate the caller.
  const { data: userData, error: userErr } = await admin.auth.getUser(callerJwt);
  if (userErr || !userData?.user) {
    return json({ ok: false, error: 'Invalid token' }, 401);
  }
  const user = userData.user;

  // Idempotency: already bootstrapped? Return existing company_id.
  const existingCompanyId =
    (user.app_metadata?.company_id as string | undefined) ?? null;
  if (existingCompanyId) {
    return json({ ok: true, company_id: existingCompanyId, already_bootstrapped: true });
  }

  // 2. Create the company.
  const code = deriveCode(companyName);
  const { data: company, error: coErr } = await admin
    .from('companies')
    .insert({
      code,
      name: companyName,
      trade_name: body.trade_name ?? null,
      country: 'PH',
    })
    .select('id')
    .single();
  if (coErr || !company) {
    return json(
      { ok: false, error: `Could not create company: ${coErr?.message}` },
      500,
    );
  }
  const companyId = company.id as string;

  // 3. Create a default hiring entity — customers can edit it later under
  //    Settings → Company Info. Having one on signup means every employee row
  //    can reference a valid entity immediately.
  await admin.from('hiring_entities').insert({
    company_id: companyId,
    code: 'MAIN',
    name: companyName,
    country: 'PH',
    is_active: true,
  });

  // 4. Link the auth user to the company via the `users` table.
  const { error: userInsertErr } = await admin.from('users').upsert(
    { id: user.id, company_id: companyId, status: 'ACTIVE' },
    { onConflict: 'id' },
  );
  if (userInsertErr) {
    return json(
      { ok: false, error: `Could not link user: ${userInsertErr.message}` },
      500,
    );
  }

  // 5. Stamp app_role + company_id into auth app_metadata so the JWT carries
  //    the claims required by RLS helpers (auth_app_role(), auth_company_id()).
  const mergedMeta = {
    ...(user.app_metadata ?? {}),
    app_role: 'SUPER_ADMIN',
    company_id: companyId,
  };
  const { error: metaErr } = await admin.auth.admin.updateUserById(user.id, {
    app_metadata: mergedMeta,
  });
  if (metaErr) {
    return json(
      { ok: false, error: `Could not set app_metadata: ${metaErr.message}` },
      500,
    );
  }

  return json({ ok: true, company_id: companyId });
});
