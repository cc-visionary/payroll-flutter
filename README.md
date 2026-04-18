# Payroll Flutter

Cross-platform Flutter + Supabase port of [payrollos](../payrollos) — a PH-compliant payroll system with a battle-tested calculation engine.

Desktop-first (Windows primary). Also builds for macOS, Linux, iOS, and web.

## Quick start

```bash
flutter pub get

# Run locally (point at your Supabase dev project)
flutter run -d linux \
  --dart-define=SUPABASE_URL=https://<project>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-key>
```

## Project structure

| Path | Purpose |
|---|---|
| `lib/features/payroll/engine/` | **Pure-Dart payroll computation engine** — ported 1:1 from `payrollos/lib/payroll/*.ts`. All money uses `Decimal`. |
| `lib/features/` | Auth, employees, responsibility cards, attendance, payroll runs, payslip PDF |
| `lib/data/` | Models + Supabase-backed repositories |
| `supabase/migrations/` | 14 SQL migrations covering all 46 Prisma models + RLS |
| `supabase/functions/` | Deno Edge Functions for Lark sync + approval webhooks |
| `test/engine/` | Engine smoke tests + PDF golden tests |
| `installer/windows/` | Inno Setup script for the `.exe` installer |
| `.github/workflows/` | CI + release matrix (Windows / macOS / Linux) |

## Building releases

Tag `vX.Y.Z` on `main` — GitHub Actions runs engine tests, builds all three desktop targets, and attaches the artifacts to a release:

- `PayrollFlutter-Setup-vX.Y.Z.exe` (unsigned Inno Setup installer)
- `PayrollFlutter-X.Y.Z.dmg`
- `PayrollFlutter-X.Y.Z-x86_64.AppImage`

Local Windows build: see [`installer/windows/README.md`](installer/windows/README.md).

## Engine parity

The payroll engine is **non-negotiable** — every payslip must match payrollos byte-for-byte. Smoke tests live in `test/engine/`; full parity fixtures (50+ real payslip input/output pairs dumped from the payrollos dev DB) plug in via:

```bash
flutter test test/engine/
```

## Required secrets (GitHub Actions)

| Secret | Used by |
|---|---|
| `SUPABASE_URL` | `build` job (compile-time `--dart-define`) |
| `SUPABASE_ANON_KEY` | `build` job |

Edge Function secrets (set in the Supabase dashboard, not GitHub):

| Var | Purpose |
|---|---|
| `LARK_APP_ID` / `LARK_APP_SECRET` | Lark Open Platform custom app credentials |
| `LARK_BASE_URL` | `https://open.larksuite.com/open-apis` (international) or `https://open.feishu.cn/open-apis` (CN) |
| `LARK_WEBHOOK_TOKEN` | Shared secret for approval webhook |
| `LARK_PAYSLIP_APPROVAL_CODE` | Lark approval-template code |
| `LARK_SYSTEM_USER_ID` | UUID used for `lark_sync_logs.synced_by_id` |
