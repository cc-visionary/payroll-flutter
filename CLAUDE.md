# payroll-flutter — Claude Code project instructions

Flutter desktop payroll app for Luxium HQ. Backend: Supabase (Postgres + Edge Functions in Deno). Lark integration for HR data sync (attendance, leaves, OT, holidays, approvals).

## Design System

This project uses the **Luxium brand** — full design context in `.impeccable.md`.

Quick rules (override Flutter defaults):

- **Theme:** Light + dark, system-driven. Light = website-verbatim; dark = brand-tinted.
- **Single CTA color:** Luxium purple `#635BFF` (light) / `#7F7DFC` (dark). Never use cyan/sky-blue accents.
- **Typography:** Satoshi (display + body) + Geist Mono (numbers, IDs, dates, currencies).
- **Radius:** 6px default; pills only for primary CTAs and badges.
- **Spacing:** 4px grid — `4 · 8 · 12 · 16 · 24 · 32 · 48 · 64`.
- **Status chips:** tinted background + darker text, no colored borders.

Before adding new screens, components, or chips, read `.impeccable.md`.
Sibling brand reference: `/home/ccvisionary/Documents/Work/[07] Projects/luxium-website` (Next.js + Tailwind + shadcn).

## Tech stack

- Flutter (Material 3, Riverpod state, GoRouter routing)
- Supabase (Postgres + Edge Functions in Deno + Realtime)
- Lark Open Platform (international `larksuite.com`)

## Conventions

- Tables → wrap with `lib/widgets/responsive_table.dart` (max 1100px, horizontal-scroll fallback).
- Edge Functions live in `supabase/functions/<name>/index.ts`; share helpers via `supabase/functions/_shared/`.
- Run Supabase function tests with `deno test supabase/tests/<name>_test.ts`.
- Deploy edge functions with `supabase functions deploy <name>`.
