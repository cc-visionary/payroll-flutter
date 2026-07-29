// supabase/functions/lark-bot-handler/index.ts
// Luxium People self-service bot. Lark event -> decrypt/verify -> resolve
// employee by lark_user_id -> route intent -> reply with a scoped card.
// verify_jwt=false (see config.toml); fail closed on token/secret errors.
import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { authFromEnv, larkRequest, json } from '../_shared/lark.ts';
import { decryptLarkEvent, eventKeyToIntent, keywordToIntent, type BotIntent } from '../_shared/lark_events.ts';
import {
  linkPromptCard, helpCard, errorCard, payslipCard, leaveCard, tasksCard, reviewsCard, infoCard,
  maskLast4, type LarkCard, type PayslipVM, type LeaveVM, type TasksVM, type ReviewsVM, type InfoVM,
} from '../_shared/bot_cards.ts';

async function reply(auth: ReturnType<typeof authFromEnv>, larkUserId: string, card: LarkCard) {
  await larkRequest(auth, '/im/v1/messages?receive_id_type=user_id', {
    method: 'POST',
    body: JSON.stringify({ receive_id: larkUserId, msg_type: 'interactive', content: JSON.stringify(card) }),
  });
}

// -----------------------------------------------------------------------------
// Formatting helpers — VM fields arrive as pre-formatted strings (bot_cards.ts
// only places them), so all number/date -> string formatting happens here.
// No Intl currency/locale data; a small manual formatter keeps this portable
// across the Deno edge runtime.
// -----------------------------------------------------------------------------

function formatPeso(value: unknown): string {
  const num = typeof value === 'number' ? value : parseFloat(String(value ?? 0));
  const amount = Number.isFinite(num) ? num : 0;
  const sign = amount < 0 ? '-' : '';
  const [intPart, decPart] = Math.abs(amount).toFixed(2).split('.');
  const withCommas = intPart.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  return `${sign}₱${withCommas}.${decPart}`;
}

function formatPct(value: unknown): string {
  const num = typeof value === 'number' ? value : parseFloat(String(value ?? 0));
  const amount = Number.isFinite(num) ? num : 0;
  const rounded = Math.round(amount * 100) / 100;
  return `${Number.isInteger(rounded) ? rounded.toFixed(0) : rounded.toFixed(2)}%`;
}

function formatDays(value: unknown): string {
  const num = typeof value === 'number' ? value : parseFloat(String(value ?? 0));
  const amount = Number.isFinite(num) ? num : 0;
  const rounded = Math.round(amount * 100) / 100;
  const label = Number.isInteger(rounded) ? rounded.toFixed(0) : rounded.toFixed(2);
  return `${label} day${rounded === 1 ? '' : 's'}`;
}

function formatRating(value: unknown): string {
  const num = typeof value === 'number' ? value : parseFloat(String(value ?? 0));
  return Number.isFinite(num) ? `${num.toFixed(1)}/5` : '—';
}

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/** Parse a `yyyy-mm-dd` date column manually (no `Date` construction) so
 *  timezone offsets never shift the displayed day. */
function formatDateShort(iso: string): string {
  const [y, m, d] = iso.split('-').map((s) => parseInt(s, 10));
  if (!y || !m || !d) return iso;
  return `${MONTHS[m - 1]} ${d}, ${y}`;
}

function formatPeriodLabel(startIso: string, endIso: string): string {
  const [sy, sm, sd] = startIso.split('-').map((s) => parseInt(s, 10));
  const [ey, em, ed] = endIso.split('-').map((s) => parseInt(s, 10));
  const startLabel = sy === ey ? `${MONTHS[sm - 1]} ${sd}` : `${MONTHS[sm - 1]} ${sd}, ${sy}`;
  const endLabel = `${MONTHS[em - 1]} ${ed}, ${ey}`;
  return `${startLabel} – ${endLabel}`;
}

/** `submitted_at` is a full timestamptz (a real instant), unlike the
 *  date-only columns above — safe to go through `Date`. Formatted in UTC
 *  since the edge runtime has no reliable local timezone. */
function formatTimestampDate(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return `${MONTHS[d.getUTCMonth()]} ${d.getUTCDate()}, ${d.getUTCFullYear()}`;
}

function titleCase(s: string): string {
  return s
    .toLowerCase()
    .split('_')
    .filter((w) => w.length > 0)
    .map((w) => w[0].toUpperCase() + w.slice(1))
    .join(' ');
}

const ID_TYPE_LABELS: Record<string, string> = {
  SSS: 'SSS',
  PHILHEALTH: 'PhilHealth',
  PAGIBIG: 'Pag-IBIG',
  TIN: 'TIN',
};

const ATTENDANCE_LABELS: Record<string, string> = {
  PRESENT: 'Present',
  ABSENT: 'Absent',
  HALF_DAY: 'Half Day',
  ON_LEAVE: 'On Leave',
  REST_DAY: 'Rest Day',
  HOLIDAY: 'Holiday',
};

// -----------------------------------------------------------------------------
// Event resolution — menu click vs. text message, sender id from either shape.
// -----------------------------------------------------------------------------

interface ResolveResult {
  senderUserId: string | null;
  intent: BotIntent;
}

/** Menu-click events carry a top-level `event_key`; message-receive events
 *  carry `event.message`. We branch on which is present rather than on the
 *  envelope's `header.event_type` string, since that keeps this working
 *  regardless of the exact event-type identifiers Lark uses for the bot
 *  custom menu vs. `im.message.receive_v1`. `body` is accepted per the task
 *  interface but isn't needed beyond `event` for this branch. */
function resolve(_body: Record<string, unknown>, event: Record<string, unknown>): ResolveResult {
  const eventKey = typeof event.event_key === 'string' ? event.event_key : undefined;

  let intent: BotIntent;
  if (eventKey !== undefined) {
    intent = eventKeyToIntent(eventKey);
  } else {
    const message = (event.message ?? {}) as Record<string, unknown>;
    let text = '';
    if (typeof message.content === 'string') {
      try {
        const parsed = JSON.parse(message.content) as { text?: unknown };
        text = typeof parsed.text === 'string' ? parsed.text : '';
      } catch {
        text = '';
      }
    }
    intent = keywordToIntent(text);
  }

  const operator = (event.operator ?? {}) as Record<string, unknown>;
  const operatorId = (operator.operator_id ?? {}) as Record<string, unknown>;
  const sender = (event.sender ?? {}) as Record<string, unknown>;
  const senderId = (sender.sender_id ?? {}) as Record<string, unknown>;
  const senderUserId =
    (typeof operatorId.user_id === 'string' ? operatorId.user_id : undefined) ??
    (typeof senderId.user_id === 'string' ? senderId.user_id : undefined) ??
    null;

  return { senderUserId, intent };
}

// -----------------------------------------------------------------------------
// Per-domain reads -> view models -> cards.
// -----------------------------------------------------------------------------

interface EmpRow {
  id: string;
  company_id: string;
  first_name: string;
  middle_name: string | null;
  last_name: string;
  birth_date: string | null;
  phone_number: string | null;
  present_address_line1: string | null;
  role_scorecard_id: string | null;
}

function fullName(emp: EmpRow): string {
  return [emp.first_name, emp.middle_name, emp.last_name].filter((p) => !!p && p.trim() !== '').join(' ');
}

async function buildPayslipCard(supabase: SupabaseClient, emp: EmpRow): Promise<LarkCard> {
  // approval_status lives on payslips (DRAFT_IN_REVIEW/PENDING_APPROVAL/...)
  // but "released" is a property of the RUN, not the payslip -- payroll_runs
  // has its own status enum with a RELEASED value (period_start/period_end/
  // status were moved onto payroll_runs directly in
  // 20260418000006_drop_pay_periods_resilient.sql, replacing the old
  // pay_periods join). Filtering on payroll_runs.status requires !inner.
  const { data: rows, error } = await supabase
    .from('payslips')
    .select(
      'net_pay, gross_pay, total_deductions, sss_ee, philhealth_ee, pagibig_ee, withholding_tax, ' +
        'ytd_gross_pay, ytd_tax_withheld, payroll_runs!inner(period_start, period_end, status)',
    )
    .eq('employee_id', emp.id)
    .eq('payroll_runs.status', 'RELEASED')
    .limit(500);
  if (error) throw new Error(`payslips: ${error.message}`);

  // PostgREST doesn't support ordering the parent by an embedded to-one
  // column, so pick the latest period client-side (bounded by the .limit above).
  let latest: Record<string, unknown> | null = null;
  let latestEnd = '';
  for (const row of (rows ?? []) as unknown as Array<Record<string, unknown>>) {
    const run = row.payroll_runs as { period_start: string; period_end: string } | null;
    if (!run?.period_end) continue;
    if (run.period_end > latestEnd) {
      latest = row;
      latestEnd = run.period_end;
    }
  }
  if (!latest) return payslipCard(null);

  const run = latest.payroll_runs as { period_start: string; period_end: string };
  const vm: PayslipVM = {
    periodLabel: formatPeriodLabel(run.period_start, run.period_end),
    netPay: formatPeso(latest.net_pay),
    grossPay: formatPeso(latest.gross_pay),
    totalDeductions: formatPeso(latest.total_deductions),
    sssEe: formatPeso(latest.sss_ee),
    philhealthEe: formatPeso(latest.philhealth_ee),
    pagibigEe: formatPeso(latest.pagibig_ee),
    withholdingTax: formatPeso(latest.withholding_tax),
    ytdGross: formatPeso(latest.ytd_gross_pay),
    ytdTax: formatPeso(latest.ytd_tax_withheld),
  };
  return payslipCard(vm);
}

async function buildLeaveCard(supabase: SupabaseClient, emp: EmpRow): Promise<LarkCard> {
  const year = new Date().getUTCFullYear();
  const { data: balanceRows, error: balErr } = await supabase
    .from('leave_balances')
    .select(
      'opening_balance, accrued, used, forfeited, converted, adjusted, carried_over_from_previous, ' +
        'leave_types(name)',
    )
    .eq('employee_id', emp.id)
    .eq('year', year);
  if (balErr) throw new Error(`leave_balances: ${balErr.message}`);

  const balances = ((balanceRows ?? []) as unknown as Array<Record<string, unknown>>).map((row) => {
    const type = row.leave_types as { name: string } | null;
    const available =
      Number(row.opening_balance ?? 0) +
      Number(row.accrued ?? 0) +
      Number(row.carried_over_from_previous ?? 0) +
      Number(row.adjusted ?? 0) -
      Number(row.used ?? 0) -
      Number(row.forfeited ?? 0) -
      Number(row.converted ?? 0);
    return { type: type?.name ?? 'Leave', available: formatDays(available) };
  });

  // Last ~14 days of attendance, summarized as status counts (not a per-day
  // dump — cards need to stay short).
  const since = new Date();
  since.setUTCDate(since.getUTCDate() - 13);
  const sinceIso = since.toISOString().slice(0, 10);
  const { data: attRows, error: attErr } = await supabase
    .from('attendance_day_records')
    .select('attendance_status')
    .eq('employee_id', emp.id)
    .gte('attendance_date', sinceIso);
  if (attErr) throw new Error(`attendance_day_records: ${attErr.message}`);

  const counts = new Map<string, number>();
  for (const row of (attRows ?? []) as unknown as Array<Record<string, unknown>>) {
    const status = String(row.attendance_status ?? '');
    if (!status) continue;
    counts.set(status, (counts.get(status) ?? 0) + 1);
  }
  const statusOrder = ['PRESENT', 'ON_LEAVE', 'ABSENT', 'HALF_DAY', 'REST_DAY', 'HOLIDAY'];
  const recentAttendance = [
    { label: 'Period', value: 'Last 14 days' },
    ...statusOrder
      .filter((status) => counts.has(status))
      .map((status) => {
        const n = counts.get(status)!;
        return { label: ATTENDANCE_LABELS[status] ?? titleCase(status), value: `${n} day${n === 1 ? '' : 's'}` };
      }),
  ];

  const vm: LeaveVM = { balances, recentAttendance };
  return leaveCard(vm);
}

async function buildTasksCard(supabase: SupabaseClient, emp: EmpRow): Promise<LarkCard> {
  // Two sources feed one list: tasks assigned directly to this employee, and
  // tasks assigned to the role card they currently hold (emp.role_scorecard_id).
  // Both are wp_task_assignments rows -- one targets employee_id, the other
  // role_scorecard_id (see the one_target constraint in
  // 20260724000001_wp_task_assignments.sql) -- so both queries have the same
  // shape and are just merged + deduped by task_id.
  const { data: personalRows, error: personalErr } = await supabase
    .from('wp_task_assignments')
    .select('task_id, assignment_role, allocation_pct, wp_tasks(name, responsibility_area)')
    .eq('employee_id', emp.id);
  if (personalErr) throw new Error(`wp_task_assignments (employee): ${personalErr.message}`);

  let roleRows: Array<Record<string, unknown>> = [];
  if (emp.role_scorecard_id) {
    const { data, error } = await supabase
      .from('wp_task_assignments')
      .select('task_id, assignment_role, allocation_pct, wp_tasks(name, responsibility_area)')
      .eq('role_scorecard_id', emp.role_scorecard_id);
    if (error) throw new Error(`wp_task_assignments (role card): ${error.message}`);
    roleRows = (data ?? []) as unknown as Array<Record<string, unknown>>;
  }

  const merged = new Map<string, Record<string, unknown>>();
  for (const row of [...((personalRows ?? []) as unknown as Array<Record<string, unknown>>), ...roleRows]) {
    const taskId = row.task_id as string;
    if (!merged.has(taskId)) merged.set(taskId, row);
  }

  const tasks = Array.from(merged.values())
    .map((row) => {
      const task = row.wp_tasks as { name: string; responsibility_area: string | null } | null;
      return {
        name: task?.name ?? 'Untitled task',
        role: row.assignment_role === 'PRIMARY' ? 'Primary' : 'Contributor',
        allocationPct: formatPct(row.allocation_pct),
        area: task?.responsibility_area ?? '—',
      };
    })
    .sort((a, b) => a.area.localeCompare(b.area) || a.name.localeCompare(b.name));

  const vm: TasksVM = { tasks };
  return tasksCard(vm);
}

async function buildReviewsCard(supabase: SupabaseClient, emp: EmpRow): Promise<LarkCard> {
  const { data: reviewRows, error: reviewErr } = await supabase
    .from('employee_reviews')
    .select('review_type, status, overall_outcome, overall_rating')
    .eq('employee_id', emp.id)
    .order('review_period_end', { ascending: false })
    .limit(1);
  if (reviewErr) throw new Error(`employee_reviews: ${reviewErr.message}`);
  const reviewRow = ((reviewRows ?? []) as unknown as Array<Record<string, unknown>>)[0];

  const { count: selfEvalCount, error: countErr } = await supabase
    .from('lark_self_eval_responses')
    .select('id', { count: 'exact', head: true })
    .eq('employee_id', emp.id);
  if (countErr) throw new Error(`lark_self_eval_responses count: ${countErr.message}`);

  let latestSelfEvalDate: string | undefined;
  if ((selfEvalCount ?? 0) > 0) {
    const { data: latestRows, error: latestErr } = await supabase
      .from('lark_self_eval_responses')
      .select('submitted_at')
      .eq('employee_id', emp.id)
      .not('submitted_at', 'is', null)
      .order('submitted_at', { ascending: false })
      .limit(1);
    if (latestErr) throw new Error(`lark_self_eval_responses latest: ${latestErr.message}`);
    const iso = (latestRows ?? [])[0]?.submitted_at as string | undefined;
    if (iso) latestSelfEvalDate = formatTimestampDate(iso);
  }

  const vm: ReviewsVM = {
    latest: reviewRow
      ? {
        type: titleCase(String(reviewRow.review_type ?? '')),
        status: titleCase(String(reviewRow.status ?? '')),
        outcome: reviewRow.overall_outcome ? titleCase(String(reviewRow.overall_outcome)) : undefined,
        rating: reviewRow.overall_rating != null ? formatRating(reviewRow.overall_rating) : undefined,
      }
      : undefined,
    selfEvalCount: String(selfEvalCount ?? 0),
    latestSelfEvalDate,
  };
  return reviewsCard(vm);
}

async function buildInfoCard(supabase: SupabaseClient, emp: EmpRow): Promise<LarkCard> {
  const { data: statutoryRows, error: statErr } = await supabase
    .from('employee_statutory_ids')
    .select('id_type, id_number')
    .eq('employee_id', emp.id);
  if (statErr) throw new Error(`employee_statutory_ids: ${statErr.message}`);

  const { data: bankRows, error: bankErr } = await supabase
    .from('employee_bank_accounts')
    .select('bank_name, account_number')
    .eq('employee_id', emp.id)
    .is('deleted_at', null)
    .order('is_primary', { ascending: false });
  if (bankErr) throw new Error(`employee_bank_accounts: ${bankErr.message}`);

  const vm: InfoVM = {
    fullName: fullName(emp),
    birthday: emp.birth_date ? formatDateShort(emp.birth_date) : undefined,
    contact: emp.phone_number ?? undefined,
    address: emp.present_address_line1 ?? undefined,
    statutory: ((statutoryRows ?? []) as unknown as Array<Record<string, unknown>>).map((r) => ({
      label: ID_TYPE_LABELS[String(r.id_type)] ?? String(r.id_type),
      masked: maskLast4(r.id_number as string | null),
    })),
    banks: ((bankRows ?? []) as unknown as Array<Record<string, unknown>>).map((r) => ({
      label: String(r.bank_name ?? 'Bank'),
      masked: maskLast4(r.account_number as string | null),
    })),
  };
  return infoCard(vm);
}

async function buildCard(supabase: SupabaseClient, intent: BotIntent, emp: EmpRow): Promise<LarkCard> {
  switch (intent) {
    case 'my_payslip':
      return buildPayslipCard(supabase, emp);
    case 'my_leave':
      return buildLeaveCard(supabase, emp);
    case 'my_tasks':
      return buildTasksCard(supabase, emp);
    case 'my_reviews':
      return buildReviewsCard(supabase, emp);
    case 'my_info':
      return buildInfoCard(supabase, emp);
    case 'help':
    default:
      return helpCard();
  }
}

// -----------------------------------------------------------------------------
// HTTP entrypoint.
// -----------------------------------------------------------------------------

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method not allowed' }, 405);
  const encryptKey = Deno.env.get('LARK_BOT_ENCRYPT_KEY');
  const verifyToken = Deno.env.get('LARK_BOT_VERIFICATION_TOKEN');
  if (!encryptKey || !verifyToken) return json({}, 200); // fail closed, no detail

  let body: Record<string, unknown>;
  try {
    const outer = await req.json();
    body = typeof outer.encrypt === 'string'
      ? await decryptLarkEvent(outer.encrypt, encryptKey)
      : outer;
  } catch { return json({}, 200); }

  // Challenge handshake.
  if (body.type === 'url_verification' && typeof body.challenge === 'string') {
    if (body.token !== verifyToken) return json({}, 200);
    return json({ challenge: body.challenge });
  }

  // Token check (v1 places it at top level; v2 in header.token).
  const header = (body.header ?? {}) as Record<string, unknown>;
  const token = (body.token ?? header.token) as string | undefined;
  if (token !== verifyToken) return json({}, 200);

  // Resolve sender + intent from either a message event or a bot-menu event.
  const event = (body.event ?? {}) as Record<string, unknown>;
  const { senderUserId, intent } = resolve(body, event);
  if (!senderUserId) return json({}, 200);

  const auth = authFromEnv();
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } },
  );

  try {
    const { data: emp } = await supabase.from('employees')
      .select('id, company_id, first_name, middle_name, last_name, birth_date, phone_number, present_address_line1, role_scorecard_id')
      .eq('lark_user_id', senderUserId).is('deleted_at', null).limit(1).maybeSingle();
    if (!emp) { await reply(auth, senderUserId, linkPromptCard()); return json({ ok: true }); }

    const card = await buildCard(supabase, intent, emp as EmpRow);
    await reply(auth, senderUserId, card);
    return json({ ok: true });
  } catch (_e) {
    try { await reply(auth, senderUserId, errorCard()); } catch { /* ignore */ }
    return json({ ok: true }); // never surface internals to Lark/user
  }
});
