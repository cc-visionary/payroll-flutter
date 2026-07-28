# Lark Workload Confirmation — Design Spec

> Date: 2026-07-25. Step 7 (final step) of the accountability model
> (`2026-07-23-accountability-model-design.md`). The manager-side model (steps
> 1–6) is complete; this closes the manager↔employee loop the HRBoK calls for:
> **job analysis by questionnaire** — ask the person who does the work how long
> it takes, rather than the manager guessing. This app stays the **manager's**
> tool; the employee interacts only through **Lark**.

## Problem

An *uncosted* accountability (real, essential work with no `hours_per_month`)
sits in the needs-attention backlog with nobody able to say how long it takes —
except the person doing it. Today the manager either guesses or leaves it
uncosted. Step 7 lets the manager, in one tap, **ask the owner** over Lark and,
when they answer, **apply** that number to `hours_per_month`.

## Decisions (locked in brainstorming)

| Question | Decision |
|---|---|
| Delivery mechanism | Reuse the **proven Lark form-link + webhook pattern** already in the repo (`send-performance-self-reviews` / `sync-performance-self-review`, and the payslip-approval send/sync pair). No new mechanism. |
| What the reply does | **Staged, not auto-applied.** The answer lands as a *pending* value; the task shows `answered: <name> says ~Xh — [Apply] [Dismiss]`; the **manager** applies it. Keeps the manager in control (this app is their tool). |
| Who is asked | **Auto-target the effective owner** — the task's PRIMARY *person* assignment, or the sole active holder of its PRIMARY *card*. **Prompt to pick only when ambiguous** — a card held by several people (offer each + "both"), or a task with no owner. |
| Status home | A small new table, **`wp_workload_requests`** (lifecycle rows), not loose columns on `wp_tasks` — the send→answer→apply/dismiss lifecycle needs its own record (and a per-request one-time token), mirroring how payslip approvals stage. |
| Manager surface | The **Tasks tab**, on uncosted rows: an "Ask owner" action and the inline "answered — apply" affordance. The needs-attention "uncosted essential" signal may show which uncosted tasks already have a pending answer. |

## Non-goals (YAGNI)

- **Batch ask** ("ask about all my uncosted tasks at once") — start with the
  single-task loop; batching is a thin add later.
- The spec's *other* Lark ideas — **notify-on-allocation-change acknowledgements**
  and **KPI check-ins** — are separate features, each its own spec.
- Any *employee-facing UI in this app* — the employee only ever sees the Lark
  message/form. This app shows the manager the request's status, nothing more.

## Data model — `wp_workload_requests`

```sql
create table wp_workload_requests (
  id               uuid primary key default gen_random_uuid(),
  company_id       uuid not null references companies(id) on delete cascade,
  task_id          uuid not null references wp_tasks(id) on delete cascade,
  employee_id      uuid not null references employees(id) on delete cascade,
  status           text not null default 'SENT'
                   check (status in ('SENT','ANSWERED','APPLIED','DISMISSED')),
  answered_hours   numeric check (answered_hours is null or answered_hours >= 0),
  submission_token text not null,          -- one-time secret the webhook validates
  sent_at          timestamptz not null default now(),
  answered_at      timestamptz,
  applied_at       timestamptz,
  created_by       uuid references auth.users(id),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index wp_workload_requests_task on wp_workload_requests (task_id);
-- At most one OPEN ask per (task, employee), where OPEN = still awaiting or
-- awaiting-apply. Re-asking the same person is allowed only once the prior ask
-- is APPLIED or DISMISSED, so the Tasks tab never shows two live asks (a "sent"
-- and/or a pending "answered") for the same person on the same task.
create unique index wp_workload_requests_open
  on wp_workload_requests (task_id, employee_id) where status in ('SENT','ANSWERED');
```
- **RLS:** company-scoped select; HR/ADMIN/SUPER_ADMIN write (same pattern as
  `wp_task_assignments`). The inbound webhook writes via the **service role** and
  authenticates the specific row with `submission_token`, not RLS.
- `updated_at` trigger via the existing `set_updated_at()`.
- Multiple *historical* rows per task are fine; the partial unique index only
  forbids two simultaneously-open asks for the same (task, employee).

## Edge functions (Deno) — mirror the self-review pair

### `send-workload-request` (outbound)
- **Input:** `{ task_id, employee_id }` (invoked from the app via
  `functions.invoke`, with the caller's `Authorization` header — HR/admin gated
  the same way `send-performance-self-reviews` checks its cycle).
- **Does:** insert a `wp_workload_requests` row (`status='SENT'`, a fresh
  `submission_token`, `created_by` = caller); resolve the recipient's Lark
  `user_id` from `employees` (already synced by `sync-lark-employees`); send a
  Lark message via `_shared/lark.ts` containing a deep link to the **workload
  Lark form**, built with the existing `formLink(...)` helper and carrying the
  hidden `task_id`, `employee_id`, `submission_token`, and the task name +
  current-hours context. Return the created request id.
- **Idempotency / errors:** the partial unique index rejects a second open ask
  for the same (task, employee) — surface that as "already asked". A Lark send
  failure marks the row so the app can show a retry (or the row is left removable).
- **Config (secrets, provided out of band, like the self-review form):**
  `LARK_WORKLOAD_FORM_TEMPLATE` (a Lark form id or full URL) and, if the template
  is an id, `LARK_WORKLOAD_FORM_BASE_URL`; the Lark app credentials the shared
  helper already reads.

### `sync-workload-request` (inbound webhook)
- **Input:** the Lark form automation POSTs
  `{ task_id, employee_id, submission_token, hours }` (plus Lark's
  `url_verification` challenge handshake, handled like
  `sync-performance-self-review`).
- **Does:** validate `submission_token` against the matching open row; record
  `answered_hours = hours`, `status='ANSWERED'`, `answered_at = now()` via a
  `SECURITY DEFINER` RPC (`answer_workload_request(...)`) so RLS is bypassed only
  for this one guarded write. Idempotent: a second POST for an
  already-answered/applied row is a no-op success. A number outside a sane range
  (e.g. > 744 h/mo) is rejected with a 400 so a fat-fingered reply can't poison
  the plan.

## Flutter (manager) — Tasks tab

- **Model + repo:** `WpWorkloadRequest` model; `workloadRequests()` read
  (paged) → a `wpWorkloadRequestsProvider` grouped by task id; `applyWorkloadRequest(id)`
  and `dismissWorkloadRequest(id)` writes. "Send" is `functions.invoke('send-workload-request', …)`.
- **Recipient resolution (pure, tested):** `resolveAskRecipients(task, assignments,
  employees)` → returns the single effective owner when unambiguous, else the
  candidate list (holders / contributors) for the picker. Reuses the same
  active-holder predicate as the rest of workforce planning.
- **On an uncosted task row:**
  - **Ask owner** → resolve recipients; if one, invoke `send-workload-request`
    straight away; if several, a small picker (each holder + "both"). Then a
    tinted `sent` chip.
  - When a request is `ANSWERED`: inline `answered: <name> says ~Xh —
    [Apply] [Dismiss]`. **Apply** writes `hours_per_month = answered_hours`
    (through the existing direct-hours write) and calls `applyWorkloadRequest`
    (`status='APPLIED'`, `applied_at`); the task leaves the uncosted backlog.
    **Dismiss** → `dismissWorkloadRequest` (`status='DISMISSED'`), no hours change.
- **Needs-attention:** the existing "uncosted essential" signal is unchanged in
  count, but a task with a pending `ANSWERED` request is visually marked so the
  manager knows an answer is waiting to be applied (a chip, not a new signal).

## Error handling

- Send: no Lark `user_id` for the employee → clear error, no row left dangling
  (delete/rollback the inserted row or mark it failed). Duplicate open ask →
  friendly "already asked <name>".
- Webhook: bad/again-used token → 401/no-op; out-of-range hours → 400; unknown
  task/employee → 404. Never 500 on a malformed payload.
- Apply: the task may have been costed by another path since the answer arrived
  — Apply still overwrites `hours_per_month` with the answered value (the
  manager chose to apply it), and is a no-op-safe if the request is already
  APPLIED/DISMISSED.

## Testing

- **Migration (Deno, throwaway Postgres):** table + RLS shape; the partial
  unique index forbids a second open ask; `answer_workload_request` RPC records
  the answer and is idempotent; the range guard rejects an absurd number.
- **Flutter:** `resolveAskRecipients` pure unit tests (single owner / multi-holder
  / no owner); a widget test for the uncosted row — Ask sends, an ANSWERED request
  renders Apply/Dismiss, Apply writes the hours + marks APPLIED.
- **Edge functions:** the webhook's token-validation + idempotency path is
  unit-testable; the outbound send is exercised end-to-end only in a live Lark
  environment (documented, like the existing send functions).
- `flutter analyze` clean; full suite green.

## Sequencing (each step ships working)

1. **Migration + RPC** — `wp_workload_requests`, RLS, `set_updated_at`,
   `answer_workload_request` SECURITY DEFINER RPC. Applied to prod (no data
   change; pure addition).
2. **Model + repo + providers** — `WpWorkloadRequest`, reads/writes, provider.
3. **`send-workload-request` edge function** + the recipient-resolution pure
   helper.
4. **`sync-workload-request` webhook** + the RPC wired.
5. **Tasks-tab UI** — Ask owner (with the picker) + the answered/Apply/Dismiss
   affordance + the needs-attention pending marker.

Steps 1–2 are inert until 3–5 land; 3–4 are the Lark plumbing (need the two
secrets configured to actually fire); 5 is the manager surface. The app-side
recipient resolution and the Apply/Dismiss loop are fully testable without a
live Lark connection.

## Appendix — the Lark form contract (what to build in Lark)

Modeled exactly on the existing self-review form (`sync-performance-self-review`),
so it reuses the same plumbing. The form is a normal Lark form whose **automation
POSTs a JSON body to the `sync-workload-request` function URL**.

**What the employee sees** — one real question:
- A read-only context line (the message that links here already names the task):
  *"Your manager is estimating the workload for: **&lt;task name&gt;**."*
- **Number input (required, ≥ 0):** *"About how many hours a month does this take
  you? A rough estimate is fine."*

That's it — no other fields. (No free-text; keep it a micro-form.)

**Hidden fields** — pre-filled from the deep-link query params that
`send-workload-request` builds, and echoed back unchanged on submit:
- `task_id` (uuid) · `employee_id` (uuid) · `submission_token` (one-time secret)
  · `form_version` (integer, start at `1`).

**On submit, the form automation POSTs** (JSON) to the webhook:
```json
{
  "task_id": "<uuid>",
  "employee_id": "<uuid>",
  "submission_token": "<one-time token>",
  "form_version": 1,
  "hours": 10
}
```
- Send header `x-workload-webhook-token: <shared secret>` (or a `webhook_token`
  body field) — the webhook checks it against `LARK_WORKLOAD_FORM_WEBHOOK_TOKEN`
  and fails closed, exactly like the self-review webhook's
  `x-performance-webhook-token`.
- The webhook also answers Lark's `url_verification` challenge and is deployed
  `verify_jwt = false` (so Lark can reach it) — same as the self-review one.

**The three secrets to configure** (Supabase function env):
- `LARK_WORKLOAD_FORM_TEMPLATE` — the form id, or its full URL.
- `LARK_WORKLOAD_FORM_BASE_URL` — only if the template is an id (the base the id
  is appended to), mirroring `LARK_SELF_REVIEW_FORM_BASE_URL`.
- `LARK_WORKLOAD_FORM_WEBHOOK_TOKEN` — the shared secret above.

**Recipient delivery** uses `employees.lark_user_id` (already stamped by
`sync-lark-employees`), so an employee with no Lark account can't be asked — the
"Ask owner" action must handle that with a clear message.

## Out of scope (revisit when needed)

Everything the parent spec's "Two audiences" section lists beyond the workload
ask: allocation-change acknowledgements, the periodic job-analysis review loop,
and KPI check-ins (which already point at Lark and have their own pending
wiring). Each is its own spec once this loop is proven in use.
