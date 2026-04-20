// Edge Function: sync-lark-attendance
// supabase functions deploy sync-lark-attendance
// Pulls attendance user_tasks from Lark for a date range and upserts them into
// public.attendance_day_records with proper classification:
//
//   • PRESENT / HALF_DAY  — has clock records
//   • ABSENT              — Lark Lack/Lack on a workday with no records
//   • ON_LEAVE            — Lark supplement = "Leave" (or covered by approval)
//   • REST_DAY            — no shift assigned (shift_id 0/-1) and not a holiday
//   • HOLIDAY             — date matches calendar_events
//
// Day type is set from holiday calendar (REGULAR_HOLIDAY / SPECIAL_HOLIDAY /
// SPECIAL_WORKING) when applicable; otherwise REST_DAY when no shift, else
// WORKDAY. Mirrors the classification in payrollos/lib/payroll/day-type-resolver
// + payrollos/app/actions/lark-sync.ts.
//
// Input (POST JSON):
//   { "company_id": "uuid", "from": "2026-04-01", "to": "2026-04-15" }
// If from/to omitted, defaults to (today - 1) → today.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import {
  authFromEnv,
  queryUserTasks,
  queryUserDailyShifts,
  queryUserApprovals,
  logSyncStart,
  logSyncProgress,
  logSyncFinish,
  userIdFromAuthHeader,
  json,
  type LarkUserTask,
  type LarkUserDailyShift,
  type LarkUserApproval,
} from '../_shared/lark.ts';

interface Body { company_id?: string; from?: string; to?: string }

function toYYYYMMDD(d: Date): string {
  return `${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, '0')}${String(d.getDate()).padStart(2, '0')}`;
}

function dayToDate(day: string | number): string {
  const s = String(day);
  return `${s.slice(0, 4)}-${s.slice(4, 6)}-${s.slice(6, 8)}`;
}

function checkTimeToISO(raw: string | undefined): string | null {
  if (!raw) return null;
  // Lark returns unix SECONDS as string for check_time
  const n = parseInt(raw, 10);
  if (isNaN(n)) return null;
  const ms = n < 1_000_000_000_000 ? n * 1000 : n;
  return new Date(ms).toISOString();
}

interface Classification {
  status: 'PRESENT' | 'HALF_DAY' | 'ABSENT' | 'ON_LEAVE' | 'REST_DAY' | 'HOLIDAY';
  dayType: 'WORKDAY' | 'REST_DAY' | 'REGULAR_HOLIDAY' | 'SPECIAL_HOLIDAY' | 'SPECIAL_WORKING';
  holidayName: string | null;
  firstIn: string | null;
  lastOut: string | null;
  overrideReasonCode: string | null;
}

/** Classify a single Lark task into our (status, day_type) pair.
 *  Returns null when the task should be skipped (e.g. Todo / future date). */
function classifyTask(
  task: LarkUserTask,
  event: { dayType: Classification['dayType']; name: string } | undefined,
): Classification | null {
  // Aggregate record signals — most days have one record but Lark can split
  // a day into multiple punch slots. Take the union of signals.
  let firstIn: string | null = null;
  let lastOut: string | null = null;
  let hasTodo = false;
  let hasLeave = false;
  let allNoNeedCheck = true;
  let allLack = true;
  let recordCount = 0;
  let supplement: string | null = null;

  for (const rec of task.records ?? []) {
    recordCount++;
    const ci = rec.check_in_result ?? '';
    const co = rec.check_out_result ?? '';
    const cis = rec.check_in_result_supplement ?? '';
    const cos = rec.check_out_result_supplement ?? '';
    if (ci === 'Todo' || co === 'Todo') hasTodo = true;
    if (cis === 'Leave' || cos === 'Leave') {
      hasLeave = true;
      supplement = 'Leave';
    } else if ((cis || cos) && !supplement) {
      supplement = cis || cos;
    }
    if (ci !== 'NoNeedCheck' || co !== 'NoNeedCheck') allNoNeedCheck = false;
    if (ci !== 'Lack' || co !== 'Lack') allLack = false;
    const inT = checkTimeToISO(rec.check_in_record?.check_time);
    const outT = checkTimeToISO(rec.check_out_record?.check_time);
    if (inT && (firstIn === null || inT < firstIn)) firstIn = inT;
    if (outT && (lastOut === null || outT > lastOut)) lastOut = outT;
  }
  if (recordCount === 0) {
    allNoNeedCheck = false;
    allLack = false;
  }

  // Future / not-yet-finalized data — skip the upsert entirely.
  if (hasTodo) return null;

  // shift_id "0" / "-1" / empty = no work scheduled.
  const sid = task.shift_id;
  const noShift = !sid || sid === '0' || sid === '-1';

  // -------- day_type --------
  // Holiday calendar wins. Otherwise REST_DAY when no shift, else WORKDAY.
  // Special case: if Lark assigned a shift on a holiday-rest-day combo, the
  // event still describes the legal day type — keep it.
  let dayType: Classification['dayType'];
  let holidayName: string | null = null;
  if (event) {
    dayType = event.dayType;
    holidayName = event.name;
  } else if (noShift) {
    dayType = 'REST_DAY';
  } else {
    dayType = 'WORKDAY';
  }

  // -------- attendance_status --------
  let status: Classification['status'];
  if (hasLeave) {
    status = 'ON_LEAVE';
  } else if (firstIn || lastOut) {
    // Even on a rest day / holiday, if they actually clocked in we record
    // PRESENT/HALF_DAY so OT pay can be computed off real punches.
    status = (firstIn && lastOut) ? 'PRESENT' : 'HALF_DAY';
  } else if (recordCount > 0 && allNoNeedCheck) {
    // Lark says "no check needed" for every slot — rest day or holiday.
    if (event) {
      status = 'HOLIDAY';
    } else {
      status = 'REST_DAY';
      // Force day_type to REST_DAY to stay internally consistent.
      if (dayType === 'WORKDAY') dayType = 'REST_DAY';
    }
  } else if (recordCount > 0 && allLack) {
    status = 'ABSENT';
  } else if (recordCount === 0) {
    // No records at all — fall back to day_type to decide. Lark does emit
    // user_task rows for rest days with NoNeedCheck records, so an empty
    // records array usually means "scheduled but missed".
    status = noShift ? 'REST_DAY' : 'ABSENT';
  } else {
    // Mixed signals (some Lack, some NoNeedCheck) and no clock records —
    // most conservative read is ABSENT on a workday.
    status = noShift ? 'REST_DAY' : 'ABSENT';
  }

  return {
    status,
    dayType,
    holidayName,
    firstIn,
    lastOut,
    overrideReasonCode: supplement,
  };
}

interface OtApproval {
  earlyInApproved: boolean;
  lateOutApproved: boolean;
  approvedOtMinutes: number | null;
}

/** Squeeze every OT approval for the day into the flag/duration triple we
 *  persist. Lark can return multiple `overtime_works` entries per day (e.g.
 *  an early-in OT AND a late-out OT filed separately); the old code only
 *  consumed the first, which silently dropped one half. We now sum
 *  durations and set whichever side(s) of noon the entries fall on.
 *
 *  The time strings are local (Lark ships "yyyy-MM-dd HH:mm:ss" without a
 *  timezone) — we parse them as UTC for consistency. The offset doesn't
 *  affect `end - start` duration math; for the noon heuristic it's close
 *  enough since Lark users are usually in a single fixed timezone. */
function resolveOt(approval: LarkUserApproval | undefined): OtApproval {
  const empty: OtApproval = {
    earlyInApproved: false,
    lateOutApproved: false,
    approvedOtMinutes: null,
  };
  if (!approval || !approval.overtime_works?.length) return empty;
  let earlyInApproved = false;
  let lateOutApproved = false;
  let total = 0;
  for (const ot of approval.overtime_works) {
    const start = new Date(ot.start_time.replace(' ', 'T') + 'Z');
    const end = new Date(ot.end_time.replace(' ', 'T') + 'Z');
    if (isNaN(start.getTime()) || isNaN(end.getTime())) continue;
    const minutes = Math.max(
      0,
      Math.round((end.getTime() - start.getTime()) / 60000),
    );
    if (minutes === 0) continue;
    total += minutes;
    if (start.getUTCHours() < 12) {
      earlyInApproved = true;
    } else {
      lateOutApproved = true;
    }
  }
  if (total === 0) return empty;
  return {
    earlyInApproved,
    lateOutApproved,
    approvedOtMinutes: total,
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

  const now = new Date();
  let to = body.to ? new Date(body.to) : now;
  if (to > now) to = now;
  const from = body.from
    ? new Date(body.from)
    : new Date(to.getTime() - 24 * 60 * 60 * 1000);

  const syncedById = userIdFromAuthHeader(req);
  const logId = await logSyncStart(supabase, {
    companyId,
    syncType: 'ATTENDANCE',
    dateFrom: from.toISOString().slice(0, 10),
    dateTo: to.toISOString().slice(0, 10),
    syncedById,
  });

  const errors: string[] = [];
  let created = 0, updated = 0, skipped = 0, total = 0;

  try {
    const auth = authFromEnv();

    // 1. Employees (Lark-linked)
    const { data: emps, error: empErr } = await supabase
      .from('employees')
      .select('id, lark_user_id')
      .eq('company_id', companyId)
      .is('deleted_at', null)
      .not('lark_user_id', 'is', null);
    if (empErr) throw new Error(`employees select: ${empErr.message}`);
    const empByLarkId = new Map<string, string>();
    for (const e of emps ?? []) empByLarkId.set(e.lark_user_id as string, e.id as string);
    const larkUserIds = Array.from(empByLarkId.keys());
    if (larkUserIds.length === 0) {
      await logSyncFinish(supabase, logId, { total: 0, created, updated, skipped, errors });
      return json({ ok: true, total: 0, note: 'no employees linked to Lark yet' });
    }

    // 2. Shift templates — map Lark shift_id → local shift_templates.id so we
    //    can persist shift_template_id on each attendance row.
    const { data: shiftRows, error: shiftErr } = await supabase
      .from('shift_templates')
      .select('id, lark_shift_id')
      .eq('company_id', companyId)
      .not('lark_shift_id', 'is', null);
    if (shiftErr) throw new Error(`shift_templates select: ${shiftErr.message}`);
    const shiftByLarkId = new Map<string, string>();
    for (const s of shiftRows ?? []) {
      if (s.lark_shift_id) shiftByLarkId.set(String(s.lark_shift_id), s.id as string);
    }

    // 3. Holiday calendar events for the entire range — single query, then
    //    keyed by ISO date. Used to set day_type / holiday_name.
    const fromIso = from.toISOString().slice(0, 10);
    const toIso = to.toISOString().slice(0, 10);
    const { data: calRows, error: calErr } = await supabase
      .from('calendar_events')
      .select('date, name, day_type, holiday_calendars!inner(company_id, is_active)')
      .eq('holiday_calendars.company_id', companyId)
      .eq('holiday_calendars.is_active', true)
      .gte('date', fromIso)
      .lte('date', toIso);
    if (calErr) throw new Error(`calendar_events select: ${calErr.message}`);
    type EventEntry = { dayType: Classification['dayType']; name: string };
    const eventMap = new Map<string, EventEntry>();
    for (const r of calRows ?? []) {
      eventMap.set(
        r.date as string,
        { dayType: r.day_type as EventEntry['dayType'], name: r.name as string },
      );
    }

    // 3. Split range into 30-day windows (Lark caps at 30).
    const windows: Array<[Date, Date]> = [];
    const MS = 24 * 60 * 60 * 1000;
    let cursor = new Date(from);
    while (cursor <= to) {
      const winEnd = new Date(Math.min(cursor.getTime() + 29 * MS, to.getTime()));
      windows.push([new Date(cursor), winEnd]);
      cursor = new Date(winEnd.getTime() + MS);
    }

    for (const [winFrom, winTo] of windows) {
      const fromDay = toYYYYMMDD(winFrom);
      const toDay = toYYYYMMDD(winTo);

      // Fetch tasks + per-day shifts + approvals for this window in parallel.
      // Daily-shifts is the canonical source for "what shift is scheduled on
      // this day for this user" (see queryUserDailyShifts); tasks' own
      // shift_id can fall back to a group default when the roster is
      // fuzzy. We try daily-shifts first and fall back to the task value.
      const [tasks, dailyShifts, approvals] = await Promise.all([
        queryUserTasks(auth, larkUserIds, fromDay, toDay),
        queryUserDailyShifts(auth, larkUserIds, fromDay, toDay).catch((e) => {
          errors.push(`daily_shifts fetch (${fromDay}-${toDay}): ${e}`);
          return [] as LarkUserDailyShift[];
        }),
        queryUserApprovals(auth, larkUserIds, fromDay, toDay).catch((e) => {
          // Approvals are optional — don't fail the whole sync.
          errors.push(`approvals fetch (${fromDay}-${toDay}): ${e}`);
          return [] as LarkUserApproval[];
        }),
      ]);

      // Lookup keys: "larkUserId|YYYYMMDD".
      //
      // We query user_tasks / user_approvals / user_daily_shifts with
      // `employee_type=employee_id`. Lark's responses populate `employee_id`
      // for some records and only `user_id` for others — and the field
      // populated for the SAME employee can differ between endpoints. Naively
      // keying by `employee_id ?? user_id` makes lookups silently miss
      // whenever one endpoint returns user_id and another returns
      // employee_id, which silently drops shift assignments for whole
      // employees (Gyllian, Jayr, Evan, Noemi all hit this).
      //
      // Fix: index the auxiliary maps under BOTH ids when present, then look
      // up by either when consuming a task row.
      const keyOf = (uid: string, day: string) => `${uid}|${day}`;

      function indexBoth<T>(
        map: Map<string, T>,
        rec: { employee_id?: string; user_id?: string },
        day: string,
        value: T,
      ) {
        if (rec.employee_id) map.set(keyOf(rec.employee_id, day), value);
        if (rec.user_id && rec.user_id !== rec.employee_id) {
          map.set(keyOf(rec.user_id, day), value);
        }
      }

      function lookupBoth<T>(
        map: Map<string, T>,
        employee_id: string | undefined,
        user_id: string | undefined,
        day: string,
      ): T | undefined {
        if (employee_id) {
          const v = map.get(keyOf(employee_id, day));
          if (v !== undefined) return v;
        }
        if (user_id) {
          const v = map.get(keyOf(user_id, day));
          if (v !== undefined) return v;
        }
        return undefined;
      }

      const approvalByKey = new Map<string, LarkUserApproval>();
      for (const a of approvals) {
        const dayStr = String(a.date);
        if (!dayStr) continue;
        indexBoth(approvalByKey, a, dayStr, a);
      }

      // Per-day scheduled-shift lookup. `is_clear_schedule: true` means Lark
      // explicitly cleared the roster for that day (rest day / day off) —
      // treat as no shift.
      const dailyShiftByKey = new Map<string, string>();
      // Track whether Lark returned ANY daily-shifts row per user, so we can
      // surface a clear warning when an employee gets attendance rows but
      // zero shift entries (typically a Lark group-config issue: "Fixed
      // Schedule" group whose shift only lives on the user_task fallback).
      const dailyShiftSeenByUser = new Set<string>();
      for (const ds of dailyShifts) {
        if (ds.employee_id) dailyShiftSeenByUser.add(ds.employee_id);
        if (ds.user_id) dailyShiftSeenByUser.add(ds.user_id);
        if (ds.is_clear_schedule) continue;
        const dayStr = String(ds.day);
        const sid = ds.shift_id;
        if (!dayStr || sid === undefined || sid === null) continue;
        const sidStr = String(sid);
        if (!sidStr || sidStr === '0' || sidStr === '-1') continue;
        indexBoth(dailyShiftByKey, ds, dayStr, sidStr);
      }

      total += tasks.length;

      // Pre-fetch existing rows to avoid N round-trips in the upsert loop.
      const empIdList = Array.from(empByLarkId.values());
      const { data: existing } = await supabase
        .from('attendance_day_records')
        .select('id, employee_id, attendance_date, is_locked')
        .in('employee_id', empIdList)
        .gte('attendance_date', dayToDate(fromDay))
        .lte('attendance_date', dayToDate(toDay));
      const existingByKey = new Map<string, { id: string; isLocked: boolean }>();
      for (const r of existing ?? []) {
        existingByKey.set(
          `${r.employee_id}|${r.attendance_date}`,
          { id: r.id as string, isLocked: !!r.is_locked },
        );
      }

      // Track which lark user IDs we saw in tasks but never in daily_shifts,
      // so we can warn the operator once per user (not per day).
      const warnedNoDailyShift = new Set<string>();

      for (const task of tasks) {
        // Skip OT records — only regular daily tasks should drive attendance.
        if (typeof task.task_shift_type === 'number' && task.task_shift_type !== 0) {
          skipped++;
          continue;
        }
        const larkEmpId = task.employee_id;
        const larkUserId = task.user_id;
        const larkId = larkEmpId ?? larkUserId ?? '';
        const employeeId = empByLarkId.get(larkId)
          ?? (larkUserId ? empByLarkId.get(larkUserId) : undefined);
        if (!employeeId) { skipped++; continue; }

        const date = dayToDate(task.day);
        const event = eventMap.get(date);
        const cls = classifyTask(task, event);
        if (!cls) { skipped++; continue; } // Todo / future

        const existingRow = existingByKey.get(`${employeeId}|${date}`);
        if (existingRow?.isLocked) {
          skipped++;
          continue;
        }

        const ot = resolveOt(
          lookupBoth(approvalByKey, larkEmpId, larkUserId, String(task.day)),
        );

        // Resolve the day's Lark shift id. Priority:
        //   1. user_daily_shifts entry for (user, day) — authoritative
        //      roster, reflects per-day assignments.
        //   2. task.shift_id — falls back here when daily_shifts didn't
        //      return a row for this day (e.g. no schedule configured).
        // Either path produces a Lark shift id string, which we then map to
        // our local `shift_templates.id`. Null = rest day / no match.
        const dailyHit = lookupBoth(
          dailyShiftByKey, larkEmpId, larkUserId, String(task.day),
        );
        const larkShiftId = dailyHit ?? (() => {
          const sid = task.shift_id;
          if (!sid || sid === '0' || sid === '-1') return null;
          return String(sid);
        })();
        const shiftTemplateId = larkShiftId
          ? shiftByLarkId.get(larkShiftId) ?? null
          : null;

        // When we have a Lark shift id but can't map it locally, surface
        // the id in the error log so the operator knows to sync shifts
        // first. Soft — don't block the row.
        if (larkShiftId && shiftTemplateId === null) {
          errors.push(
            `${employeeId}|${date}: unmapped lark_shift_id=${larkShiftId} — run Sync Shifts`,
          );
        }

        // Diagnostic: this employee has tasks but Lark never returned them
        // in user_daily_shifts AND task.shift_id is also empty. Almost
        // always means their attendance group in Lark isn't roster-driven
        // (or the user is missing from any group). Warn once per user so
        // the operator can fix the Lark setup.
        if (
          larkShiftId === null &&
          !warnedNoDailyShift.has(larkId) &&
          larkId &&
          !dailyShiftSeenByUser.has(larkId) &&
          (!larkUserId || !dailyShiftSeenByUser.has(larkUserId))
        ) {
          warnedNoDailyShift.add(larkId);
          errors.push(
            `${employeeId}: no shift returned by Lark (user_daily_shifts empty AND task.shift_id empty) — check the employee's Lark attendance group / roster`,
          );
        }

        const payload: Record<string, unknown> = {
          employee_id: employeeId,
          attendance_date: date,
          actual_time_in: cls.firstIn,
          actual_time_out: cls.lastOut,
          attendance_status: cls.status,
          day_type: cls.dayType,
          holiday_name: cls.holidayName,
          shift_template_id: shiftTemplateId,
          source_type: 'LARK_IMPORT',
          source_record_id: task.result_id,
          early_in_approved: ot.earlyInApproved,
          late_out_approved: ot.lateOutApproved,
          approved_ot_minutes: ot.approvedOtMinutes,
          override_reason_code: cls.overrideReasonCode,
        };

        if (existingRow) {
          const { error } = await supabase
            .from('attendance_day_records')
            .update(payload)
            .eq('id', existingRow.id);
          if (error) { errors.push(`${employeeId}|${date}: ${error.message}`); continue; }
          updated++;
        } else {
          const { error } = await supabase
            .from('attendance_day_records')
            .insert(payload);
          if (error) { errors.push(`${employeeId}|${date}: ${error.message}`); continue; }
          created++;
        }
      }
      await logSyncProgress(supabase, logId, { total, created, updated, skipped });
    }

    await logSyncFinish(supabase, logId, { total, created, updated, skipped, errors });
    return json({ ok: true, total, created, updated, skipped, errors });
  } catch (e) {
    errors.push(String(e));
    await logSyncFinish(supabase, logId, { total, created, updated, skipped, errors });
    return json({ ok: false, error: String(e) }, 500);
  }
});
