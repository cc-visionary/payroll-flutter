# Self-Evaluation Response Sync — Design

**Date:** 2026-07-29 · **Roadmap:** Lark integration #2 (see `2026-07-25-lark-integration-strategy-design.md`) · **Builds on:** the master-data sync (`2026-07-25-employee-master-data-sync-design.md`) — same Base, same wiki/Bitable rails, same match-by-Lark-user pattern.

## Goal

Ingest employee **self-evaluation responses** from the Lark onboarding Base into the app, one-way, for a per-employee history + rating trend. Cover the existing **1st / 3rd / 6th-month (probationary)** forms now, and a **to-be-created quarterly self-eval for regular employees** the moment its Base table exists — without a schema change.

## Why a new track (not the existing review module)

The app already has a formal review module (`review_cycles → employee_reviews → self_review_requests → self_review_submissions`). It does **not** fit these forms:

| App formal self-review | Lark Base self-evals |
|---|---|
| App issues the form + a hidden `submission_token` | Lark **Automations** send them (off Start Date); no app token |
| **6 fixed** text columns | **Variable** questions (14 / 19 / 21, differ per form) |
| Token-gated ingest RPC (`ingest_self_review_submission`) | Rows just land in the Base |

So the Base self-evals are a separate, lighter **engagement-pulse** track. Forcing them into `self_review_submissions` would break the token-gated flow and lose the variable questions. → **new landing table**, standalone for v1 (may cross-reference `employee_reviews` later, e.g. M6 → regularization).

## Data model — new table `lark_self_eval_responses`

```
id                       uuid pk
company_id               uuid not null → companies
employee_id              uuid not null → employees          -- resolved from the row's "Respondents"
review_type              varchar(30) not null               -- PROBATIONARY_M1 | _M3 | _M6 | QUARTERLY | ...
source_table             varchar(120) not null              -- Base table name (provenance)
source_record_id         varchar(64) not null unique        -- Bitable record_id -> dedup / idempotent re-sync
respondent_lark_user_id  varchar(100)                       -- the "Respondents" user_id
submitted_at             timestamptz                        -- the "Submitted on" cell
answers                  jsonb not null default '{}'        -- { "<question text>": "<answer>" } (all fields)
ratings                  jsonb not null default '{}'        -- { "<question text>": <number> } (the 1-5 questions)
created_at / updated_at  timestamptz
```

- **Dedup key = `source_record_id` (Bitable record_id).** Re-sync upserts → idempotent; an edited Base cell updates the row.
- **Flexible Q&A in jsonb** → any question set (incl. the future quarterly form) works with no migration. `ratings` mirrors the numeric (1-5) questions so the UI can chart a trend where questions repeat (quarterly gives a real single-metric trend; the M1/M3/M6 set is a progression).
- **RLS:** company-scoped read for HR/admin roles (mirror `self_review_submissions` policies); writes are service-role only (the edge function). No employee-self read in v1.

## Sync — `sync-lark-self-evals` edge function

Reuses the master-data plumbing (`_shared/lark.ts`: `resolveWikiNode` / `listBaseTables` / `listBaseRecords({userIdType:'user_id'})` / `baseCellText`).

- **Table-driven config** (a constant map): `{ "1st Month Employee Self-Evaluation Form": "PROBATIONARY_M1", "3rd Month …": "PROBATIONARY_M3", "6th Month …": "PROBATIONARY_M6" }`. Adding QUARTERLY later = **one line** once the Base table exists.
- Per configured table → per record:
  - **Match employee** via the **"Respondents"** field (created-by user) → `employees.lark_user_id` (records read with `user_id_type=user_id`). No match / no respondent → **skip + name it** on the same "couldn't apply" report the master-data sync uses.
  - Build `answers` = every non-meta field (`baseCellText`, keyed by field name); `ratings` = the numeric fields; `submitted_at` = "Submitted on"; `source_record_id` = record_id.
  - **Upsert on `source_record_id`.**
- Input: `{ company_id, dry_run? }`. dry_run returns aggregate counts (per-type synced/skipped) — no answer content. Logs to `lark_sync_logs` (sync_type `SELF_EVAL`). Per-record isolation; report created/updated/skipped/unapplied/errors.
- **Pure mapper** `_shared/self_eval_map.ts` (`mapSelfEvalRecord(fields, reviewType) -> { respondentLarkUserId, submittedAt, answers, ratings, ... }`) — unit-tested (meta-field separation, numeric→ratings, missing respondent, datetime parse). Meta fields excluded from answers: "Submitted on", "Respondents".

## App UI

- **Trigger:** a "Sync Self-Evaluations from Lark" action in **Settings → Integrations**, beside the master-data sync, with the same preview(dry_run)→apply + "couldn't apply" named list.
- **View:** a read-only **Self-Evaluations** history on the employee profile (or the performance/development area): responses listed by `review_type` + `submitted_at`, each expandable to its Q&A; a small ratings trend where a question repeats across responses. Read-only (Lark-owned), like the master-data badges intent.

## Companion (Lark-side, separate short doc): the quarterly form

The regular-employee quarterly self-eval doesn't exist in Lark yet. To be set up in Lark (not app code): a **new Base table + form** in the same Base, plus a **recurring quarterly Automation** targeting **regular (non-probationary)** employees. Once created, add its table name → `QUARTERLY` in the sync config. I'll provide the setup steps as a companion doc.

## Out of scope (v1)

Linking responses into `employee_reviews`; employee-facing self-view; auto-scheduling from the app (Lark Automations own scheduling — app only ingests, per the division of labor).

## Testing

- Deno unit tests for the pure mapper (`self_eval_map_test.ts`).
- Dry-run against the live Base (counts only, no answer content) before any write.
- Idempotency: second run = all no-op (upsert on `source_record_id`).
