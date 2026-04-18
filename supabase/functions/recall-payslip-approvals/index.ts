// Edge Function: recall-payslip-approvals
// For every PENDING_APPROVAL payslip in a run that has a Lark
// approval instance, cancels that instance via Lark's
// `/approval/v4/instances/cancel` endpoint, then flips the local payslip
// to:
//   approval_status      = 'RECALLED'
//   lark_approval_status = NULL
//
// Setting lark_approval_status back to NULL is the signal the compute
// service uses to treat the payslip as editable / recomputable again.
//
// Input: { "run_id": "uuid" }

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

  const { run_id: runId } = await req.json().catch(() => ({}));
  if (!runId) return json({ error: 'run_id required' }, 400);

  const approvalCode = Deno.env.get('LARK_PAYSLIP_APPROVAL_CODE');
  if (!approvalCode) {
    return json({ error: 'LARK_PAYSLIP_APPROVAL_CODE not configured' }, 500);
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } },
  );

  // Pull every payslip in this run that's still pending in Lark.
  const { data: payslips, error } = await supabase
    .from('payslips')
    .select(
      'id, lark_approval_instance_code, employees(lark_user_id)',
    )
    .eq('payroll_run_id', runId)
    .eq('approval_status', 'PENDING_APPROVAL');
  if (error) return json({ error: error.message }, 500);
  if (!payslips || payslips.length === 0) {
    return json({ ok: true, recalled: 0, failed: 0, errors: [] });
  }

  const auth = authFromEnv();
  let recalled = 0;
  let failed = 0;
  const errors: Array<{ payslipId: string; error: string }> = [];

  for (const p of payslips) {
    const instanceCode = p.lark_approval_instance_code as string | null;
    // deno-lint-ignore no-explicit-any
    const emp: any = p.employees;
    const userId = emp?.lark_user_id as string | undefined;

    // If either piece is missing we still flip the local state, but
    // nothing to cancel in Lark — just report as a soft failure so the
    // caller can see why.
    if (!instanceCode || !userId) {
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
        error: !instanceCode
          ? 'no lark_approval_instance_code on payslip'
          : 'employee has no lark_user_id',
      });
      continue;
    }

    try {
      // Lark approval cancel — see
      // https://open.larksuite.com/document/approval-v4/instance/cancel
      await larkRequest(auth, '/approval/v4/instances/cancel', {
        method: 'POST',
        body: JSON.stringify({
          approval_code: approvalCode,
          instance_code: instanceCode,
          user_id: userId,
        }),
      });

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
      // Don't flip local state on hard Lark failure — we want the user to
      // see the error and retry. The payslip stays PENDING_APPROVAL.
    }
  }

  return json({ ok: true, recalled, failed, errors });
});
