// Edge Function: sync-payslip-approvals
// Pull fresh approval status from Lark for every payslip in a run that has
// a `lark_approval_instance_code`. This is the explicit "pull" path — the
// `lark-approval-webhook` does near-realtime updates when configured, but
// this function gives the user a deterministic "refresh now" button and
// backfills status if the webhook missed events / isn't deployed.
//
// Input:
//   { "run_id": "uuid" }                    // syncs every sent payslip
//   { "run_id": "uuid", "payslip_ids": [...] }  // syncs only those
//
// Output: { ok, synced, failed, errors: [{payslipId, error}] }
//
// We only touch rows that already have an instance_code — DRAFT_IN_REVIEW /
// RECALLED rows stay untouched.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { authFromEnv, getApprovalInstance } from '../_shared/lark.ts';

function mapToPayslipApprovalStatus(larkStatus: string): string {
  switch (larkStatus) {
    case 'APPROVED': return 'APPROVED';
    case 'REJECTED': return 'REJECTED';
    case 'CANCELED':
    case 'DELETED': return 'RECALLED';
    default: return 'PENDING_APPROVAL';
  }
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method Not Allowed', { status: 405 });
  }

  const body = await req.json().catch(() => ({}));
  const runId = body.run_id as string | undefined;
  const payslipIds = Array.isArray(body.payslip_ids)
    ? (body.payslip_ids as string[]).filter((v) => typeof v === 'string')
    : null;
  if (!runId) return json({ error: 'run_id required' }, 400);

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } },
  );

  // Exclude RECALLED rows even when the caller tries to sync them —
  // a revoke is sticky, and if the employee re-approves in Lark after
  // we revoked (because cancel-on-approved reopens the instance), we
  // don't want the sync to flip the row back to APPROVED. The UI's
  // "Sync Selected" already filters these out; this is defense in
  // depth for manual / curl callers.
  let query = supabase
    .from('payslips')
    .select('id, lark_approval_instance_code')
    .eq('payroll_run_id', runId)
    .not('lark_approval_instance_code', 'is', null)
    .neq('approval_status', 'RECALLED');
  if (payslipIds && payslipIds.length > 0) {
    query = query.in('id', payslipIds);
  }
  const { data: rows, error } = await query;
  if (error) return json({ error: error.message }, 500);
  if (!rows || rows.length === 0) {
    return json({ ok: true, synced: 0, failed: 0, errors: [] });
  }

  const auth = authFromEnv();
  let synced = 0;
  let failed = 0;
  const errors: Array<{ payslipId: string; error: string }> = [];

  for (const r of rows) {
    const code = r.lark_approval_instance_code as string;
    try {
      const instance = await getApprovalInstance(auth, code);
      const larkStatus = instance.status;
      const appStatus = mapToPayslipApprovalStatus(larkStatus);
      const { error: upErr } = await supabase
        .from('payslips')
        .update({
          approval_status: appStatus,
          lark_approval_status: larkStatus,
        })
        .eq('id', r.id);
      if (upErr) throw new Error(upErr.message);
      synced++;
    } catch (e) {
      failed++;
      errors.push({
        payslipId: r.id as string,
        error: e instanceof Error ? e.message : String(e),
      });
    }
  }

  return json({ ok: true, synced, failed, errors });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
