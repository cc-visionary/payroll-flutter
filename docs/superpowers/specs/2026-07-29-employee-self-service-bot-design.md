# Luxium People Self-Service Bot — Design

**Date:** 2026-07-29 · **Roadmap:** Lark integration #4 (outbound / employee-facing). See `2026-07-25-lark-integration-strategy-design.md`. **Builds on:** the identity mapping `employees.lark_user_id` (stamped by `sync-lark-employees`) and the shared Lark rails (`_shared/lark.ts`).

## Goal

Let an employee, inside Lark, tap the **Luxium People** bot menu (or send a keyword) and get an interactive card showing **their own** data across five domains: payslip, leave & attendance, tasks & responsibilities, reviews, and personal/statutory info. Read-only. No login — the employee's identity comes from Lark's verified event.

**Explicitly deferred (future project):** the richer **web portal** (OAuth web view) and **employee self-update** (writeback, e.g. bank details). This spec is the bot only. The web portal will reuse this same identity→employee bridge.

## Non-goals (YAGNI)

- No NLP — keyword matching only, with a help fallback.
- No write actions — fully read-only.
- No web view / OAuth — bot surface only.

## Architecture

One edge function, `lark-bot-handler` (Deno; `verify_jwt = false` so Lark can reach it; reuses `_shared/lark.ts`). Request lifecycle:

1. **Verify.** Answer Lark's `url_verification` challenge. Decrypt the event body with the **Encrypt Key** and validate the **Verification Token**. Fail closed: an unset secret or bad token → drop (no data, no detail leaked). Mirrors the fail-closed posture of `sync-performance-self-review` / `lark-approval-webhook`.
2. **Identify.** Extract the sender's `user_id` (fall back to `open_id`) from the event. Map → `employees.lark_user_id` (single active, non-deleted row). No match → a friendly "your Lark account isn't linked yet — contact HR" card. **Security boundary: the employee is ALWAYS derived from Lark's verified event, never from anything a card/button sends back.**
3. **Route.** Bot-menu event → switch on the menu `event_key`. Text message → match keywords (`payslip`, `leave`, `tasks`/`responsibilities`, `reviews`, `info`) → intent; unknown → help card listing the menu.
4. **Build + reply.** Fetch the employee's data (service-role client, scoped to their `employee_id`), build an interactive card, send via the messaging API (`POST /im/v1/messages`, `receive_id_type=user_id`, `msg_type=interactive`).

Two supported inbound event types: `im.message.receive_v1` (keyword path) and the **custom bot-menu event** (`event_key` path — exact event name confirmed against current Lark docs at build time). Both resolve to the same intent enum, so the router is agnostic to which surface fired.

## The five cards — data sources + rules

| Intent (`event_key`) | Card contents | Source |
|---|---|---|
| `my_payslip` | Latest **RELEASED** payslip: pay period, net pay, gross, total deductions, SSS/PhilHealth/Pag-IBIG EE, withholding tax, YTD gross/tax. Footer: "Full PDF in the portal (coming soon)." | `payslips` where `approval_status = 'RELEASED'`, joined to `payroll_runs` for the period, newest first |
| `my_leave` | Available balance per leave type (`opening_balance + accrued + carried_over + adjusted − used − forfeited − converted`), current year; plus a short recent-attendance summary | `leave_balances` (+ `leave_types` for names) and `attendance_day_records` |
| `my_tasks` | Their tasks with role (PRIMARY/CONTRIBUTOR) + `allocation_pct`, grouped; plus role responsibility areas | `wp_task_assignments` (employee_id) → `wp_tasks` (name, responsibility_area); role via `employees.role_scorecard_id → role_scorecards` |
| `my_reviews` | Latest formal review: status, outcome, overall rating (1–5); plus count + latest date of synced self-evals | `employee_reviews` (newest by cycle) + `lark_self_eval_responses` |
| `my_info` | Personal (name, birthday, contact, address), statutory IDs, bank accounts — **masked to last 4** (e.g. `SSS ••••1234`, `GCash ••••5678`) | `employees` + `employee_statutory_ids` + `employee_bank_accounts` |

**Cross-cutting rules:** payslips surface only when `approval_status = 'RELEASED'` (never DRAFT/PENDING). Statutory + bank numbers are always masked to last-4. Every card footers with "Something looks wrong? Contact HR."

## Error handling & edge cases

- **Unlinked sender** (no `lark_user_id` match) → "not linked yet, contact HR" card.
- **No data yet** (e.g. no released payslip, no reviews) → friendly empty state per card, not an error.
- **Verification failure** (bad token / decrypt) → return 200 with no action; log server-side only. Never echo why.
- **Handler exception** → generic "please try again or contact HR" card; real error logged server-side, never sent to the user.
- **Idempotency / retries:** Lark may retry events; replies are naturally idempotent (a re-sent card is harmless). No dedup store needed.

## Security

- `verify_jwt = false` + Encrypt Key + Verification Token are the gate; fail closed.
- Employee identity is derived server-side from the verified event only.
- Service-role reads are always filtered by the resolved `employee_id`; no query trusts client input.
- Sensitive numbers masked; unreleased payroll never shown.
- Config in **Supabase edge-function secrets** (new: `LARK_BOT_ENCRYPT_KEY`, `LARK_BOT_VERIFICATION_TOKEN`). `LARK_APP_ID/SECRET` already set.

## Components (isolation)

- `lark-bot-handler/index.ts` — HTTP entry: verify → identify → route → reply.
- `_shared/lark_events.ts` — pure: decrypt + verify + parse event → `{ senderUserId, intent }`. Unit-tested.
- `_shared/bot_cards.ts` — pure card builders (one per intent) + the `maskLast4` helper. Unit-tested with sample data (no Lark/DB).
- Data reads live in the handler (service-role client), thin per-domain fetch helpers.

## Lark-side setup (user; captured in a companion doc)

Bot send/receive message scopes · enable "Message received" + bot-menu events · define the 5 custom menu items with the `event_key`s above · **Events & Callbacks → "Send callbacks to developer's server"** → the deployed function URL · set Encrypt Key + Verification Token (→ stored as the two new secrets). Not "persistent connection" mode (doesn't fit stateless edge functions).

## Testing

- Pure unit tests: each card builder (incl. empty states), `maskLast4`, the event parser/router (event → intent), and decrypt/verify (with a known Encrypt Key vector).
- A "who am I" probe path (temporary) to confirm identity mapping against real `lark_user_id`s before menus are wired, returning name only (no sensitive data).
- Manual: link a test employee, tap each menu item, confirm correct scoped data + masking.

## Sequencing

1. Migration: none (all reads on existing tables).
2. Pure modules + tests (`lark_events.ts`, `bot_cards.ts`).
3. `lark-bot-handler` + deploy + set the two secrets.
4. Identity probe → verify mapping.
5. User wires the Lark bot (scopes/events/menu/callback) per the companion doc.
6. End-to-end test each card.
