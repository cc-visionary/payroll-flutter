-- Manager evaluation workflow, scoped to the allocated direct manager.

alter table review_kpi_results add column check_frequency text;

create or replace function set_review_kpi_frequency()
returns trigger language plpgsql set search_path = public as $$
declare v_kpis jsonb;
begin
  if new.check_frequency is null then
    select card.kpis into v_kpis
      from employee_reviews review
      join role_scorecards card on card.id = review.responsibility_card_id
      where review.id = new.review_id;
    new.check_frequency := v_kpis -> (new.snapshot_order) ->> 'frequency';
  end if;
  return new;
end;
$$;
create trigger _review_kpi_frequency before insert on review_kpi_results
  for each row execute function set_review_kpi_frequency();

-- Backfill reviews generated before this field was introduced.
update review_kpi_results result set
  check_frequency = card.kpis -> (result.snapshot_order) ->> 'frequency'
from employee_reviews review
join role_scorecards card on card.id = review.responsibility_card_id
where result.review_id = review.id and result.check_frequency is null;

create table manager_reviews (
  id                                  uuid primary key default gen_random_uuid(),
  review_id                           uuid not null unique references employee_reviews(id) on delete cascade,
  overall_feedback                    text,
  performance_concerns                text,
  support_manager_will_provide        text,
  readiness_for_additional_duties     text,
  strengths                           jsonb not null default '[]'::jsonb,
  development_areas                   jsonb not null default '[]'::jsonb,
  recommended_outcome                 review_outcome,
  submitted_at                        timestamptz,
  submitted_by                        uuid references users(id),
  created_at                          timestamptz not null default now(),
  updated_at                          timestamptz not null default now(),
  constraint manager_review_strengths_array check (
    jsonb_typeof(strengths) = 'array' and jsonb_array_length(strengths) <= 3
  ),
  constraint manager_review_development_areas_array check (
    jsonb_typeof(development_areas) = 'array'
    and jsonb_array_length(development_areas) <= 2
  )
);
create trigger _manager_reviews_updated before update on manager_reviews
  for each row execute function set_updated_at();

create or replace function can_manage_employee_review(p_review_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from employee_reviews review
    join review_cycles cycle on cycle.id = review.review_cycle_id
    where review.id = p_review_id
      and (
        auth_app_role() = 'SUPER_ADMIN'
        or (cycle.company_id = auth_company_id()
          and auth_app_role() in ('ADMIN', 'HR', 'HR_ADMIN'))
        or review.direct_manager_id = auth_employee_id()
      )
  );
$$;

create or replace function save_manager_evaluation(
  p_review_id uuid,
  p_kpis jsonb,
  p_skills jsonb,
  p_overall_feedback text,
  p_performance_concerns text,
  p_support_manager_will_provide text,
  p_readiness_for_additional_duties text,
  p_strengths jsonb,
  p_development_areas jsonb,
  p_overall_rating numeric,
  p_recommended_outcome review_outcome,
  p_submit boolean default false
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_review employee_reviews%rowtype;
  v_item jsonb;
begin
  select * into v_review from employee_reviews where id = p_review_id for update;
  if not found then raise exception 'Review not found'; end if;
  if not can_manage_employee_review(p_review_id) then raise exception 'Not authorized for this allocated employee'; end if;
  if v_review.status in ('FINALIZED', 'CANCELLED') then raise exception 'This review is locked'; end if;
  if jsonb_typeof(coalesce(p_strengths, '[]')) <> 'array'
    or jsonb_array_length(coalesce(p_strengths, '[]')) > 3 then
    raise exception 'A maximum of three strengths is allowed';
  end if;
  if jsonb_typeof(coalesce(p_development_areas, '[]')) <> 'array'
    or jsonb_array_length(coalesce(p_development_areas, '[]')) > 2 then
    raise exception 'A maximum of two development areas is allowed';
  end if;

  for v_item in select value from jsonb_array_elements(coalesce(p_kpis, '[]')) loop
    update review_kpi_results set
      actual_value = nullif(v_item->>'actual_value', ''),
      result_status = nullif(v_item->>'result_status', '')::kpi_result_status,
      manager_rating = nullif(v_item->>'manager_rating', '')::integer,
      manager_comment = nullif(v_item->>'manager_comment', '')
    where id = (v_item->>'id')::uuid and review_id = p_review_id;
  end loop;
  for v_item in select value from jsonb_array_elements(coalesce(p_skills, '[]')) loop
    update review_skill_ratings set
      manager_rating = nullif(v_item->>'manager_rating', '')::integer,
      manager_comment = nullif(v_item->>'manager_comment', ''),
      development_needed = coalesce((v_item->>'development_needed')::boolean, false)
    where id = (v_item->>'id')::uuid and review_id = p_review_id;
  end loop;

  insert into manager_reviews (
    review_id, overall_feedback, performance_concerns,
    support_manager_will_provide, readiness_for_additional_duties,
    strengths, development_areas, recommended_outcome,
    submitted_at, submitted_by
  ) values (
    p_review_id, nullif(trim(p_overall_feedback), ''),
    nullif(trim(p_performance_concerns), ''),
    nullif(trim(p_support_manager_will_provide), ''),
    nullif(trim(p_readiness_for_additional_duties), ''),
    coalesce(p_strengths, '[]'), coalesce(p_development_areas, '[]'),
    p_recommended_outcome, case when p_submit then now() end,
    case when p_submit then auth.uid() end
  ) on conflict (review_id) do update set
    overall_feedback = excluded.overall_feedback,
    performance_concerns = excluded.performance_concerns,
    support_manager_will_provide = excluded.support_manager_will_provide,
    readiness_for_additional_duties = excluded.readiness_for_additional_duties,
    strengths = excluded.strengths,
    development_areas = excluded.development_areas,
    recommended_outcome = excluded.recommended_outcome,
    submitted_at = case when p_submit then now() else manager_reviews.submitted_at end,
    submitted_by = case when p_submit then auth.uid() else manager_reviews.submitted_by end;

  if p_submit then
    if nullif(trim(p_overall_feedback), '') is null then raise exception 'Overall feedback is required'; end if;
    if p_overall_rating is null or p_recommended_outcome is null then
      raise exception 'Overall rating and recommended outcome are required';
    end if;
    if exists (select 1 from review_kpi_results where review_id = p_review_id
      and (result_status is null or manager_rating is null)) then
      raise exception 'Complete every KPI result and rating';
    end if;
    if exists (select 1 from review_skill_ratings where review_id = p_review_id
      and manager_rating is null) then raise exception 'Rate every skill and expectation'; end if;
    if exists (select 1 from jsonb_array_elements(coalesce(p_strengths, '[]')) item
      where nullif(trim(item->>'title'), '') is null) then
      raise exception 'Every strength requires a title';
    end if;
    if exists (select 1 from jsonb_array_elements(coalesce(p_development_areas, '[]')) item
      where nullif(trim(item->>'area'), '') is null) then
      raise exception 'Every development area requires a name';
    end if;
  end if;

  update employee_reviews set
    overall_rating = p_overall_rating,
    overall_outcome = p_recommended_outcome,
    status = case when p_submit then 'READY_FOR_DISCUSSION'::employee_review_status
      else 'MANAGER_REVIEW_IN_PROGRESS'::employee_review_status end
  where id = p_review_id;
end;
$$;

revoke all on function can_manage_employee_review(uuid) from public;
grant execute on function can_manage_employee_review(uuid) to authenticated;
revoke all on function save_manager_evaluation(
  uuid, jsonb, jsonb, text, text, text, text, jsonb, jsonb, numeric, review_outcome, boolean
) from public;
grant execute on function save_manager_evaluation(
  uuid, jsonb, jsonb, text, text, text, text, jsonb, jsonb, numeric, review_outcome, boolean
) to authenticated;

alter table manager_reviews enable row level security;
create policy manager_reviews_read on manager_reviews for select using (
  can_manage_employee_review(review_id)
);
