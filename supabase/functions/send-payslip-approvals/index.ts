// Edge Function: send-payslip-approvals
//
// Ported from payrollos (`app/actions/lark-approval.ts`). The flow:
//   1. Fetch the approval template via `getApprovalDefinition` so we can
//      map widgets by *name* ("Department", "Pay Period", "PDF"). Widget
//      IDs in Lark are auto-generated and can't be set manually in the
//      admin UI, so we can't hard-code them.
//   2. For each DRAFT_IN_REVIEW payslip (optionally filtered to a subset
//      via `payslip_ids`), upload its PDF via `uploadApprovalFile`, then
//      create an approval instance where ADMIN (LARK_ADMIN_USER_ID) is the
//      initiator and the EMPLOYEE is the approver via
//      `node_approver_user_id_list`.
//   3. Persist the returned `instance_code` + `PENDING` state on the
//      payslip row. The `lark-approval-webhook` later flips the status.
//
// Input:
//   {
//     "run_id": "uuid",
//     "payslip_ids": ["uuid", ...],     // optional: subset to dispatch
//     "pdfs_base64": { "payslip-uuid": "base64..." }
//                                       // required for every payslip we
//                                       // intend to send; Lark's template
//                                       // has a required PDF widget.
//   }
//
// Output: { ok, sent, failed, skipped, errors: [{payslipId, error}] }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import {
  authFromEnv,
  getApprovalDefinition,
  larkRequest,
  uploadApprovalFile,
} from '../_shared/lark.ts';

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function base64ToBytes(b64: string): Uint8Array {
  // Strip any data-URL prefix; accept raw base64 payloads too.
  const clean = b64.replace(/^data:[^;]+;base64,/, '');
  const bin = atob(clean);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
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
  const pdfsBase64 = (body.pdfs_base64 ?? {}) as Record<string, string>;
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

  const auth = authFromEnv();

  // 1. Fetch the approval template so we can look up widget IDs by name.
  //    Matching rules mirror payrollos: substring match on lowercased widget
  //    name, with type-based fallback for attachment widgets so we still
  //    discover the PDF widget even if it's named something like "Payslip"
  //    rather than "PDF".
  let widgetIds: { department?: string; payPeriod?: string; pdf?: string } = {};
  let approverNodeId: string | undefined;
  try {
    const definition = await getApprovalDefinition(auth, approvalCode);
    approverNodeId = definition.nodeList?.[0]?.id;
    for (const w of definition.form) {
      const nameLower = w.name.toLowerCase();
      if (nameLower.includes('department')) {
        widgetIds.department = w.id;
      } else if (nameLower.includes('pay period') || nameLower.includes('period')) {
        widgetIds.payPeriod = w.id;
      } else if (
        nameLower.includes('pdf') ||
        nameLower.includes('payslip') ||
        nameLower.includes('attachment') ||
        w.type === 'attachmentV2' ||
        w.type === 'attachment'
      ) {
        widgetIds.pdf = w.id;
      }
    }
  } catch (e) {
    return json({
      error: `Failed to fetch approval definition: ${e instanceof Error ? e.message : String(e)}`,
    }, 500);
  }

  // 2. Pull DRAFT_IN_REVIEW payslips + employee/department/hiring-entity +
  //    pay period context so we can fill in the form fields server-side.
  // DRAFT_IN_REVIEW = never sent; RECALLED = previously sent then recalled
  // (the cancel flow nulls `lark_approval_status` and flips approval_status
  // to RECALLED). Both are valid "send now" candidates — we overwrite the
  // prior instance_code with the newly created one.
  let query = supabase
    .from('payslips')
    .select(
      'id, employee_id, '
        + 'employees(lark_user_id, first_name, last_name, '
          + 'departments!employees_department_id_fkey(name)), '
        + 'payroll_runs!inner(period_start, period_end)',
    )
    .eq('payroll_run_id', runId)
    .in('approval_status', ['DRAFT_IN_REVIEW', 'RECALLED']);
  if (payslipIds && payslipIds.length > 0) {
    query = query.in('id', payslipIds);
  }
  const { data, error } = await query;
  if (error) return json({ error: error.message }, 500);
  // Embedded selects confuse the PostgREST-generated generics, so we cast
  // through `unknown` — at runtime these are plain objects with the shape
  // used below.
  // deno-lint-ignore no-explicit-any
  const payslips = (data ?? []) as Array<any>;
  if (payslips.length === 0) {
    return json({ ok: true, sent: 0, failed: 0, skipped: 0, errors: [] });
  }

  let sent = 0;
  let failed = 0;
  let skipped = 0;
  const errors: Array<{ payslipId: string; error: string }> = [];

  for (const p of payslips) {
    // deno-lint-ignore no-explicit-any
    const emp: any = p.employees;
    // deno-lint-ignore no-explicit-any
    const run: any = p.payroll_runs;
    const fullName = `${emp?.last_name ?? ''}, ${emp?.first_name ?? ''}`.trim();
    const payPeriodLabel = run?.period_start && run?.period_end
      ? `${run.period_start} - ${run.period_end}`
      : '';

    if (!emp?.lark_user_id) {
      skipped++;
      errors.push({ payslipId: p.id, error: 'employee has no lark_user_id' });
      continue;
    }

    const pdfBase64 = pdfsBase64[p.id];
    if (!pdfBase64) {
      skipped++;
      errors.push({ payslipId: p.id, error: 'missing pdf bytes for payslip' });
      continue;
    }

    try {
      // 2a. Upload the PDF so we can attach it by file code.
      const pdfBytes = base64ToBytes(pdfBase64);
      const upload = await uploadApprovalFile(
        auth,
        pdfBytes,
        `Payslip-${p.id}.pdf`,
      );

      // 2b. Build form payload — only include widgets the template
      //     actually has so we don't trigger 60022 for optional slots that
      //     the admin removed.
      const formWidgets: Array<Record<string, unknown>> = [];
      if (widgetIds.department) {
        formWidgets.push({
          id: widgetIds.department,
          type: 'input',
          value: emp?.departments?.name ?? 'N/A',
        });
      }
      if (widgetIds.payPeriod) {
        formWidgets.push({
          id: widgetIds.payPeriod,
          type: 'input',
          value: payPeriodLabel,
        });
      }
      if (widgetIds.pdf) {
        formWidgets.push({
          id: widgetIds.pdf,
          type: 'attachmentV2',
          value: [upload.code],
        });
      }

      // 2c. Create the approval instance. Admin is the initiator; the
      //     employee is the approver on the first node (matches payrollos).
      //     `user_id_type=user_id` tells Lark to interpret BOTH the
      //     initiator `user_id` field and the approver ids inside
      //     `node_approver_user_id_list.value` as tenant user_ids (what
      //     we store) rather than open_ids. Cancel has the same rule —
      //     see recall-payslip-approvals/index.ts.
      const createRes = await larkRequest<{ instance_code: string }>(
        auth,
        '/approval/v4/instances?user_id_type=user_id',
        {
          method: 'POST',
          body: JSON.stringify({
            approval_code: approvalCode,
            user_id: adminUserId,
            form: JSON.stringify(formWidgets),
            node_approver_user_id_list: approverNodeId
              ? [{ key: approverNodeId, value: [emp.lark_user_id] }]
              : undefined,
            // Timestamp suffix so a recall-then-resend on the same payslip
            // doesn't collide with Lark's UUID-based idempotency check.
            uuid: `${p.id}-${Date.now()}`,
            title: `Payslip Acknowledgement - ${payPeriodLabel} - ${fullName}`,
          }),
        },
      );

      await supabase
        .from('payslips')
        .update({
          approval_status: 'PENDING_APPROVAL',
          lark_approval_instance_code: createRes.instance_code,
          lark_approval_sent_at: new Date().toISOString(),
          lark_approval_status: 'PENDING',
        })
        .eq('id', p.id);

      sent++;
    } catch (e) {
      failed++;
      errors.push({
        payslipId: p.id,
        error: e instanceof Error ? e.message : String(e),
      });
    }
  }

  return json({ ok: true, sent, failed, skipped, errors });
});
