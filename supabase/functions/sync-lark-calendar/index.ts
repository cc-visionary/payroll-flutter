// Edge Function: sync-lark-calendar
// Pulls holiday events from a Lark calendar and upserts them into
// holiday_calendars + calendar_events (source='LARK'). Manually-added rows
// (source='MANUAL') are never touched. Updates holiday_calendars.last_synced_at.
//
// Input (POST JSON):
//   { "company_id": "uuid", "year": 2026, "calendar_id": "<lark-cal-id>" }
// calendar_id defaults to env LARK_HOLIDAY_CALENDAR_ID.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import {
  authFromEnv,
  listCalendarEvents,
  parseHolidaySummary,
  logSyncStart,
  logSyncFinish,
  userIdFromAuthHeader,
  json,
} from '../_shared/lark.ts';

interface Body { company_id?: string; year?: number; calendar_id?: string }

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
  const year = body.year ?? new Date().getFullYear();
  const larkCalId = body.calendar_id ?? Deno.env.get('LARK_HOLIDAY_CALENDAR_ID');
  if (!larkCalId) return json({ error: 'calendar_id required (or set LARK_HOLIDAY_CALENDAR_ID)' }, 400);

  const syncedById = userIdFromAuthHeader(req);
  const logId = await logSyncStart(supabase, {
    companyId,
    syncType: 'HOLIDAY',
    dateFrom: `${year}-01-01`,
    dateTo: `${year}-12-31`,
    syncedById,
  });

  const errors: string[] = [];
  let created = 0, updated = 0, skipped = 0, total = 0;

  try {
    // Ensure holiday_calendar row for this company+year
    let { data: hc } = await supabase
      .from('holiday_calendars')
      .select('id')
      .eq('company_id', companyId)
      .eq('year', year)
      .maybeSingle();
    if (!hc) {
      const { data, error } = await supabase
        .from('holiday_calendars')
        .insert({ company_id: companyId, year, name: `${year} Holidays` })
        .select('id')
        .single();
      if (error) throw new Error(`holiday_calendars insert: ${error.message}`);
      hc = data;
    }
    const calendarId = hc!.id as string;

    const auth = authFromEnv();
    const from = new Date(year, 0, 1);
    const to = new Date(year, 11, 31, 23, 59, 59);
    const events = await listCalendarEvents(auth, larkCalId, from, to);
    total = events.length;

    for (const ev of events) {
      const parsed = parseHolidaySummary(ev.summary);
      if (!parsed) { skipped++; continue; }
      const dateStr = ev.start_time?.date
        ?? (ev.start_time?.timestamp
              ? new Date(parseInt(ev.start_time.timestamp, 10) * 1000).toISOString().slice(0, 10)
              : null);
      if (!dateStr) { skipped++; continue; }

      const { data: existing } = await supabase
        .from('calendar_events')
        .select('id, source')
        .eq('calendar_id', calendarId)
        .eq('date', dateStr)
        .maybeSingle();

      if (existing && existing.source === 'MANUAL') { skipped++; continue; }

      const payload = {
        calendar_id: calendarId,
        date: dateStr,
        name: parsed.name,
        day_type: parsed.dayType,
        source: 'LARK',
      };

      if (existing) {
        const { error } = await supabase.from('calendar_events').update(payload).eq('id', existing.id);
        if (error) { errors.push(`${dateStr}: ${error.message}`); continue; }
        updated++;
      } else {
        const { error } = await supabase.from('calendar_events').insert(payload);
        if (error) { errors.push(`${dateStr}: ${error.message}`); continue; }
        created++;
      }
    }

    // Stamp last_synced_at
    await supabase
      .from('holiday_calendars')
      .update({ last_synced_at: new Date().toISOString() })
      .eq('id', calendarId);

    await logSyncFinish(supabase, logId, { total, created, updated, skipped, errors });
    return json({ ok: true, total, created, updated, skipped, errors });
  } catch (e) {
    errors.push(String(e));
    await logSyncFinish(supabase, logId, { total, created, updated, skipped, errors });
    return json({ ok: false, error: String(e) }, 500);
  }
});
// redeploy 1776241510 supabase functions deploy sync-lark-calendar
// redeploy 1776241885
