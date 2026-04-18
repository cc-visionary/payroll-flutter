// Edge Function: sync-lark-ot
// Pulls approved overtime_works from Lark's user_approvals and updates
// attendance_day_records.approved_ot_minutes + early_in_approved / late_out_approved.
// Creates the day record if it doesn't exist yet.
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

function toMs(v: string | number): number {
  if (typeof v === 'number') return v;
  return /^\d+$/.test(v) ? parseInt(v, 10) : new Date(v).getTime();
}

function toISODate(v: string | number): string {
  return new Date(toMs(v)).toISOString().slice(0, 10);
}

function hhmmToMinutes(hhmm: string): number {
  const [h, m] = hhmm.split(':').map((s) => parseInt(s, 10));
  return h * 60 + (m || 0);
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
  if (to > now) to = now;
  const from = body.from ? new Date(body.from) : new Date(to.getTime() - 30 * 24 * 60 * 60 * 1000);

  const syncedById = userIdFromAuthHeader(req);
  const logId = await logSyncStart(supabase, {
    companyId,
    syncType: 'OT',
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
      .select('id, lark_user_id, role_scorecard_id')
      .eq('company_id', companyId)
      .is('deleted_at', null)
      .not('lark_user_id', 'is', null);
    const empByLarkId = new Map<string, { id: string; scorecardId: string | null }>();
    for (const e of emps ?? []) {
      empByLarkId.set(e.lark_user_id as string, {
        id: e.id as string,
        scorecardId: (e.role_scorecard_id ?? null) as string | null,
      });
    }
    const larkUserIds = Array.from(empByLarkId.keys());

    // Pull scorecard → shift to derive shift start/end for early-in / late-out inference
    const { data: scorecards } = await supabase
      .from('role_scorecards')
      .select('id, shift_template_id')
      .in('id', Array.from(new Set(Array.from(empByLarkId.values()).map((v) => v.scorecardId).filter(Boolean))) as string[]);
    const scToShift = new Map<string, string>();
    for (const s of scorecards ?? []) {
      if (s.shift_template_id) scToShift.set(s.id as string, s.shift_template_id as string);
    }
    const { data: shifts } = await supabase
      .from('shift_templates')
      .select('id, start_time, end_time');
    const shiftTimes = new Map<string, { startMin: number; endMin: number }>();
    for (const s of shifts ?? []) {
      shiftTimes.set(s.id as string, {
        startMin: hhmmToMinutes(String(s.start_time).slice(0, 5)),
        endMin: hhmmToMinutes(String(s.end_time).slice(0, 5)),
      });
    }

    if (larkUserIds.length === 0) {
      await logSyncFinish(supabase, logId, { total: 0, created, updated, skipped, errors });
      return json({ ok: true, total: 0, note: 'no employees linked to Lark' });
    }

    const approvals = await queryUserApprovals(auth, larkUserIds, toYYYYMMDD(from), toYYYYMMDD(to));

    for (const ua of approvals) {
      const emp = empByLarkId.get(ua.employee_id ?? ua.user_id ?? '');
      if (!emp) continue;
      for (const ot of ua.overtime_works ?? []) {
        total++;
        const date = toISODate(ot.start_time);
        // Lark overtime_works.unit: 1=days, 2=hours, 3=half-days. Old code
        // treated unit=1 as hours and the else branch as already-minutes,
        // which fed fractional hours like 0.5 / 0.183 straight into the
        // integer column and threw "invalid input syntax for type integer".
        const rawDuration = Number(ot.duration);
        const minutesPerWorkday = 8 * 60;
        const minutesRaw = ot.unit === 1
            ? rawDuration * minutesPerWorkday
            : ot.unit === 3
                ? rawDuration * (minutesPerWorkday / 2)
                : rawDuration * 60; // unit=2 (hours) and default fallback
        const otMinutes = Math.round(minutesRaw);
        if (!isFinite(otMinutes) || otMinutes <= 0) {
          errors.push(`OT ${emp.id.slice(-12)}|${date}: cannot derive minutes from unit=${ot.unit} duration=${ot.duration}`);
          continue;
        }

        // Derive flags vs shift times
        let earlyIn = false, lateOut = false;
        const shiftId = emp.scorecardId ? scToShift.get(emp.scorecardId) : undefined;
        const st = shiftId ? shiftTimes.get(shiftId) : undefined;
        if (st) {
          const otStartMin = new Date(toMs(ot.start_time)).getUTCHours() * 60 +
                             new Date(toMs(ot.start_time)).getUTCMinutes();
          const otEndMin = new Date(toMs(ot.end_time)).getUTCHours() * 60 +
                           new Date(toMs(ot.end_time)).getUTCMinutes();
          if (otStartMin < st.startMin) earlyIn = true;
          if (otEndMin > st.endMin) lateOut = true;
        }

        const { data: existing } = await supabase
          .from('attendance_day_records')
          .select('id, approved_ot_minutes')
          .eq('employee_id', emp.id)
          .eq('attendance_date', date)
          .maybeSingle();

        const otPatch = {
          approved_ot_minutes: otMinutes,
          early_in_approved: earlyIn,
          late_out_approved: lateOut,
        };

        const tag = `OT ${emp.id.slice(-12)}|${date}`;
        if (existing) {
          const { error } = await supabase
            .from('attendance_day_records')
            .update(otPatch)
            .eq('id', existing.id);
          if (error) { errors.push(`${tag}: ${error.message}`); continue; }
          updated++;
        } else {
          const { error } = await supabase.from('attendance_day_records').insert({
            employee_id: emp.id,
            attendance_date: date,
            day_type: 'WORKDAY',
            source_type: 'LARK_IMPORT',
            attendance_status: 'PRESENT',
            ...otPatch,
          });
          if (error) {
            // Race against the attendance sync (or any other inserter): the row
            // appeared between our maybeSingle() and our insert(). Refetch and
            // patch only the OT fields so we don't overwrite actual times.
            const msg = (error.message || '').toLowerCase();
            if (msg.includes('duplicate') || msg.includes('unique')) {
              const { data: raced } = await supabase
                .from('attendance_day_records')
                .select('id')
                .eq('employee_id', emp.id)
                .eq('attendance_date', date)
                .maybeSingle();
              if (raced) {
                const { error: upErr } = await supabase
                  .from('attendance_day_records')
                  .update(otPatch)
                  .eq('id', raced.id);
                if (upErr) { errors.push(`${tag}: ${upErr.message}`); continue; }
                updated++;
                continue;
              }
            }
            errors.push(`${tag}: ${error.message}`);
            continue;
          }
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
// redeploy 1776241510 supabase functions deploy sync-lark-ot
// redeploy 1776241871
