// Edge Function: sync-lark-leaves
// Pulls approved leaves from Lark's attendance user_approvals endpoint and
// upserts leave_requests (dedup by employee|leave_type_id|start|end).
//
// Input (POST JSON):
//   { "company_id": "uuid", "from": "2026-04-01", "to": "2026-04-15" }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import {
  authFromEnv,
  queryUserApprovals,
  logSyncStart,
  logSyncFinish,
  userIdFromAuthHeader,
  json,
} from '../_shared/lark.ts';

interface Body { company_id?: string; from?: string; to?: string }

function toYYYYMMDD(d: Date): string {
  return `${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, '0')}${String(d.getDate()).padStart(2, '0')}`;
}

function toMs(epochOrIso: string | number): number {
  return typeof epochOrIso === 'number'
    ? epochOrIso
    : (/^\d+$/.test(epochOrIso) ? parseInt(epochOrIso, 10) : new Date(epochOrIso).getTime());
}

function toISODate(epochOrIso: string | number): string {
  return new Date(toMs(epochOrIso)).toISOString().slice(0, 10);
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method not allowed' }, 405);

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } },
  );

  let body: Body = {};
  try { body = await req.json(); } catch (_) {}
  const companyId = body.company_id;
  if (!companyId) return json({ error: 'company_id required' }, 400);

  const now = new Date();
  let to = body.to ? new Date(body.to) : now;
  if (to > now) to = now; // Lark only has data up to today
  const from = body.from ? new Date(body.from) : new Date(to.getTime() - 30 * 24 * 60 * 60 * 1000);

  const syncedById = userIdFromAuthHeader(req);
  const logId = await logSyncStart(supabase, {
    companyId,
    syncType: 'LEAVE',
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
    const larkUserIds = Array.from(empByLarkId.keys());

    // Map Lark leave_type_id → local leave_types.id
    const { data: lts } = await supabase
      .from('leave_types')
      .select('id, lark_leave_type_id, code')
      .eq('company_id', companyId);
    const ltByLarkId = new Map<string, string>();
    for (const lt of lts ?? []) {
      if (lt.lark_leave_type_id) ltByLarkId.set(lt.lark_leave_type_id as string, lt.id as string);
    }

    if (larkUserIds.length === 0) {
      await logSyncFinish(supabase, logId, { total: 0, created, updated, skipped, errors });
      return json({ ok: true, total: 0, note: 'no employees linked to Lark' });
    }

    const approvals = await queryUserApprovals(auth, larkUserIds, toYYYYMMDD(from), toYYYYMMDD(to));

    // Dedup by employee|leaveType|start|end
    const seen = new Set<string>();

    for (const ua of approvals) {
      const employeeId = empByLarkId.get(ua.employee_id ?? ua.user_id ?? '');
      if (!employeeId) continue;
      for (const lv of ua.leaves ?? []) {
        total++;
        const candidateKey = lv.leave_type_id ?? lv.uniq_id ?? '';
        if (!candidateKey) { skipped++; continue; }
        let ltId = ltByLarkId.get(candidateKey);
        if (!ltId) {
          // Auto-create a local leave_type row keyed by Lark's uniq_id so
          // subsequent syncs find it. Name from i18n_names[default_locale].
          const names = (lv.i18n_names ?? {}) as Record<string, string>;
          const locale = lv.default_locale ?? 'en_us';
          const displayName = (names[locale] ?? names['en_us'] ?? names['zh_cn'] ?? candidateKey).toString().slice(0, 100);
          // Prefer a readable code derived from the display name; fall back to
          // the Lark id. Two different Lark ids can collapse to the same
          // 20-char slice, so retry with -2/-3/… on unique-violation.
          const baseSource = (displayName || candidateKey.toString())
              .toUpperCase()
              .replace(/[^A-Z0-9]+/g, '_')
              .replace(/^_+|_+$/g, '');
          const baseCode = (baseSource || 'LARK').slice(0, 18); // leave room for "-N"
          let ltErrLast: { message: string } | null = null;
          for (let attempt = 0; attempt < 25 && !ltId; attempt++) {
            const code = attempt === 0 ? baseCode : `${baseCode.slice(0, 18)}-${attempt + 1}`;
            const { data: newLt, error: ltErr } = await supabase
              .from('leave_types')
              .insert({
                company_id: companyId,
                code: code.slice(0, 20),
                name: displayName || code,
                lark_leave_type_id: candidateKey.toString().slice(0, 100),
                accrual_type: 'NONE',
                is_active: true,
              })
              .select('id')
              .single();
            if (!ltErr) {
              ltId = newLt.id as string;
              ltByLarkId.set(candidateKey, ltId);
              break;
            }
            ltErrLast = ltErr;
            // Only retry on unique-violation (Postgres 23505); anything else
            // is a real schema/permission error and should surface immediately.
            const msg = (ltErr.message || '').toLowerCase();
            if (!msg.includes('duplicate') && !msg.includes('unique')) break;
          }
          if (!ltId) {
            errors.push(`auto-create leave_type ${candidateKey} (${displayName}): ${ltErrLast?.message ?? 'unknown'}`);
            continue;
          }
        }
        const startDate = toISODate(lv.start_time);
        const endDate = toISODate(lv.end_time);
        const dedupKey = `${employeeId}|${ltId}|${startDate}|${endDate}`;
        if (seen.has(dedupKey)) { skipped++; continue; }
        seen.add(dedupKey);

        // Lark leave unit codes (see LarkUserApproval in _shared/lark.ts):
        //   1 = day, 2 = half-day, 0 = hour
        // Lark often omits `duration` on the wire even though it's typed as
        // required — that was why every leave was falling through to a blunt
        // inclusive-date count and rendering "1.0 days" for every half-day.
        const rawDuration = Number(lv.duration);
        const unitDays = lv.unit === 1
            ? rawDuration
            : lv.unit === 2
                ? rawDuration * 0.5
                : lv.unit === 0
                    ? rawDuration / 8
                    : NaN;

        let days: number;
        if (isFinite(unitDays) && unitDays > 0) {
          days = unitDays;
        } else {
          // Derive from the real clock window Lark gave us. Same-day leaves
          // honour partial-hour windows (09:30→14:30 → 5h/8 = 0.625d);
          // multi-day spans fall back to an inclusive date count since Lark's
          // times for those are usually bookend values, not hours worked.
          const startMs = toMs(lv.start_time);
          const endMs = toMs(lv.end_time);
          const validRange = isFinite(startMs) && isFinite(endMs) && endMs >= startMs;
          if (validRange && startDate === endDate) {
            const hours = (endMs - startMs) / (60 * 60 * 1000);
            days = hours > 0 ? hours / 8 : 1;
          } else if (validRange) {
            const dayMs = 24 * 60 * 60 * 1000;
            days = Math.max(1, Math.round((endMs - startMs) / dayMs) + 1);
          } else {
            days = 1;
          }
        }
        days = Math.max(0.01, Math.round(days * 100) / 100);

        const { data: existing } = await supabase
          .from('leave_requests')
          .select('id')
          .eq('employee_id', employeeId)
          .eq('leave_type_id', ltId)
          .eq('start_date', startDate)
          .eq('end_date', endDate)
          .maybeSingle();

        const payload = {
          employee_id: employeeId,
          leave_type_id: ltId,
          start_date: startDate,
          end_date: endDate,
          leave_days: days,
          // Preserve Lark's raw inputs so the UI can render "4 hrs" / "1 day"
          // / "0.5 half-days" instead of always collapsing to a day count.
          lark_leave_unit: Number.isFinite(lv.unit) ? lv.unit : null,
          lark_leave_duration: Number.isFinite(rawDuration) && rawDuration > 0 ? rawDuration : null,
          status: 'APPROVED',
          approved_at: new Date().toISOString(),
          reason: `Synced from Lark (${lv.uniq_id})`,
        };
        const tag = `leave ${lv.uniq_id ?? dedupKey} (${startDate}→${endDate})`;
        if (existing) {
          const { error } = await supabase.from('leave_requests').update(payload).eq('id', existing.id);
          if (error) { errors.push(`${tag}: ${error.message}`); continue; }
          updated++;
        } else {
          const { error } = await supabase.from('leave_requests').insert(payload);
          if (error) { errors.push(`${tag}: ${error.message}`); continue; }
          created++;
        }
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
// redeploy 1776241510 supabase functions deploy sync-lark-leaves
// redeploy 1776241866
