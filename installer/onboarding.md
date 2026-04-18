# Onboarding & first-run setup

Luxium Payroll is for **employers / HR / payroll admins**. Individual
employees do not log in — they are tracked as records that the employer
manages. So there is effectively one user persona per installed app.

Three setup scenarios in order of frequency:

1. [A new employer signs up](#a-new-employer-signs-up) — self-service via the app's signup screen.
2. [A returning admin on a new device / reinstall](#b-new-install-existing-account) — sign in with existing credentials.
3. [Luxium ops stands up a fresh Supabase project](#c-new-supabase-project-luxium-ops) — one-time per-environment bootstrap.

---

## A. New employer signs up

The primary path. Self-service, no Luxium intervention.

### User flow

1. Downloads the app from the Luxium website / App Store / Play Store.
2. First launch → **Create Account** on the login screen.
3. Fills **Company name** + **email** + **password** (min 8 chars).
4. Clicks **Create account**.
5. App calls `Supabase.auth.signUp` → auth user created.
6. App immediately calls the `bootstrap-company` Edge Function with the new
   JWT. The function (using the service-role key) atomically:
   - Inserts a new row in `companies`.
   - Inserts a default hiring entity (`code = MAIN`).
   - Inserts a `users` row linking the auth user to the company.
   - Stamps `app_metadata.app_role = SUPER_ADMIN` and
     `app_metadata.company_id = <new>` on the auth user.
7. App refreshes the session so the new JWT claims are picked up.
8. Router lands on `/dashboard`. The dashboard is empty — all tables (`employees`, `departments`, `shift_templates`, `attendance_day_records`, `payroll_runs`) are fresh.
9. The admin walks through **Settings**:
   - **Company Info** — edit the default hiring entity: fill TIN, SSS employer ID, PhilHealth employer ID, Pag-IBIG employer ID, address, RDO code.
   - **Departments** — create OPS / HR / SLS / … as needed.
   - **Shift Templates** — either sync from Lark or create the first template manually (when manual UI lands; today only sync is wired).
   - **Holidays** — add this year's calendar via the + button.
   - **Integrations** — pick attendance source (Lark vs Manual CSV); disable Lark if the company isn't on Lark.
10. **Employees → Add Employee** for each person on payroll. Assign role scorecards, hiring entity, department.
11. **Payroll → New Run** to process the first period.

### Email confirmation setting

For the frictionless flow above, disable email confirmation in Supabase
dashboard → Auth → Providers → Email → uncheck "Confirm email".

If you leave confirmation on, `signUpEmployer` returns
`SignUpOutcome.emailConfirmationRequired` and the login screen shows
"Check your inbox — confirm your email, then sign in." The user confirms,
signs in, and the `bootstrap-company` call fires on that first sign-in
instead (TODO — today we only call bootstrap on the sign-up return path;
add a post-auth trigger if keeping confirmation on).

### What a brand-new signup sees on first login

| Screen | State |
|---|---|
| Dashboard | KPI cards all zero, chart cards show "No data" |
| Employees | Empty list with "No employees found." |
| Payroll | Empty list, **New Run** CTA visible |
| Settings → Company Info | Default hiring entity `MAIN` with blank TIN/SSS/etc. |
| Settings → Departments | Empty |
| Settings → Integrations | Attendance source = Lark (the default) — switch to Manual Import if not on Lark |

None of these block the admin — they're editable from the start.

---

## B. New install, existing account

The device path — admin reinstalls the app, account already exists.

1. App boots → Supabase SDK checks secure storage. On a fresh install there's no session.
2. Router sees no auth state → redirects to `/login`.
3. Admin enters work email + password → signed in → dashboard.
4. Session persists in Keychain (iOS) / Keystore (Android) / flutter_secure_storage (desktop); next launch auto-logs in.

### Forgot password

1. Admin enters their email on the login screen.
2. Taps **Forgot password?**.
3. App calls `Supabase.auth.resetPasswordForEmail`. Supabase silently returns 200 even for unknown emails (prevents enumeration).
4. Generic message: "If an account exists for …, a reset link is on the way."
5. Admin opens the email → clicks link → sets new password.

Set a project-level redirect URL in Supabase → Auth → URL Configuration. Suggested: `https://payroll.luxium.ph/auth/reset` (a static landing page on the marketing site that says "you can now open the app").

---

## C. New Supabase project (Luxium ops)

Only Luxium ops run this — once per environment (dev, staging, prod).
Individual employer customers do **not** run this.

### 1. Create the Supabase project

- Supabase dashboard → New Project.
- Region: `ap-southeast-1` (Singapore) for PH latency.
- Save the **Project URL**, **anon key** (for app builds), and **service_role key** (for bootstrap function).

### 2. Apply migrations

```bash
supabase link --project-ref <ref>
supabase db push
```

All files under `supabase/migrations/` run in order.

### 3. Seed global roles

The `roles` table has 4 system roles (SUPER_ADMIN, HR_ADMIN, PAYROLL_ADMIN, FINANCE_MANAGER). These are independent of any specific customer — seed them once for the environment.

```bash
# supabase/seed/02_roles.sql
psql <connection-string> < supabase/seed/02_roles.sql
```

Do **not** run `tool/seed.dart` — that's the old single-tenant dev seeder and creates dummy customer data.

### 4. Disable email confirmation (recommended)

Supabase dashboard → Auth → Providers → Email → untick "Confirm email".
This makes signup one-step for employers.

### 5. Deploy Edge Functions

```bash
supabase secrets set SUPABASE_SERVICE_ROLE_KEY=<service-role-key>
# Lark secrets (only if any customer uses Lark):
supabase secrets set LARK_APP_ID=... LARK_APP_SECRET=...

# Deploy everything in supabase/functions/
supabase functions deploy
```

Critical function: **`bootstrap-company`** — without it, signup lands the user in a broken state with no company row.

### 6. Ship the client

```bash
flutter build windows --release \
  --dart-define=SUPABASE_URL=https://<project>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-key> \
  --dart-define=UPDATE_MANIFEST_URL=https://updates.luxium.ph/payroll/version.json
```

Every employer that downloads this binary hits the same Supabase project
and creates their own isolated company via the signup flow. RLS on
`company_id` keeps tenants separated.

### 7. Verify end-to-end

- Sign up a test employer with a disposable email.
- Confirm a new row appears in `companies` with the deriv'd code.
- Confirm the auth user has `app_metadata.app_role = SUPER_ADMIN` and `company_id` set.
- Log in → dashboard renders empty state → edit the `MAIN` hiring entity, add a department, add an employee.
- Log out → log back in — session picks up where left off.

---

## Multi-tenancy posture

**One Supabase project serves many employers** (SaaS model):

- `companies.id` is the tenant key. Every downstream table has a `company_id` FK and company-scoped RLS.
- `users.company_id` is set on signup by `bootstrap-company` and never changes.
- `app_metadata.company_id` in the JWT is what `auth_company_id()` reads in RLS policies.
- The old `user_companies` junction table exists but isn't used — reserved for a future "admin member of multiple companies" feature.

A customer's data is **never** visible to another customer — enforced by Postgres RLS, not just app logic.

---

## Security notes

- The `bootstrap-company` function is callable by any authenticated user, but is **idempotent** — a caller who already has `company_id` in their JWT gets back the existing company_id with no changes.
- Service-role key stays server-only (`supabase secrets set`). Never ship in `--dart-define` or bundle with the app.
- Passwords are Supabase-managed (Argon2id, salted). The app never sees the password hash.
- Supabase default token lifetime: 1 hour access token + 60 day refresh. Secure storage (Keychain / Keystore) holds the refresh token.
- Forgot-password links are single-use and expire after Supabase's default (1 hour, configurable).
