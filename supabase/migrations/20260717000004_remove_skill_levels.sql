-- Skill standards are descriptive; ratings happen during the employee review.
-- Remove previously stored expected levels and neutralize older snapshot code.

update role_scorecards card
set required_skills = coalesce(
  (
    select jsonb_agg(skill - 'required_level')
    from jsonb_array_elements(card.required_skills) skill
  ),
  '[]'::jsonb
);

update review_skill_ratings set required_level = null;

create or replace function clear_review_skill_required_level()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.required_level := null;
  return new;
end;
$$;

create trigger _review_skill_ratings_clear_required_level
before insert or update of required_level on review_skill_ratings
for each row execute function clear_review_skill_required_level();

alter table review_skill_ratings
  drop constraint review_skill_required_level_valid,
  add constraint review_skill_required_level_removed check (required_level is null);

comment on column role_scorecards.required_skills is
  'Ordered role skill standards: name and description.';
comment on column review_skill_ratings.required_level is
  'Deprecated compatibility column. Always null; skill levels are not used.';
