# Per-Employee KPI Assignment (Phase 2) — Design Spec

> Phase 2 of KPI tracking. Date: 2026-07-18. Builds on the Phase 1 KPI library
> (`docs/superpowers/specs/2026-07-18-kpi-library-design.md`).

## Background & goal

After Phase 1, KPIs are a first-class library (`kpis`) linked to role cards
(`role_scorecard_kpis`), and `generate_employee_review` snapshots a role card's
KPIs for each employee on that role. Every employee on a role is therefore
tracked/reviewed on the *whole* role KPI set.

The user wants each employee tracked on only the **realistic few KPIs that apply
to them** — a per-employee subset of their role card's KPIs. This is where the
"only KPIs people can actually track (not lie-prone ones like kiosk floor
conversion)" curation happens. This phase adds that subset layer and points
review generation at it. It does NOT add per-employee targets, the ongoing log,
Lark submission, or the trend view (Phases 3–4).

## Scope

**In:**
- `employee_kpis` join table (which of the role's KPIs an employee owns).
- Re-point `generate_employee_review` to snapshot the employee's assigned subset,
  falling back to the full role set when un-curated.
- An HR/admin assignment section on the employee profile's role tab.
- RLS.

**Out (later phases / YAGNI):**
- Per-employee target/frequency overrides (targets stay on `role_scorecard_kpis`).
- The ongoing KPI log, Lark submission, manager approval (Phase 3).
- Development-tab trend (Phase 4).
- Off-role KPIs — assignment is strictly a subset of the employee's role card.

## Data model

```
employee_kpis
  id           uuid pk default gen_random_uuid()
  employee_id  uuid not null references employees(id) on delete cascade
  kpi_id       uuid not null references kpis(id) on delete cascade
  created_at   timestamptz not null default now()
  unique (employee_id, kpi_id)
```
Index on `employee_id`. No `target`/`frequency` — those come from the employee's
role card link (`role_scorecard_kpis`). `on delete cascade` on both FKs: deleting
an employee or a library KPI removes the assignment row (no orphan). This means
`delete_employee_cascade` needs no change (the FK cascades), and merging/removing
a library KPI (Phase 1 flows) cleans up assignments automatically.

**The "no rows = full role set" rule.** An employee with zero `employee_kpis`
rows is tracked on their entire role card (today's behavior — nothing regresses,
existing employees are unaffected until curated). A non-empty set means "exactly
these." You cannot assign "nothing"; an un-curated employee always has the role's
KPIs.

**Integrity as roles change** — enforced at *read* time, not by triggers:
- The assigned set is always intersected with the role's *current* KPIs. A KPI
  removed from the role card, or left over after the employee changes roles,
  simply drops out. If the intersection is empty, callers fall back to the full
  (new) role set.
- The assignment UI only offers the employee's current role KPIs, so an off-role
  KPI can never be ticked.

## Review generation change

Forward migration re-pointing `generate_employee_review` (copy the current body
from `20260718000002_generate_review_from_kpi_link.sql` verbatim via `sed`;
change only the KPI loop; `v_item` stays jsonb — it is shared with the skills
loops). Add a declared `v_has_assignment boolean` and, before the KPI loop:

```sql
select exists (
  select 1
  from employee_kpis ek
    join role_scorecard_kpis rsk
      on rsk.kpi_id = ek.kpi_id and rsk.role_scorecard_id = v_card.id
  where ek.employee_id = v_employee.id
) into v_has_assignment;
```

Then the KPI loop's source becomes:

```sql
  v_index := 0;
  for v_item in
    select jsonb_build_object(
      'name', k.name,
      'measurement', k.measurement_unit,
      'target', rsk.target
    ) as value
    from role_scorecard_kpis rsk
      join kpis k on k.id = rsk.kpi_id
    where rsk.role_scorecard_id = v_card.id
      and (
        not v_has_assignment
        or exists (
          select 1 from employee_kpis ek
          where ek.employee_id = v_employee.id and ek.kpi_id = rsk.kpi_id
        )
      )
    order by rsk.sort_order
  loop
    insert into review_kpi_results (
      review_id, snapshot_order, kpi_name, description,
      measurement_unit, target_value, is_qualitative
    ) values (
      v_review_id, v_index,
      coalesce(v_item->>'name', ''),
      null, v_item->>'measurement', v_item->>'target',
      false
    );
    v_index := v_index + 1;
  end loop;
```

`v_has_assignment` false (no rows, or none intersecting the current role) → full
role set. True → only the assigned subset. Everything else in the function is
preserved verbatim.

## Assignment UI

On the employee profile's **`role_tab`** (`lib/features/employees/profile/tabs/role_tab.dart`),
HR/admin-gated, a "KPIs this employee is tracked on" section:
- Reads the employee's role KPIs (via the role card) and their `employee_kpis`
  rows; renders the role's current KPIs as a checklist.
- **0 rows:** show "Tracking all N role KPIs (default)" with a *Customize*
  action; opening it pre-checks all so HR only un-checks what doesn't apply.
- **Save:** diff to `employee_kpis` (insert newly-checked, delete unchecked).
  If *all* are checked, store no rows (all-checked ≡ default all), so the table
  only ever holds genuine subsets.
- KPIs not on the current role never appear (read intersects the role).

Non-HR viewers (the employee, their manager) see the list read-only per RLS.

## RLS

Reuse the existing performance helper `auth_is_performance_admin_for_employee(uuid)`
(SECURITY DEFINER, company-scoped, HR/ADMIN/HR_ADMIN-aware; from
`20260717000009`).

```sql
alter table employee_kpis enable row level security;
create policy employee_kpis_read on employee_kpis for select using (
  auth_is_performance_admin_for_employee(employee_id)
  or employee_id = auth_employee_id()
  or exists (select 1 from employees e
             where e.id = employee_id and e.reports_to_id = auth_employee_id())
);
create policy employee_kpis_write on employee_kpis for all
  using (auth_is_performance_admin_for_employee(employee_id))
  with check (auth_is_performance_admin_for_employee(employee_id));
```

## Testing

- **Migration** (throwaway Postgres, then isolated replica before any prod push):
  table + RLS apply; the re-pointed `generate_employee_review` snapshots (a) the
  subset for an employee with an assignment, (b) the full role set for an
  employee with none, (c) the full role set for an employee whose only
  assignment references a KPI not on their current role.
- **Dart:** repo test for reading an employee's assigned ids intersected with the
  role, and for the save-diff payload builder (added vs removed).
- **UI:** widget test on the role-tab section — renders role KPIs, reflects
  checked state, produces the correct insert/delete diff on save.
- `flutter analyze` clean; full suite green.

## Design system

Follows `PRODUCT.md`: single Luxium purple CTA, 6px radius, tinted chips, tables
via `responsive_table.dart` where tabular. No new packages.
