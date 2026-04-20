// Edge Function: recall-payslip-approvals
//
// Cancels Lark approval instances for PENDING_APPROVAL payslips in a run
// (optionally filtered to a subset via `payslip_ids`), then flips the
// local row to:
//   approval_status      = 'RECALLED'
//   lark_approval_status = NULL
//
// Setting lark_approval_status back to NULL signals to the compute
// service that the payslip is editable / recomputable again.
//
// IMPORTANT: Lark's `/approval/v4/instances/cancel` endpoint only accepts
// the INITIATOR of the instance as the canceller. Send sets the admin
// (`LARK_ADMIN_USER_ID`) as initiator, so the recall must also pass the
// admin's user_id — not the employee's. Passing the employee produces an
// "unauthorized" rejection on every cancel.
//
// Input:
//   { "run_id": "uuid" }                          // recall every PENDING row in the run
//   { "run_id": "uuid", "payslip_ids": [...] }    // recall only those rows

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { authFromEnv, larkRequest } from '../_shared/lark.ts';

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
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

  const approvalCode = Deno.env.get('LARK_PAYSLIP_APPROVAL_CODE');
  if (!approvalCode) {
    return json({ error: 'LARK_PAYSLIP_APPROVAL_CODE not configured' }, 500);
  }
  const adminUserId = Deno.env.get('LARK_ADMIN_USER_ID');
  if (!adminUserId) {
    return json({ error: 'LARK_ADMIN_USER_ID not configured' }, 500);
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } },
  );

  // Both PENDING_APPROVAL ("Recall" in the UI) and APPROVED ("Revoke") are
  // valid targets. Lark's /approval/v4/instances/cancel handles both when
  // the approval template has "Allow cancellation of approved instances
  // within X days" enabled (允许撤销 X 天内通过的审批). For an approved
  // instance Lark reverts it to pending internally and notifies the
  // employee — we flip our local row to RECALLED immediately regardless,
  // and the webhook + sync ignore RECALLED rows to keep the revoke sticky.
  let query = supabase
    .from('payslips')
    .select('id, lark_approval_instance_code')
    .eq('payroll_run_id', runId)
    .in('approval_status', ['PENDING_APPROVAL', 'APPROVED']);
  if (payslipIds && payslipIds.length > 0) {
    query = query.in('id', payslipIds);
  }
  const { data: rows, error } = await query;
  if (error) return json({ error: error.message }, 500);
  if (!rows || rows.length === 0) {
    return json({ ok: true, recalled: 0, failed: 0, errors: [] });
  }

  const auth = authFromEnv();
  let recalled = 0;
  let failed = 0;
  const errors: Array<{ payslipId: string; error: string }> = [];

  for (const p of rows) {
    const instanceCode = p.lark_approval_instance_code as string | null;

    // Defensive: PENDING_APPROVAL without an instance_code shouldn't happen
    // (send always pairs them), but treat it as a local-only soft recall
    // so the row doesn't stay stuck in PENDING forever.
    if (!instanceCode) {
      await supabase
        .from('payslips')
        .update({
          approval_status: 'RECALLED',
          lark_approval_status: null,
        })
        .eq('id', p.id);
      failed++;
      errors.push({
        payslipId: p.id as string,
        error: 'no lark_approval_instance_code on payslip',
      });
      continue;
    }

    try {
      // See https://open.larksuite.com/document/approval-v4/instance/cancel
      // The user_id must be the instance's INITIATOR (admin), not the
      // approver (employee). Lark defaults to `user_id_type=open_id` for
      // this endpoint's body field — we store user_ids (`9de5d1b1`-style
      // tenant IDs) in LARK_ADMIN_USER_ID, so we explicitly switch the
      // type. Without this, Lark rejects with 99992351 "not a valid
      // open_id, example {ou_...}".
      await larkRequest(
        auth,
        '/approval/v4/instances/cancel?user_id_type=user_id',
        {
          method: 'POST',
          body: JSON.stringify({
            approval_code: approvalCode,
            instance_code: instanceCode,
            user_id: adminUserId,
          }),
        },
      );

      await supabase
        .from('payslips')
        .update({
          approval_status: 'RECALLED',
          lark_approval_status: null,
        })
        .eq('id', p.id);
      recalled++;
    } catch (e) {
      failed++;
      errors.push({
        payslipId: p.id as string,
        error: e instanceof Error ? e.message : String(e),
      });
      // Don't flip local state on hard Lark failure — surface the error so
      // the user can retry. The payslip stays PENDING_APPROVAL.
    }
  }

  return json({ ok: true, recalled, failed, errors });
});
