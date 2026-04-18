// Edge Function: sync-lark-shifts
// Pulls shift templates from Lark and upserts into public.shift_templates.
// Uses lark_shift_id as the stable external key; if a row with the same
// shift_name+company_id already exists (manual), it's linked to the Lark row.
//
// Input (POST JSON):
//   { "company_id": "uuid" }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import {
  authFromEnv,
  listShifts,
  logSyncStart,
  logSyncFinish,
  userIdFromAuthHeader,
  json,
  type LarkShift,
} from '../_shared/lark.ts';

interface Body { company_id?: string }

function toTime(hhmm: string): string {
  // Accepts "HHmm" or "HH:mm" → "HH:mm:00".
  //
  // Lark encodes "1am the next day" as "25:00" on overnight shifts. Postgres
  // `time` only permits 00:00:00..24:00:00, so hours >= 24 are wrapped back
  // into range (25:00 → 01:00). The overnight flag on the row — computed in
  // minutesBetween — preserves the "next day" semantics so the engine still
  // builds the correct shift window for attendance comparisons.
  const clean = hhmm.replace(':', '').padStart(4, '0');
  let hh = parseInt(clean.slice(0, 2), 10);
  const mm = clean.slice(2, 4);
  if (hh >= 24) hh -= 24;
  return `${String(hh).padStart(2, '0')}:${mm}:00`;
}

function minutesBetween(startHHmm: string, endHHmm: string): { minutes: number; overnight: boolean } {
  // Lark ships two overnight encodings:
  //   (a) end < start, e.g. start=1600 end=0100 (wrap form)
  //   (b) end >= 24:00, e.g. start=1600 end=2500 (extended-hours form)
  // We normalise both to { overnight: true, minutes: actual duration }.
  const s = startHHmm.replace(':', '').padStart(4, '0');
  const e = endHHmm.replace(':', '').padStart(4, '0');
  const sm = parseInt(s.slice(0, 2), 10) * 60 + parseInt(s.slice(2, 4), 10);
  let em = parseInt(e.slice(0, 2), 10) * 60 + parseInt(e.slice(2, 4), 10);
  let overnight = false;
  if (em >= 24 * 60) {
    // Extended-hours form — em already represents minutes past the start
    // day's midnight, no further correction needed.
    overnight = true;
  } else if (em <= sm) {
    // Wrap form — push em forward by 24h to compute the real span.
    overnight = true;
    em += 24 * 60;
  }
  return { minutes: em - sm, overnight };
}

function mapLarkShift(shift: LarkShift, companyId: string) {
  const firstPunch = shift.punch_time_rule?.[0];
  const startRaw = firstPunch?.on_time ?? '09:00';
  const endRaw = firstPunch?.off_time ?? '18:00';
  const { minutes: span, overnight } = minutesBetween(startRaw, endRaw);

  const firstRest = shift.rest_time_rule?.[0];
  let breakMinutes = 0;
  if (firstRest) {
    breakMinutes = minutesBetween(firstRest.rest_begin_time, firstRest.rest_end_time).minutes;
  } else if (span >= 6 * 60) {
    breakMinutes = 60; // sensible default for ≥ 6h
  }

  return {
    company_id: companyId,
    code: shift.shift_name,
    name: shift.shift_name,
    start_time: toTime(startRaw),
    end_time: toTime(endRaw),
    is_overnight: overnight,
    break_type: firstRest ? 'FIXED' : 'AUTO_DEDUCT',
    break_minutes: breakMinutes,
    break_start_time: firstRest ? toTime(firstRest.rest_begin_time) : null,
    break_end_time: firstRest ? toTime(firstRest.rest_end_time) : null,
    scheduled_work_minutes: span - breakMinutes,
    grace_minutes_late: firstPunch?.late_minutes_as_late ?? 0,
    grace_minutes_early_out: firstPunch?.early_minutes_as_early ?? 0,
    nd_start_time: '22:00:00',
    nd_end_time: '06:00:00',
    lark_shift_id: shift.shift_id,
    is_active: true,
  };
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

  const syncedById = userIdFromAuthHeader(req);
  const logId = await logSyncStart(supabase, {
    companyId,
    syncType: 'SHIFT',
    syncedById,
  });

  const errors: string[] = [];
  let created = 0, updated = 0, skipped = 0;

  try {
    const auth = authFromEnv();
    const rawShifts = await listShifts(auth);

    // Lark can theoretically return the same shift twice; dedupe so we don't
    // race ourselves into a unique(company_id, code) violation.
    const dedup = new Map<string, LarkShift>();
    for (const s of rawShifts) {
      dedup.set(s.shift_id || s.shift_name, s);
    }
    const shifts = Array.from(dedup.values());

    // Pull existing rows once to decide create vs update
    const { data: existing } = await supabase
      .from('shift_templates')
      .select('id, code, lark_shift_id')
      .eq('company_id', companyId);
    const byLarkId = new Map<string, string>();
    const byCode = new Map<string, string>();
    for (const r of existing ?? []) {
      if (r.lark_shift_id) byLarkId.set(r.lark_shift_id, r.id);
      if (r.code) byCode.set(r.code, r.id);
    }

    for (const s of shifts) {
      const payload = mapLarkShift(s, companyId);
      const existingId = byLarkId.get(s.shift_id) ?? byCode.get(s.shift_name);
      if (existingId) {
        const { error } = await supabase
          .from('shift_templates')
          .update(payload)
          .eq('id', existingId);
        if (error) { errors.push(`${s.shift_name}: ${error.message}`); continue; }
        updated++;
      } else {
        const { data: inserted, error } = await supabase
          .from('shift_templates')
          .insert(payload)
          .select('id')
          .single();
        if (error) { errors.push(`${s.shift_name}: ${error.message}`); continue; }
        // Refresh in-memory maps so a later iteration with the same shift_id or
        // shift_name resolves to UPDATE instead of a duplicate INSERT.
        if (inserted?.id) {
          if (s.shift_id) byLarkId.set(s.shift_id, inserted.id);
          if (s.shift_name) byCode.set(s.shift_name, inserted.id);
        }
        created++;
      }
    }

    await logSyncFinish(supabase, logId, {
      total: shifts.length,
      created, updated, skipped, errors,
    });

    return json({ ok: true, total: shifts.length, created, updated, errors });
  } catch (e) {
    errors.push(String(e));
    await logSyncFinish(supabase, logId, { total: 0, created, updated, skipped, errors });
    return json({ ok: false, error: String(e) }, 500);
  }
});
// redeploy 1776241510 supabase functions deploy sync-lark-shifts
// redeploy 1776241857
