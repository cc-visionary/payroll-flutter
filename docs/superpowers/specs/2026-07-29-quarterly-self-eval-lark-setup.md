# Quarterly Self-Eval (Regular Employees) — Lark-side Setup

**Companion to** `2026-07-29-self-eval-response-sync-design.md`. This is a **Lark-side** setup (no app code) for the recurring quarterly self-evaluation for **regular (non-probationary) employees**. The app's `sync-lark-self-evals` already handles it — it just needs the Base table to exist and one config line.

> **As-built (2026-07-29):** the **"Quarterly Check-In"** table now exists in the Base (7 Number 1–5 ratings named by theme + text reflections; meta fields **"Submitted By"** / **"Submitted At"**). It is **wired** in the sync (`'Quarterly Check-In': 'QUARTERLY'`) and deployed; a dry-run finds it (0 records until people submit). **Remaining Lark-side work:** the recurring quarterly Automation + making sure regular employees are linked (`lark_user_id` stamped).

## What to create in Lark

All in the **same Base** as the onboarding forms (HR Wiki → *Employee information* Base, already shared with the **Luxium People** app).

1. **New table + form.** Create a new table, e.g. **"Quarterly Self-Evaluation Form"**, and turn it into a Lark **Form** (Share → form link). Reuse/adapt the 6th-month question set. Since it repeats every quarter with the *same* questions, its numeric (1–5) questions give a real per-person **trend over time** in the app.
   - Keep rating questions as **Number** (1–5) — leading-zero issues don't apply to ratings.
   - Free-text questions as **Text**.

2. **Two system fields the sync depends on** (Form response tables get these automatically — just confirm the names):
   - **"Respondents"** — the submitter (created-by user). This is the **match key** → the employee's Lark user → `employees.lark_user_id`.
   - **"Submitted on"** — the submission time (created-time) → `submitted_at`.
   - ✅ The sync accepts **either** naming convention: `Respondents`/`Submitted on` (onboarding tables) **or** `Submitted By`/`Submitted At` (the Quarterly Check-In table). No rename needed.

3. **Recurring Automation.** Mirror the existing *"1st Month Probationary Evaluation Reminder"* automation, but:
   - **Trigger:** a **scheduled/recurring** quarterly run (e.g. 1st of Jan / Apr / Jul / Oct), instead of "off Start Date".
   - **Audience:** **regular (non-probationary)** employees — filter by employment status in your people table/directory.
   - **Action:** send the form link via the **Luxium People** bot (same as the onboarding reminders).

## App side — ✅ DONE

`TABLE_TYPES` in `sync-lark-self-evals` now includes `'Quarterly Check-In': 'QUARTERLY'` and is deployed. The flexible jsonb model already fits its questions; the 7 Number ratings will build a per-person trend across quarters. Note: the rating columns are named by theme (`results / accountability`, `role clarity`, …), so the app's "Self-Evals" tab shows those labels — rename the Base columns if you'd prefer the full question text.

## Prerequisite for responses to land

A regular employee's response only syncs if they're **linked** — i.e. they exist in the app **and** have `lark_user_id` stamped (run the **Employees** sync). Unlinked submitters show up on the sync's **"couldn't apply"** list (reason `NOT_IN_APP`) rather than being lost — so it's self-correcting: link them, re-sync, done.
