-- Penalty installment lifecycle trigger.
--
-- Keeps `penalties.total_deducted` in sync with the sum of deducted
-- installment amounts, and flips `penalties.status` to COMPLETED once every
-- installment has been withdrawn from a payroll run. Reverses itself if
-- installments are reset (e.g. payroll-run cancel path), so the parent row
-- never drifts out of sync with its children.
--
-- CANCELLED is a terminal manual status and is never overwritten.

create or replace function update_penalty_totals() returns trigger as $$
declare
  target_penalty_id uuid;
  new_total         numeric(12,2);
  pending_count     integer;
begin
  target_penalty_id := coalesce(new.penalty_id, old.penalty_id);

  select coalesce(sum(amount) filter (where is_deducted), 0),
         count(*) filter (where not is_deducted)
    into new_total, pending_count
    from penalty_installments
   where penalty_id = target_penalty_id;

  update penalties
     set total_deducted = new_total,
         status = case
           when status = 'CANCELLED' then 'CANCELLED'::penalty_status
           when pending_count = 0 and new_total > 0 then 'COMPLETED'::penalty_status
           else 'ACTIVE'::penalty_status
         end,
         completed_at = case
           when status = 'CANCELLED' then completed_at
           when pending_count = 0 and new_total > 0
             then coalesce(completed_at, now())
           else null
         end
   where id = target_penalty_id;

  return null;
end;
$$ language plpgsql;

create trigger _penalty_installments_totals
  after insert or update or delete on penalty_installments
  for each row execute function update_penalty_totals();
