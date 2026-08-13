# Handover — leave is unpaid unless someone says so

**Branch:** `fix/leave-types-unpaid` · **Commit:** `bf2bece`
**Migration:** `20260815000001_leave_types_unpaid_by_default.sql` — **not applied**

## What was wrong

`leave_types.is_paid` was `not null default true`, and `sync-lark-leaves`
auto-created a row for every leave type Lark reported without naming that
column. So the default decided it. Every leave type in the database — all of
them created by that sync, since no migration ever seeded one — became paid,
and payroll emitted a full-day `PAID_LEAVE` earnings line for each. There was
no screen anywhere that could set the field, so it could not be corrected.

## Before you run `supabase db push`

The migration prints what it is about to change before changing it:

```
NOTICE: leave_types: flipping N Lark-created type(s) across M company(ies) from paid to unpaid
```

If that count is zero and you expected otherwise, stop and look — it means
something already changed the rows.

## Released payslips already paid this leave

The migration deliberately does **not** touch them. It changes configuration,
so future runs and recomputes are correct; money already paid to an employee
stays paid.

To see the exposure, run this against production:

```sql
select pp.start_date,
       pp.end_date,
       pr.status,
       e.employee_number,
       e.last_name || ', ' || e.first_name as employee,
       pl.description,
       pl.quantity as days,
       pl.amount
  from payslip_lines pl
  join payslips     p  on p.id  = pl.payslip_id
  join payroll_runs pr on pr.id = p.payroll_run_id
  join pay_periods  pp on pp.id = pr.pay_period_id
  join employees    e  on e.id  = p.employee_id
 where pl.category = 'PAID_LEAVE'
   and pr.status   = 'RELEASED'
 order by pp.start_date desc, e.last_name;
```

Totals per period, if you want the number rather than the rows:

```sql
select pp.start_date, pp.end_date,
       count(*) as lines, sum(pl.amount) as total_paid
  from payslip_lines pl
  join payslips     p  on p.id  = pl.payslip_id
  join payroll_runs pr on pr.id = p.payroll_run_id
  join pay_periods  pp on pp.id = pr.pay_period_id
 where pl.category = 'PAID_LEAVE'
   and pr.status   = 'RELEASED'
 group by 1, 2
 order by 1 desc;
```

Whether any of it should be recovered is a decision for you and Brixter, not
something this change makes for you. Nothing in the app will revisit it.

## Open runs

Any run still in `DRAFT` or `REVIEW` keeps its computed numbers until it is
recomputed. Recompute after applying the migration and the `PAID_LEAVE` lines
disappear for types that are now unpaid — the two payslips in the report
(Brixter, Marjory; Jul 31 – Aug 14) each drop ₱1,184.61 of leave from gross.

## After applying

1. Deploy the edge function: `supabase functions deploy sync-lark-leaves`.
   Until then the old code keeps inserting rows — harmless now that the column
   default is `false`, but the explicit write is the guard that matters.
2. Open **Settings ▸ Leave Types** and mark the types that genuinely are paid.
   Everything is unpaid after the migration, so if SIL or any statutory paid
   leave is in that list, it needs turning on before the next run.
3. Recompute any open run.

## Why the fix is shaped this way

Lark reports a leave type's **name**. It never reports whether the company
pays for it. An importer that cannot know must not guess the expensive
answer — an underpayment is visible to the employee and correctable, an
overpayment ships silently and is awkward to claw back.

So: the sync writes `is_paid: false` explicitly, the column default is now
`false` for whoever forgets next time, and the decision moved to a screen
where a person makes it.
