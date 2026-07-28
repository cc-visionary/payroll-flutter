# Lark ↔ App Integration Strategy

> Date: 2026-07-25. The durable **map** of how Lark (Feishu) and this payroll app
> fit together as one HR-payroll system: who owns what, how data crosses, and the
> prioritized roadmap of integration work. This is a *strategy*, not a single
> implementation spec — each concrete piece below (master-data sync, self-eval
> sync, …) gets its own spec → plan → build cycle.

## The goal

One HR-payroll system where **Lark is where the people are** and **the app is
where the money and planning get computed** — integrated so nobody types the
same fact twice and the two never disagree on the numbers that move money.

## The boundary — two systems

| | **Lark (Feishu)** | **The App (payroll-flutter)** |
|---|---|---|
| Role | System of **engagement** + source-of-truth for **people & time** | System of **computation & record** for **money & planning** |
| Holds | Employee master data (Lark Base), attendance, leave, OT, shifts, calendar; forms, approvals, messaging, **automations** | Payroll engine (gross/net, SSS/PhilHealth/Pag-IBIG, payslips), workforce/accountability model, document generation, the **manager cockpit** |
| Who touches it | **Employees & HR**, in the tool they already live in | **Managers/HR/Finance**, for decisions & computation |

The app should own **only what Lark can't do**: computation, cross-employee
financial logic, the workforce/accountability model ([[project_accountability_model]]),
document generation, and the manager decision surface.

## System of record — who owns each domain

| Domain | Owner | App's job |
|---|---|---|
| **Employee master data** (personal, TIN/SSS/PhilHealth/Pag-IBIG, Metrobank/GCash) | **Lark Base** (via the "Employee Information for Onboarding" form) | **sync in, read-only mirror** |
| Attendance / leave / OT / shifts / calendar | **Lark** | sync in → feed payroll |
| **Payroll / payslips / statutory contributions** | **App** | own it; push approvals to Lark |
| **Workforce / accountability planning** | **App** | own it (built, steps 1–6) |
| Performance / self-evaluations | **Lark** (forms + automations) | **sync responses in** to track |
| Approvals (payslip / leave / OT / cash-advance) | **Lark** (native Approvals) | initiate where needed + sync decisions |
| Documents / contracts | **App** | generate; deliver via Lark |

## The three flows — the only ways data crosses

1. **Lark → App (SYNC / ingest).** The app pulls what it needs to compute and
   track. *Most integration lives here.* Existing: attendance, leave, OT, shifts,
   calendar, cash advances, reimbursements, employee **identity**. New: employee
   **master-data field values**, and self-eval **responses**.
2. **App → Lark (PUSH / engage).** The app pushes computed artifacts a person
   must act on — **payslip approvals** (built), generated documents, "payslip
   ready" notifications — using Lark's **native** Approvals + messaging. The app
   never renders an employee-facing UI of its own.
3. **Lark ⟲ Lark (native automations — app stays out).** Anything triggered by a
   date or a field: the onboarding **probationary-evaluation reminders** and the
   self-eval **sends** already run as **Lark Base Automations** (trigger on Start
   Date → send Lark message/form). The app does **not** rebuild these.

## The guiding rule

**Never reinvent in the app what Lark's Base / Automations / Forms / Approvals
already do.** Default test for any new employee-facing need, in order:
1. Can Lark's Base/Automations/Forms/Approvals do it? → **Lark-native** (app stays out).
2. Does the app need the resulting data to compute or track? → add a **sync**.
3. Does the app produce something a person must act on? → **push** (approval / message / document).

This is the lesson the self-evals taught: the reflex was "build a scheduler +
send pipeline"; the right answer was "Lark already sends it — just sync the
answers."

## The master-data rule — one-way, Lark-primary (locked)

For every field on the onboarding "Employee Information" form (personal, the four
statutory IDs, bank/GCash):

- Direction is **one-way: Lark → App. Lark is primary.**
- HR maintains master data in **one** place — the Lark form/Base — never twice.
- The app **mirrors** these fields (surfaced as "synced from Lark," **not**
  independently editable), so a payroll run and Lark can never disagree on a TIN,
  an SSS number, or a disbursement account.
- Rationale: the alternative (HR also editing statutory IDs in the app) is exactly
  the drift that produces a wrong statutory deduction or a mis-paid account.

## Current state (what already exists)

- **Inbound syncs (built):** `sync-lark-attendance`, `-leaves`, `-ot`, `-shifts`,
  `-calendar`, `-cash-advances`, `-reimbursements`, and `sync-lark-employees` —
  **but the last one only stamps `lark_user_id` (identity match by employee
  number); it pulls NO master-data field values.**
- **Outbound (built):** `send-payslip-approvals` / `sync-payslip-approvals` /
  `recall-payslip-approvals` (Lark Approval instances) + `lark-approval-webhook`;
  and `send-performance-self-reviews` / `sync-performance-self-review` (form
  pattern) — **the self-review pair is built but never switched on (missing 2
  secrets).**
- **Shared rails:** `_shared/lark.ts` (tenant auth, messaging, the Approval
  toolkit, `formLink`).

## Roadmap — prioritized, each its own build

1. **Employee master-data sync** *(foundational — do first).* Read the "Employee
   Information" Lark Base into the app's employee + statutory-ID + disbursement
   records. One-way, Lark-primary; app fields become read-only mirrors. Payroll
   correctness depends on this. Net-new (identity is already mapped; field values
   are not). A `sync-lark-*`-style job.
2. **Self-eval response sync.** Pull onboarding (M1/M3/M6 — already automated in
   Lark) and the new **quarterly** self-eval responses into the app for tracking
   (per-employee timeline + rating trends). Lark automates the *send*; the app only
   *ingests*. Flexible answer storage (jsonb Q&A), since forms carry 14–19 varying
   questions.
3. **Turn on the existing wirings.** Configure the self-review + payslip-approval
   secrets so those live flows actually fire.
4. **Push improvements (later).** "Payslip ready" notification; document/contract
   delivery via Lark; any manager→employee notify (FYI, not confirm).

## Decisions locked

- Boundary + ownership map above.
- **Master data: one-way, Lark-primary.** App mirrors read-only.
- **Employee-facing scheduling / sends / forms / reminders / approvals stay
  Lark-native**; the app ingests responses or pushes artifacts, never reinvents
  the mechanism.
- **Self-evals:** onboarding = M1/M3/M6 (Lark-automated already); recurring =
  **quarterly** (Lark-automated); app **syncs responses only**.
- **Leaves / OT:** Lark-native approval; app syncs the outcome.
- The accountability-model's **Lark workload-confirmation form (step 7) is
  parked** ([[project_accountability_model]]) — not a priority; if ever, it too is
  a Lark form + app sync, not an app-built send.

## Non-goals

- Rebuilding Lark's automations/forms/approvals inside the app.
- Making the app the primary editor of employee master data.
- An employee-facing app UI (employees interact only through Lark).

## How to extend this integration (the recipe)

For any new HR/payroll need: run the three-question test (Lark-native? → sync? →
push?), decide the owner from the map, pick the flow, and — if it's a sync or push
— add a thin `sync-X` / `send-X` on the shared `_shared/lark.ts` rails plus (for a
form) the hidden-field + webhook-token contract. Update this doc's ownership map
and roadmap.
