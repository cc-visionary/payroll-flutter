// Edge Function: lark-ping
// Health-check: verifies LARK_APP_ID / LARK_APP_SECRET are set AND reachable.
// Returns the tenant_access_token's expiry + the authenticated bot's name.
//
// Usage (from Flutter):
//   await Supabase.instance.client.functions.invoke('lark-ping');
// Or curl from dev machine:
//   curl -X POST https://<project>.supabase.co/functions/v1/lark-ping \
//     -H "Authorization: Bearer $SUPABASE_ANON_KEY"

import { authFromEnv, tenantAccessToken, larkRequest } from '../_shared/lark.ts';

Deno.serve(async (_req) => {
  try {
    const auth = authFromEnv();
    const token = await tenantAccessToken(auth);
    // "self" endpoint — returns details of the authenticated app / tenant
    const info = await larkRequest<{ tenant_key?: string; app_id?: string }>(
      auth,
      '/tenant/v2/tenant/query',
    ).catch(() => ({}));

    return new Response(
      JSON.stringify({
        ok: true,
        app_id: auth.appId,
        tenant_access_token_prefix: token.substring(0, 12) + '...',
        tenant_info: info,
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    );
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return new Response(
      JSON.stringify({ ok: false, error: msg }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    );
  }
});
// redeploy 1776241510 supabase functions deploy lark-ping
// redeploy 1776241817
