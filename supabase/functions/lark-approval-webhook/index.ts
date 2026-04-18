// Edge Function: lark-approval-webhook
// Receives callbacks from Lark when approval instances change status.
// Routes the event to the right table based on the approval definition:
//   - Leave → leave_requests
//   - Cash Advance → cash_advances
//   - Reimbursement → reimbursements
//   - Payslip (our own) → payslips.approval_status
//
// Lark challenge/verification: https://open.larksuite.com/document/ukTMukTMukTM/uUTNz4SN1MjL1UzM
// The first POST from Lark is `{"challenge": "...", "type": "url_verification"}`.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { authFromEnv, getApprovalInstance } from '../_shared/lark.ts';

interface LarkCallback {
  type?: string;             // "url_verification" | "event_callback"
  challenge?: string;        // url_verification response
  token?: string;            // verification token
  event?: {
    type?: string;           // e.g. "leave_approvalV2" | generic "approval_instance"
    instance_code?: string;
    status?: string;         // APPROVED | REJECTED | CANCELED | DELETED | PENDING
    approval_code?: string;  // which approval template this instance belongs to
  };
  // Lark v2 encrypted callbacks (if enabled) would arrive as `encrypt` — not
  // handled here; configure the app to send plaintext for V1.
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('Method Not Allowed', { status: 405 });

  const body = (await req.json().catch(() => ({}))) as LarkCallback;

  // Verify the shared token (set in Lark app config + Supabase env)
  const expectedToken = Deno.env.get('LARK_WEBHOOK_TOKEN');
  if (expectedToken && body.token && body.token !== expectedToken) {
    return new Response('invalid token', { status: 401 });
  }

  // URL verification handshake
  if (body.type === 'url_verification' && body.challenge) {
    return json({ challenge: body.challenge });
  }

  const event = body.event;
  if (!event?.instance_code || !event?.status) {
    return json({ ok: true, note: 'nothing to do' });
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } },
  );

  try {
    // Fetch full instance details (the callback only carries code+status)
    const auth = authFromEnv();
    const instance = await getApprovalInstance(auth, event.instance_code);
    const instanceCode = instance.instance_code;
    const larkStatus = instance.status;
    const approvalCode = event.approval_code ?? instance.approval_code ?? '';

    // Route by approval_code matched against env-configured template codes.
    const codes = {
      payslip: Deno.env.get('LARK_PAYSLIP_APPROVAL_CODE'),
      cashAdvance: Deno.env.get('LARK_CASH_ADVANCE_APPROVAL_CODE'),
      reimbursement: Deno.env.get('LARK_REIMBURSEMENT_APPROVAL_CODE'),
    };

    let result: unknown;
    if (approvalCode && approvalCode === codes.payslip) {
      result = await updatePayslipApproval(supabase, instanceCode, larkStatus);
    } else if (approvalCode && approvalCode === codes.cashAdvance) {
      result = await updateCashAdvance(supabase, instanceCode, larkStatus);
    } else if (approvalCode && approvalCode === codes.reimbursement) {
      result = await updateReimbursement(supabase, instanceCode, larkStatus);
    } else {
      // Unknown — try payslips first (most likely in our flow)
      result = await updatePayslipApproval(supabase, instanceCode, larkStatus);
    }
    return json({ ok: true, approval_code: approvalCode, result });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return json({ error: msg }, 500);
  }
});

// deno-lint-ignore no-explicit-any
async function updatePayslipApproval(supabase: any, instanceCode: string, larkStatus: string) {
  const appStatus = mapToPayslipApprovalStatus(larkStatus);
  const { data, error } = await supabase
    .from('payslips')
    .update({
      approval_status: appStatus,
      lark_approval_status: larkStatus,
    })
    .eq('lark_approval_instance_code', instanceCode)
    .select('id');
  if (error) return { table: 'payslips', error: error.message };
  return { table: 'payslips', matched: data?.length ?? 0 };
}

function mapToPayslipApprovalStatus(larkStatus: string): string {
  switch (larkStatus) {
    case 'APPROVED': return 'APPROVED';
    case 'REJECTED': return 'REJECTED';
    case 'CANCELED':
    case 'DELETED': return 'RECALLED';
    default: return 'PENDING_APPROVAL';
  }
}

// deno-lint-ignore no-explicit-any
async function updateCashAdvance(supabase: any, instanceCode: string, larkStatus: string) {
  const { data, error } = await supabase
    .from('cash_advances')
    .update({
      lark_approval_status: larkStatus,
      lark_approved_at: larkStatus === 'APPROVED' ? new Date().toISOString() : null,
    })
    .eq('lark_instance_code', instanceCode)
    .select('id');
  if (error) return { table: 'cash_advances', error: error.message };
  return { table: 'cash_advances', matched: data?.length ?? 0 };
}

// deno-lint-ignore no-explicit-any
async function updateReimbursement(supabase: any, instanceCode: string, larkStatus: string) {
  const { data, error } = await supabase
    .from('reimbursements')
    .update({
      lark_approval_status: larkStatus,
      lark_approved_at: larkStatus === 'APPROVED' ? new Date().toISOString() : null,
    })
    .eq('lark_instance_code', instanceCode)
    .select('id');
  if (error) return { table: 'reimbursements', error: error.message };
  return { table: 'reimbursements', matched: data?.length ?? 0 };
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
