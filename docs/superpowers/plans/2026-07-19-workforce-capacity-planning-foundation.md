# Workforce Capacity Planning — Foundation (Plan 1 of 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the backend + Dart data layer for the driver-based capacity model — schema, RLS, computed views, an idempotent xlsx seed, plain-Dart models, a repository, and the pure `capacity_math` / `org_tree` helpers — so per-person load is queryable and unit-tested with no UI yet.

**Architecture:** Six company-scoped `wp_*` tables hold nodes, drivers, rates, tasks, per-person capacity overrides, and one config row. Two `security_invoker` Postgres views (`wp_task_computed`, `wp_person_load`) expose per-task hours and per-person aggregates (fixed hours + growing-at-×1 hours + capacity + stored multiplier); all base/scaled/load math lives in one tested Dart module (`capacity_math`) so the UI can project any multiplier live. A one-time generated data migration seeds the model from `luxium_capacity_model.xlsx`.

**Tech Stack:** Supabase Postgres + RLS, Flutter (plain-Dart models, Riverpod providers), `supabase_flutter`, Python `openpyxl` (build-time seed generator only), `flutter test`.

## Global Constraints

- **Spec:** `docs/superpowers/specs/2026-07-19-workforce-capacity-planning-design.md`. This is Plan 1 (Foundation) of the 3-plan slice; Plans 2 (hub + read tabs) and 3 (Structure drag-drop) follow.
- Repo gates on **`flutter analyze` only** — do **NOT** run `dart format`; match each file's surrounding style.
- Migrations are **forward-only**; never edit an applied migration. New files sort after `20260718000007`.
- RLS on every `wp_*` table mirrors `kpis` (`20260718000001`): company read, HR/Admin/Super-admin write, via `auth_app_role()` / `auth_company_id()`.
- Numeric DB columns → Dart `double` (`(r['x'] as num?)?.toDouble()`); ids → `String`.
- Postgres client in repos: `Supabase.instance.client` passed to the constructor; Riverpod `Provider` at file end (pattern in `role_scorecard_repository.dart:375`).
- Never edit an applied migration; validate every migration on the isolated replica before any prod push (memory `reference_local_supabase_rls_testing`: run an isolated copy on ports 643xx, seed spliced **before** `20260418000002`, simulate roles via `request.jwt.claims`). **Do not push to prod in this plan** — validation only; the user runs the prod push.
- Design system (`PRODUCT.md`) applies to Plans 2–3, not this backend plan.

---

## File Structure

**Create:**
- `supabase/migrations/20260719000001_wp_core_tables.sql` — 6 tables + indexes + RLS.
- `supabase/migrations/20260719000002_wp_views.sql` — `wp_task_computed`, `wp_person_load`.
- `supabase/migrations/20260719000003_wp_seed_from_xlsx.sql` — generated idempotent seed.
- `scripts/wp_seed_from_xlsx.py` — build-time generator that reads the xlsx and emits the seed migration (committed for reproducibility; not run in prod).
- `lib/data/models/workforce_planning.dart` — `WpNode`, `WpDriver`, `WpRate`, `WpConfig`, `WpTask`, `WpTaskComputed`, `WpPersonLoad`.
- `lib/features/workforce_planning/capacity_math.dart` — pure hours/load/status calculator.
- `lib/features/workforce_planning/org_tree.dart` — pure tree builder + cycle guard.
- `lib/data/repositories/workforce_planning_repository.dart` — reads/writes + providers.
- `test/features/workforce_planning/capacity_math_test.dart`
- `test/features/workforce_planning/org_tree_test.dart`
- `test/data/models/workforce_planning_test.dart`

**Modify:** none in this plan (the screen rebuild is Plan 2).

---

### Task 1: Core tables migration

**Files:**
- Create: `supabase/migrations/20260719000001_wp_core_tables.sql`

**Interfaces:**
- Produces: tables `wp_value_chain_nodes`, `wp_drivers`, `wp_rates`, `wp_config`, `wp_tasks`, `wp_capacity_overrides` with the columns Task 2's views and Task 4's models read.

- [ ] **Step 1: Write the migration**

```sql
-- Workforce Capacity Planning (Phase A+B) — foundation tables.
-- Driver-based model: costed tasks -> per-person load. Company-scoped.
-- RLS mirrors kpis (20260718000001): company read, HR/Admin/Super-admin write.

create table wp_value_chain_nodes (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references companies(id) on delete cascade,
  code        text not null,
  name        text not null,
  sort_order  int  not null default 0,
  created_at  timestamptz not null default now()
);
create unique index wp_value_chain_nodes_uniq on wp_value_chain_nodes (company_id, lower(trim(name)));
create index wp_value_chain_nodes_company on wp_value_chain_nodes (company_id);

create table wp_drivers (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references companies(id) on delete cascade,
  name        text not null,
  value       numeric not null default 0,
  grows       boolean not null default false,
  note        text,
  sort_order  int  not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index wp_drivers_uniq on wp_drivers (company_id, lower(trim(name)));
create index wp_drivers_company on wp_drivers (company_id);

create table wp_rates (
  id           uuid primary key default gen_random_uuid(),
  company_id   uuid not null references companies(id) on delete cascade,
  name         text not null,
  minutes_each numeric not null default 0,
  note         text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create unique index wp_rates_uniq on wp_rates (company_id, lower(trim(name)));
create index wp_rates_company on wp_rates (company_id);

create table wp_config (
  company_id             uuid primary key references companies(id) on delete cascade,
  growth_multiplier      numeric not null default 1.0,
  default_capacity_hours numeric not null default 160,
  updated_at             timestamptz not null default now()
);

create table wp_tasks (
  id                  uuid primary key default gen_random_uuid(),
  company_id          uuid not null references companies(id) on delete cascade,
  node_id             uuid references wp_value_chain_nodes(id) on delete set null,
  name                text not null,
  brand_scope         text,
  cadence             text,
  times_source        text not null default 'manual' check (times_source in ('manual','driver')),
  times_manual        numeric,
  driver_id           uuid references wp_drivers(id) on delete set null,
  driver_factor       numeric not null default 1,
  minutes_source      text not null default 'manual' check (minutes_source in ('manual','rate')),
  minutes_manual      numeric,
  rate_id             uuid references wp_rates(id) on delete set null,
  skill_tier          text check (skill_tier is null or skill_tier in ('Transactional','Operational','Managerial','Strategic')),
  risk                text check (risk is null or risk in ('Low','Medium','High')),
  capability          text,
  owner_employee_id   uuid references employees(id) on delete set null,
  role_scorecard_id   uuid references role_scorecards(id) on delete set null,
  responsibility_area text,
  notes               text,
  external_ref        text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create unique index wp_tasks_external_ref_uniq on wp_tasks (company_id, external_ref) where external_ref is not null;
create index wp_tasks_company on wp_tasks (company_id);
create index wp_tasks_owner   on wp_tasks (owner_employee_id);
create index wp_tasks_node    on wp_tasks (node_id);

create table wp_capacity_overrides (
  employee_id    uuid primary key references employees(id) on delete cascade,
  capacity_hours numeric not null,
  updated_at     timestamptz not null default now()
);

-- RLS: company-scoped read, HR/Admin/Super-admin write (mirrors kpis).
do $$
declare tbl text;
begin
  foreach tbl in array array['wp_value_chain_nodes','wp_drivers','wp_rates','wp_config','wp_tasks'] loop
    execute format('alter table %I enable row level security;', tbl);
    execute format(
      'create policy %1$s_select on %1$I for select using (company_id = auth_company_id() or auth_app_role() = ''SUPER_ADMIN'');',
      tbl);
    execute format(
      'create policy %1$s_write on %1$I for all '
      'using (auth_app_role() in (''SUPER_ADMIN'',''ADMIN'',''HR'') and (company_id = auth_company_id() or auth_app_role() = ''SUPER_ADMIN'')) '
      'with check (auth_app_role() in (''SUPER_ADMIN'',''ADMIN'',''HR'') and (company_id = auth_company_id() or auth_app_role() = ''SUPER_ADMIN''));',
      tbl);
  end loop;
end $$;

-- wp_capacity_overrides is keyed by employee_id; resolve company through employees.
alter table wp_capacity_overrides enable row level security;
create policy wp_capacity_overrides_select on wp_capacity_overrides for select using (
  exists (select 1 from employees e where e.id = employee_id
    and (e.company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN')));
create policy wp_capacity_overrides_write on wp_capacity_overrides for all
  using (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR') and exists (
    select 1 from employees e where e.id = employee_id
      and (e.company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN')))
  with check (auth_app_role() in ('SUPER_ADMIN','ADMIN','HR') and exists (
    select 1 from employees e where e.id = employee_id
      and (e.company_id = auth_company_id() or auth_app_role() = 'SUPER_ADMIN')));
```

- [ ] **Step 2: Validate on the isolated replica**

Bring up the isolated replica (memory `reference_local_supabase_rls_testing`), apply this migration, then assert the schema:

Run:
```bash
psql "$WP_REPLICA_URL" -f supabase/migrations/20260719000001_wp_core_tables.sql
psql "$WP_REPLICA_URL" -c "\d wp_tasks" \
  -c "select count(*) from pg_policies where tablename like 'wp\_%';"
```
Expected: `wp_tasks` shows the columns above with the two CHECK constraints and the partial unique index; the policy count is **11** (2 each on nodes/drivers/rates/config/tasks + capacity_overrides' 2 — i.e. 12; confirm ≥ 2 per table and no errors). No errors.

- [ ] **Step 3: Sanity-check the CHECK + partial index**

Run:
```bash
psql "$WP_REPLICA_URL" -c "insert into wp_tasks (company_id, name, skill_tier) values ((select id from companies limit 1), 't', 'Bogus');"
```
Expected: FAIL — `new row ... violates check constraint "wp_tasks_skill_tier_check"`.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260719000001_wp_core_tables.sql
git commit -m "feat(workforce): wp_* core tables + RLS for capacity planning"
```

---

### Task 2: Computed views

**Files:**
- Create: `supabase/migrations/20260719000002_wp_views.sql`

**Interfaces:**
- Consumes: Task 1 tables.
- Produces: view `wp_task_computed(task_id, company_id, owner_employee_id, node_id, skill_tier, risk, is_growing, times_per_month_base, minutes_each, hours_per_month_base)` and view `wp_person_load(employee_id, company_id, tasks_owned, hours_fixed, hours_growing_base, capacity_hours, growth_multiplier)`. Base/scaled/load are computed in Dart (`capacity_math`, Task 5) from these aggregates so the UI can project any multiplier live.

- [ ] **Step 1: Write the migration**

```sql
-- Canonical per-task hours and per-person aggregates. security_invoker so base
-- table RLS governs visibility. base = multiplier 1. A task "grows" only when it
-- is driver-bound AND its driver grows; hours_growing_base is those tasks at x1,
-- so any multiplier m projects as hours_fixed + hours_growing_base * m (in Dart).

create view wp_task_computed with (security_invoker = true) as
select
  x.*,
  (x.times_per_month_base * x.minutes_each / 60.0) as hours_per_month_base
from (
  select
    t.id                as task_id,
    t.company_id,
    t.owner_employee_id,
    t.node_id,
    t.skill_tier,
    t.risk,
    (t.times_source = 'driver' and coalesce(d.grows, false)) as is_growing,
    case when t.times_source = 'driver'
         then coalesce(d.value, 0) * t.driver_factor
         else coalesce(t.times_manual, 0) end as times_per_month_base,
    case when t.minutes_source = 'rate'
         then coalesce(r.minutes_each, 0)
         else coalesce(t.minutes_manual, 0) end as minutes_each
  from wp_tasks t
  left join wp_drivers d on d.id = t.driver_id
  left join wp_rates   r on r.id = t.rate_id
) x;

create view wp_person_load with (security_invoker = true) as
select
  e.id         as employee_id,
  e.company_id,
  count(tc.task_id) as tasks_owned,
  coalesce(sum(tc.hours_per_month_base) filter (where not tc.is_growing), 0) as hours_fixed,
  coalesce(sum(tc.hours_per_month_base) filter (where tc.is_growing), 0)     as hours_growing_base,
  coalesce(ov.capacity_hours, cfg.default_capacity_hours, 160) as capacity_hours,
  coalesce(cfg.growth_multiplier, 1) as growth_multiplier
from employees e
left join wp_task_computed      tc  on tc.owner_employee_id = e.id
left join wp_capacity_overrides ov  on ov.employee_id = e.id
left join wp_config             cfg on cfg.company_id = e.company_id
where e.employment_status = 'ACTIVE'
group by e.id, e.company_id, ov.capacity_hours, cfg.default_capacity_hours, cfg.growth_multiplier;
```

- [ ] **Step 2: Validate the math on the isolated replica**

Run (seeds one company, one config, one growing driver, one manual task, assigns both to one employee, checks aggregates):
```bash
psql "$WP_REPLICA_URL" -f supabase/migrations/20260719000002_wp_views.sql
psql "$WP_REPLICA_URL" <<'SQL'
do $$
declare c uuid; emp uuid; drv uuid; nod uuid;
begin
  select id into c from companies limit 1;
  select id into emp from employees where company_id = c and employment_status='ACTIVE' limit 1;
  insert into wp_config(company_id, growth_multiplier, default_capacity_hours) values (c, 2, 160)
    on conflict (company_id) do update set growth_multiplier=2, default_capacity_hours=160;
  insert into wp_drivers(company_id, name, value, grows) values (c,'T-orders',100,true) returning id into drv;
  -- driver-bound task: 100 units x 12 min /60 = 20 hrs base; grows -> 40 at x2
  insert into wp_tasks(company_id, name, times_source, driver_id, minutes_source, minutes_manual, owner_employee_id)
    values (c,'flash', 'driver', drv, 'manual', 12, emp);
  -- manual fixed task: 4 times x 30 min /60 = 2 hrs, never grows
  insert into wp_tasks(company_id, name, times_source, times_manual, minutes_source, minutes_manual, owner_employee_id)
    values (c,'vet', 'manual', 4, 'manual', 30, emp);
end $$;
select tasks_owned, hours_fixed, hours_growing_base, capacity_hours, growth_multiplier
  from wp_person_load where employee_id = (select id from employees where employment_status='ACTIVE' limit 1);
SQL
```
Expected: one row `tasks_owned=2, hours_fixed=2, hours_growing_base=20, capacity_hours=160, growth_multiplier=2`. (Load at ×2 = (2 + 20·2)/160 = 0.2625, computed later in Dart.)

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260719000002_wp_views.sql
git commit -m "feat(workforce): wp_task_computed + wp_person_load views"
```

---

### Task 3: xlsx → SQL seed generator + seed migration

**Files:**
- Create: `scripts/wp_seed_from_xlsx.py`
- Create: `supabase/migrations/20260719000003_wp_seed_from_xlsx.sql` (generated output)

**Interfaces:**
- Consumes: Task 1 tables. Reads `~/Downloads/luxium_capacity_model.xlsx`.
- Produces: an idempotent seed. Nodes/drivers/rates find-or-insert by name; tasks upsert by `(company_id, external_ref)`. Owners resolved by `first_name || ' ' || last_name`; unmatched → null.

- [ ] **Step 1: Write the generator**

```python
#!/usr/bin/env python3
"""Generate supabase/migrations/20260719000003_wp_seed_from_xlsx.sql from the
Luxium capacity model. Run once at build time; the emitted SQL is committed and
is what actually applies to a database. Idempotent: re-running the SQL is safe.

Usage: python3 scripts/wp_seed_from_xlsx.py ~/Downloads/luxium_capacity_model.xlsx
"""
import sys, openpyxl

SRC = sys.argv[1] if len(sys.argv) > 1 else \
    __import__('os').path.expanduser('~/Downloads/luxium_capacity_model.xlsx')
OUT = 'supabase/migrations/20260719000003_wp_seed_from_xlsx.sql'

def q(v):
    if v is None: return 'null'
    return "'" + str(v).replace("'", "''").strip() + "'"

def num(v):
    if v in (None, ''): return 'null'
    try: return repr(float(v))
    except (TypeError, ValueError): return 'null'

wb = openpyxl.load_workbook(SRC, data_only=True)

# --- Nodes: Lists sheet, "Value chain node" column A, rows 4.. until blank ---
nodes = []  # (code, name)
ws = wb['Lists']
for r in range(4, ws.max_row + 1):
    name = ws.cell(r, 1).value
    if not name or not str(name).strip(): continue
    name = str(name).strip()
    code = name.split('.', 1)[0].strip() if '.' in name else name.split()[0].strip()
    nodes.append((code, name))

# --- Drivers (Block 1) + Rates (Block 2) from Drivers sheet ---
ws = wb['Drivers']
drivers, rates = [], []  # drivers: (name,value,grows); rates: (name,minutes)
mode = None
for r in range(1, ws.max_row + 1):
    a = ws.cell(r, 1).value
    at = str(a).strip() if a else ''
    if at.startswith('BLOCK 1'): mode = 'drv'; continue
    if at.startswith('BLOCK 2'): mode = 'rate'; continue
    if not at or at.lower() == 'driver' or at.lower() == 'rate': continue
    if mode == 'drv':
        val = ws.cell(r, 2).value
        grows = str(ws.cell(r, 4).value or '').strip().upper().startswith('Y')
        if val is not None and str(val).strip() != '':
            drivers.append((at, val, grows))
    elif mode == 'rate':
        mins = ws.cell(r, 2).value
        if mins is not None and str(mins).strip() != '':
            rates.append((at, mins))

# value -> unique driver name (for best-effort volume binding)
from collections import Counter
val_counts = Counter(round(float(v), 6) for _, v, _ in drivers if str(v).strip() != '')
val_to_driver = {round(float(v), 6): n for n, v, _ in drivers
                 if val_counts[round(float(v), 6)] == 1}

# --- Tasks sheet ---
ws = wb['Tasks']
tasks = []
for r in range(5, ws.max_row + 1):
    tid = ws.cell(r, 1).value
    name = ws.cell(r, 3).value
    if not tid or not name: continue
    cadence = str(ws.cell(r, 5).value or '').strip()
    times = ws.cell(r, 6).value
    minutes = ws.cell(r, 7).value
    is_volume = 'volume' in cadence.lower() or 'per-unit' in cadence.lower()
    bind = None
    if is_volume and times is not None:
        bind = val_to_driver.get(round(float(times), 6))
    tasks.append(dict(
        ref=str(tid).strip(),
        node=str(ws.cell(r, 2).value or '').strip(),
        name=str(name).strip(),
        brand=ws.cell(r, 4).value,
        cadence=cadence or None,
        times=times, minutes=minutes, bind_driver=bind,
        tier=ws.cell(r, 9).value, risk=ws.cell(r, 10).value,
        capability=ws.cell(r, 11).value, owner=ws.cell(r, 12).value,
    ))

# --- Emit SQL ---
L = []
L.append("-- GENERATED by scripts/wp_seed_from_xlsx.py from luxium_capacity_model.xlsx.")
L.append("-- One-time Luxium capacity-model seed. Idempotent. Do not hand-edit; regenerate.")
L.append("do $$")
L.append("declare v_company uuid;")
L.append("begin")
L.append("  if (select count(*) from companies) <> 1 then")
L.append("    raise exception 'wp seed: expected exactly one company; set v_company explicitly';")
L.append("  end if;")
L.append("  select id into v_company from companies limit 1;")
for code, name in nodes:
    L.append(f"  insert into wp_value_chain_nodes(company_id, code, name) "
             f"select v_company, {q(code)}, {q(name)} "
             f"where not exists (select 1 from wp_value_chain_nodes n "
             f"where n.company_id=v_company and lower(trim(n.name))=lower(trim({q(name)})));")
for n, v, g in drivers:
    L.append(f"  insert into wp_drivers(company_id, name, value, grows) "
             f"select v_company, {q(n)}, {num(v)}, {str(g).lower()} "
             f"where not exists (select 1 from wp_drivers d "
             f"where d.company_id=v_company and lower(trim(d.name))=lower(trim({q(n)})));")
for n, m in rates:
    L.append(f"  insert into wp_rates(company_id, name, minutes_each) "
             f"select v_company, {q(n)}, {num(m)} "
             f"where not exists (select 1 from wp_rates r "
             f"where r.company_id=v_company and lower(trim(r.name))=lower(trim({q(n)})));")
for t in tasks:
    owner = (f"(select id from employees where company_id=v_company and "
             f"lower(trim(first_name||' '||last_name))=lower(trim({q(t['owner'])})) limit 1)") \
             if t['owner'] and str(t['owner']).strip() else "null"
    node = (f"(select id from wp_value_chain_nodes where company_id=v_company and "
            f"lower(trim(name))=lower(trim({q(t['node'])})) limit 1)") if t['node'] else "null"
    if t['bind_driver']:
        tsrc, tman = "'driver'", "null"
        drv = (f"(select id from wp_drivers where company_id=v_company and "
               f"lower(trim(name))=lower(trim({q(t['bind_driver'])})) limit 1)")
    else:
        tsrc, tman, drv = "'manual'", num(t['times']), "null"
    tier = q(t['tier']) if t['tier'] in ('Transactional','Operational','Managerial','Strategic') else 'null'
    risk = q(t['risk']) if t['risk'] in ('Low','Medium','High') else 'null'
    L.append(
        "  insert into wp_tasks(company_id, external_ref, name, node_id, brand_scope, cadence, "
        "times_source, times_manual, driver_id, minutes_source, minutes_manual, skill_tier, risk, "
        "capability, owner_employee_id) values ("
        f"v_company, {q(t['ref'])}, {q(t['name'])}, {node}, {q(t['brand'])}, {q(t['cadence'])}, "
        f"{tsrc}, {tman}, {drv}, 'manual', {num(t['minutes'])}, {tier}, {risk}, "
        f"{q(t['capability'])}, {owner}) "
        "on conflict (company_id, external_ref) do update set "
        "name=excluded.name, node_id=excluded.node_id, brand_scope=excluded.brand_scope, "
        "cadence=excluded.cadence, times_source=excluded.times_source, times_manual=excluded.times_manual, "
        "driver_id=excluded.driver_id, minutes_source=excluded.minutes_source, "
        "minutes_manual=excluded.minutes_manual, skill_tier=excluded.skill_tier, risk=excluded.risk, "
        "capability=excluded.capability, owner_employee_id=excluded.owner_employee_id, updated_at=now();")
L.append("  insert into wp_config(company_id) select v_company "
         "where not exists (select 1 from wp_config where company_id=v_company);")
L.append("end $$;")
open(OUT, 'w').write("\n".join(L) + "\n")
print(f"Wrote {OUT}: {len(nodes)} nodes, {len(drivers)} drivers, {len(rates)} rates, {len(tasks)} tasks")
```

> Note: `on conflict (company_id, external_ref)` targets the **partial** unique index; every seeded task has a non-null `external_ref`, so the predicate is always satisfied and the conflict target is valid. Tasks created in-app (Plan 2) leave `external_ref` null and never collide.

- [ ] **Step 2: Generate the seed migration**

Run:
```bash
python3 scripts/wp_seed_from_xlsx.py ~/Downloads/luxium_capacity_model.xlsx
```
Expected: prints `Wrote supabase/migrations/20260719000003_wp_seed_from_xlsx.sql: NN nodes, NN drivers, NN rates, ~160 tasks` and the file exists.

- [ ] **Step 3: Apply on the isolated replica and report match rate**

Run:
```bash
psql "$WP_REPLICA_URL" -f supabase/migrations/20260719000003_wp_seed_from_xlsx.sql
psql "$WP_REPLICA_URL" -c "select count(*) tasks, count(owner_employee_id) owned, count(*) filter (where node_id is not null) noded from wp_tasks;"
# Idempotency: applying twice must not change the count.
psql "$WP_REPLICA_URL" -f supabase/migrations/20260719000003_wp_seed_from_xlsx.sql
psql "$WP_REPLICA_URL" -c "select count(*) from wp_tasks;"
```
Expected: first query reports ~160 tasks with an owned/noded breakdown (record the numbers — this is the "match rate" to report to the user; unmatched owners are expected and get fixed in-app). The second apply leaves the task count unchanged (idempotent).

- [ ] **Step 4: Commit**

```bash
git add scripts/wp_seed_from_xlsx.py supabase/migrations/20260719000003_wp_seed_from_xlsx.sql
git commit -m "feat(workforce): idempotent capacity-model seed from xlsx"
```

---

### Task 4: Dart models

**Files:**
- Create: `lib/data/models/workforce_planning.dart`
- Test: `test/data/models/workforce_planning_test.dart`

**Interfaces:**
- Consumes: view/table column names from Tasks 1–2.
- Produces: `WpNode`, `WpDriver`, `WpRate`, `WpConfig`, `WpTask`, `WpTaskComputed`, `WpPersonLoad` with `fromRow`; `WpDriver.toUpsert`, `WpRate.toUpsert`, `WpTask.toUpsert`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';

void main() {
  test('WpPersonLoad.fromRow parses aggregates', () {
    final p = WpPersonLoad.fromRow({
      'employee_id': 'e1', 'company_id': 'c1', 'tasks_owned': 2,
      'hours_fixed': 2.0, 'hours_growing_base': 20.0,
      'capacity_hours': 160.0, 'growth_multiplier': 2.0,
    });
    expect(p.tasksOwned, 2);
    expect(p.hoursGrowingBase, 20.0);
    expect(p.capacityHours, 160.0);
    expect(p.growthMultiplier, 2.0);
  });

  test('WpTask.toUpsert emits driver source with null manual', () {
    const t = WpTask(id: '', companyId: 'c1', name: 'flash',
      timesSource: 'driver', driverId: 'd1', driverFactor: 1,
      minutesSource: 'manual', minutesManual: 12);
    final m = t.toUpsert('c1');
    expect(m['times_source'], 'driver');
    expect(m['driver_id'], 'd1');
    expect(m['times_manual'], isNull);
    expect(m['minutes_manual'], 12);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/data/models/workforce_planning_test.dart`
Expected: FAIL — `Target of URI doesn't exist` / `WpPersonLoad` undefined.

- [ ] **Step 3: Write the models**

```dart
double _d(Object? v) => (v as num?)?.toDouble() ?? 0;
double? _dn(Object? v) => (v as num?)?.toDouble();
int _i(Object? v) => (v as num?)?.toInt() ?? 0;
String? _s(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();

class WpNode {
  final String id, companyId, code, name;
  final int sortOrder;
  const WpNode({required this.id, required this.companyId, required this.code,
    required this.name, this.sortOrder = 0});
  factory WpNode.fromRow(Map<String, dynamic> r) => WpNode(
    id: r['id'] as String, companyId: r['company_id'] as String,
    code: r['code'] as String, name: r['name'] as String,
    sortOrder: _i(r['sort_order']));
}

class WpDriver {
  final String id, companyId, name;
  final double value;
  final bool grows;
  final String? note;
  final int sortOrder;
  const WpDriver({required this.id, required this.companyId, required this.name,
    this.value = 0, this.grows = false, this.note, this.sortOrder = 0});
  factory WpDriver.fromRow(Map<String, dynamic> r) => WpDriver(
    id: r['id'] as String, companyId: r['company_id'] as String,
    name: r['name'] as String, value: _d(r['value']),
    grows: r['grows'] as bool? ?? false, note: r['note'] as String?,
    sortOrder: _i(r['sort_order']));
  Map<String, dynamic> toUpsert(String companyId) => {
    'company_id': companyId, 'name': name.trim(), 'value': value,
    'grows': grows, 'note': _s(note), 'sort_order': sortOrder};
}

class WpRate {
  final String id, companyId, name;
  final double minutesEach;
  final String? note;
  const WpRate({required this.id, required this.companyId, required this.name,
    this.minutesEach = 0, this.note});
  factory WpRate.fromRow(Map<String, dynamic> r) => WpRate(
    id: r['id'] as String, companyId: r['company_id'] as String,
    name: r['name'] as String, minutesEach: _d(r['minutes_each']),
    note: r['note'] as String?);
  Map<String, dynamic> toUpsert(String companyId) => {
    'company_id': companyId, 'name': name.trim(),
    'minutes_each': minutesEach, 'note': _s(note)};
}

class WpConfig {
  final String companyId;
  final double growthMultiplier, defaultCapacityHours;
  const WpConfig({required this.companyId, this.growthMultiplier = 1,
    this.defaultCapacityHours = 160});
  factory WpConfig.fromRow(Map<String, dynamic> r) => WpConfig(
    companyId: r['company_id'] as String,
    growthMultiplier: _dn(r['growth_multiplier']) ?? 1,
    defaultCapacityHours: _dn(r['default_capacity_hours']) ?? 160);
}

class WpTask {
  final String id, companyId, name;
  final String? nodeId, brandScope, cadence, driverId, rateId, skillTier, risk,
      capability, ownerEmployeeId, roleScorecardId, responsibilityArea, notes,
      externalRef;
  final String timesSource, minutesSource;
  final double? timesManual, minutesManual;
  final double driverFactor;
  const WpTask({required this.id, required this.companyId, required this.name,
    this.nodeId, this.brandScope, this.cadence,
    this.timesSource = 'manual', this.timesManual, this.driverId,
    this.driverFactor = 1, this.minutesSource = 'manual', this.minutesManual,
    this.rateId, this.skillTier, this.risk, this.capability,
    this.ownerEmployeeId, this.roleScorecardId, this.responsibilityArea,
    this.notes, this.externalRef});
  factory WpTask.fromRow(Map<String, dynamic> r) => WpTask(
    id: r['id'] as String, companyId: r['company_id'] as String,
    name: r['name'] as String, nodeId: r['node_id'] as String?,
    brandScope: r['brand_scope'] as String?, cadence: r['cadence'] as String?,
    timesSource: r['times_source'] as String? ?? 'manual',
    timesManual: _dn(r['times_manual']), driverId: r['driver_id'] as String?,
    driverFactor: _dn(r['driver_factor']) ?? 1,
    minutesSource: r['minutes_source'] as String? ?? 'manual',
    minutesManual: _dn(r['minutes_manual']), rateId: r['rate_id'] as String?,
    skillTier: r['skill_tier'] as String?, risk: r['risk'] as String?,
    capability: r['capability'] as String?,
    ownerEmployeeId: r['owner_employee_id'] as String?,
    roleScorecardId: r['role_scorecard_id'] as String?,
    responsibilityArea: r['responsibility_area'] as String?,
    notes: r['notes'] as String?, externalRef: r['external_ref'] as String?);
  Map<String, dynamic> toUpsert(String companyId) => {
    'company_id': companyId, 'name': name.trim(), 'node_id': nodeId,
    'brand_scope': _s(brandScope), 'cadence': _s(cadence),
    'times_source': timesSource,
    'times_manual': timesSource == 'driver' ? null : timesManual,
    'driver_id': timesSource == 'driver' ? driverId : null,
    'driver_factor': driverFactor,
    'minutes_source': minutesSource,
    'minutes_manual': minutesSource == 'rate' ? null : minutesManual,
    'rate_id': minutesSource == 'rate' ? rateId : null,
    'skill_tier': skillTier, 'risk': risk, 'capability': _s(capability),
    'owner_employee_id': ownerEmployeeId, 'role_scorecard_id': roleScorecardId,
    'responsibility_area': _s(responsibilityArea), 'notes': _s(notes)};
}

class WpTaskComputed {
  final String taskId, companyId;
  final String? ownerEmployeeId, nodeId, skillTier, risk;
  final bool isGrowing;
  final double timesPerMonthBase, minutesEach, hoursPerMonthBase;
  const WpTaskComputed({required this.taskId, required this.companyId,
    this.ownerEmployeeId, this.nodeId, this.skillTier, this.risk,
    this.isGrowing = false, this.timesPerMonthBase = 0, this.minutesEach = 0,
    this.hoursPerMonthBase = 0});
  factory WpTaskComputed.fromRow(Map<String, dynamic> r) => WpTaskComputed(
    taskId: r['task_id'] as String, companyId: r['company_id'] as String,
    ownerEmployeeId: r['owner_employee_id'] as String?,
    nodeId: r['node_id'] as String?, skillTier: r['skill_tier'] as String?,
    risk: r['risk'] as String?, isGrowing: r['is_growing'] as bool? ?? false,
    timesPerMonthBase: _d(r['times_per_month_base']),
    minutesEach: _d(r['minutes_each']),
    hoursPerMonthBase: _d(r['hours_per_month_base']));
}

class WpPersonLoad {
  final String employeeId, companyId;
  final int tasksOwned;
  final double hoursFixed, hoursGrowingBase, capacityHours, growthMultiplier;
  const WpPersonLoad({required this.employeeId, required this.companyId,
    this.tasksOwned = 0, this.hoursFixed = 0, this.hoursGrowingBase = 0,
    this.capacityHours = 160, this.growthMultiplier = 1});
  factory WpPersonLoad.fromRow(Map<String, dynamic> r) => WpPersonLoad(
    employeeId: r['employee_id'] as String, companyId: r['company_id'] as String,
    tasksOwned: _i(r['tasks_owned']), hoursFixed: _d(r['hours_fixed']),
    hoursGrowingBase: _d(r['hours_growing_base']),
    capacityHours: _dn(r['capacity_hours']) ?? 160,
    growthMultiplier: _dn(r['growth_multiplier']) ?? 1);
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/data/models/workforce_planning_test.dart`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add lib/data/models/workforce_planning.dart test/data/models/workforce_planning_test.dart
git commit -m "feat(workforce): plain-Dart models for wp_* tables + views"
```

---

### Task 5: capacity_math (the shared calculator)

**Files:**
- Create: `lib/features/workforce_planning/capacity_math.dart`
- Test: `test/features/workforce_planning/capacity_math_test.dart`

**Interfaces:**
- Consumes: `WpPersonLoad` (Task 4).
- Produces: `enum LoadStatus { under, ok, over }`; `double projectedHours(double hoursFixed, double hoursGrowingBase, double multiplier)`; `double loadFraction(double hours, double capacityHours)`; `double personLoad(WpPersonLoad p, {double? multiplier})`; `LoadStatus loadStatus(double fraction)`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/workforce_planning/capacity_math.dart';
import 'package:payroll_flutter/data/models/workforce_planning.dart';

void main() {
  test('projectedHours scales only the growing component', () {
    expect(projectedHours(2, 20, 1), 22);
    expect(projectedHours(2, 20, 2), 42);
    expect(projectedHours(2, 20, 0.5), 12);
  });

  test('loadFraction guards zero capacity', () {
    expect(loadFraction(80, 160), 0.5);
    expect(loadFraction(80, 0), 0);
  });

  test('personLoad uses stored multiplier by default, override when given', () {
    const p = WpPersonLoad(employeeId: 'e', companyId: 'c',
      hoursFixed: 2, hoursGrowingBase: 20, capacityHours: 160, growthMultiplier: 2);
    expect(personLoad(p), (2 + 20 * 2) / 160);
    expect(personLoad(p, multiplier: 1), (2 + 20) / 160);
  });

  test('loadStatus boundaries: 0.79 under, 0.80 ok, 1.00 ok, 1.01 over', () {
    expect(loadStatus(0.79), LoadStatus.under);
    expect(loadStatus(0.80), LoadStatus.ok);
    expect(loadStatus(1.00), LoadStatus.ok);
    expect(loadStatus(1.01), LoadStatus.over);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/workforce_planning/capacity_math_test.dart`
Expected: FAIL — undefined `projectedHours`.

- [ ] **Step 3: Write the implementation**

```dart
import '../../data/models/workforce_planning.dart';

/// Load band for a person. Over = >100%, OK = 80–100% inclusive, Under = <80%.
enum LoadStatus { under, ok, over }

/// Monthly hours at [multiplier]: fixed work is constant, growing work scales.
double projectedHours(double hoursFixed, double hoursGrowingBase, double multiplier) =>
    hoursFixed + hoursGrowingBase * multiplier;

/// Load as a fraction of capacity; 0 when capacity is unknown/zero.
double loadFraction(double hours, double capacityHours) =>
    capacityHours <= 0 ? 0 : hours / capacityHours;

/// A person's load fraction. Uses the person's stored [WpPersonLoad.growthMultiplier]
/// unless [multiplier] is supplied (live slider preview).
double personLoad(WpPersonLoad p, {double? multiplier}) => loadFraction(
    projectedHours(p.hoursFixed, p.hoursGrowingBase, multiplier ?? p.growthMultiplier),
    p.capacityHours);

LoadStatus loadStatus(double fraction) {
  if (fraction > 1.0) return LoadStatus.over;
  if (fraction >= 0.8) return LoadStatus.ok;
  return LoadStatus.under;
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/workforce_planning/capacity_math_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/workforce_planning/capacity_math.dart test/features/workforce_planning/capacity_math_test.dart
git commit -m "feat(workforce): capacity_math shared load calculator"
```

---

### Task 6: org_tree (builder + cycle guard)

**Files:**
- Create: `lib/features/workforce_planning/org_tree.dart`
- Test: `test/features/workforce_planning/org_tree_test.dart`

**Interfaces:**
- Produces: `class OrgNode { final String id; final String? parentId; final List<OrgNode> children; }`; `List<OrgNode> buildOrgTree(List<({String id, String? parentId})> people)` (roots = null parent OR a parent not present); `Set<String> descendantsOf(String id, Map<String, List<String>> childrenOf)`; `bool wouldCreateCycle({required String movingId, required String newParentId, required List<({String id, String? parentId})> people})` (true when newParentId == movingId or is a descendant of movingId). Consumed by Plan 3's Structure tab.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/workforce_planning/org_tree.dart';

void main() {
  // ceo <- coo <- gm ; ceo <- ops
  final people = <({String id, String? parentId})>[
    (id: 'ceo', parentId: null),
    (id: 'coo', parentId: 'ceo'),
    (id: 'gm',  parentId: 'coo'),
    (id: 'ops', parentId: 'ceo'),
  ];

  test('buildOrgTree nests under managers, roots have no/absent parent', () {
    final roots = buildOrgTree(people);
    expect(roots.map((n) => n.id), ['ceo']);
    final ceo = roots.single;
    expect(ceo.children.map((n) => n.id).toSet(), {'coo', 'ops'});
    final coo = ceo.children.firstWhere((n) => n.id == 'coo');
    expect(coo.children.single.id, 'gm');
  });

  test('wouldCreateCycle: self, direct descendant, deep descendant', () {
    expect(wouldCreateCycle(movingId: 'coo', newParentId: 'coo', people: people), isTrue);
    expect(wouldCreateCycle(movingId: 'coo', newParentId: 'gm', people: people), isTrue);
    expect(wouldCreateCycle(movingId: 'ceo', newParentId: 'gm', people: people), isTrue);
  });

  test('wouldCreateCycle false for a valid re-parent', () {
    expect(wouldCreateCycle(movingId: 'gm', newParentId: 'ops', people: people), isFalse);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/workforce_planning/org_tree_test.dart`
Expected: FAIL — undefined `buildOrgTree`.

- [ ] **Step 3: Write the implementation**

```dart
class OrgNode {
  final String id;
  final String? parentId;
  final List<OrgNode> children;
  OrgNode(this.id, this.parentId) : children = [];
}

Map<String, List<String>> _childrenOf(List<({String id, String? parentId})> people) {
  final ids = {for (final p in people) p.id};
  final map = <String, List<String>>{};
  for (final p in people) {
    final parent = p.parentId;
    if (parent != null && ids.contains(parent)) {
      (map[parent] ??= []).add(p.id);
    }
  }
  return map;
}

/// Roots are people with a null parent OR a parent id not present in the list.
List<OrgNode> buildOrgTree(List<({String id, String? parentId})> people) {
  final ids = {for (final p in people) p.id};
  final nodes = {for (final p in people) p.id: OrgNode(p.id, p.parentId)};
  final roots = <OrgNode>[];
  for (final p in people) {
    final node = nodes[p.id]!;
    final parent = p.parentId;
    if (parent != null && nodes.containsKey(parent) && ids.contains(parent)) {
      nodes[parent]!.children.add(node);
    } else {
      roots.add(node);
    }
  }
  return roots;
}

Set<String> descendantsOf(String id, Map<String, List<String>> childrenOf) {
  final out = <String>{};
  final stack = [...(childrenOf[id] ?? const <String>[])];
  while (stack.isNotEmpty) {
    final cur = stack.removeLast();
    if (out.add(cur)) stack.addAll(childrenOf[cur] ?? const <String>[]);
  }
  return out;
}

/// A re-parent creates a cycle when the new parent is the node itself or any of
/// its descendants.
bool wouldCreateCycle({
  required String movingId,
  required String newParentId,
  required List<({String id, String? parentId})> people,
}) {
  if (movingId == newParentId) return true;
  return descendantsOf(movingId, _childrenOf(people)).contains(newParentId);
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/workforce_planning/org_tree_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/workforce_planning/org_tree.dart test/features/workforce_planning/org_tree_test.dart
git commit -m "feat(workforce): org_tree builder + cycle guard"
```

---

### Task 7: workforce_planning_repository

**Files:**
- Create: `lib/data/repositories/workforce_planning_repository.dart`

**Interfaces:**
- Consumes: models (Task 4), views/tables (Tasks 1–2).
- Produces: `WorkforcePlanningRepository` + `workforcePlanningRepositoryProvider`; read methods `nodes()`, `drivers()`, `rates()`, `config()`, `tasks()`, `personLoads()`, `taskComputedForOwner(String employeeId)`; write methods `saveTask(WpTask)`, `deleteTask(String id)`, `reassignTaskOwner(String taskId, String? ownerEmployeeId)`, `saveDriver(WpDriver)`, `saveRate(WpRate)`, `setGrowthMultiplier(String companyId, double m)`, `setCapacityOverride(String employeeId, double? hours)`. (Reporting writes live in `employee_repository` in Plan 3.) Repositories are thin glue — verified by `flutter analyze` here and exercised via widget tests in Plans 2–3, not unit-tested (no local Supabase).

- [ ] **Step 1: Write the repository**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/workforce_planning.dart';

class WorkforcePlanningRepository {
  final SupabaseClient _client;
  WorkforcePlanningRepository(this._client);

  Future<List<WpNode>> nodes() async {
    final rows = await _client.from('wp_value_chain_nodes').select().order('sort_order');
    return rows.cast<Map<String, dynamic>>().map(WpNode.fromRow).toList();
  }

  Future<List<WpDriver>> drivers() async {
    final rows = await _client.from('wp_drivers').select().order('sort_order').order('name');
    return rows.cast<Map<String, dynamic>>().map(WpDriver.fromRow).toList();
  }

  Future<List<WpRate>> rates() async {
    final rows = await _client.from('wp_rates').select().order('name');
    return rows.cast<Map<String, dynamic>>().map(WpRate.fromRow).toList();
  }

  Future<WpConfig?> config() async {
    final row = await _client.from('wp_config').select().maybeSingle();
    return row == null ? null : WpConfig.fromRow(row);
  }

  Future<List<WpTask>> tasks() async {
    final rows = await _client.from('wp_tasks').select().order('name');
    return rows.cast<Map<String, dynamic>>().map(WpTask.fromRow).toList();
  }

  Future<List<WpPersonLoad>> personLoads() async {
    final rows = await _client.from('wp_person_load').select();
    return rows.cast<Map<String, dynamic>>().map(WpPersonLoad.fromRow).toList();
  }

  Future<List<WpTaskComputed>> taskComputedForOwner(String employeeId) async {
    final rows = await _client
        .from('wp_task_computed').select().eq('owner_employee_id', employeeId);
    return rows.cast<Map<String, dynamic>>().map(WpTaskComputed.fromRow).toList();
  }

  Future<void> saveTask(WpTask task) async {
    final payload = task.toUpsert(task.companyId);
    if (task.id.isEmpty) {
      await _client.from('wp_tasks').insert(payload);
    } else {
      await _client.from('wp_tasks').update(payload).eq('id', task.id);
    }
  }

  Future<void> deleteTask(String id) async =>
      _client.from('wp_tasks').delete().eq('id', id);

  Future<void> reassignTaskOwner(String taskId, String? ownerEmployeeId) async =>
      _client.from('wp_tasks').update({'owner_employee_id': ownerEmployeeId}).eq('id', taskId);

  Future<void> saveDriver(WpDriver driver) async {
    final payload = driver.toUpsert(driver.companyId);
    if (driver.id.isEmpty) {
      await _client.from('wp_drivers').insert(payload);
    } else {
      await _client.from('wp_drivers').update(payload).eq('id', driver.id);
    }
  }

  Future<void> saveRate(WpRate rate) async {
    final payload = rate.toUpsert(rate.companyId);
    if (rate.id.isEmpty) {
      await _client.from('wp_rates').insert(payload);
    } else {
      await _client.from('wp_rates').update(payload).eq('id', rate.id);
    }
  }

  Future<void> setGrowthMultiplier(String companyId, double m) async =>
      _client.from('wp_config').upsert({
        'company_id': companyId, 'growth_multiplier': m, 'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'company_id');

  Future<void> setCapacityOverride(String employeeId, double? hours) async {
    if (hours == null) {
      await _client.from('wp_capacity_overrides').delete().eq('employee_id', employeeId);
    } else {
      await _client.from('wp_capacity_overrides').upsert({
        'employee_id': employeeId, 'capacity_hours': hours,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'employee_id');
    }
  }
}

final workforcePlanningRepositoryProvider = Provider<WorkforcePlanningRepository>(
    (ref) => WorkforcePlanningRepository(Supabase.instance.client));
```

- [ ] **Step 2: Verify it compiles clean**

Run: `flutter analyze lib/data/repositories/workforce_planning_repository.dart lib/data/models/workforce_planning.dart lib/features/workforce_planning/`
Expected: `No issues found!`

- [ ] **Step 3: Run the full suite + analyze**

Run: `flutter analyze && flutter test`
Expected: analyze clean; all tests (including the three new files) pass.

- [ ] **Step 4: Commit**

```bash
git add lib/data/repositories/workforce_planning_repository.dart
git commit -m "feat(workforce): workforce_planning_repository (reads + writes + provider)"
```

---

## Self-Review

**Spec coverage (this plan = Foundation only):**
- `wp_*` tables (nodes, drivers, rates, tasks, capacity_overrides, config) → Task 1. ✓
- Views (`wp_task_computed`, `wp_person_load`, base + scaled/projected) → Task 2 (aggregates) + Task 5 (base/scaled/load in `capacity_math`). ✓
- Idempotent xlsx seed, owner/card matching, unmatched null, match-rate report → Task 3. ✓
- RLS mirroring `kpis`; capacity_overrides via employees; `security_invoker` views → Tasks 1–2. ✓
- Simplification 1 (flat drivers, grows-flag scaling) → `is_growing` in Task 2 + `projectedHours` in Task 5. ✓
- Simplification 2 (single multiplier) → `wp_config.growth_multiplier` + `personLoad(multiplier:)`. ✓
- Cycle guard for Plan 3's reporting drag → `wouldCreateCycle` in Task 6 (built here as a pure helper). ✓
- Deferred to later plans (correctly absent here): the 5-tab UI, drag-drop, KPI read-only surfacing, `employees.reports_to_id` write (verified already HR/Admin-permitted → no migration).

**Placeholder scan:** none — every step has concrete SQL/Dart/commands. Seed row data is produced by the committed generator (Task 3), which is the complete source.

**Type consistency:** `WpPersonLoad` fields (`hoursFixed`, `hoursGrowingBase`, `capacityHours`, `growthMultiplier`) match `wp_person_load` columns (Task 2) and `capacity_math.personLoad` usage (Task 5). `WpTask.toUpsert` keys match Task 1 columns. `wouldCreateCycle` signature matches its test and the Plan 3 consumer note.

**Card matching note:** Task 3's generator resolves `owner_employee_id` by name but does not attempt `role_scorecard_id` linking (the xlsx has no reliable card key). The spec allows unmatched → null; card linking is left to in-app editing (Plan 2). This is a deliberate narrowing, recorded here.
