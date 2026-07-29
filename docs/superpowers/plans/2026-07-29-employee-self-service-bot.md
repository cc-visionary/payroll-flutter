# Luxium People Self-Service Bot — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An employee taps the Luxium People bot menu (or sends a keyword) in Lark and gets an interactive card of their own payslip / leave & attendance / tasks & responsibilities / reviews / personal+statutory info.

**Architecture:** One Deno edge function `lark-bot-handler` (`verify_jwt=false`) receives Lark events → decrypts + verifies (Encrypt Key + Verification Token) → resolves the sender to an employee via `lark_user_id` → routes the menu `event_key`/keyword to an intent → fetches that employee's data (service role, scoped) → replies with an interactive card via the messaging API. Two pure, unit-tested modules do the decrypt/parse (`_shared/lark_events.ts`) and card building/masking (`_shared/bot_cards.ts`); the handler wires them to the DB and Lark.

**Tech Stack:** Deno + Web Crypto (AES-CBC, SHA-256), Supabase Postgres (service role), Lark Messaging API via `_shared/lark.ts` (`larkRequest`, `authFromEnv`). `deno test` for units.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-29-employee-self-service-bot-design.md`.
- **Read-only. No migration.** All reads hit existing tables.
- **Identity is ALWAYS derived server-side** from the verified Lark event → `lark_user_id`; never from card/button payload.
- **Fail closed:** unset secret or bad Verification Token → return 200, do nothing, log nothing user-visible.
- **Payslips only when `approval_status = 'RELEASED'`.** Statutory + bank numbers **masked to last-4**.
- Config in **Supabase edge-function secrets** (new: `LARK_BOT_ENCRYPT_KEY`, `LARK_BOT_VERIFICATION_TOKEN`; `LARK_APP_ID/SECRET/BASE_URL` already set). `verify_jwt = false` for the handler in `supabase/config.toml`.
- Deno tests that import `_shared/lark.ts` need `--allow-env` (top-level `LARK_BASE_URL` read).
- Reply pattern (verbatim from `send-performance-self-reviews`): `larkRequest(auth, '/im/v1/messages?receive_id_type=user_id', { method:'POST', body: JSON.stringify({ receive_id: larkUserId, msg_type:'interactive', content: JSON.stringify(card) }) })`.

---

## Task 1: Pure event module — decrypt, verify, parse → intent

**Files:**
- Create: `supabase/functions/_shared/lark_events.ts`
- Test: `supabase/functions/_shared/lark_events_test.ts`

**Interfaces (Produces):**
- `type BotIntent = 'my_payslip' | 'my_leave' | 'my_tasks' | 'my_reviews' | 'my_info' | 'help'`
- `decryptLarkEvent(encrypt: string, encryptKey: string): Promise<Record<string, unknown>>`
- `keywordToIntent(text: string): BotIntent`
- `eventKeyToIntent(key: string): BotIntent` (unknown → `'help'`)

- [ ] **Step 1: Write the failing tests**

```ts
// supabase/functions/_shared/lark_events_test.ts
import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { decryptLarkEvent, keywordToIntent, eventKeyToIntent } from './lark_events.ts';

// AES-CBC + SHA-256(key) round trip (encrypt here exactly as Lark does, then decrypt).
async function larkEncrypt(plain: string, key: string): Promise<string> {
  const enc = new TextEncoder();
  const keyBytes = new Uint8Array(await crypto.subtle.digest('SHA-256', enc.encode(key)));
  const iv = crypto.getRandomValues(new Uint8Array(16));
  const ck = await crypto.subtle.importKey('raw', keyBytes, { name: 'AES-CBC' }, false, ['encrypt']);
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-CBC', iv }, ck, enc.encode(plain)));
  const packed = new Uint8Array(iv.length + ct.length);
  packed.set(iv, 0); packed.set(ct, iv.length);
  return btoa(String.fromCharCode(...packed));
}

Deno.test('decryptLarkEvent round-trips a Lark-encrypted payload', async () => {
  const payload = JSON.stringify({ type: 'url_verification', challenge: 'abc123', token: 'vt' });
  const encrypted = await larkEncrypt(payload, 'my-encrypt-key');
  const out = await decryptLarkEvent(encrypted, 'my-encrypt-key');
  assertEquals(out.challenge, 'abc123');
  assertEquals(out.token, 'vt');
});

Deno.test('keywordToIntent maps known keywords, else help', () => {
  assertEquals(keywordToIntent('  Payslip '), 'my_payslip');
  assertEquals(keywordToIntent('leave'), 'my_leave');
  assertEquals(keywordToIntent('my tasks'), 'my_tasks');
  assertEquals(keywordToIntent('responsibilities'), 'my_tasks');
  assertEquals(keywordToIntent('reviews'), 'my_reviews');
  assertEquals(keywordToIntent('info'), 'my_info');
  assertEquals(keywordToIntent('hello?'), 'help');
});

Deno.test('eventKeyToIntent maps menu keys, else help', () => {
  assertEquals(eventKeyToIntent('my_payslip'), 'my_payslip');
  assertEquals(eventKeyToIntent('nonsense'), 'help');
});
```

- [ ] **Step 2: Run to verify it fails** — `deno test --allow-env supabase/functions/_shared/lark_events_test.ts` → FAIL (module missing).

- [ ] **Step 3: Implement**

```ts
// supabase/functions/_shared/lark_events.ts
// Pure helpers for the Luxium People bot: decrypt a Lark event, and map a menu
// event_key / message keyword to a bot intent. No Lark/DB dependency.
// See docs/superpowers/specs/2026-07-29-employee-self-service-bot-design.md.

export type BotIntent =
  | 'my_payslip' | 'my_leave' | 'my_tasks' | 'my_reviews' | 'my_info' | 'help';

/** Decrypt a Lark `encrypt` payload. Lark: key = SHA-256(EncryptKey); the
 *  base64 body is IV(16 bytes) || AES-256-CBC ciphertext (PKCS7). */
export async function decryptLarkEvent(
  encrypt: string,
  encryptKey: string,
): Promise<Record<string, unknown>> {
  const keyBytes = new Uint8Array(
    await crypto.subtle.digest('SHA-256', new TextEncoder().encode(encryptKey)),
  );
  const raw = Uint8Array.from(atob(encrypt), (c) => c.charCodeAt(0));
  const iv = raw.slice(0, 16);
  const ct = raw.slice(16);
  const ck = await crypto.subtle.importKey('raw', keyBytes, { name: 'AES-CBC' }, false, ['decrypt']);
  const pt = await crypto.subtle.decrypt({ name: 'AES-CBC', iv }, ck, ct);
  return JSON.parse(new TextDecoder().decode(pt)) as Record<string, unknown>;
}

const _KEYWORDS: Array<[RegExp, BotIntent]> = [
  [/pay ?slip|payroll|salary/i, 'my_payslip'],
  [/leave|attendance|balance/i, 'my_leave'],
  [/task|responsib|workload/i, 'my_tasks'],
  [/review|self.?eval|evaluation/i, 'my_reviews'],
  [/info|profile|personal|bank|statutory/i, 'my_info'],
];

export function keywordToIntent(text: string): BotIntent {
  const t = (text ?? '').trim();
  for (const [re, intent] of _KEYWORDS) if (re.test(t)) return intent;
  return 'help';
}

const _MENU_KEYS = new Set<BotIntent>(['my_payslip', 'my_leave', 'my_tasks', 'my_reviews', 'my_info']);

export function eventKeyToIntent(key: string): BotIntent {
  return _MENU_KEYS.has(key as BotIntent) ? (key as BotIntent) : 'help';
}
```

- [ ] **Step 4: Run to verify it passes** — `deno test --allow-env supabase/functions/_shared/lark_events_test.ts` → PASS (3 tests).

- [ ] **Step 5: Commit** — `git add supabase/functions/_shared/lark_events*.ts && git commit -m "feat(lark-bot): pure event decrypt + intent parsing"`.

---

## Task 2: Pure card builders + masking

**Files:**
- Create: `supabase/functions/_shared/bot_cards.ts`
- Test: `supabase/functions/_shared/bot_cards_test.ts`

**Interfaces (Consumes):** `BotIntent` from Task 1 (not required here — cards are keyed by their own view models).
**Interfaces (Produces):** a `LarkCard = Record<string, unknown>` and one builder per view, each returning a Lark interactive-card object:
- `maskLast4(v: string | null): string`
- `linkPromptCard(): LarkCard` · `helpCard(): LarkCard` · `errorCard(): LarkCard`
- `payslipCard(v: PayslipVM | null): LarkCard` · `leaveCard(v: LeaveVM): LarkCard` · `tasksCard(v: TasksVM): LarkCard` · `reviewsCard(v: ReviewsVM): LarkCard` · `infoCard(v: InfoVM): LarkCard`
- View-model types (exported): `PayslipVM { periodLabel; netPay; grossPay; totalDeductions; sssEe; philhealthEe; pagibigEe; withholdingTax; ytdGross; ytdTax }` (all strings, pre-formatted); `LeaveVM { balances: {type; available}[]; recentAttendance: {label; value}[] }`; `TasksVM { tasks: {name; role; allocationPct; area}[] }`; `ReviewsVM { latest?: {type; status; outcome?; rating?}; selfEvalCount; latestSelfEvalDate? }`; `InfoVM { fullName; birthday?; contact?; address?; statutory: {label; masked}[]; banks: {label; masked}[] }`.

- [ ] **Step 1: Write the failing tests**

```ts
// supabase/functions/_shared/bot_cards_test.ts
import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { maskLast4, payslipCard, infoCard, helpCard, linkPromptCard } from './bot_cards.ts';

Deno.test('maskLast4 keeps only the last four digits', () => {
  assertEquals(maskLast4('123456789'), '••••6789');
  assertEquals(maskLast4('12'), '••••12');
  assertEquals(maskLast4(null), '—');
  assertEquals(maskLast4(''), '—');
});

Deno.test('payslipCard renders an empty state when there is no released payslip', () => {
  const card = payslipCard(null);
  const json = JSON.stringify(card);
  assertEquals(json.includes('No released payslip'), true);
  assertEquals((card as { config?: unknown }).config !== undefined || 'elements' in card, true);
});

Deno.test('payslipCard shows net pay and the period', () => {
  const json = JSON.stringify(payslipCard({
    periodLabel: 'Jun 1–15, 2026', netPay: '₱12,345.00', grossPay: '₱15,000.00',
    totalDeductions: '₱2,655.00', sssEe: '₱675.00', philhealthEe: '₱375.00',
    pagibigEe: '₱100.00', withholdingTax: '₱1,505.00', ytdGross: '₱90,000', ytdTax: '₱9,000',
  }));
  assertEquals(json.includes('₱12,345.00'), true);
  assertEquals(json.includes('Jun 1–15, 2026'), true);
});

Deno.test('infoCard masks statutory + bank numbers', () => {
  const json = JSON.stringify(infoCard({
    fullName: 'Juan Dela Cruz', statutory: [{ label: 'SSS', masked: maskLast4('3411223344') }],
    banks: [{ label: 'GCash', masked: maskLast4('09171234567') }],
  }));
  assertEquals(json.includes('••••3344'), true);
  assertEquals(json.includes('3411223344'), false); // full number never present
});

Deno.test('helpCard and linkPromptCard are valid cards', () => {
  for (const c of [helpCard(), linkPromptCard()]) {
    assertEquals('elements' in c || 'config' in c, true);
  }
});
```

- [ ] **Step 2: Run to verify it fails** — `deno test supabase/functions/_shared/bot_cards_test.ts` → FAIL (module missing).

- [ ] **Step 3: Implement** — build each function returning a Lark interactive card (`{ config:{wide_screen_mode:true}, header:{title:{tag:'plain_text', content:'…'}}, elements:[…] }`). Use `div` blocks with `lark_md` text. Provide the `maskLast4` below verbatim; build one card per view model, and an empty state inside `payslipCard(null)` (and empty arrays in the others → "Nothing here yet" line). Every card's last element is a note: "Something looks wrong? Contact HR."

```ts
export function maskLast4(v: string | null): string {
  const s = (v ?? '').replace(/\s+/g, '');
  if (s.length === 0) return '—';
  return '••••' + s.slice(-4);
}
```

- [ ] **Step 4: Run to verify it passes** — `deno test supabase/functions/_shared/bot_cards_test.ts` → PASS (5 tests).

- [ ] **Step 5: Commit** — `git add supabase/functions/_shared/bot_cards*.ts && git commit -m "feat(lark-bot): pure card builders + last-4 masking"`.

---

## Task 3: `lark-bot-handler` edge function + config + secrets + deploy

**Files:**
- Create: `supabase/functions/lark-bot-handler/index.ts`
- Modify: `supabase/config.toml` (add `[functions.lark-bot-handler]` / `verify_jwt = false`)

**Interfaces (Consumes):** all of Task 1 + Task 2. Reply pattern from Global Constraints.

- [ ] **Step 1: Add the config block** — append to `supabase/config.toml`:

```toml
[functions.lark-bot-handler]
verify_jwt = false
```

- [ ] **Step 2: Write the handler.** Structure (real reads shown; no placeholders):

```ts
// supabase/functions/lark-bot-handler/index.ts
// Luxium People self-service bot. Lark event -> decrypt/verify -> resolve
// employee by lark_user_id -> route intent -> reply with a scoped card.
// verify_jwt=false (see config.toml); fail closed on token/secret errors.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { authFromEnv, larkRequest, json } from '../_shared/lark.ts';
import { decryptLarkEvent, eventKeyToIntent, keywordToIntent, type BotIntent } from '../_shared/lark_events.ts';
import {
  linkPromptCard, helpCard, errorCard, payslipCard, leaveCard, tasksCard, reviewsCard, infoCard,
  maskLast4, type LarkCard,
} from '../_shared/bot_cards.ts';

async function reply(auth: ReturnType<typeof authFromEnv>, larkUserId: string, card: LarkCard) {
  await larkRequest(auth, '/im/v1/messages?receive_id_type=user_id', {
    method: 'POST',
    body: JSON.stringify({ receive_id: larkUserId, msg_type: 'interactive', content: JSON.stringify(card) }),
  });
}

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

    const card = await buildCard(supabase, intent, emp);
    await reply(auth, senderUserId, card);
    return json({ ok: true });
  } catch (_e) {
    try { await reply(auth, senderUserId, errorCard()); } catch { /* ignore */ }
    return json({ ok: true }); // never surface internals to Lark/user
  }
});
```

  Also implement, in the same file: `resolve(body, event)` (menu event → `eventKeyToIntent(event.event_key)`; message event → parse `event.message.content` JSON `.text` → `keywordToIntent`; sender from `event.operator?.operator_id?.user_id` or `event.sender?.sender_id?.user_id`), and `buildCard(supabase, intent, emp)` with the real per-domain reads:
  - `my_payslip`: `payslips` join `payroll_runs(period_start,period_end)` where `employee_id=emp.id and approval_status='RELEASED'`, order by run period desc, limit 1 → format ₱ → `payslipCard`.
  - `my_leave`: `leave_balances` (+ `leave_types(name)`) for the current year → available = `opening_balance+accrued+carried_over_from_previous+adjusted-used-forfeited-converted`; `attendance_day_records` last ~14 days summarized → `leaveCard`.
  - `my_tasks`: `wp_task_assignments` where `employee_id=emp.id` join `wp_tasks(name,responsibility_area)` → rows with role + `allocation_pct`; role responsibilities via `emp.role_scorecard_id` → `tasksCard`.
  - `my_reviews`: `employee_reviews` where `employee_id=emp.id` newest → status/outcome/rating; `lark_self_eval_responses` count + latest `submitted_at` → `reviewsCard`.
  - `my_info`: `employee_statutory_ids` + `employee_bank_accounts` (active) → `maskLast4` each → `infoCard` (name/birthday/contact/address from `emp`).
  - `help`: `helpCard()`.

- [ ] **Step 3: `flutter analyze` is N/A (Deno); type-check** — `deno check supabase/functions/lark-bot-handler/index.ts` → no errors.

- [ ] **Step 4: Set secrets + deploy**

```bash
supabase secrets set LARK_BOT_ENCRYPT_KEY=<from Lark console> LARK_BOT_VERIFICATION_TOKEN=<from Lark console>
supabase functions deploy lark-bot-handler
```
(If the Lark values aren't created yet, set placeholders now and re-set after the user creates them in Step of the companion doc; the function fails closed until they match.)

- [ ] **Step 5: Commit** — `git add supabase/functions/lark-bot-handler/index.ts supabase/config.toml && git commit -m "feat(lark-bot): lark-bot-handler edge function (5 scoped self-service cards)"`.

---

## Task 4: Identity-mapping sanity check (no new code)

**Files:** none (verification only).

- [ ] **Step 1: Confirm coverage** — with the service role (flag the privileged use), count employees that can use the bot:

```bash
URL=$(jq -r .SUPABASE_URL env/prod.json); KEY=$(jq -r .SUPABASE_SERVICE_ROLE_KEY env/prod.json)
curl -sI "$URL/rest/v1/employees?select=id&lark_user_id=not.is.null&deleted_at=is.null" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Prefer: count=exact" -H "Range: 0-0" \
  | grep -i content-range
```
Expected: a non-zero count (these employees will resolve; others get the link-prompt card). Record the number in the ledger.

---

## Task 5: Lark-side setup companion doc

**Files:**
- Create: `docs/superpowers/specs/2026-07-29-luxium-people-bot-lark-setup.md`

- [ ] **Step 1: Write the doc** covering, step by step in the Lark Developer Console for the Luxium People app:
  1. **Bot** feature enabled.
  2. **Permissions & Scopes:** add bot message send + receive scopes (`im:message`, `im:message:send_as_bot`, receive p2p messages); publish a version.
  3. **Custom bot menu:** add 5 items with exact `event_key`s: `my_payslip` ("My Payslip"), `my_leave` ("My Leave & Attendance"), `my_tasks` ("My Tasks & Responsibilities"), `my_reviews` ("My Reviews"), `my_info` ("My Info").
  4. **Events & Callbacks:** subscribe to "Message received" (`im.message.receive_v1`) + the bot-menu event; set **Subscription mode = "Send callbacks to developer's server"** (NOT persistent connection) → URL `https://<project>.supabase.co/functions/v1/lark-bot-handler`.
  5. **Encryption Strategy:** set an **Encrypt Key** + note the **Verification Token** → give both to me → I run `supabase secrets set LARK_BOT_ENCRYPT_KEY=… LARK_BOT_VERIFICATION_TOKEN=…` and redeploy.
  6. **Verify:** the console's URL verification should go green (the handler answers the challenge).
  7. **Test:** DM the bot / tap each menu item; confirm the right scoped, masked card.

- [ ] **Step 2: Commit** — `git add docs/superpowers/specs/2026-07-29-luxium-people-bot-lark-setup.md && git commit -m "docs: Lark-side setup guide for the Luxium People self-service bot"`.

---

## Self-Review

**Spec coverage:** architecture/one-function (T3); verify+decrypt fail-closed (T1 decrypt, T3 token/challenge); identify via lark_user_id + link-prompt (T3); route menu/keyword→intent (T1, T3 resolve); 5 cards + sources + RELEASED gate + masking (T2 builders, T3 reads); errors/empty states (T2 empty cards, T3 try/catch); security/secrets/verify_jwt (Global + T3); Lark-side setup (T5); testing (T1/T2 units, T4 identity check). ✓

**Placeholder scan:** pure modules have full code; T3 gives the full handler skeleton + explicit per-domain read specs (formulae + tables named) rather than vague "fetch data". No TBD/TODO. ✓

**Type consistency:** `BotIntent` (T1) is the intent type used by `resolve`/`buildCard` (T3); card builders + view models (T2) are the exact functions T3 calls; `maskLast4`/`larkRequest`/reply shape consistent across tasks. ✓

**No migration** — confirmed all reads are existing tables.
