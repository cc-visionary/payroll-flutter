-- Lark self-review request queue and atomic review-cycle activation.

create type self_review_request_status as enum (
  'PENDING', 'SENT', 'FAILED', 'CANCELLED'
);

create table self_review_requests (
  id                    uuid primary key default gen_random_uuid(),
  review_id             uuid not null unique references employee_reviews(id) on delete cascade,
  review_cycle_id       uuid not null references review_cycles(id) on delete cascade,
  employee_id           uuid not null references employees(id) on delete cascade,
  form_template_id      text not null,
  form_version          integer not null default 1,
  submission_token      uuid not null default gen_random_uuid() unique,
  status                self_review_request_status not null default 'PENDING',
  form_link             text,
  lark_message_id       text,
  sent_at               timestamptz,
  last_attempt_at       timestamptz,
  attempt_count         integer not null default 0,
  error_message         text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  constraint self_review_form_version_positive check (form_version > 0),
  constraint self_review_attempt_count_nonnegative check (attempt_count >= 0)
);
create index on self_review_requests (review_cycle_id, status);
create index on self_review_requests (employee_id, created_at desc);
create trigger _self_review_requests_updated before update on self_review_requests
  for each row execute function set_updated_at();

create or replace function activate_review_cycle(p_review_cycle_id uuid)
returns integer
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_cycle review_cycles%rowtype;
  v_review employee_reviews%rowtype;
  v_count integer := 0;
begin
  select * into v_cycle from review_cycles where id = p_review_cycle_id for update;
  if not found then raise exception 'Review cycle not found'; end if;
  if v_cycle.status <> 'DRAFT' then
    raise exception 'Only draft review cycles can be activated';
  end if;
  if not exists (
    select 1 from employee_reviews where review_cycle_id = p_review_cycle_id
  ) then
    raise exception 'Generate at least one employee review before activation';
  end if;

  for v_review in
    select * from employee_reviews where review_cycle_id = p_review_cycle_id
  loop
    insert into self_review_requests (
      review_id, review_cycle_id, employee_id, form_template_id, form_version
    ) values (
      v_review.id, v_cycle.id, v_review.employee_id,
      v_cycle.lark_form_template_id, 1
    ) on conflict (review_id) do nothing;

    update employee_reviews
      set status = 'AWAITING_SELF_REVIEW'
      where id = v_review.id and status = 'DRAFT';
    v_count := v_count + 1;
  end loop;

  update review_cycles set status = 'ACTIVE' where id = p_review_cycle_id;
  return v_count;
end;
$$;

alter table self_review_requests enable row level security;
create policy self_review_requests_read on self_review_requests for select using (
  auth_app_role() in ('SUPER_ADMIN', 'ADMIN', 'HR')
  or employee_id = auth_employee_id()
  or exists (
    select 1 from employee_reviews review
    where review.id = self_review_requests.review_id
      and review.direct_manager_id = auth_employee_id()
  )
);
create policy self_review_requests_hr_write on self_review_requests for all
  using (auth_app_role() in ('SUPER_ADMIN', 'ADMIN', 'HR'))
  with check (auth_app_role() in ('SUPER_ADMIN', 'ADMIN', 'HR'));
