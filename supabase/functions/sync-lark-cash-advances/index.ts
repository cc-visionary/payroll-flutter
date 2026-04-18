// Edge Function: sync-lark-cash-advances
// Pulls approved cash-advance approval instances from Lark and upserts
// cash_advances by lark_instance_code.
//
// Input (POST JSON):
//   { "company_id": "uuid", "from": "...", "to": "..." }
// Required secret: LARK_CASH_ADVANCE_APPROVAL_CODE

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import {
  authFromEnv,
  listApprovalInstances,
  getApprovalInstance,
  logSyncStart,
  logSyncFinish,
  userIdFromAuthHeader,
  json,
} from '../_shared/lark.ts';

interface Body { company_id?: string; from?: string; to?: string }

// Walk Lark approval form and pluck first numeric value as amount + first
// text value as reason. Lark widget IDs are auto-generated, so we discover
// fields by `type`/`name` patterns rather than literal id lookup.
function extractCashAdvance(formJson: string): { amount: number | null; reason: string | null } {
  let widgets: unknown;
  try { widgets = JSON.parse(formJson); } catch { widgets = []; }
  if (!Array.isArray(widgets)) widgets = [];
  let amount: number | null = null;
  let reason: string | null = null;
  const walk = (nodes: unknown): void => {
    if (!Array.isArray(nodes)) return;
    for (const n of nodes as Array<Record<string, unknown>>) {
      const name = String(n.name ?? '').toLowerCase();
      const type = String(n.type ?? '').toLowerCase();
      const val = n.value;
      if (Array.isArray(val)) { walk(val); continue; }
      if (amount === null && (type === 'number' || type === 'amount' || type === 'money'
          || name.includes('amount') || name.includes('金额') || name.includes('halaga'))) {
        const num = parseFloat(String(val ?? ''));
        if (!isNaN(num) && num > 0) amount = num;
      }
      if (reason === null && val != null && (type === 'textarea' || type === 'input'
          || name.includes('reason') || name.includes('备注') || name.includes('purpose'))) {
        const s = String(val).trim();
        if (s.length > 0) reason = s;
      }
    }
  };
  walk(widgets);
  // Last-resort: first positive numeric value of any field
  if (amount === null) {
    const flat = (nodes: unknown): void => {
      if (!Array.isArray(nodes)) return;
      for (const n of nodes as Array<Record<string, unknown>>) {
        if (amount !== null) return;
        const v = n.value;
        if (Array.isArray(v)) { flat(v); continue; }
        const num = parseFloat(String(v ?? ''));
        if (!isNaN(num) && num > 0) amount = num;
      }
    };
    flat(widgets);
  }
  return { amount, reason };
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method not allowed' }, 405);

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } },
  );

  const approvalCode = Deno.env.get('LARK_CASH_ADVANCE_APPROVAL_CODE');
  if (!approvalCode) return json({ error: 'LARK_CASH_ADVANCE_APPROVAL_CODE env var required' }, 500);

  let body: Body = {};
  try { body = await req.json(); } catch (_) {}
  const companyId = body.company_id;
  if (!companyId) return json({ error: 'company_id required' }, 400);

  const now = new Date();
  let to = body.to ? new Date(body.to) : now;
  if (to > now) to = now; // Lark rejects future date ranges with 1220001.
  let from = body.from ? new Date(body.from) : new Date(to.getTime() - 30 * 24 * 60 * 60 * 1000);
  if (from > to) from = to;

  const syncedById = userIdFromAuthHeader(req);
  const logId = await logSyncStart(supabase, {
    companyId,
    syncType: 'CASH_ADVANCE',
    dateFrom: from.toISOString().slice(0, 10),
    dateTo: to.toISOString().slice(0, 10),
    syncedById,
  });

  const errors: string[] = [];
  let created = 0, updated = 0, skipped = 0, total = 0;

  try {
    const auth = authFromEnv();

    const { data: emps } = await supabase
      .from('employees')
      .select('id, lark_user_id')
      .eq('company_id', companyId)
      .is('deleted_at', null)
      .not('lark_user_id', 'is', null);
    const empByLarkId = new Map<string, string>();
    for (const e of emps ?? []) empByLarkId.set(e.lark_user_id as string, e.id as string);

    const instanceCodes = await listApprovalInstances(auth, approvalCode, from, to);
    total = instanceCodes.length;

    for (const code of instanceCodes) {
      try {
        const inst = await getApprovalInstance(auth, code);
        if (inst.status !== 'APPROVED') { skipped++; continue; }
        const employeeId = empByLarkId.get(inst.user_id) ?? empByLarkId.get(inst.open_id ?? '');
        if (!employeeId) { skipped++; errors.push(`${code}: no employee for user ${inst.user_id}`); continue; }
        const parsed = inst.form ? extractCashAdvance(inst.form) : { amount: null, reason: null };
        if (parsed.amount == null) {
          errors.push(`${code}: could not parse amount (form=${(inst.form ?? '').slice(0, 200)})`); skipped++; continue;
        }
        const amount = parsed.amount;
        const reason = parsed.reason;
        const approvedAt = inst.end_time
          ? new Date(typeof inst.end_time === 'number' ? inst.end_time : parseInt(String(inst.end_time), 10)).toISOString()
          : null;

        const { data: existing } = await supabase
          .from('cash_advances')
          .select('id')
          .eq('lark_instance_code', code)
          .maybeSingle();

        // Fields safe to overwrite every sync: Lark-side state and parsed form data.
        // The local `status` (PENDING/DEDUCTED/CANCELLED) reflects local payroll
        // lifecycle and must not be reset back to PENDING on a re-sync.
        const updatePayload = {
          lark_approval_status: inst.status,
          lark_approved_at: approvedAt,
          amount,
          reason,
          synced_at: new Date().toISOString(),
        };

        if (existing) {
          const { error } = await supabase.from('cash_advances').update(updatePayload).eq('id', existing.id);
          if (error) { errors.push(`${code}: ${error.message}`); continue; }
          updated++;
        } else {
          const { error } = await supabase.from('cash_advances').insert({
            ...updatePayload,
            company_id: companyId,
            employee_id: employeeId,
            lark_instance_code: code,
            status: 'PENDING',
          });
          if (error) { errors.push(`${code}: ${error.message}`); continue; }
          created++;
        }
      } catch (e) {
        errors.push(`${code}: ${e}`);
      }
    }

    await logSyncFinish(supabase, logId, { total, created, updated, skipped, errors });
    return json({ ok: true, total, created, updated, skipped, errors });
  } catch (e) {
    errors.push(String(e));
    await logSyncFinish(supabase, logId, { total, created, updated, skipped, errors });
    return json({ ok: false, error: String(e) }, 500);
  }
});
// redeploy 1776241510 supabase functions deploy sync-lark-cash-advances
// redeploy 1776241875
