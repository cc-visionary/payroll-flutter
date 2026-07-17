-- Add the role standards required by the employee performance module.
-- JSON snapshots preserve display order and make the existing Responsibility
-- Card editor additive. Employee reviews will copy these values when created.

alter table role_scorecards
  add column required_skills jsonb not null default '[]'::jsonb,
  add column behavioral_expectations jsonb not null default '[]'::jsonb,
  add column version integer not null default 1;

alter table role_scorecards
  add constraint role_scorecards_version_positive check (version > 0),
  add constraint role_scorecards_required_skills_array
    check (jsonb_typeof(required_skills) = 'array'),
  add constraint role_scorecards_behavioral_expectations_array
    check (jsonb_typeof(behavioral_expectations) = 'array');

comment on column role_scorecards.required_skills is
  'Ordered role skill standards: name, description, required_level (1-5).';
comment on column role_scorecards.behavioral_expectations is
  'Ordered behavior standards: name and observable description.';
comment on column role_scorecards.version is
  'Human-readable version copied into employee review snapshots.';

create or replace function increment_role_scorecard_version()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.job_title is distinct from old.job_title
     or new.mission_statement is distinct from old.mission_statement
     or new.key_responsibilities is distinct from old.key_responsibilities
     or new.kpis is distinct from old.kpis
     or new.required_skills is distinct from old.required_skills
     or new.behavioral_expectations is distinct from old.behavioral_expectations
  then
    new.version := old.version + 1;
  else
    new.version := old.version;
  end if;
  return new;
end;
$$;

create trigger _role_scorecards_increment_version
before update on role_scorecards
for each row execute function increment_role_scorecard_version();
