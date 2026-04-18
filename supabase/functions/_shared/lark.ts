// Shared Lark Open Platform client (Feishu/Lark international).
// Edge Functions run in Deno, so we use the native fetch API — no SDK needed.
//
// Docs: https://open.larksuite.com/document/ (international)
//       https://open.feishu.cn/document/ (CN)
//
// Auth flow: app_id + app_secret → tenant_access_token (expires ~2h, cacheable).

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

const LARK_BASE = Deno.env.get('LARK_BASE_URL') ?? 'https://open.larksuite.com/open-apis';

export interface LarkAuth {
  appId: string;
  appSecret: string;
}

export function authFromEnv(): LarkAuth {
  const appId = Deno.env.get('LARK_APP_ID');
  const appSecret = Deno.env.get('LARK_APP_SECRET');
  if (!appId || !appSecret) {
    throw new Error('Missing LARK_APP_ID / LARK_APP_SECRET env vars.');
  }
  return { appId, appSecret };
}

let _tokenCache: { token: string; expiresAt: number } | null = null;

export async function tenantAccessToken(auth: LarkAuth): Promise<string> {
  if (_tokenCache && _tokenCache.expiresAt > Date.now() + 60_000) {
    return _tokenCache.token;
  }
  const res = await fetch(`${LARK_BASE}/auth/v3/tenant_access_token/internal`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
    body: JSON.stringify({ app_id: auth.appId, app_secret: auth.appSecret }),
  });
  if (!res.ok) {
    throw new Error(`Lark token fetch failed: ${res.status} ${await res.text()}`);
  }
  const body = await res.json();
  if (body.code !== 0) {
    throw new Error(`Lark token error ${body.code}: ${body.msg}`);
  }
  _tokenCache = {
    token: body.tenant_access_token as string,
    expiresAt: Date.now() + (body.expire as number) * 1000,
  };
  return _tokenCache.token;
}

export async function larkRequest<T = unknown>(
  auth: LarkAuth,
  path: string,
  init: RequestInit = {},
): Promise<T> {
  const token = await tenantAccessToken(auth);
  const res = await fetch(`${LARK_BASE}${path}`, {
    ...init,
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json; charset=utf-8',
      ...(init.headers ?? {}),
    },
  });
  const body = await res.json();
  if (!res.ok || body.code !== 0) {
    throw new Error(`Lark ${path} failed: ${body.code ?? res.status} ${body.msg ?? res.statusText}`);
  }
  return body.data as T;
}

// -----------------------------------------------------------------------------
// Contact — /contact/v3/department/list + /contact/v3/user/list
// -----------------------------------------------------------------------------
export interface LarkUser {
  user_id: string;
  open_id?: string;
  union_id?: string;
  employee_no?: string;
  name: string;
  email?: string;
  mobile?: string;
  department_ids?: string[];
}

export async function listContactUsers(auth: LarkAuth): Promise<LarkUser[]> {
  // Mirror payrollos/lib/lark/contact.ts: list departments (fetch_child) then
  // per-department list users. Dedup by user_id. user_id_type=user_id so the
  // returned `user_id` field is the stable tenant user id we store.
  const deptIds = await _listAllDepartmentIds(auth);
  const seen = new Set<string>();
  const out: LarkUser[] = [];
  for (const deptId of deptIds) {
    let pageToken: string | undefined;
    do {
      const qs = new URLSearchParams({
        department_id: deptId,
        department_id_type: 'department_id',
        user_id_type: 'user_id',
        page_size: '50',
      });
      if (pageToken) qs.set('page_token', pageToken);
      const data = await larkRequest<{ items?: LarkUser[]; has_more?: boolean; page_token?: string }>(
        auth,
        `/contact/v3/users?${qs}`,
      );
      for (const u of data.items ?? []) {
        const key = u.user_id ?? u.open_id ?? '';
        if (!key || seen.has(key)) continue;
        seen.add(key);
        out.push(u);
      }
      pageToken = data.has_more ? data.page_token : undefined;
    } while (pageToken);
  }
  return out;
}

async function _listAllDepartmentIds(auth: LarkAuth): Promise<string[]> {
  const all = new Set<string>(['0']); // '0' = root department
  let pageToken: string | undefined;
  do {
    const qs = new URLSearchParams({
      parent_department_id: '0',
      fetch_child: 'true',
      department_id_type: 'department_id',
      page_size: '50',
    });
    if (pageToken) qs.set('page_token', pageToken);
    const data = await larkRequest<{
      items?: Array<{ department_id: string }>;
      has_more?: boolean;
      page_token?: string;
    }>(auth, `/contact/v3/departments?${qs}`);
    for (const d of data.items ?? []) all.add(d.department_id);
    pageToken = data.has_more ? data.page_token : undefined;
  } while (pageToken);
  return Array.from(all);
}

// -----------------------------------------------------------------------------
// Attendance — shifts + user_tasks + user_approvals
// -----------------------------------------------------------------------------
export interface LarkShift {
  shift_id: string;
  shift_name: string;
  punch_times: number; // 1 or 2 (in/out)
  sub_shift_leader_ids?: string[];
  is_flexible?: boolean;
  flexible_minutes?: number;
  no_need_off?: boolean;
  punch_time_rule?: Array<{
    on_time: string; // HH:mm
    off_time: string; // HH:mm
    late_minutes_as_late?: number;
    late_minutes_as_lack?: number;
    on_advance_minutes?: number;
    off_delay_minutes?: number;
    early_minutes_as_early?: number;
    early_minutes_as_lack?: number;
  }>;
  late_off_late_on_rule?: Array<unknown>;
  rest_time_rule?: Array<{
    rest_begin_time: string;
    rest_end_time: string;
  }>;
}

export async function listShifts(auth: LarkAuth): Promise<LarkShift[]> {
  let pageToken: string | undefined;
  const out: LarkShift[] = [];
  do {
    const qs = new URLSearchParams({ page_size: '50' });
    if (pageToken) qs.set('page_token', pageToken);
    const data = await larkRequest<{
      shift_list?: LarkShift[];
      has_more?: boolean;
      page_token?: string;
    }>(auth, `/attendance/v1/shifts?${qs}`);
    out.push(...(data.shift_list ?? []));
    pageToken = data.has_more ? data.page_token : undefined;
  } while (pageToken);
  return out;
}

export interface LarkFlowRecord {
  check_time?: string; // unix seconds as string
  location_name?: string;
  comment?: string;
}

export interface LarkTaskRecord {
  check_in_record_id?: string;
  check_in_record?: LarkFlowRecord;
  check_out_record_id?: string;
  check_out_record?: LarkFlowRecord;
  // Lark check_in/check_out result codes:
  //   Normal | Early | Late | SeriousLate | Lack | NoNeedCheck | Todo
  check_in_result?: string;
  check_out_result?: string;
  // Override reason from approvals: Leave | Travel | ManagerModification | ...
  check_in_result_supplement?: string;
  check_out_result_supplement?: string;
  // Lark scheduled shift times for the slot — unix seconds as string. Useful
  // for distinguishing OT periods from regular work in approvals.
  check_in_shift_time?: string;
  check_out_shift_time?: string;
}

export interface LarkUserTask {
  result_id: string;
  employee_id?: string;
  user_id?: string;
  employee_name?: string;
  day: string | number; // yyyymmdd (usually numeric)
  group_id?: string;
  // shift_id "0" or "-1" or empty → no shift assigned (rest day).
  shift_id?: string;
  // 0 = regular work, 1 = overtime task. Skip OT tasks for attendance sync.
  task_shift_type?: number;
  records?: LarkTaskRecord[];
}

/** Query attendance user_tasks. Lark caps date range at 30 days, user count at 50. */
export async function queryUserTasks(
  auth: LarkAuth,
  userIds: string[],
  fromDay: string, // yyyymmdd
  toDay: string,
): Promise<LarkUserTask[]> {
  const out: LarkUserTask[] = [];
  for (let i = 0; i < userIds.length; i += 50) {
    const batch = userIds.slice(i, i + 50);
    const data = await larkRequest<{ user_task_results?: LarkUserTask[] }>(
      auth,
      '/attendance/v1/user_tasks/query?employee_type=employee_id&ignore_invalid_users=true&include_terminated_user=true',
      {
        method: 'POST',
        body: JSON.stringify({
          user_ids: batch,
          check_date_from: parseInt(fromDay, 10),
          check_date_to: parseInt(toDay, 10),
          need_overtime_result: true,
        }),
      },
    );
    out.push(...(data.user_task_results ?? []));
  }
  return out;
}

// -----------------------------------------------------------------------------
// Attendance — per-day shift assignment (authoritative roster)
// -----------------------------------------------------------------------------

/** One row per (user, day) with the shift Lark *scheduled* for that specific
 *  day. Distinct from `user_task.shift_id`, which can fall back to the
 *  employee's group default when the roster is thin. */
export interface LarkUserDailyShift {
  group_id?: string;
  shift_id?: string | number;
  user_id?: string;
  employee_id?: string;
  day: string | number;
  is_clear_schedule?: boolean;
}

/** Query per-day scheduled shifts. Use this as the primary source of
 *  `attendance_day_records.shift_template_id` — it reflects roster changes
 *  (e.g. "morning Mon-Fri, evening Sat-Sun") that `user_tasks.shift_id`
 *  sometimes flattens. */
export async function queryUserDailyShifts(
  auth: LarkAuth,
  userIds: string[],
  fromDay: string, // yyyymmdd
  toDay: string,
): Promise<LarkUserDailyShift[]> {
  const out: LarkUserDailyShift[] = [];
  for (let i = 0; i < userIds.length; i += 50) {
    const batch = userIds.slice(i, i + 50);
    const data = await larkRequest<{ user_daily_shifts?: LarkUserDailyShift[] }>(
      auth,
      '/attendance/v1/user_daily_shifts/query?employee_type=employee_id',
      {
        method: 'POST',
        body: JSON.stringify({
          user_ids: batch,
          check_date_from: parseInt(fromDay, 10),
          check_date_to: parseInt(toDay, 10),
        }),
      },
    );
    out.push(...(data.user_daily_shifts ?? []));
  }
  return out;
}

// -----------------------------------------------------------------------------
// Attendance — user_approvals (leaves + OT + trips, per user per date range)
// -----------------------------------------------------------------------------
export interface LarkUserApproval {
  user_id?: string;
  employee_id?: string;
  date: string; // yyyymmdd
  leaves?: Array<{
    uniq_id: string; // approval instance code
    leave_type_id?: string;
    start_time: string;
    end_time: string;
    unit: number; // 1 = day, 0 = hour, 2 = half-day
    duration: number;
    i18n_names?: Record<string, string>;
    default_locale?: string;
  }>;
  overtime_works?: Array<{
    approval_id: string;
    start_time: string;
    end_time: string;
    duration: number; // minutes or hours depending on unit
    unit: number;
    type: number; // 0=no rules, 1=comp leave, 2=OT pay
    category: number; // 1=workday, 2=day off, 3=holiday
  }>;
  trips?: Array<unknown>;
}

export async function queryUserApprovals(
  auth: LarkAuth,
  userIds: string[],
  fromDay: string,
  toDay: string,
): Promise<LarkUserApproval[]> {
  // Lark caps the date range at 30 days; chunk internally so callers don't need to.
  const windows = _splitInto30DayWindows(fromDay, toDay);
  const out: LarkUserApproval[] = [];
  // Pull PENDING (1) + APPROVED (2). Skip REJECTED (3) and CANCELED (4).
  const statuses = [1, 2];
  for (const [wF, wT] of windows) {
    for (let i = 0; i < userIds.length; i += 50) {
      const batch = userIds.slice(i, i + 50);
      for (const status of statuses) {
        const data = await larkRequest<{ user_approvals?: LarkUserApproval[] }>(
          auth,
          '/attendance/v1/user_approvals/query?employee_type=employee_id',
          {
            method: 'POST',
            body: JSON.stringify({
              user_ids: batch,
              check_date_from: parseInt(wF, 10),
              check_date_to: parseInt(wT, 10),
              status,
            }),
          },
        );
        out.push(...(data.user_approvals ?? []));
      }
    }
  }
  return out;
}

function _splitInto30DayWindows(fromDay: string, toDay: string): Array<[string, string]> {
  const toDate = (d: string) => new Date(
    parseInt(d.slice(0, 4), 10),
    parseInt(d.slice(4, 6), 10) - 1,
    parseInt(d.slice(6, 8), 10),
  );
  const toDay8 = (d: Date) => `${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, '0')}${String(d.getDate()).padStart(2, '0')}`;
  const MS = 24 * 60 * 60 * 1000;
  const start = toDate(fromDay);
  const end = toDate(toDay);
  const windows: Array<[string, string]> = [];
  let cursor = new Date(start);
  // Lark's 30-day cap is inclusive on both ends, so we chunk at 27 days
  // (= 28 calendar days inclusive) to leave a safe margin for DST/TZ edges.
  while (cursor <= end) {
    const winEnd = new Date(Math.min(cursor.getTime() + 27 * MS, end.getTime()));
    windows.push([toDay8(cursor), toDay8(winEnd)]);
    cursor = new Date(winEnd.getTime() + MS);
  }
  return windows;
}

// -----------------------------------------------------------------------------
// Approval — /approval/v4/instances (cash advances, reimbursements, etc.)
// -----------------------------------------------------------------------------
export interface LarkApprovalInstance {
  instance_code: string;
  approval_code: string;
  status: 'PENDING' | 'APPROVED' | 'REJECTED' | 'CANCELED' | 'DELETED';
  start_time: string | number;
  end_time?: string | number;
  user_id: string;
  open_id?: string;
  form?: string; // JSON-encoded form widget array
  serial_number?: string;
}

/** List approval instance codes for a given approval template within [from, to].
 *  Lark caps /approval/v4/instances/query at a 30-day window, so we chunk. */
export async function listApprovalInstances(
  auth: LarkAuth,
  approvalCode: string,
  from: Date,
  to: Date,
): Promise<string[]> {
  const MS = 24 * 60 * 60 * 1000;
  const out: string[] = [];
  let cursor = new Date(from);
  // Lark's /approval/v4/instances/query caps the range at 30 calendar days
  // inclusive. Chunk at 27 days to leave headroom for DST/TZ edges (29-day
  // chunks were observed to fail with 1390001 "exceeds 30 days").
  while (cursor <= to) {
    const winEnd = new Date(Math.min(cursor.getTime() + 27 * MS, to.getTime()));
    let pageToken: string | undefined;
    do {
      const qs = new URLSearchParams({ page_size: '100' });
      if (pageToken) qs.set('page_token', pageToken);
      const data = await larkRequest<{
        instance_list?: Array<{ instance?: { code?: string } }>;
        has_more?: boolean;
        page_token?: string;
      }>(auth, `/approval/v4/instances/query?${qs}`, {
        method: 'POST',
        body: JSON.stringify({
          approval_code: approvalCode,
          // Lark expects milliseconds as strings here.
          instance_start_time_from: cursor.getTime().toString(),
          instance_start_time_to: winEnd.getTime().toString(),
        }),
      });
      for (const row of data.instance_list ?? []) {
        const code = row.instance?.code;
        if (code) out.push(code);
      }
      pageToken = data.has_more ? data.page_token : undefined;
    } while (pageToken);
    cursor = new Date(winEnd.getTime() + MS);
  }
  return out;
}

export async function getApprovalInstance(
  auth: LarkAuth,
  instanceCode: string,
): Promise<LarkApprovalInstance> {
  return larkRequest<LarkApprovalInstance>(
    auth,
    `/approval/v4/instances/${instanceCode}`,
  );
}

/** Parse Lark approval form JSON (array of widgets). Returns flat {id→value} map. */
export function parseApprovalForm(formJson: string): Record<string, unknown> {
  try {
    const widgets = JSON.parse(formJson) as Array<{ id?: string; name?: string; value?: unknown; type?: string }>;
    const out: Record<string, unknown> = {};
    for (const w of widgets) {
      if (w.id) out[w.id] = w.value;
      if (w.name) out[w.name] = w.value;
    }
    return out;
  } catch {
    return {};
  }
}

// -----------------------------------------------------------------------------
// Calendar — event summary parsing + list events
// -----------------------------------------------------------------------------
export interface LarkCalendarEvent {
  event_id: string;
  summary?: string;
  start_time?: { date?: string; timestamp?: string };
  end_time?: { date?: string; timestamp?: string };
}

export async function listCalendarEvents(
  auth: LarkAuth,
  calendarId: string,
  from: Date,
  to: Date,
): Promise<LarkCalendarEvent[]> {
  const qs = new URLSearchParams({
    start_time: Math.floor(from.getTime() / 1000).toString(),
    end_time: Math.floor(to.getTime() / 1000).toString(),
    page_size: '500',
  });
  const data = await larkRequest<{ items?: LarkCalendarEvent[] }>(
    auth,
    `/calendar/v4/calendars/${calendarId}/events?${qs}`,
  );
  return data.items ?? [];
}

/** Parse Lark HR-Calendar event summaries → day_type + clean name.
 *
 *  Recognized parenthesized suffixes (case-insensitive substring on the suffix text):
 *    "Maundy Thursday (Regular Holiday)"              → REGULAR_HOLIDAY
 *    "Eidul Adha (Special Non-Working Holiday)"       → SPECIAL_HOLIDAY
 *    "EDSA Anniversary (Special Working Holiday)"     → SPECIAL_WORKING
 *    "New Year's Day (Regular)"                       → REGULAR_HOLIDAY (legacy short)
 *
 *  Legacy bracket prefixes still supported:
 *    "[REGULAR] Name", "[SPECIAL] Name", "[EXTRA]/[WORKING] Name"
 *
 *  Returns null for missing/blank summaries and for any event without a
 *  recognized type tag (employee leaves, miscellaneous events). Callers must
 *  treat null as "not a holiday — skip". */
export function parseHolidaySummary(summary: string | undefined | null): { dayType: string; name: string } | null {
  if (!summary) return null;
  const s = summary.trim();
  if (!s) return null;

  // Trailing parenthesized suffix — capture whatever's inside and classify by keyword.
  const parenMatch = s.match(/^(.+?)\s*\(([^)]+)\)\s*$/);
  if (parenMatch) {
    const name = parenMatch[1].trim();
    const suffix = parenMatch[2].toLowerCase();
    if (suffix.includes('regular')) {
      return { dayType: 'REGULAR_HOLIDAY', name };
    }
    if (suffix.includes('special')) {
      // Order matters: "non-working" must be tested before "working" so
      // "(Special Non-Working Holiday)" doesn't fall into SPECIAL_WORKING.
      const isNonWorking = suffix.includes('non-working') || suffix.includes('non working');
      if (isNonWorking) return { dayType: 'SPECIAL_HOLIDAY', name };
      if (suffix.includes('working')) return { dayType: 'SPECIAL_WORKING', name };
      return { dayType: 'SPECIAL_HOLIDAY', name };
    }
    // Parenthesized but not a holiday tag — fall through to null.
  }

  // Legacy prefix: "[REGULAR] Name" / "[SPECIAL] Name" / "[EXTRA] Name" / "[WORKING] Name"
  const pref = s.match(/^\[(REGULAR|SPECIAL|EXTRA|WORKING)\]\s*(.+)$/i);
  if (pref) {
    const kind = pref[1].toUpperCase();
    return {
      dayType: kind === 'REGULAR'
        ? 'REGULAR_HOLIDAY'
        : kind === 'SPECIAL'
        ? 'SPECIAL_HOLIDAY'
        : 'SPECIAL_WORKING',
      name: pref[2].trim(),
    };
  }

  return null;
}

// -----------------------------------------------------------------------------
// lark_sync_logs helpers — every sync function uses these
// -----------------------------------------------------------------------------
export interface SyncLogInput {
  companyId: string;
  syncType: string; // 'ATTENDANCE' | 'LEAVE' | 'OT' | 'CASH_ADVANCE' | 'REIMBURSEMENT' | 'HOLIDAY' | 'EMPLOYEE' | 'SHIFT'
  dateFrom?: string | null; // yyyy-mm-dd
  dateTo?: string | null;
  syncedById?: string | null;
}

export async function logSyncStart(
  supabase: SupabaseClient,
  input: SyncLogInput,
): Promise<string> {
  const row = {
    company_id: input.companyId,
    sync_type: input.syncType,
    date_from: input.dateFrom,
    date_to: input.dateTo,
    status: 'IN_PROGRESS',
    total_records: 0,
    created_count: 0,
    updated_count: 0,
    skipped_count: 0,
    error_count: 0,
    synced_by_id: input.syncedById,
    started_at: new Date().toISOString(),
  };
  const { data, error } = await supabase
    .from('lark_sync_logs')
    .insert(row)
    .select('id')
    .single();
  if (error) throw new Error(`lark_sync_logs insert: ${error.message}`);
  return data.id as string;
}

export interface SyncLogResult {
  total: number;
  created: number;
  updated: number;
  skipped?: number;
  errors: string[];
}

/** Update the IN_PROGRESS row with running counts so Realtime-subscribed clients
 *  can show live progress ("120 created, 30 updated..."). Call after each batch. */
export async function logSyncProgress(
  supabase: SupabaseClient,
  id: string,
  partial: { total?: number; created?: number; updated?: number; skipped?: number },
): Promise<void> {
  await supabase
    .from('lark_sync_logs')
    .update({
      total_records: partial.total ?? 0,
      created_count: partial.created ?? 0,
      updated_count: partial.updated ?? 0,
      skipped_count: partial.skipped ?? 0,
    })
    .eq('id', id);
}

export async function logSyncFinish(
  supabase: SupabaseClient,
  id: string,
  result: SyncLogResult,
): Promise<void> {
  await supabase
    .from('lark_sync_logs')
    .update({
      status: result.errors.length > 0
        ? (result.created + result.updated > 0 ? 'PARTIAL' : 'FAILED')
        : 'COMPLETED',
      total_records: result.total,
      created_count: result.created,
      updated_count: result.updated,
      skipped_count: result.skipped ?? 0,
      error_count: result.errors.length,
      error_details: result.errors.length ? result.errors : null,
      completed_at: new Date().toISOString(),
    })
    .eq('id', id);
}

/** Best-effort extraction of the caller's auth.users.id from a Bearer JWT. */
export function userIdFromAuthHeader(req: Request): string | null {
  const h = req.headers.get('Authorization') ?? '';
  const m = h.match(/^Bearer\s+(.+)$/i);
  if (!m) return null;
  const parts = m[1].split('.');
  if (parts.length !== 3) return null;
  try {
    const pad = (s: string) => s + '='.repeat((4 - (s.length % 4)) % 4);
    const payload = JSON.parse(
      new TextDecoder().decode(
        Uint8Array.from(atob(pad(parts[1]).replace(/-/g, '+').replace(/_/g, '/')), (c) => c.charCodeAt(0)),
      ),
    );
    return (payload.sub as string | undefined) ?? null;
  } catch {
    return null;
  }
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
