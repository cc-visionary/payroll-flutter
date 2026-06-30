-- Default brand (hiring entity) for a role scorecard. Lets the Edit Employee
-- form derive an employee's brand allocation from their selected scorecard.
-- Nullable: a scorecard may have no default brand, in which case the employee
-- form requires the brand to be set manually.
alter table role_scorecards
  add column if not exists hiring_entity_id uuid
    references hiring_entities(id) on delete restrict;

create index if not exists role_scorecards_hiring_entity_id_idx
  on role_scorecards (hiring_entity_id)
  where hiring_entity_id is not null;

comment on column role_scorecards.hiring_entity_id is
  'Default brand allocation for employees assigned this scorecard. The Edit '
  'Employee form uses it in derive mode; NULL means the employee must set the '
  'brand manually.';
