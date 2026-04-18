// Edge Function: send-payslip-approvals
// Creates a Lark approval instance for every DRAFT_IN_REVIEW payslip in a
// given payroll run and stores the instance_code on the payslip row.
// Called by the desktop "Send" button inside a REVIEW state payroll run.
//
// Input: { "run_id": "uuid" }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { authFromEnv, larkRequest } from '../_shared/lark.ts';

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('Method Not Allowed', { status: 405 });

  const { run_id: runId } = await req.json().catch(() => ({}));
  if (!runId) return json({ error: 'run_id required' }, 400);

  const approvalCode = Deno.env.get('LARK_PAYSLIP_APPROVAL_CODE');
  if (!approvalCode) return json({ error: 'LARK_PAYSLIP_APPROVAL_CODE not configured' }, 500);

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } },
  );

  const { data: payslips, error } = await supabase
    .from('payslips')
    .select('id, employee_id, gross_pay, net_pay, employees(lark_user_id, first_name, last_name)')
    .eq('payroll_run_id', runId)
    .eq('approval_status', 'DRAFT_IN_REVIEW');
  if (error) return json({ error: error.message }, 500);
  if (!payslips || payslips.length === 0) return json({ ok: true, sent: 0 });

  const auth = authFromEnv();
  let sent = 0, failed = 0;
  const errors: Array<{ payslipId: string; error: string }> = [];

  for (const p of payslips) {
    // deno-lint-ignore no-explicit-any
    const emp: any = p.employees;
    if (!emp?.lark_user_id) { failed++; errors.push({ payslipId: p.id, error: 'no lark_user_id' }); continue; }

    try {
      const res = await larkRequest<{ instance_code: string }>(
        auth,
        '/approval/v4/instances',
        {
          method: 'POST',
          body: JSON.stringify({
            approval_code: approvalCode,
            open_id: emp.lark_user_id,
            form: JSON.stringify([
              { id: 'payslip_id', type: 'input', value: p.id },
              { id: 'employee', type: 'input', value: `${emp.first_name} ${emp.last_name}` },
              { id: 'gross_pay', type: 'number', value: p.gross_pay },
              { id: 'net_pay', type: 'number', value: p.net_pay },
            ]),
          }),
        },
      );

      await supabase
        .from('payslips')
        .update({
          approval_status: 'PENDING_APPROVAL',
          lark_approval_instance_code: res.instance_code,
          lark_approval_sent_at: new Date().toISOString(),
          lark_approval_status: 'PENDING',
        })
        .eq('id', p.id);

      sent++;
    } catch (e) {
      failed++;
      errors.push({ payslipId: p.id, error: e instanceof Error ? e.message : String(e) });
    }
  }

  return json({ ok: true, sent, failed, errors });
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
// redeploy 1776241510 supabase functions deploy send-payslip-approvals
// redeploy 1776241891
