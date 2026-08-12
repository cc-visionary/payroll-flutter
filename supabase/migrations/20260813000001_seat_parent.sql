-- The Accountability Chart is a tree of SEATS, not of people. employees
-- .reports_to_id cannot express it: a person can hold two seats in different
-- branches (Clinton holds Visionary and Sourcing), and reports_to_id is one
-- value per person.

-- ON DELETE SET NULL, not the default NO ACTION: deleting a seat that has
-- children must not be blocked by an uncaught FK violation (neither delete
-- call site traps one). A re-rooted child is a visible, repairable state — a
-- manager sees it at the top of the chart and can re-parent it — whereas a
-- silently failed delete tells the user nothing. ON DELETE CASCADE is wrong
-- for the opposite reason: it would delete real seats, and with them their
-- holders' role assignment, when only the parent was meant to go.
alter table role_scorecards
  add column if not exists parent_id uuid references role_scorecards(id) on delete set null;
create index if not exists role_scorecards_parent on role_scorecards (parent_id);

comment on column role_scorecards.parent_id is
  'Parent SEAT in the Accountability Chart. Independent of employees.reports_to_id '
  'by design — the two trees answer different questions. Null means a root seat.';

-- A seat must not be its own ancestor. The Dart guard protects the drag-and-drop
-- path; this protects every other path.
create or replace function assert_no_seat_cycle() returns trigger
language plpgsql as $$
declare
  cur uuid := new.parent_id;
  hops int := 0;
begin
  while cur is not null loop
    if cur = new.id then
      raise exception 'seat % cannot be its own ancestor', new.id;
    end if;
    hops := hops + 1;
    if hops > 100 then
      raise exception 'seat parent chain exceeded 100 hops; data is already cyclic';
    end if;
    select parent_id into cur from role_scorecards where id = cur;
  end loop;
  return new;
end $$;

drop trigger if exists _role_scorecards_no_cycle on role_scorecards;
create trigger _role_scorecards_no_cycle
  before insert or update of parent_id on role_scorecards
  for each row when (new.parent_id is not null)
  execute function assert_no_seat_cycle();
