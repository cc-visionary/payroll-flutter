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
import {
  detectEndDateConvention,
  expandHolidayDates,
} from '../_shared/holiday_span.ts';

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
  let created = 0, updated = 0, skipped = 0, deleted = 0, total = 0;

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

    // How this calendar expresses an all-day end date. Read off the batch
    // rather than assumed — see _shared/holiday_span.ts — and reported back
    // so the first run after a deploy says which way it read them.
    const convention = detectEndDateConvention(events);

    // Every date Lark still claims as a holiday, for the prune below.
    const larkDates = new Set<string>();

    for (const ev of events) {
      const parsed = parseHolidaySummary(ev.summary);
      if (!parsed) { skipped++; continue; }

      // A holiday can run several days (ASEAN Summit, Nov 16-18 2026). Each
      // day it covers needs its own row: payroll resolves day types per date.
      let dates: string[];
      try {
        dates = expandHolidayDates(ev.start_time, ev.end_time, convention);
      } catch (e) {
        errors.push(`${parsed.name}: ${e instanceof Error ? e.message : String(e)}`);
        continue;
      }
      if (dates.length === 0) { skipped++; continue; }

      for (const dateStr of dates) {
        const { data: existing } = await supabase
          .from('calendar_events')
          .select('id, source')
          .eq('calendar_id', calendarId)
          .eq('date', dateStr)
          .maybeSingle();

        if (existing && existing.source === 'MANUAL') { skipped++; continue; }

        // Counted even when the row is written below, so the prune never
        // deletes a date this sync just wrote.
        larkDates.add(dateStr);

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
    }

    // Drop LARK rows this calendar no longer claims — a holiday cancelled in
    // Lark, or a span that used to be read a day too long. Nothing else can:
    // the settings screen only offers Delete on MANUAL rows. MANUAL rows are
    // never touched, and the calendar row is per company+year, so this stays
    // inside the year being synced.
    //
    // Guarded on a non-empty set: a Lark call that comes back with nothing
    // (or whose events all failed to parse) must not wipe the year's
    // holidays.
    if (larkDates.size > 0) {
      const { data: larkRows } = await supabase
        .from('calendar_events')
        .select('id, date')
        .eq('calendar_id', calendarId)
        .eq('source', 'LARK');
      const staleIds = (larkRows ?? [])
        .filter((r) => !larkDates.has(r.date as string))
        .map((r) => r.id as string);
      if (staleIds.length > 0) {
        const { error } = await supabase
          .from('calendar_events')
          .delete()
          .in('id', staleIds);
        if (error) errors.push(`prune: ${error.message}`);
        else deleted = staleIds.length;
      }
    }

    // Stamp last_synced_at
    await supabase
      .from('holiday_calendars')
      .update({ last_synced_at: new Date().toISOString() })
      .eq('id', calendarId);

    await logSyncFinish(supabase, logId, { total, created, updated, skipped, errors });
    return json({
      ok: true,
      total,
      created,
      updated,
      skipped,
      deleted,
      endDateConvention: convention,
      errors,
    });
  } catch (e) {
    errors.push(String(e));
    await logSyncFinish(supabase, logId, { total, created, updated, skipped, errors });
    return json({ ok: false, error: String(e) }, 500);
  }
});
// redeploy 1776241510 supabase functions deploy sync-lark-calendar
// redeploy 1776241885
