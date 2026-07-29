# Self-Evaluation Response Sync — Implementation Plan

> Spec: `docs/superpowers/specs/2026-07-29-self-eval-response-sync-design.md`. Reuses the master-data sync rails.

**Goal:** Sync employee self-eval responses from the Lark Base (M1/M3/M6 now; quarterly later via config) into a new flexible `lark_self_eval_responses` table, one-way, matched by the row's "Respondents" → `lark_user_id`, idempotent on the Bitable `record_id`.

## Global constraints
- One-way (Lark → App); no writeback. Match = "Respondents" user → `employees.lark_user_id`. No respondent / no match → skip + name it.
- Flexible jsonb Q&A → no schema change per form. Dedup/idempotent on `source_record_id`.
- Migrations forward-only. Gate on `flutter analyze` (0 errors); do NOT run `dart format`. Deno tests for the pure mapper.
- Base access is live (app_token `OJf1bkvKbasA2Us7ddRl7hT4gde`, wiki secret `LARK_EMPLOYEE_BASE_WIKI_TOKEN`). Self-eval tables: `tblbYmMelCZ3Qtop` (M1), `tblDHkHEYjvMK6EI` (M3), `tblsLA9CLd4yieX4` (M6).

## Task 1 — Migration: `lark_self_eval_responses` + RLS
Create the table per the spec (unique `source_record_id`; indexes on `(company_id, employee_id)`, `review_type`). RLS: company-scoped read for HR/admin roles (mirror `self_review_submissions`); service-role writes only. Apply to prod (additive, inert). Commit.

## Task 2 — Pure mapper `_shared/self_eval_map.ts` (+ tests)
`mapSelfEvalRecord(fields, reviewType) -> { respondentLarkUserId, submittedAt (ISO|null), answers (Record<string,string>), ratings (Record<string,number>) }`.
- Exclude meta fields "Submitted on" (→ submittedAt) and "Respondents" (→ respondentLarkUserId).
- `answers` = every other field via `baseCellText`; `ratings` = fields whose cell is numeric.
- Reuse `larkPersonId` (for Respondents) + a datetime→ISO helper. Unit tests: meta separation, numeric→ratings, missing respondent → null, datetime parse, empty answers skipped.

## Task 3 — Edge function `sync-lark-self-evals`
Config map `{table name → review_type}` (M1/M3/M6). Resolve wiki → for each configured table found in the Base → `listBaseRecords(userIdType:'user_id')` → per row: map; skip+name if no respondent or no employee match; else upsert on `source_record_id` (company_id from the matched employee). `dry_run` returns per-type counts + unapplied names (no answer content). Log `lark_sync_logs` type `SELF_EVAL`. Deploy; dry-run on prod; verify idempotency.

## Task 4 — App UI
- `lark_repository.dart`: `syncSelfEvals({companyId, dryRun})` + result type (reuse the master-data result shape incl. `unapplied`).
- `lark_settings_screen.dart`: a "Sync Self-Evaluations from Lark" card (preview→apply + unapplied section), consistent with the master-data card.
- Employee profile: a read-only "Self-Evaluations" history section (list by type+date, expandable Q&A, rating trend where repeated). If invasive, ship the sync + a cycle/list view first and defer the profile section.

## Task 5 — Companion doc (Lark-side quarterly form)
Short doc: create the regular-employee quarterly self-eval Base table + form + recurring Automation in Lark; then add its table name → `QUARTERLY` in the Task 3 config. No app code.

## Self-review
Spec coverage: new table (T1), flexible mapper (T2), table-driven sync + match + dedup + dry-run (T3), UI + history (T4), quarterly path (T5 + config). Placeholder scan: quarterly form is honestly deferred to Lark setup, not faked. Sequencing: T1→T2→T3 (backend, dry-run gated) then T4 (UI) then T5 (doc).
