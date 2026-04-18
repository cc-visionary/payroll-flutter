# Payroll Flutter — End-to-end setup guide

First-run checklist for provisioning Supabase + Lark + GitHub Actions so syncs, webhooks, and builds all work.

> **V1 note:** we're running **prod only** — a single Supabase project, no separate dev environment. Every step below targets that one project. When we add a dev env later, duplicate §1, §2, §6, §7 into a second project and point `dev` builds at it via `--dart-define`.

---

## Credential map (where every value lives)

| What | Goes in… | Format |
|---|---|---|
| `SUPABASE_URL` | (a) `--dart-define` when running/building the Flutter app, (b) GitHub Actions secret, (c) NOT set as an Edge Function secret — auto-injected | `https://<ref>.supabase.co` |
| `SUPABASE_ANON_KEY` | (a) `--dart-define`, (b) GitHub Actions secret, (c) auto-injected for Edge Functions | long JWT |
| `SUPABASE_SERVICE_ROLE_KEY` | Edge Function secret (auto-injected) + `create_admin_users.ts` local run | long JWT — **server-side only, never ship in app** |
| `LARK_APP_ID` | Edge Function secret (Supabase dashboard → Project Settings → Edge Functions → Secrets) | `cli_xxxxxxxxxxxxxxxx` |
| `LARK_APP_SECRET` | Edge Function secret | 32-char string |
| `LARK_BASE_URL` | Edge Function secret (optional — defaults to international) | `https://open.larksuite.com/open-apis` (EN) or `https://open.feishu.cn/open-apis` (CN) |
| `LARK_WEBHOOK_TOKEN` | **Optional.** Only needed if you deploy `lark-approval-webhook` (§5). Skip for V1 — payslip approval status updates on manual Refresh instead. | random 32+ char string you pick |
| `LARK_PAYSLIP_APPROVAL_CODE` | Edge Function secret | approval template code from your Lark tenant (see §4) |
| `LARK_CASH_ADVANCE_APPROVAL_CODE` | Edge Function secret | approval template code for cash-advance requests |
| `LARK_REIMBURSEMENT_APPROVAL_CODE` | Edge Function secret | approval template code for reimbursement requests |
| `LARK_HOLIDAY_CALENDAR_ID` | Edge Function secret | Lark shared calendar ID whose events are PH holidays |
| `LARK_SYSTEM_USER_ID` | Edge Function secret | UUID of a `public.users` row that owns server-initiated syncs |

---

## 1. Provision the Supabase project

1. Go to https://supabase.com/dashboard and create **one** project: `payroll-flutter` (region close to PH — Singapore is a good pick).
2. Pick a strong database password and store it in your password manager.
3. Go to **Project Settings → API** and copy:
   - **Project URL** → this is `SUPABASE_URL`
   - **anon public** key → `SUPABASE_ANON_KEY`
   - **service_role** key → `SUPABASE_SERVICE_ROLE_KEY` (keep secret, server-only, **never ship in the Flutter app**)

Install the Supabase CLI once:

```bash
brew install supabase/tap/supabase           # macOS
scoop bucket add supabase https://github.com/supabase/scoop-bucket.git && scoop install supabase  # Windows
yay -S supabase-bin                          # Arch Linux (AUR)
```

Link the repo to your project and push migrations:

```bash
cd "[07] Projects/payroll-flutter"
supabase link --project-ref <project-ref>    # from the dashboard URL, e.g. "abcd1234efgh5678"
supabase db push                             # applies supabase/migrations/*.sql
```

> Never run `supabase db reset` against prod — it drops every table.

---

## 2. Seed initial data + admin users (one command)

Seed data (companies, roles, departments, calendar) **and** admin auth users are both applied by a single Dart CLI — the Prisma-`db seed` equivalent for this project:

```bash
# One-time: copy the example env and fill in secrets
cp env/example.json env/prod.json
$EDITOR env/prod.json
#  └─ add SUPABASE_SERVICE_ROLE_KEY + four strong passwords (≥12 chars)

dart run tool/seed.dart --env env/prod.json
```

Expected output:

```
Target: https://<ref>.supabase.co
Service role: eyJhbGciOiJIUzI1NiIs…
Mode: apply

  ✓ companies: 1 row(s)
  ✓ hiring_entities: 2 row(s)
  ✓ roles: 4 row(s)
  ✓ departments: 4 row(s)
  ✓ payroll_calendars: 1 row(s)
  ✓ created auth user admin@gamecove.ph (SUPER_ADMIN)
  ✓ created auth user hr@gamecove.ph (HR)
  ✓ created auth user payroll@gamecove.ph (ADMIN)
  ✓ created auth user finance@gamecove.ph (ADMIN)

Seed complete.
```

Re-running is safe — every step is an upsert. Existing users transition from `created` to `updated`.

**Flags:**

| Flag | Purpose |
|---|---|
| `--env <path>` | Override env file (default `env/prod.json`) |
| `--dry-run` | Log what would change without writing |
| `--allow-default-passwords` | Accept built-in dev passwords (local / demo ONLY — fails in prod) |
| `-v`, `--verbose` | Extra logging |

**Safety rails the tool enforces:**

- Rejects anything that's not a `service_role` JWT — you can't accidentally feed it the anon key.
- Rejects passwords < 12 chars and the built-in dev defaults unless `--allow-default-passwords` is passed.
- Warns if `SUPABASE_URL` doesn't look like a Supabase domain.
- Never prints passwords; service-role key is truncated in logs.

---

## 3. Create a Lark / Feishu custom app

1. Go to https://open.larksuite.com/app (international) or https://open.feishu.cn/app (CN).
2. Create a **Custom App** — "Internal App", name it "Payroll Integration".
3. On the app's **Credentials & Basic Info** page, copy:
   - **App ID** → `LARK_APP_ID` (looks like `cli_a1b2c3d4e5f6g7h8`)
   - **App Secret** → `LARK_APP_SECRET`
4. Under **Permissions & Scopes**, grant (or request your admin to grant) these scopes:
   - **Attendance**: `attendance:task.user_flow:read`
   - **Calendar**: `calendar:calendar:read`, `calendar:calendar.event:read`
   - **Approval**: `approval:approval.instance:read`, `approval:approval.instance:write`
   - **Contact (optional)**: `contact:user.employee_id:readonly` — to match Lark user IDs to employees
5. **Publish** the app (or distribute within your tenant) so tokens work.

---

## 4. Create the payslip-approval template in Lark

The desktop "Send Payslip Approvals" button posts one Lark approval instance per payslip. You need a template:

1. In Lark, go to **Approval → Approval Admin → Create**.
2. Template name: "Payroll Payslip Review".
3. Add form fields (field IDs must match these — the Edge Function sends them):
   - `payslip_id` (Single line)
   - `employee` (Single line)
   - `gross_pay` (Number)
   - `net_pay` (Number)
4. Set the approval flow (Finance Manager → HR Director → whoever).
5. Publish. Back on **Approval Admin**, open the template's detail page — the URL contains the **approval_code** (e.g. `?approvalCode=7123456789`).
   - Copy it → `LARK_PAYSLIP_APPROVAL_CODE`.

---

## 5. Configure the Lark approval webhook (optional)

> **Skip this entire section** if you want payslip approval status to update only on manual Refresh. Everything else — attendance, leaves, OT, cash advances, reimbursements, holidays, shifts — syncs via the functions in §7 without a webhook. Come back to this section later if you want real-time payslip status updates.

1. In your Lark app → **Event Subscriptions**:
   - **Request URL**: `https://<project-ref>.supabase.co/functions/v1/lark-approval-webhook`
   - **Encrypt Key**: leave blank for V1 (simpler).
   - **Verification Token**: pick a random string (e.g. `openssl rand -hex 32`). Copy it — this is `LARK_WEBHOOK_TOKEN`.
2. Subscribe to these events:
   - `approval_instance` (v2) — all approval status changes.
3. Save. Lark will POST a `url_verification` challenge — the Edge Function already handles it, so it should turn green immediately.

If it fails: check the Supabase Edge Function logs (Dashboard → Edge Functions → `lark-approval-webhook` → Logs).

---

## 6. Set Edge Function secrets in Supabase

Dashboard → **Project Settings → Edge Functions → Manage secrets** (you can also use the CLI):

```bash
supabase secrets set \
  LARK_APP_ID="cli_xxxxxxxxxxxxxxxx" \
  LARK_APP_SECRET="<from step 3>" \
  LARK_BASE_URL="https://open.larksuite.com/open-apis" \
  LARK_PAYSLIP_APPROVAL_CODE="<from step 4>" \
  LARK_CASH_ADVANCE_APPROVAL_CODE="<cash-advance approval template code>" \
  LARK_REIMBURSEMENT_APPROVAL_CODE="<reimbursement approval template code>" \
  LARK_HOLIDAY_CALENDAR_ID="<lark shared calendar id with PH holidays>" \
  LARK_SYSTEM_USER_ID="<uuid of admin user from step 2>"

# Optional — only if you completed §5 (lark-approval-webhook):
# supabase secrets set LARK_WEBHOOK_TOKEN="<from step 5>"
```

> `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are **injected automatically** — you don't set them here.

---

## 7. Deploy the Edge Functions

```bash
supabase functions deploy lark-ping
supabase functions deploy sync-lark-employees
supabase functions deploy sync-lark-shifts
supabase functions deploy sync-lark-attendance
supabase functions deploy sync-lark-leaves
supabase functions deploy sync-lark-ot
supabase functions deploy sync-lark-cash-advances
supabase functions deploy sync-lark-reimbursements
supabase functions deploy sync-lark-calendar
supabase functions deploy send-payslip-approvals

# Optional — only if you completed §5:
supabase functions deploy lark-approval-webhook
```

Verify each deployed:

```bash
supabase functions list
```

---

## 8. Verify Lark credentials work

Call `lark-ping`:

```bash
curl -X POST \
  -H "Authorization: Bearer <SUPABASE_ANON_KEY>" \
  https://<project-ref>.supabase.co/functions/v1/lark-ping
```

Expected response:

```json
{ "ok": true, "app_id": "cli_...", "tenant_access_token_prefix": "t-..." }
```

If you see `LARK_APP_ID / LARK_APP_SECRET` missing → go back to §6. If you see a 99991663 error from Lark → the permissions haven't been approved yet (§3 step 4).

---

## 9. Wire employees to Lark users

Employees are matched automatically: the desktop's **Settings → Lark Integration → "Sync All from Lark"** button calls `sync-lark-employees`, which hits `/contact/v3/users`, then links each Lark user to the local employee by matching `employee_no ↔ employees.employee_number` (case-insensitive). Employees get a green "Linked" badge once their `lark_user_id` is populated.

Prerequisites: the employee's `employee_number` in the app must match the Lark contact's `employee_no` field exactly (ignoring case and whitespace). If a row stays "—", check both sides and re-sync.

---

## 10. Trigger syncs

### From the desktop app (the normal path)

`admin@gamecove.ph` → **Settings → Lark Integration**. Each section has its own "Sync from Lark" button:

| Section | Edge Function | Writes |
|---|---|---|
| Employee Lark User IDs | `sync-lark-employees` | `employees.lark_user_id` |
| Synced Attendance | `sync-lark-attendance` | `attendance_day_records` (upsert by employee+date) |
| Synced Leaves | `sync-lark-leaves` | `leave_requests` |
| Synced Approved OT | `sync-lark-ot` | `attendance_day_records.approved_ot_minutes` + flags |
| Synced Cash Advances | `sync-lark-cash-advances` | `cash_advances` (by `lark_instance_code`) |
| Synced Reimbursements | `sync-lark-reimbursements` | `reimbursements` |

**Payslip approvals (no webhook):** if you skipped §5, payslip status updates require a manual **Refresh** on the Payroll Review screen after approving in Lark. Other approval types (leave, cash advance, reimbursement) always poll via their dedicated sync buttons, so the webhook isn't needed for them regardless.

Plus two separate tabs:
- **Settings → Shift Templates → "Sync from Lark"** → `sync-lark-shifts` → `shift_templates` (rows get a "Lark" badge when `lark_shift_id` is set)
- **Settings → Holidays → "Sync from Lark"** → `sync-lark-calendar` → `calendar_events` with `source='LARK'`; manual rows (`source='MANUAL'`) are never overwritten. The page shows the `holiday_calendars.last_synced_at` timestamp.
  - Recognized holiday tags (parenthesized suffix on the event summary): `(Regular Holiday)` → `REGULAR_HOLIDAY`, `(Special Non-Working Holiday)` → `SPECIAL_HOLIDAY`, `(Special Working Holiday)` → `SPECIAL_WORKING`. Untagged events (employee leaves, miscellaneous events) are silently skipped — the calendar can be a shared HR calendar with mixed content.

Every sync writes one row to `lark_sync_logs` (status / total / created / updated / error counts), visible in the **Sync History** card at the bottom of the Lark page.

### One-off via curl (for ops / debugging)

```bash
CID='11111111-1111-1111-1111-000000000001'
TOKEN=$SUPABASE_ANON_KEY

# Employees (no date range)
curl -X POST https://<ref>.supabase.co/functions/v1/sync-lark-employees \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"company_id\":\"$CID\"}"

# Shift templates
curl -X POST https://<ref>.supabase.co/functions/v1/sync-lark-shifts \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"company_id\":\"$CID\"}"

# Attendance / leaves / OT / cash advances / reimbursements all take {company_id, from, to}
curl -X POST https://<ref>.supabase.co/functions/v1/sync-lark-attendance \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"company_id\":\"$CID\",\"from\":\"2026-04-01\",\"to\":\"2026-04-15\"}"

curl -X POST https://<ref>.supabase.co/functions/v1/sync-lark-leaves \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"company_id\":\"$CID\",\"from\":\"2026-04-01\",\"to\":\"2026-04-15\"}"

curl -X POST https://<ref>.supabase.co/functions/v1/sync-lark-ot \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"company_id\":\"$CID\",\"from\":\"2026-04-01\",\"to\":\"2026-04-15\"}"

curl -X POST https://<ref>.supabase.co/functions/v1/sync-lark-cash-advances \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"company_id\":\"$CID\",\"from\":\"2026-04-01\",\"to\":\"2026-04-15\"}"

curl -X POST https://<ref>.supabase.co/functions/v1/sync-lark-reimbursements \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"company_id\":\"$CID\",\"from\":\"2026-04-01\",\"to\":\"2026-04-15\"}"

# Holidays: takes year; calendar_id defaults to env LARK_HOLIDAY_CALENDAR_ID
curl -X POST https://<ref>.supabase.co/functions/v1/sync-lark-calendar \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"company_id\":\"$CID\",\"year\":2026}"
```

Every function returns `{ ok, total, created, updated, skipped, errors }`. Re-running over the same window is safe — idempotent upserts should yield `created=0, updated=N`.

### Scheduled (daily cron for attendance)

In Supabase SQL editor, using `pg_cron` + `pg_net`:

```sql
create extension if not exists pg_cron;
create extension if not exists pg_net;

select cron.schedule(
  'lark-attendance-daily',
  '15 1 * * *',  -- every day at 01:15 UTC = 09:15 PH
  $$
  select net.http_post(
    url := 'https://<ref>.supabase.co/functions/v1/sync-lark-attendance',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || current_setting('app.settings.anon_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object(
      'company_id', '11111111-1111-1111-1111-000000000001'
    )
  );
  $$
);
```

First: `alter database postgres set app.settings.anon_key = '<anon-key>';` (once).

### From the desktop app

All sync buttons are in **Settings → Lark Integration / Shift Templates / Holidays** — see §10 above. Internally they call `ref.read(larkRepositoryProvider).sync*()` which wraps `client.functions.invoke(...)`. `PayrollRepository.sendPayslipApprovals(runId)` (separate flow) calls `send-payslip-approvals`.

---

## 11. Flutter — use an `env/prod.json` file instead of flags

Flutter 3.7+ supports `--dart-define-from-file`, which is the cleanest way to inject `SUPABASE_URL` / `SUPABASE_ANON_KEY` into the app without leaking them into shell history or your IDE run config.

```bash
# One-time:
cp env/example.json env/prod.json     # env/*.json is gitignored (except example.json)
$EDITOR env/prod.json                  # paste SUPABASE_URL + SUPABASE_ANON_KEY (not service role!)

# Run the app locally:
flutter run -d linux   --dart-define-from-file=env/prod.json     # Arch/Linux
flutter run -d windows --dart-define-from-file=env/prod.json     # Windows
flutter run -d macos   --dart-define-from-file=env/prod.json     # macOS

# Release builds:
flutter build windows --release --dart-define-from-file=env/prod.json
flutter build macos   --release --dart-define-from-file=env/prod.json
flutter build linux   --release --dart-define-from-file=env/prod.json
```

No code changes needed — `const String.fromEnvironment('SUPABASE_URL')` in `lib/core/env.dart` automatically picks the values up at compile time.

> **Never** put the `service_role` key in `env/prod.json` — that JWT bypasses RLS. Only `anon` goes in the client; `service_role` only ever lives server-side (Edge Functions + the one-off seed script).

---

## 12. Add GitHub Actions secrets (for installer CI)

GitHub → your repo → **Settings → Secrets and variables → Actions → New repository secret**:

| Name | Value |
|---|---|
| `SUPABASE_URL` | project URL from step 1 |
| `SUPABASE_ANON_KEY` | anon key from step 1 |

The CI workflow (`.github/workflows/release.yml`) already reads these via env and passes them as `--dart-define` to `flutter build`. Tag `v0.1.0` → `release.yml` builds the Windows `.exe`, macOS `.dmg`, and Linux `.AppImage`, runs engine tests, and attaches artifacts to a GitHub Release.

> V1 ships prod credentials in every build. When we add a dev environment, split into `main` → dev builds and tags → prod builds.

---

## 13. End-to-end smoke test

1. Log in as `admin@gamecove.ph`.
2. **Settings → Lark Integration → Test Connection** → green.
3. **Employee Lark User IDs → Sync All from Lark** → every linked employee gets a "Linked" badge.
4. **Settings → Shift Templates → Sync from Lark** → shift rows appear with a "Lark" badge.
5. **Settings → Holidays → Sync from Lark** (year = 2026) → rows appear with SOURCE=LARK. Click **Add Holiday** → new row SOURCE=MANUAL. Re-sync Lark → MANUAL row is preserved.
6. On the Lark Integration page, set a date range that covers real Lark data, then click **Sync from Lark** on each card (Attendance, Leaves, OT, Cash Advances, Reimbursements) → each shows last-N rows + adds a row to **Sync History** (status=COMPLETED).
7. Re-run any sync over the same range → `created=0, updated=N` (proves idempotency).
8. **Payroll** → create a run → compute → REVIEW → click **Send** → Lark users receive approval cards.
9. Approve them in Lark. If you deployed `lark-approval-webhook` (§5), status updates within seconds; otherwise click **Refresh** on the Review screen → `payslips.approval_status` flips to APPROVED → counts go green → **Release** enables.
10. On any payslip, open **Payslip preview** → PDF opens with `print` / `share` buttons.

If every step passes — Lark syncing works end to end.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `lark-ping` → `LARK_APP_ID missing` | secrets not set | run `supabase secrets set …` in §6 |
| `lark-ping` → code `99991663` | permissions not approved | in the Lark app → Permissions, ensure every scope is **Enabled** |
| `sync-lark-attendance` returns `{ created: 0 }` | no employees have `lark_user_id` | step 9 |
| *(if using §5)* Webhook 401 | `LARK_WEBHOOK_TOKEN` mismatch between Lark & Supabase secrets | re-copy, redeploy with `supabase functions deploy lark-approval-webhook` |
| *(if using §5)* Payslip row stays `PENDING_APPROVAL` after approval in Lark | webhook URL wrong | check Lark app's Request URL = `https://<ref>.supabase.co/functions/v1/lark-approval-webhook` |
| Payslip row stays `PENDING_APPROVAL` after approval (no webhook deployed) | expected — click **Refresh** on the Payroll Review screen | or deploy the webhook per §5 for real-time updates |
| All rows come back empty after sync | `LARK_BASE_URL` wrong (EN vs CN tenant) | set `LARK_BASE_URL=https://open.feishu.cn/open-apis` for CN |
| `sync-lark-cash-advances` / `-reimbursements` → "APPROVAL_CODE env var required" | template code not set | `supabase secrets set LARK_CASH_ADVANCE_APPROVAL_CODE=… LARK_REIMBURSEMENT_APPROVAL_CODE=…` + redeploy |
| `sync-lark-calendar` → "calendar_id required" | no default holiday calendar | `supabase secrets set LARK_HOLIDAY_CALENDAR_ID=<id>` (or pass `calendar_id` in the request body) |
| Holiday row you added manually disappeared after sync | — | it shouldn't; `source='MANUAL'` rows are preserved. If it vanished, check `calendar_events.source` — may be mis-stamped |
| Shift templates list is empty after sync | Lark contact scope `attendance:shift:read` not granted | in Lark app → Permissions, enable it, reapprove |
| `sync-lark-leaves` → "unmapped leave_type" errors | `leave_types.lark_leave_type_id` not set | in `leave_types`, set `lark_leave_type_id` to each Lark leave template ID |
