-- Backfill penalties.total_deducted / status / completed_at from installments.
--
-- The `_penalty_installments_totals` trigger (20260418000008) keeps the parent
-- penalty in sync, but only fires on installment writes. Installments that were
-- marked deducted on 2026-04-18 BEFORE the trigger was installed — and never
-- touched again — left their parents frozen at total_deducted=0 / ACTIVE while
-- the installments (and the employee-profile UI, which derives from them) say
-- fully deducted. Seen on prod: EMP008 Property Damage ₱720, EMP007 Late
-- Opening ₱524.38.
--
-- This re-runs the exact aggregation the trigger performs, for every penalty
-- whose stored totals disagree with its installments. Idempotent; CANCELLED
-- stays terminal, mirroring the trigger. completed_at backfills from the last
-- deducted_at so the historical completion date is meaningful.

update penalties p
   set total_deducted = agg.deducted_total,
       status = case
         when p.status = 'CANCELLED' then p.status
         when agg.pending_count = 0 and agg.deducted_total > 0
           then 'COMPLETED'::penalty_status
         else 'ACTIVE'::penalty_status
       end,
       completed_at = case
         when p.status = 'CANCELLED' then p.completed_at
         when agg.pending_count = 0 and agg.deducted_total > 0
           then coalesce(p.completed_at, agg.last_deducted_at, now())
         else null
       end
  from (
    select penalty_id,
           coalesce(sum(amount) filter (where is_deducted), 0) as deducted_total,
           count(*) filter (where not is_deducted)             as pending_count,
           max(deducted_at)                                    as last_deducted_at
      from penalty_installments
     group by penalty_id
  ) agg
 where agg.penalty_id = p.id
   and p.total_deducted is distinct from agg.deducted_total;
