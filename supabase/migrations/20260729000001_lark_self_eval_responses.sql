-- Landing table for employee self-evaluation responses synced one-way from the
-- Lark onboarding Base (1st/3rd/6th-month probationary forms now; a quarterly
-- regular-employee form later, via config). Deliberately separate from the
-- app's formal review module (self_review_submissions): these forms are
-- Lark-automated (no app-issued submission_token) and have VARIABLE questions,
-- so answers live in flexible jsonb and any form fits without a schema change.
-- Writes go through the service-role edge function sync-lark-self-evals only.
-- See docs/superpowers/specs/2026-07-29-self-eval-response-sync-design.md.
create table lark_self_eval_responses (
  id                       uuid primary key default gen_random_uuid(),
  company_id               uuid not null references companies(id),
  employee_id              uuid not null references employees(id) on delete cascade,
  review_type              varchar(30) not null,   -- PROBATIONARY_M1 | _M3 | _M6 | QUARTERLY | ...
  source_table             varchar(120) not null,  -- Base table name (provenance)
  source_record_id         varchar(64) not null,   -- Bitable record_id -> dedup / idempotent re-sync
  respondent_lark_user_id  varchar(100),
  submitted_at             timestamptz,
  answers                  jsonb not null default '{}'::jsonb,  -- { "<question text>": "<answer>" }
  ratings                  jsonb not null default '{}'::jsonb,  -- { "<question text>": <number> } (1-5 questions)
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),
  unique (source_table, source_record_id)
);
create index on lark_self_eval_responses (company_id, employee_id);
create index on lark_self_eval_responses (review_type);
create trigger _lark_self_eval_responses_updated before update on lark_self_eval_responses
  for each row execute function set_updated_at();

alter table lark_self_eval_responses enable row level security;

-- Read: HR/performance admins of the employee's company (company-scoped helper,
-- same gate the performance module uses). No client writes — the sync edge
-- function uses the service role, which bypasses RLS.
create policy lark_self_eval_responses_read on lark_self_eval_responses for select using (
  auth_is_performance_admin_for_employee(employee_id)
);
