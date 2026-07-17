-- Immutable, versioned responses received from the universal Lark form.

alter table self_review_requests add column submitted_at timestamptz;

create table self_review_submissions (
  id                        uuid primary key default gen_random_uuid(),
  review_id                 uuid not null references employee_reviews(id) on delete cascade,
  request_id                uuid not null references self_review_requests(id) on delete cascade,
  employee_id               uuid not null references employees(id) on delete cascade,
  version_number            integer not null,
  form_version              integer not null,
  external_submission_id    text,
  accomplishments           text,
  challenges                text,
  learnings                 text,
  desired_development_area  text,
  support_needed            text,
  additional_comments       text,
  attachments               jsonb not null default '[]'::jsonb,
  submitted_at              timestamptz not null default now(),
  is_active                 boolean not null default true,
  superseded_by_id          uuid references self_review_submissions(id),
  created_at                timestamptz not null default now(),
  constraint self_review_submission_version_positive check (version_number > 0),
  constraint self_review_submission_attachments_array
    check (jsonb_typeof(attachments) = 'array'),
  unique (request_id, version_number),
  unique (request_id, external_submission_id)
);
create unique index self_review_submissions_one_active
  on self_review_submissions (request_id) where is_active;
create index on self_review_submissions (review_id, submitted_at desc);

create or replace function ingest_self_review_submission(
  p_review_id uuid,
  p_employee_id uuid,
  p_form_version integer,
  p_submission_token uuid,
  p_external_submission_id text,
  p_accomplishments text,
  p_challenges text,
  p_learnings text,
  p_desired_development_area text,
  p_support_needed text,
  p_additional_comments text,
  p_attachments jsonb default '[]'::jsonb
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request self_review_requests%rowtype;
  v_previous_id uuid;
  v_submission_id uuid;
  v_version integer;
begin
  select * into v_request from self_review_requests
    where review_id = p_review_id for update;
  if not found then raise exception 'Self-review request not found'; end if;
  if v_request.employee_id <> p_employee_id then
    raise exception 'Employee does not match review request';
  end if;
  if v_request.form_version <> p_form_version then
    raise exception 'Form version does not match review request';
  end if;
  if v_request.submission_token <> p_submission_token then
    raise exception 'Invalid submission token';
  end if;
  if v_request.status = 'CANCELLED' then
    raise exception 'Self-review request is cancelled';
  end if;

  if p_external_submission_id is not null then
    select id into v_submission_id from self_review_submissions
      where request_id = v_request.id
        and external_submission_id = p_external_submission_id;
    if found then return v_submission_id; end if;
  end if;

  select id into v_previous_id from self_review_submissions
    where request_id = v_request.id and is_active for update;
  select coalesce(max(version_number), 0) + 1 into v_version
    from self_review_submissions where request_id = v_request.id;
  update self_review_submissions set is_active = false
    where request_id = v_request.id and is_active;

  insert into self_review_submissions (
    review_id, request_id, employee_id, version_number, form_version,
    external_submission_id, accomplishments, challenges, learnings,
    desired_development_area, support_needed, additional_comments, attachments
  ) values (
    p_review_id, v_request.id, p_employee_id, v_version, p_form_version,
    p_external_submission_id, p_accomplishments, p_challenges, p_learnings,
    p_desired_development_area, p_support_needed, p_additional_comments,
    coalesce(p_attachments, '[]'::jsonb)
  ) returning id into v_submission_id;

  if v_previous_id is not null then
    update self_review_submissions set superseded_by_id = v_submission_id
      where id = v_previous_id;
  end if;
  update self_review_requests set submitted_at = now() where id = v_request.id;
  update employee_reviews set status = 'SELF_REVIEW_SUBMITTED'
    where id = p_review_id
      and status in ('AWAITING_SELF_REVIEW', 'OVERDUE');
  return v_submission_id;
end;
$$;

revoke all on function ingest_self_review_submission(
  uuid, uuid, integer, uuid, text, text, text, text, text, text, text, jsonb
) from public;
grant execute on function ingest_self_review_submission(
  uuid, uuid, integer, uuid, text, text, text, text, text, text, text, jsonb
) to service_role;

alter table self_review_submissions enable row level security;
create policy self_review_submissions_read on self_review_submissions for select using (
  auth_app_role() in ('SUPER_ADMIN', 'ADMIN', 'HR')
  or employee_id = auth_employee_id()
  or exists (
    select 1 from employee_reviews review
    where review.id = self_review_submissions.review_id
      and review.direct_manager_id = auth_employee_id()
  )
);
