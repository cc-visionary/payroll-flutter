-- Leave is UNPAID unless someone says otherwise.
--
-- `leave_types.is_paid` was declared `not null default true`
-- (20260414000008_leave.sql:14), and sync-lark-leaves auto-creates a row for
-- every leave type Lark reports without naming that column. So the default
-- decided it: every Lark leave type in this database became paid, including
-- Personal leave, and payroll emitted a full-day PAID_LEAVE earnings line for
-- each one. No migration ever seeded a leave type, so EVERY row here came
-- through that path.
--
-- Lark reports a leave type's name, never whether the company pays for it.
-- That is a payroll decision, and the safe direction for an unknown type is
-- unpaid: an underpayment is visible to the employee and correctable, while an
-- overpayment ships silently and is awkward to claw back.
--
-- Two changes, and the second is the one that stops this recurring:
--   1. Flip the Lark-created rows to unpaid.
--   2. Change the column default, so the next writer who forgets the field
--      gets the safe answer instead of the expensive one.
--
-- Released payslips are deliberately NOT touched. This changes configuration,
-- so future runs and recomputes are correct; money already paid to an employee
-- stays paid. See the handover notes for the query that lists them.

-- 1. Say what is about to change, before changing it.
do $$
declare
  v_paid int;
  v_companies int;
begin
  select count(*), count(distinct company_id)
    into v_paid, v_companies
    from leave_types
   where lark_leave_type_id is not null
     and is_paid;

  raise notice 'leave_types: flipping % Lark-created type(s) across % company(ies) from paid to unpaid', v_paid, v_companies;
end $$;

-- 2. Only Lark-created types. A row without lark_leave_type_id was authored by
--    a human, and a human's "paid" is a decision this migration has no standing
--    to overturn. (Today there are none, but that is a fact about this
--    database, not a rule about the column.)
-- (updated_at is left to the _leave_types_updated trigger, 20260414000008:29.)
update leave_types
   set is_paid = false
 where lark_leave_type_id is not null
   and is_paid;

-- 3. The trap itself. `default true` on a column that decides whether payroll
--    pays a day is the kind of default that costs money the first time someone
--    forgets it — which is exactly what happened.
alter table leave_types
  alter column is_paid set default false;

comment on column leave_types.is_paid is
  'Whether payroll pays a full day for leave of this type. Defaults to FALSE: '
  'an importer that does not know the answer must not guess an expensive one. '
  'Set deliberately in Settings > Leave Types. Lark never supplies this — it '
  'reports a type''s name only.';
