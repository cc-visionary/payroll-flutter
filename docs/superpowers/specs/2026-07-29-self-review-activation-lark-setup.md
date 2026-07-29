# Formal Self-Review Module — Activation & Lark Setup

**Date:** 2026-07-29 · **Roadmap:** Lark integration #3. This activates the app's *formal* performance-review self-review track (`review_cycles → employee_reviews → self_review_requests → self_review_submissions`), distinct from the lighter [Base self-eval sync](2026-07-29-self-eval-response-sync-design.md) (onboarding + quarterly pulse). Use this track for the manager-review appraisal cycle's employee self-portion.

> **Overlap note:** this track and the Base self-eval sync both collect "self-evaluations." Keep this one only if you want the *formal, cycle-based* appraisal self-review (tied to `employee_reviews`, KPIs, manager evaluation, outcome). If the Base quarterly pulse is enough, you can leave this dormant.

## What's already done (backend — live on prod)

- `send-performance-self-reviews` (outbound) and `sync-performance-self-review` (inbound webhook, `verify_jwt=false`) are **deployed**.
- The webhook secret **`LARK_PERFORMANCE_FORM_WEBHOOK_TOKEN`** is **set** (generated + stored in the gitignored `env/prod.json` under that key — copy it from there into your Lark automation).
- Verified: correct token → the ingest RPC runs; wrong token → 401.

## The flow (once Lark-side is wired)

1. HR creates a **review cycle** in the app and pastes the **Lark self-review form URL** as the cycle's form template (`review_cycles.lark_form_template_id`). Because the send function accepts a full URL, **`LARK_SELF_REVIEW_FORM_BASE_URL` is not needed** — paste the whole form URL.
2. Activating the cycle generates a `self_review_request` per employee (each with a unique `submission_token`) and calls `send-performance-self-reviews`, which DMs each employee (via the Luxium People bot) a card with an **"Open self-review"** button. The button URL is the form URL **plus** these appended query params:
   `review_id`, `review_cycle_id`, `employee_id`, `employee_name`, `role_id`, `role_name`, `manager_id`, `review_period`, `form_version`, `submission_token`.
3. The employee opens the form (pre-carrying those params), fills the 6 questions, submits → the response lands in the form's Base table.
4. A **Lark Base automation** ("when a record is created") POSTs the response to the inbound webhook.
5. `sync-performance-self-review` validates the token, matches `review_id`+`submission_token`, and writes `self_review_submissions` → the review flips to `SELF_REVIEW_SUBMITTED` and shows on the employee-review screen.

## Lark-side setup (you)

### A. Create the self-review form (in a Lark Base)
Six question fields (free text) — these map to the app columns:
`accomplishments`, `challenges`, `learnings`, `desired_development_area`, `support_needed`, `additional_comments`.

Plus **hidden fields** to carry the identity params from the link: at minimum `review_id`, `submission_token`, `employee_id`, `form_version`. (These must survive into the Base record so the automation can POST them back.)

### B. ⚠️ Prefill nuance — confirm this before going live
The app appends **raw** param names to the form URL (`...&review_id=<x>&submission_token=<y>&form_version=1`). Lark Base share-forms typically prefill via a **`prefill_<Field Name>=`** query format, not raw field names. So one of these must be true:
- Your form's prefill accepts the raw names as-is (test it), **or**
- The hidden fields are named so the raw params land in them, **or**
- **Tell me** and I'll change the param keys the send function emits (e.g. to `prefill_review_id`) to match your form's exact prefill scheme — a one-line-per-param edit in `send-performance-self-reviews`, then redeploy.

Test by opening a sample link with `?review_id=TEST&submission_token=TEST` and confirming those values appear (hidden) in the submitted record. This is the one place that needs a live check against your actual form.

### C. Base automation → POST to the webhook
Trigger: **when a record is created** in the form's table. Action: **send an HTTP request**:
- **Method:** POST
- **URL:** `https://tsylbligjojkhpaobcsi.supabase.co/functions/v1/sync-performance-self-review`
- **Header:** `x-performance-webhook-token: <the value from env/prod.json → LARK_PERFORMANCE_FORM_WEBHOOK_TOKEN>`
- **Body (JSON):** map the record's fields:
  ```json
  {
    "review_id": "<hidden review_id>",
    "employee_id": "<hidden employee_id>",
    "submission_token": "<hidden submission_token>",
    "form_version": <hidden form_version as an integer>,
    "external_submission_id": "<the Base record id>",
    "accomplishments": "<answer>",
    "challenges": "<answer>",
    "learnings": "<answer>",
    "desired_development_area": "<answer>",
    "support_needed": "<answer>",
    "additional_comments": "<answer>"
  }
  ```
  `form_version` must be an **integer**. `external_submission_id` (the Base record id) dedups re-sends.

### D. Prerequisite
Employees must be **linked** (`employees.lark_user_id` set — the Employees→Lark sync) or the send step marks their request FAILED with "Employee has no Lark user ID."

## Test end-to-end
1. Create a review cycle with the form URL; add one linked test employee; activate.
2. The employee gets the bot card → opens → submits.
3. Confirm the automation fired (Lark automation run log) and the app shows the self-review on the employee-review screen.
4. If the webhook 400s "not found", the `submission_token`/`review_id` didn't survive prefill → revisit step B.
