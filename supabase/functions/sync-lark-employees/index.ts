// Edge Function: sync-lark-employees
// Pulls the Lark contact directory and stamps employees.lark_user_id by
// matching on employee_number ↔ Lark employee_no (case-insensitive).
//
// Input (POST JSON):
//   { "company_id": "uuid" }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import {
  authFromEnv,
  listContactUsers,
  logSyncStart,
  logSyncFinish,
  userIdFromAuthHeader,
  json,
} from '../_shared/lark.ts';

interface Body { company_id?: string }

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method not allowed' }, 405);

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } },
  );

  let body: Body = {};
  try { body = await req.json(); } catch (_) { /* empty body */ }
  const companyId = body.company_id;
  if (!companyId) return json({ error: 'company_id required' }, 400);

  const syncedById = userIdFromAuthHeader(req);
  const logId = await logSyncStart(supabase, {
    companyId,
    syncType: 'EMPLOYEE',
    syncedById,
  });

  const errors: string[] = [];
  let created = 0, updated = 0, skipped = 0;

  try {
    const auth = authFromEnv();
    const larkUsers = await listContactUsers(auth);

    // Build case-insensitive lookup Lark employee_no → Lark user_id
    const larkByEmpNo = new Map<string, string>();
    for (const u of larkUsers) {
      if (u.employee_no && u.user_id) {
        larkByEmpNo.set(u.employee_no.trim().toUpperCase(), u.user_id);
      }
    }

    // Fetch employees for the company
    const { data: emps, error } = await supabase
      .from('employees')
      .select('id, employee_number, lark_user_id')
      .eq('company_id', companyId)
      .is('deleted_at', null);
    if (error) throw new Error(`employees select: ${error.message}`);

    for (const e of emps ?? []) {
      const key = (e.employee_number as string).trim().toUpperCase();
      const larkId = larkByEmpNo.get(key);
      if (!larkId) { skipped++; continue; }
      if (e.lark_user_id === larkId) { skipped++; continue; }
      const wasEmpty = !e.lark_user_id;
      const { error: upErr } = await supabase
        .from('employees')
        .update({ lark_user_id: larkId })
        .eq('id', e.id);
      if (upErr) { errors.push(`${e.employee_number}: ${upErr.message}`); continue; }
      if (wasEmpty) created++; else updated++;
    }

    await logSyncFinish(supabase, logId, {
      total: emps?.length ?? 0,
      created, updated, skipped, errors,
    });

    return json({
      ok: true,
      total: emps?.length ?? 0,
      linked: created + updated,
      created, updated, skipped,
      errors,
    });
  } catch (e) {
    errors.push(String(e));
    await logSyncFinish(supabase, logId, { total: 0, created, updated, skipped, errors });
    return json({ ok: false, error: String(e) }, 500);
  }
});
// redeploy 1776241510 supabase functions deploy sync-lark-employees
// redeploy 1776241849
