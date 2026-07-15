# Adjuncts hard-delete + Statutory "Mark Paid" hiding — design

**Date:** 2026-07-15
**Status:** Approved (design), pending implementation plan

## Problem

Two removal/clean-up gaps surfaced from the Compliance and Adjuncts screens:

1. **Compliance → Statutory Payables:** the row-action **Mark Paid** shows even on
   rows that are already fully paid, which is confusing.
2. **Adjuncts (Penalties / Cash Advances / Reimbursements):** the screen is
   read-only. There is no way to remove an erroneous or test record. Unlike
   employees, roles, departments, compensation changes, etc., these three tables
   have no delete path anywhere in the app.

## Goals

- Statutory: hide **Mark Paid** once a payable is fully settled (`paid`/`overpaid`).
- Adjuncts: add a **hard delete** for a penalty / cash advance / reimbursement,
  restricted to HR/admin, blocked for anything already consumed by payroll.

## Non-goals

- No "delete" for statutory payable *rows* — they are computed on the fly by
  `statutory_payables_due_v` from released payslips; there is nothing to delete.
  The statutory "undo" is the existing **Void** on a payment (soft-void with
  reason, in `ViewPaymentsDialog`) — unchanged by this work.
- No soft "Cancel" status for adjuncts (explicitly chose hard delete).
- No bulk delete. One row at a time.

---

## Part A — Statutory: hide Mark Paid when settled

Single UI change in `lib/features/compliance/widgets/payables_table.dart`,
`_RowActions`. Compute `status = classifyPayable(amountDue, paid)` (the helper
already exists and returns `unpaid | partial | paid | overpaid`) and gate the
buttons:

| Row status | Mark Paid | View |
|---|---|---|
| `unpaid`   | shown  | — (no payments yet) |
| `partial`  | shown  | shown |
| `paid`     | **hidden** | shown |
| `overpaid` | **hidden** | shown |

`View` continues to appear whenever there are payments (`paid > 0`). Undo path is
unchanged: **View → Void** returns the row to `unpaid`, and Mark Paid reappears.

No migration. No repository change.

---

## Part B — Adjuncts hard delete

### Data-model facts (verified in migrations)

- `penalty_installments.penalty_id → penalties(id) ON DELETE CASCADE` — deleting a
  penalty removes its installments automatically.
- `payslip_lines.{penalty_installment_id, cash_advance_id, reimbursement_id}` are
  FKs **with no cascade (RESTRICT)** — the DB itself refuses to delete any adjunct
  still referenced by a payslip line. This is the ultimate backstop.
- `is_deducted` / `is_paid` flip to `true` **only at run release** (`releaseRun`);
  discarding a draft run resets `payroll_run_id = null, is_deducted/is_paid = false`.
  Therefore:
  - `is_deducted` / `is_paid = true` ⟺ consumed by a **released** payslip.
  - `payroll_run_id is not null` (with the flag still false) ⟺ **queued on a draft** run.
- RLS: HR/admin (`SUPER_ADMIN`/`ADMIN`/`HR`) already have `for all` write policies
  (incl. DELETE) on `penalties`, `penalty_installments`, `cash_advances`,
  `reimbursements`. No new policy needed.

### Deletability rule (per kind)

A record is deletable **only when it has never touched payroll**:

| Kind | Deletable when |
|---|---|
| Penalty | no installment has `is_deducted = true` **and** no installment has `payroll_run_id` set |
| Cash advance | `is_deducted = false` **and** `payroll_run_id is null` |
| Reimbursement | `is_paid = false` **and** `payroll_run_id is null` |

Released → blocked permanently. Draft-queued → blocked until that run is
discarded/recomputed (then it becomes deletable). Lark `CANCELLED`/`REJECTED`
records that never hit payroll are deletable.

### DB migration — `20260715000002_delete_adjuncts.sql`

Three `security invoker` RPCs, matching the established `delete_compensation_change`
idiom (RLS backstops; `get diagnostics row_count` catches an RLS-filtered zero-row
delete; guards `raise exception '<CODE>'`):

```
delete_penalty(p_id uuid) returns void
  - select 1 from penalties where id = p_id            → not found ? raise 'PENALTY_NOT_FOUND'
  - exists installment is_deducted                     → raise 'RELEASED_PAYROLL'
  - exists installment payroll_run_id is not null      → raise 'ON_PAYROLL_RUN'
  - delete from penalties where id = p_id  (installments cascade)
  - row_count = 0 ? raise 'DELETE_FORBIDDEN'

delete_cash_advance(p_id uuid) returns void
  - lookup (is_deducted, payroll_run_id)               → not found ? raise 'CASH_ADVANCE_NOT_FOUND'
  - is_deducted                                        → raise 'RELEASED_PAYROLL'
  - payroll_run_id is not null                         → raise 'ON_PAYROLL_RUN'
  - delete + row_count guard → 'DELETE_FORBIDDEN'

delete_reimbursement(p_id uuid) returns void
  - lookup (is_paid, payroll_run_id)                   → not found ? raise 'REIMBURSEMENT_NOT_FOUND'
  - is_paid                                            → raise 'RELEASED_PAYROLL'
  - payroll_run_id is not null                         → raise 'ON_PAYROLL_RUN'
  - delete + row_count guard → 'DELETE_FORBIDDEN'
```

Each function: `revoke execute ... from public; grant execute ... to authenticated;`
Guards checked in the order above (most-specific message first).

### Flutter

**`lib/data/repositories/adjuncts_repository.dart`** (new) — thin wrapper:
`deletePenalty(id)`, `deleteCashAdvance(id)`, `deleteReimbursement(id)`, each
`await client.rpc('delete_<kind>', params: {'p_id': id})`. Catches
`PostgrestException` and maps `message` codes → user-facing strings:

| Code | Message |
|---|---|
| `RELEASED_PAYROLL` | "Can't delete — this is already deducted/paid on a released payslip." |
| `ON_PAYROLL_RUN` | "Can't delete — it's queued on an unreleased payroll run. Discard/recompute that run first." |
| `*_NOT_FOUND` / `DELETE_FORBIDDEN` | "Couldn't delete this record." (also re-fetch list) |

**`lib/features/adjuncts/adjuncts_screen.dart`** — on `_AdjunctCard`:
- Trailing **⋮ (`PopupMenuButton`) → Delete**, shown **only** when
  `profile.isHrOrAdmin` **and** the row passes the deletability rule above
  (blocked rows show no Delete — chosen over disabled+tooltip).
- Delete opens a confirm `AlertDialog` ("Delete this <kind>? This can't be
  undone."). On confirm → repository call; success → `ref.invalidate(_listProvider(kind))`
  + success SnackBar; failure → error SnackBar from the mapping above.
- Reuse the existing `mounted`-guard discipline for post-await `context`/`ref`.

The card needs the current user's role; `_AdjunctList` already has access to
`userProfileProvider` (used in `_listProvider`). Pass `isHrOrAdmin` down to the card.

## Verification

- **RPC guards:** reproduce in a throwaway local Postgres cluster (same technique
  used for the login-fix migration — no local Supabase is available). Seed a
  penalty/CA/reimbursement in each state (clean / draft-queued / released) and
  assert: clean → deleted (+ installments cascade), draft-queued → `ON_PAYROLL_RUN`,
  released → `RELEASED_PAYROLL`.
- **Flutter:** `flutter analyze` clean; drive the Adjuncts screen — Delete hidden
  for released/queued rows, confirm dialog, list refresh on success, friendly
  SnackBar on a guard rejection.

## Files touched

- `supabase/migrations/20260715000002_delete_adjuncts.sql` (new)
- `lib/data/repositories/adjuncts_repository.dart` (new)
- `lib/features/adjuncts/adjuncts_screen.dart` (Delete menu + role/deletability gating)
- `lib/features/compliance/widgets/payables_table.dart` (hide Mark Paid when settled)

## Risks / notes

- Deploying the migration to prod is a separate, explicit step (`supabase db push
  --linked`), same as prior migrations.
- Hard delete is irreversible by design (user's choice). Guards + confirm dialog +
  HR/admin gating + hide-when-not-deletable are the safety layers; the payslip_lines
  RESTRICT FK is the final DB backstop.
