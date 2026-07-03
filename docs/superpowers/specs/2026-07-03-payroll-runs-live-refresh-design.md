# Payroll Runs List — Cross-Client Live Refresh

**Date:** 2026-07-03
**Branch:** `feat/payroll-runs-live-refresh`
**Status:** Approved design — ready for implementation plan

## Problem

List screens load their data once through a `FutureProvider` (fetch-once +
cache) and only ever `ref.invalidate(...)` in response to the **current user's**
own actions (delete, release, refresh buttons). Nothing tells an open list that
a **colleague on another PC** changed the underlying data. So when someone
releases or creates a payroll run elsewhere, the Payroll Runs list a user is
staring at stays stale, and there is no way to refresh it short of navigating
away and back.

The run **detail** screen does not have this problem: it subscribes to a
Supabase Realtime channel and auto-invalidates its providers whenever
`payroll_runs` / `payslips` rows change server-side
(`payroll_run_detail_screen.dart:49-73`). The **list** screens simply never got
the same wiring.

This design extends that existing, proven pattern to the Payroll Runs list, and
factors the boilerplate into one small reusable helper so the next list screen
is cheap to wire up.

## Goal

The Payroll Runs list (`payroll_runs_screen.dart`) updates itself within ~1s of
any `payroll_runs` / `payslips` change made from any client, with no user
action, no page reload, and no lost scroll position. A manual refresh control is
added as a safety net for dropped sockets.

## Non-goals (YAGNI)

Explicitly excluded during brainstorming:

- **No DB migration.** `payroll_runs`, `payslips`, `payslip_lines` are already
  in the `supabase_realtime` publication
  (`supabase/migrations/20260418000003_realtime_payroll.sql`). This is a pure
  client-side Flutter change.
- **No `StreamProvider` rewrite.** `payrollRunsProvider` stays a
  `FutureProvider`; Realtime drives `invalidate`, it does not replace the
  provider.
- **No other list screens yet** (Employees, Attendance, Compliance,
  Documents...). The reusable helper makes those a small follow-up, but they are
  out of scope for this change.
- **No polling, no interval timers** as the primary mechanism.

## Approach

Mirror the detail screen's imperative `initState`/`dispose` Realtime pattern so
the new code reads like the code already in the repo, but extract the channel
lifecycle into a mixin.

### 1. New helper — `lib/widgets/live_refresh.dart`

A `LiveRefreshMixin` on `ConsumerState<T>` that manages one `RealtimeChannel`:

- A single method, called from the screen's `initState`, e.g.
  `startLiveRefresh(channel: 'payroll-runs-list', tables: [...], onChange: ...)`.
- Registers one `onPostgresChanges(event: all, schema: 'public', table: t)`
  listener **per table**, with **no row filter** — a list wants notifications
  about *all* rows, unlike the detail screen which filters `id=eq.<runId>`.
- **Debounce:** coalesces bursts (e.g. a bulk release touching 8 payslips) into
  a single `onChange` via a ~300ms timer, so one action ⇒ one re-fetch.
- **Safety:** the debounced callback is guarded by `mounted` before firing.
- **Cleanup:** `unsubscribe()`s the channel and cancels the debounce timer in
  `dispose()`.

The mixin owns only channel + timer lifecycle. It does not know which providers
exist — the screen supplies the `onChange` callback that does the invalidation.

### 2. Wire it into `payroll_runs_screen.dart`

- Convert the screen from `ConsumerWidget` → `ConsumerStatefulWidget` with
  `LiveRefreshMixin`.
- `initState` → `startLiveRefresh(channel: 'payroll-runs-list', tables:
  ['payroll_runs', 'payslips'], onChange: _invalidate)`.
- `_invalidate` invalidates the providers the page already reads:
  `payrollRunsProvider` and the per-run `payslipApprovalCountsProvider`
  currently invalidated by the page's own handlers.
- The existing user-action `invalidate` calls stay as-is (they give instant
  local feedback without waiting for the Realtime round-trip).

### 3. Manual refresh control (safety net)

Add a small refresh `IconButton` to the "Payroll Runs" header that runs the same
`_invalidate`. Covers the rare case where the Realtime socket dropped (laptop
asleep, network blip) and a broadcast was missed. Cheap insurance, and directly
answers the "there's no refresh" complaint.

## Data flow

```
Colleague releases a run (PC A)
  → Postgres UPDATE payroll_runs (+ payslips)
  → Supabase Realtime broadcast
  → 'payroll-runs-list' channel callback (PC B)
  → debounce ~300ms
  → _invalidate(): ref.invalidate(payrollRunsProvider, approvalCounts...)
  → FutureProvider re-fetches
  → row flips REVIEW → RELEASED on PC B  (~1s, scroll preserved)
```

## Testing

- **Widget test** (`test/widgets/live_refresh_test.dart` — tests mirror the
  `lib/` path): a host `ConsumerStatefulWidget` using the mixin invalidates the
  supplied provider when a simulated postgres event fires, debounces multiple
  rapid events into one `onChange`, and does not fire after dispose /
  unsubscribes the channel.
- **Manual two-window verification:** run two app instances signed in as
  different users; release a run in window A; confirm window B's list flips
  `REVIEW → RELEASED` within ~1s without interaction, and that the manual
  refresh button re-fetches on demand.

## Files touched

| File | Change |
|------|--------|
| `lib/widgets/live_refresh.dart` | **new** — `LiveRefreshMixin` (channel + debounce lifecycle) |
| `lib/features/payroll/runs/payroll_runs_screen.dart` | `ConsumerWidget` → `ConsumerStatefulWidget` + mixin; `_invalidate`; header refresh button |
| `test/widgets/live_refresh_test.dart` | **new** — mixin invalidate/debounce/dispose test |

No database, edge-function, or migration changes.
