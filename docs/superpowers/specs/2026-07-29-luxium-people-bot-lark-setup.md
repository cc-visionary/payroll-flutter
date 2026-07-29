# Luxium People Bot — Lark-Side Setup Guide

## Overview

This guide walks an admin through configuring the **Luxium People** self-service bot in the Lark Developer Console. The bot surfaces employee-scoped payslips, leave & attendance, tasks, performance reviews, and personal info via a stateless Supabase edge function.

See the full design specification: [`2026-07-29-employee-self-service-bot-design.md`](./2026-07-29-employee-self-service-bot-design.md).

---

## Bot Application Details

| Field | Value |
|-------|-------|
| **App Name** | Luxium People |
| **App ID** | `cli_a91b76848c78deed` |
| **Platform** | Lark international (`open.larksuite.com`) |
| **Handler URL** | `https://tsylbligjojkhpaobcsi.supabase.co/functions/v1/lark-bot-handler` |

---

## Lark Developer Console Setup Checklist

### 1. Enable Bot Feature

1. Log into the [Lark Developer Console](https://open.larksuite.com/app).
2. Navigate to your **Luxium People** app.
3. Go to **Feature Management** → **Bot**.
4. Toggle **Enable Bot** to **ON**.
5. Save.

---

### 2. Configure Permissions & Scopes

1. Go to **Permissions & Scopes**.
2. Add the following bot message scopes:
   - `im:message` — receive p2p messages from users
   - `im:message:send_as_bot` — send messages as the bot to individual users
3. **Publish a new version** (e.g., v1.0.0) so the scopes take effect.
4. Save.

---

### 3. Configure Custom Bot Menu

1. Go to **Bot** → **Custom Bot Menu**.
2. Add the following five menu items (in order). Each item must have an exact `event_key`:

| Label | Event Key | Type |
|-------|-----------|------|
| My Payslip | `my_payslip` | Card |
| My Leave & Attendance | `my_leave` | Card |
| My Tasks & Responsibilities | `my_tasks` | Card |
| My Reviews | `my_reviews` | Card |
| My Info | `my_info` | Card |

3. Save. The menu items will appear at the top of DM conversations with the bot.

---

### 4. Subscribe to Events & Configure Callbacks

#### Events Tab

1. Go to **Events & Callbacks** → **Events** tab.
2. Under **Subscribe to Events**, enable:
   - **Message received** (`im.message.receive_v1`) — triggered when a user DMs the bot
   - **Bot menu clicked** — triggered when a user taps one of the five custom menu items above
3. Save.

#### Event Configuration & Request URL

1. Go to **Event Configuration** (on the same Events tab or a sub-tab).
2. Set **Subscription Mode** to **"Send callbacks to developer's server"** (not "persistent connection").
   - *Rationale:* The Supabase edge function is stateless and cannot hold open WebSocket connections.
3. Set **Request URL** to: `https://tsylbligjojkhpaobcsi.supabase.co/functions/v1/lark-bot-handler`
4. Do **NOT** test the URL yet; the Encryption Strategy keys must be in place first (see step 5).
5. Save.

#### Callback Configuration Tab (No Action Needed)

- The **Callback Configuration** tab is for interactive card buttons (rich cards with click handlers).
- Our v1 cards are read-only (no buttons), so **no callback subscription is needed**.
- You may see a warning; it is safe to ignore.

---

### 5. Set Up Encryption Strategy

1. Go to **Event Configuration** → **Encryption Strategy**.
2. Generate a new **Encrypt Key** and **Verification Token** in the Lark console (if not already done).
3. **Keep the Encrypt Key and Verification Token safe** — they must be set as environment secrets on Supabase:
   - `LARK_BOT_ENCRYPT_KEY=<your-encrypt-key>`
   - `LARK_BOT_VERIFICATION_TOKEN=<your-verification-token>`
4. **If these were already generated and set on Supabase**, you do NOT need to rotate them. The console and Supabase must use the same values. If they are ever rotated in the future, the new values must be re-set on Supabase.
5. Save.

---

### 6. Verify the Bot Handler

1. After Encryption Strategy is configured and Supabase secrets are set, go back to **Event Configuration**.
2. Click **Verify URL** (or **Test URL Verification**).
3. The handler will receive an encrypted `url_verification` challenge, decrypt it, and respond with the challenge token.
4. **Expected result:** Green checkmark (✓) indicating successful verification.
5. If verification fails:
   - Double-check that the **Encrypt Key** and **Verification Token** in the Lark console exactly match the Supabase secrets.
   - Verify the **Request URL** is correct: `https://tsylbligjojkhpaobcsi.supabase.co/functions/v1/lark-bot-handler`.
   - Check Supabase edge function logs for errors.

---

### 7. Test the Bot

1. Open **Lark** on your device.
2. Search for or navigate to the **Luxium People** bot.
3. **Send a direct message (DM)** to the bot. You should receive a reply card.
4. **Tap each of the five custom menu items** at the top of the DM conversation:
   - **My Payslip** → Returns a masked payslip card (last 4 digits of account, salary range, status).
   - **My Leave & Attendance** → Returns leave balance and recent attendance summary.
   - **My Tasks & Responsibilities** → Returns assigned tasks and role responsibilities.
   - **My Reviews** → Returns performance reviews (self-reviews, peer reviews, etc.).
   - **My Info** → Returns personal info (name, role, team, email).
5. **Expected behavior:**
   - Each menu item returns a **scoped, masked card** (only the logged-in user's data).
   - Cards display only **RELEASED** payslips and data (not drafts or scheduled changes).
   - Cards show **masked financial fields** (e.g., account last 4 digits, salary in ranges).
   - If an employee is **not yet linked** (no `lark_user_id` in the database), they receive a "not linked yet — contact HR" message with instructions to run the employee sync.

#### Troubleshooting During Test

| Issue | Cause | Fix |
|-------|-------|-----|
| "Not linked yet" for all users | `employees.lark_user_id` not populated (Lark sync not run) | Run the **Employees → Lark** sync under Settings → Integrations to stamp `lark_user_id` on employees. Currently ~8 employees have this field set. |
| Card shows wrong user's data | `user_id` type mismatch in event payload | Verify the Lark event payload emits `user_id` (not `open_id`). Contact Lark support if events only provide `open_id`. |
| Handler returns 400 or 403 | Encryption key mismatch | Verify Lark console Encryption Strategy keys match Supabase secrets exactly. |
| Handler returns 500 | Edge function error | Check Supabase edge function logs. Verify database connection and RLS policies allow the function's service-role access. |

---

## Deployment Checklist

- [ ] Bot feature **enabled** in Lark console.
- [ ] Permissions & Scopes added and **version published**.
- [ ] Five custom menu items created with exact `event_key`s.
- [ ] `im.message.receive_v1` and bot-menu events **subscribed**.
- [ ] Subscription mode set to **"Send callbacks to developer's server"**.
- [ ] Request URL set to **`https://tsylbligjojkhpaobcsi.supabase.co/functions/v1/lark-bot-handler`**.
- [ ] **Encrypt Key** and **Verification Token** set in Lark console.
- [ ] Supabase secrets configured: `LARK_BOT_ENCRYPT_KEY` and `LARK_BOT_VERIFICATION_TOKEN`.
- [ ] URL verification **goes green** ✓.
- [ ] All five menu items tested; correct scoped, masked cards returned.
- [ ] Only employees with `lark_user_id` can resolve; others get link-prompt card.

---

## Notes

- **No database migration required** — all reads hit existing tables (`employees`, `payroll_runs`, `leave_balances`, `role_scorecards`, `performance_reviews`, `users`).
- **Edge function is stateless** — hence Subscription Mode = "Send callbacks to developer's server" (not persistent connection).
- **Cards are read-only in v1** — no Callback Configuration needed for card buttons; this is a future enhancement.
- **Email and user identity resolution** — the handler matches the Lark `user_id` from the event payload to `employees.lark_user_id` for data scoping. If events only emit `open_id`, the user will not resolve.
