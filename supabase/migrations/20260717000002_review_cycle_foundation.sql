-- Review-cycle foundation for the Employee Performance and Development module.
-- This is additive to the existing lightweight performance_check_ins feature.

create type performance_review_type as enum (
  'MONTHLY_CHECK_IN',
  'QUARTERLY',
  'PROBATIONARY',
  'REGULARIZATION',
  'ANNUAL',
  'AD_HOC',
  'PIP_REVIEW'
);

create type review_cycle_status as enum (
  'DRAFT', 'SCHEDULED', 'ACTIVE', 'CLOSED', 'CANCELLED'
);

create type employee_review_status as enum (
  'DRAFT',
  'AWAITING_SELF_REVIEW',
  'SELF_REVIEW_SUBMITTED',
  'MANAGER_REVIEW_IN_PROGRESS',
  'READY_FOR_DISCUSSION',
  'DISCUSSION_COMPLETED',
  'FINALIZED',
  'OVERDUE',
  'CANCELLED'
);

create type review_outcome as enum (
  'PERFORMING_WELL',
  'CONTINUE_DEVELOPMENT',
  'READY_FOR_CROSS_TRAINING',
  'READY_FOR_ADDITIONAL_RESPONSIBILITY',
  'PROMOTION_CONSIDERATION',
  'NEEDS_CLOSER_COACHING',
  'FORMAL_PERFORMANCE_CONCERN',
  'PIP_RECOMMENDED'
);

create type kpi_result_status as enum (
  'EXCEEDED', 'MET', 'PARTIALLY_MET', 'NOT_MET', 'NOT_APPLICABLE',
  'NOT_ENOUGH_DATA'
);

create table review_cycles (
  id                       uuid primary key default gen_random_uuid(),
  company_id               uuid not null references companies(id) on delete cascade,
  name                     varchar(150) not null,
  review_type              performance_review_type not null,
  period_start             date not null,
  period_end               date not null,
  self_review_due_date     date not null,
  manager_review_due_date  date not null,
  finalization_due_date    date,
  status                   review_cycle_status not null default 'DRAFT',
  lark_form_template_id    text not null,
  created_by               uuid not null references users(id),
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),
  constraint review_cycles_dates_valid check (
    period_start <= period_end
    and period_end <= self_review_due_date
    and self_review_due_date <= manager_review_due_date
    and (finalization_due_date is null
      or manager_review_due_date <= finalization_due_date)
  ),
  unique (company_id, name)
);
create index on review_cycles (company_id, status, period_start desc);
create trigger _review_cycles_updated before update on review_cycles
  for each row execute function set_updated_at();

create table employee_reviews (
  id                              uuid primary key default gen_random_uuid(),
  review_cycle_id                 uuid not null references review_cycles(id) on delete cascade,
  employee_id                     uuid not null references employees(id) on delete cascade,
  employee_name_snapshot          text not null,
  responsibility_card_id          uuid not null references role_scorecards(id),
  responsibility_card_version     integer not null,
  direct_manager_id               uuid not null references employees(id),
  review_type                     performance_review_type not null,
  review_period_start             date not null,
  review_period_end               date not null,
  status                          employee_review_status not null default 'DRAFT',
  responsibility_snapshot         jsonb not null default '[]'::jsonb,
  overall_rating                  numeric(3,2),
  overall_outcome                 review_outcome,
  finalized_by                    uuid references users(id),
  finalized_at                    timestamptz,
  reopened_at                     timestamptz,
  reopened_by                     uuid references users(id),
  reopen_reason                   text,
  created_at                      timestamptz not null default now(),
  updated_at                      timestamptz not null default now(),
  constraint employee_reviews_rating_valid
    check (overall_rating is null or overall_rating between 1 and 5),
  constraint employee_reviews_snapshot_array
    check (jsonb_typeof(responsibility_snapshot) = 'array'),
  constraint employee_reviews_finalization_valid check (
    (status <> 'FINALIZED')
    or (finalized_by is not null and finalized_at is not null
      and overall_outcome is not null)
  ),
  unique (review_cycle_id, employee_id)
);
create index on employee_reviews (employee_id, review_period_end desc);
create index on employee_reviews (direct_manager_id, status);
create index on employee_reviews (review_cycle_id, status);
create trigger _employee_reviews_updated before update on employee_reviews
  for each row execute function set_updated_at();

create table review_kpi_results (
  id                  uuid primary key default gen_random_uuid(),
  review_id           uuid not null references employee_reviews(id) on delete cascade,
  snapshot_order      integer not null default 0,
  kpi_name            text not null,
  description         text,
  measurement_unit    text,
  target_value        text,
  actual_value        text,
  is_qualitative      boolean not null default false,
  result_status       kpi_result_status,
  manager_rating      integer,
  manager_comment     text,
  evidence            jsonb not null default '[]'::jsonb,
  source              text not null default 'MANUAL',
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint review_kpi_rating_valid
    check (manager_rating is null or manager_rating between 1 and 5),
  constraint review_kpi_evidence_array check (jsonb_typeof(evidence) = 'array'),
  constraint review_kpi_rating_requires_actual check (
    manager_rating is null or is_qualitative or actual_value is not null
      or result_status in ('NOT_APPLICABLE', 'NOT_ENOUGH_DATA')
  ),
  unique (review_id, snapshot_order)
);
create index on review_kpi_results (review_id);
create trigger _review_kpi_results_updated before update on review_kpi_results
  for each row execute function set_updated_at();

create table review_skill_ratings (
  id                  uuid primary key default gen_random_uuid(),
  review_id           uuid not null references employee_reviews(id) on delete cascade,
  snapshot_order      integer not null default 0,
  skill_name          text not null,
  skill_description   text,
  skill_category      text not null,
  required_level      integer,
  manager_rating      integer,
  employee_comment    text,
  manager_comment     text,
  evidence            jsonb not null default '[]'::jsonb,
  development_needed  boolean not null default false,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint review_skill_required_level_valid
    check (required_level is null or required_level between 1 and 5),
  constraint review_skill_rating_valid
    check (manager_rating is null or manager_rating between 1 and 5),
  constraint review_skill_evidence_array check (jsonb_typeof(evidence) = 'array'),
  unique (review_id, snapshot_order)
);
create index on review_skill_ratings (review_id);
create trigger _review_skill_ratings_updated before update on review_skill_ratings
  for each row execute function set_updated_at();

-- Create one review and all role-standard snapshots in the same transaction.
-- Validation failures are explicit so HR can resolve assignments before launch.
create or replace function generate_employee_review(
  p_review_cycle_id uuid,
  p_employee_id uuid
) returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_cycle review_cycles%rowtype;
  v_employee employees%rowtype;
  v_card role_scorecards%rowtype;
  v_review_id uuid;
  v_item jsonb;
  v_index integer;
begin
  select * into v_cycle from review_cycles where id = p_review_cycle_id;
  if not found then raise exception 'Review cycle not found'; end if;

  select * into v_employee from employees
    where id = p_employee_id and deleted_at is null;
  if not found then raise exception 'Employee not found or archived'; end if;
  if v_employee.company_id <> v_cycle.company_id then
    raise exception 'Employee and review cycle belong to different companies';
  end if;
  if v_employee.role_scorecard_id is null then
    raise exception 'Employee has no Responsibility Card';
  end if;
  if v_employee.reports_to_id is null then
    raise exception 'Employee has no direct manager';
  end if;

  select * into v_card from role_scorecards where id = v_employee.role_scorecard_id;
  if not found then raise exception 'Responsibility Card not found'; end if;

  select id into v_review_id from employee_reviews
    where review_cycle_id = p_review_cycle_id and employee_id = p_employee_id;
  if found then return v_review_id; end if;

  insert into employee_reviews (
    review_cycle_id, employee_id, employee_name_snapshot,
    responsibility_card_id, responsibility_card_version, direct_manager_id,
    review_type, review_period_start, review_period_end,
    responsibility_snapshot
  ) values (
    v_cycle.id, v_employee.id,
    concat_ws(' ', v_employee.first_name, v_employee.middle_name, v_employee.last_name),
    v_card.id, v_card.version, v_employee.reports_to_id,
    v_cycle.review_type, v_cycle.period_start, v_cycle.period_end,
    v_card.key_responsibilities
  ) returning id into v_review_id;

  v_index := 0;
  for v_item in select value from jsonb_array_elements(v_card.kpis)
  loop
    insert into review_kpi_results (
      review_id, snapshot_order, kpi_name, description,
      measurement_unit, target_value, is_qualitative
    ) values (
      v_review_id, v_index,
      coalesce(v_item->>'name', v_item->>'metric', ''),
      null, v_item->>'measurement', v_item->>'target',
      case lower(coalesce(v_item->>'is_qualitative', 'false'))
        when 'true' then true else false
      end
    );
    v_index := v_index + 1;
  end loop;

  v_index := 0;
  for v_item in select value from jsonb_array_elements(v_card.required_skills)
  loop
    insert into review_skill_ratings (
      review_id, snapshot_order, skill_name, skill_description,
      skill_category, required_level
    ) values (
      v_review_id, v_index, coalesce(v_item->>'name', ''),
      v_item->>'description', 'TECHNICAL',
      coalesce((v_item->>'required_level')::integer, 3)
    );
    v_index := v_index + 1;
  end loop;

  for v_item in select value from jsonb_array_elements(v_card.behavioral_expectations)
  loop
    insert into review_skill_ratings (
      review_id, snapshot_order, skill_name, skill_description,
      skill_category, required_level
    ) values (
      v_review_id, v_index, coalesce(v_item->>'name', ''),
      v_item->>'description', 'BEHAVIORAL', null
    );
    v_index := v_index + 1;
  end loop;

  return v_review_id;
end;
$$;

alter table review_cycles enable row level security;
alter table employee_reviews enable row level security;
alter table review_kpi_results enable row level security;
alter table review_skill_ratings enable row level security;

create policy review_cycles_company_read on review_cycles for select using (
  auth_app_role() = 'SUPER_ADMIN'
  or (company_id = auth_company_id() and auth_app_role() in ('ADMIN', 'HR'))
);
create policy review_cycles_hr_write on review_cycles for all
  using (auth_app_role() = 'SUPER_ADMIN'
    or (company_id = auth_company_id() and auth_app_role() in ('ADMIN', 'HR')))
  with check (auth_app_role() = 'SUPER_ADMIN'
    or (company_id = auth_company_id() and auth_app_role() in ('ADMIN', 'HR')));

create policy employee_reviews_read on employee_reviews for select using (
  auth_app_role() in ('SUPER_ADMIN', 'ADMIN', 'HR')
  or employee_id = auth_employee_id()
  or direct_manager_id = auth_employee_id()
);
create policy employee_reviews_hr_write on employee_reviews for all
  using (auth_app_role() in ('SUPER_ADMIN', 'ADMIN', 'HR'))
  with check (auth_app_role() in ('SUPER_ADMIN', 'ADMIN', 'HR'));

create policy review_kpi_results_read on review_kpi_results for select using (
  exists (select 1 from employee_reviews r where r.id = review_id)
);
create policy review_kpi_results_hr_write on review_kpi_results for all
  using (auth_app_role() in ('SUPER_ADMIN', 'ADMIN', 'HR'))
  with check (auth_app_role() in ('SUPER_ADMIN', 'ADMIN', 'HR'));

create policy review_skill_ratings_read on review_skill_ratings for select using (
  exists (select 1 from employee_reviews r where r.id = review_id)
);
create policy review_skill_ratings_hr_write on review_skill_ratings for all
  using (auth_app_role() in ('SUPER_ADMIN', 'ADMIN', 'HR'))
  with check (auth_app_role() in ('SUPER_ADMIN', 'ADMIN', 'HR'));
