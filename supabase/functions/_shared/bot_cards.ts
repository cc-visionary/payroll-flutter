// Pure Lark interactive-card builders for the Luxium People self-service bot.
// One builder per view model; no Lark/DB dependency. All amounts arrive
// pre-formatted (as strings) from the handler — this module only places them.
// See docs/superpowers/specs/2026-07-29-employee-self-service-bot-design.md.

export type LarkCard = Record<string, unknown>;

const CONTACT_HR_NOTE = { tag: 'note', elements: [{ tag: 'plain_text', content: 'Something looks wrong? Contact HR.' }] };

function card(title: string, elements: unknown[], template = 'blue'): LarkCard {
  return {
    config: { wide_screen_mode: true },
    header: { title: { tag: 'plain_text', content: title }, template },
    elements: [...elements, CONTACT_HR_NOTE],
  };
}

function md(content: string) {
  return { tag: 'div', text: { tag: 'lark_md', content } };
}

/** Mask everything but the last 4 characters, e.g. '123456789' -> '••••6789'. */
export function maskLast4(v: string | null): string {
  const s = (v ?? '').replace(/\s+/g, '');
  if (s.length === 0) return '—';
  return '••••' + s.slice(-4);
}

// ---------------------------------------------------------------------------
// Generic / fallback cards
// ---------------------------------------------------------------------------

export function linkPromptCard(): LarkCard {
  return card('Not linked yet', [
    md('Your Lark account isn\'t linked to a Luxium employee record yet.'),
    md('Please contact HR to get set up.'),
  ], 'orange');
}

export function helpCard(): LarkCard {
  return card('Luxium People', [
    md('Here\'s what I can show you — just send a keyword or use the menu:'),
    md('**Payslip** — your latest released payslip'),
    md('**Leave** — leave balances + recent attendance'),
    md('**Tasks** — your tasks and responsibilities'),
    md('**Reviews** — your latest performance review + self-evals'),
    md('**Info** — your personal, statutory, and bank info'),
  ]);
}

export function errorCard(): LarkCard {
  return card('Something went wrong', [
    md('Please try again in a moment, or contact HR if this keeps happening.'),
  ], 'red');
}

// ---------------------------------------------------------------------------
// my_payslip
// ---------------------------------------------------------------------------

export interface PayslipVM {
  periodLabel: string;
  netPay: string;
  grossPay: string;
  totalDeductions: string;
  sssEe: string;
  philhealthEe: string;
  pagibigEe: string;
  withholdingTax: string;
  ytdGross: string;
  ytdTax: string;
}

export function payslipCard(v: PayslipVM | null): LarkCard {
  if (v === null) {
    return card('My Payslip', [
      md('No released payslip yet. Check back after your next pay run.'),
    ]);
  }

  return card('My Payslip', [
    md(`**${v.periodLabel}**`),
    md(`**Net Pay:** ${v.netPay}`),
    md(`**Gross Pay:** ${v.grossPay}\n**Total Deductions:** ${v.totalDeductions}`),
    md(
      `**SSS (EE):** ${v.sssEe}\n**PhilHealth (EE):** ${v.philhealthEe}\n` +
        `**Pag-IBIG (EE):** ${v.pagibigEe}\n**Withholding Tax:** ${v.withholdingTax}`,
    ),
    md(`**YTD Gross:** ${v.ytdGross}\n**YTD Tax:** ${v.ytdTax}`),
    { tag: 'hr' },
    md('Full PDF in the portal (coming soon).'),
  ]);
}

// ---------------------------------------------------------------------------
// my_leave
// ---------------------------------------------------------------------------

export interface LeaveVM {
  balances: { type: string; available: string }[];
  recentAttendance: { label: string; value: string }[];
}

export function leaveCard(v: LeaveVM): LarkCard {
  const balanceLines = v.balances.length > 0
    ? v.balances.map((b) => `**${b.type}:** ${b.available}`).join('\n')
    : 'Nothing here yet.';

  const attendanceLines = v.recentAttendance.length > 0
    ? v.recentAttendance.map((a) => `**${a.label}:** ${a.value}`).join('\n')
    : 'Nothing here yet.';

  return card('My Leave', [
    md('**Leave balances**'),
    md(balanceLines),
    { tag: 'hr' },
    md('**Recent attendance**'),
    md(attendanceLines),
  ]);
}

// ---------------------------------------------------------------------------
// my_tasks
// ---------------------------------------------------------------------------

export interface TasksVM {
  tasks: { name: string; role: string; allocationPct: string; area: string }[];
}

export function tasksCard(v: TasksVM): LarkCard {
  if (v.tasks.length === 0) {
    return card('My Tasks', [md('Nothing here yet.')]);
  }

  const lines = v.tasks.map(
    (t) => `**${t.name}** (${t.role}, ${t.allocationPct}) — _${t.area}_`,
  );

  return card('My Tasks', [md(lines.join('\n'))]);
}

// ---------------------------------------------------------------------------
// my_reviews
// ---------------------------------------------------------------------------

export interface ReviewsVM {
  latest?: { type: string; status: string; outcome?: string; rating?: string };
  selfEvalCount: number;
  latestSelfEvalDate?: string;
}

export function reviewsCard(v: ReviewsVM): LarkCard {
  const latestLines = v.latest
    ? [
      `**${v.latest.type}**`,
      `**Status:** ${v.latest.status}`,
      v.latest.outcome ? `**Outcome:** ${v.latest.outcome}` : null,
      v.latest.rating ? `**Rating:** ${v.latest.rating}` : null,
    ].filter((l): l is string => l !== null).join('\n')
    : 'Nothing here yet.';

  const selfEvalLine = v.selfEvalCount > 0
    ? `${v.selfEvalCount} submitted` + (v.latestSelfEvalDate ? ` — latest ${v.latestSelfEvalDate}` : '')
    : 'Nothing here yet.';

  return card('My Reviews', [
    md('**Latest formal review**'),
    md(latestLines),
    { tag: 'hr' },
    md('**Self-evaluations**'),
    md(selfEvalLine),
  ]);
}

// ---------------------------------------------------------------------------
// my_info
// ---------------------------------------------------------------------------

export interface InfoVM {
  fullName: string;
  birthday?: string;
  contact?: string;
  address?: string;
  statutory: { label: string; masked: string }[];
  banks: { label: string; masked: string }[];
}

export function infoCard(v: InfoVM): LarkCard {
  const personalLines = [
    `**Name:** ${v.fullName}`,
    v.birthday ? `**Birthday:** ${v.birthday}` : null,
    v.contact ? `**Contact:** ${v.contact}` : null,
    v.address ? `**Address:** ${v.address}` : null,
  ].filter((l): l is string => l !== null).join('\n');

  const statutoryLines = v.statutory.length > 0
    ? v.statutory.map((s) => `**${s.label}:** ${s.masked}`).join('\n')
    : 'Nothing here yet.';

  const bankLines = v.banks.length > 0
    ? v.banks.map((b) => `**${b.label}:** ${b.masked}`).join('\n')
    : 'Nothing here yet.';

  return card('My Info', [
    md(personalLines),
    { tag: 'hr' },
    md('**Statutory IDs**'),
    md(statutoryLines),
    { tag: 'hr' },
    md('**Bank accounts**'),
    md(bankLines),
  ]);
}
